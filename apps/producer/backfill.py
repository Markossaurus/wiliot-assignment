"""Fills gaps in the trades table from Binance's REST API, through the producer's own Kafka path.

Binance trade IDs increase by one per symbol, so a jump between consecutive IDs in PostgreSQL is a
range of trades that never landed. Each symbol has a watermark: every trade ID up to it is in the
table. Each run scans forward from the watermarks, moves each one up to its symbol's first remaining
gap, then fetches the missing trades over REST and publishes them exactly as the live stream does.
The consumer inserts them like any other trade, and its primary key absorbs any overlap.
"""

import json
import logging
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import boto3
import psycopg

from producer import SYMBOLS, kafka_config, new_producer, publish, setting

log = logging.getLogger("backfill")

REST_URL = os.environ.get("BINANCE_REST_URL", "https://api.binance.com/api/v3/historicalTrades")
# A gap counts once the trade after it landed this long ago, as in the data probe: before that, the
# missing trades may still be in flight.
SETTLE_SECONDS = 30
PAGE_SIZE = 1000
# Binance's weight for one historicalTrades call, and how much of its 6,000 per IP per minute to use.
CALL_WEIGHT = 25
WEIGHT_BUDGET = 4500

# A symbol's verified history starts at its first trade in the table.
INIT_WATERMARKS_SQL = """
INSERT INTO trade_watermarks (symbol, verified_through_id)
SELECT first.symbol, first.trade_id
FROM unnest(%s::text[]) AS s (symbol)
CROSS JOIN LATERAL (SELECT symbol, trade_id FROM trades WHERE symbol = s.symbol ORDER BY trade_id LIMIT 1) first
ON CONFLICT (symbol) DO NOTHING
"""

# Every jump between consecutive trade IDs after each watermark, and whether it has settled. The scan
# reads only the primary key; the table itself is read only for the trade after each gap.
GAPS_SQL = """
SELECT g.symbol, g.prev_id + 1, g.trade_id - 1,
       (SELECT ingested_at FROM trades t WHERE t.symbol = g.symbol AND t.trade_id = g.trade_id)
           <= now() - %s * interval '1 second'
FROM trade_watermarks w
CROSS JOIN LATERAL (
    SELECT symbol, trade_id, lag(trade_id, 1, w.verified_through_id) OVER (ORDER BY trade_id) AS prev_id
    FROM trades
    WHERE symbol = w.symbol AND trade_id > w.verified_through_id
) g
WHERE g.trade_id > g.prev_id + 1
ORDER BY g.symbol, g.trade_id
"""

LATEST_SQL = """
SELECT w.symbol, (SELECT max(trade_id) FROM trades t WHERE t.symbol = w.symbol)
FROM trade_watermarks w
"""

ADVANCE_SQL = """
UPDATE trade_watermarks SET verified_through_id = %(id)s, updated_at = now()
WHERE symbol = %(symbol)s AND verified_through_id < %(id)s
"""


def new_watermarks(latest: dict[str, int], gaps: list[tuple[str, int, int, bool]]) -> dict[str, int]:
    """Each watermark moves to just before its symbol's first gap, settled or not, else to its latest trade."""
    first_gap = {}
    for symbol, first, _, _ in gaps:
        first_gap.setdefault(symbol, first)
    return {symbol: first_gap[symbol] - 1 if symbol in first_gap else last for symbol, last in latest.items()}


def verify(conn: psycopg.Connection, symbols: list[str]) -> list[tuple[str, int, int, bool]]:
    """Moves the watermarks forward and returns every (symbol, first, last, settled) gap after them."""
    conn.execute(INIT_WATERMARKS_SQL, (symbols,))
    gaps = conn.execute(GAPS_SQL, (SETTLE_SECONDS,)).fetchall()
    latest = dict(conn.execute(LATEST_SQL).fetchall())
    marks = new_watermarks(latest, gaps)
    with conn.cursor() as cur:
        cur.executemany(ADVANCE_SQL, [{"symbol": s, "id": i} for s, i in marks.items()])
    conn.commit()
    log.info("watermarks: %s", marks)
    return gaps


class Exchange:
    """Binance's historicalTrades, paced by the request weight Binance reports for this IP."""

    def __init__(self, urlopen=urllib.request.urlopen, sleep=time.sleep, now=time.time):
        self.urlopen, self.sleep, self.now = urlopen, sleep, now
        self.used_weight = 0

    def fetch(self, symbol: str, from_id: int, limit: int) -> list[dict]:
        # Binance counts weight per clock minute, so a call over the budget waits for the next one.
        if self.used_weight + CALL_WEIGHT > WEIGHT_BUDGET:
            self.sleep(61 - self.now() % 60)
        query = urllib.parse.urlencode({"symbol": symbol, "fromId": from_id, "limit": limit})
        with self.urlopen(f"{REST_URL}?{query}", timeout=10) as response:
            self.used_weight = int(response.headers.get("x-mbx-used-weight-1m", self.used_weight + CALL_WEIGHT))
            return json.load(response)


def to_stream_message(symbol: str, trade: dict) -> str:
    """Rebuilds a REST trade as the message the WebSocket stream would have delivered."""
    return json.dumps(
        {
            "e": "trade",
            "E": trade["time"],
            "s": symbol,
            "t": trade["id"],
            "p": trade["price"],
            "q": trade["qty"],
            "T": trade["time"],
            "m": trade["isBuyerMaker"],
        },
        separators=(",", ":"),
    )


def backfill(gaps, fetch, send) -> int:
    """Fetches each missing range page by page and sends every trade in it; returns how many."""
    sent = 0
    for symbol, first, last in gaps:
        from_id = first
        while from_id <= last:
            try:
                page = fetch(symbol, from_id, min(PAGE_SIZE, last - from_id + 1))
            except urllib.error.HTTPError as exc:
                # 429 is over the limit and 418 a ban for ignoring 429s, which more calls would extend.
                if exc.code in (418, 429):
                    log.warning("rate limited by Binance (%d); the rest waits for the next run", exc.code)
                    return sent
                raise
            if not page:
                break
            for trade in page:
                if trade["id"] > last:
                    break
                send(to_stream_message(symbol, trade))
                sent += 1
            from_id = page[-1]["id"] + 1
        log.info("backfilled %s %d-%d", symbol, first, last)
    return sent


def connect() -> psycopg.Connection:
    host, port, user = setting("PGHOST"), int(setting("PGPORT", "5432")), os.environ["PGUSER"]
    # IAM authentication: a short-lived token instead of a password. TLS settings come from PG*.
    token = boto3.client("rds", region_name=os.environ["AWS_REGION"]).generate_db_auth_token(
        DBHostname=host, Port=port, DBUsername=user
    )
    conn = psycopg.connect(host=host, port=port, dbname=setting("PGDATABASE"), user=user, password=token)
    # The gap scan and the latest IDs must come from the same snapshot, or a watermark could move
    # past a gap that appeared in between.
    conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
    return conn


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    with connect() as conn:
        gaps = verify(conn, [s.upper() for s in SYMBOLS])
    settled = [(symbol, first, last) for symbol, first, last, is_settled in gaps if is_settled]
    if not settled:
        log.info("no missing trades")
        return
    missing = sum(last - first + 1 for _, first, last in settled)
    log.info("found %d missing trades in %d ranges: %s", missing, len(settled), settled[:20])
    producer = new_producer(kafka_config(), "binance-backfill")
    try:
        sent = backfill(settled, Exchange().fetch, lambda raw: publish(producer, raw))
    finally:
        unflushed = producer.flush(30)
    log.info("published %d trades, %d not acknowledged", sent, unflushed)
    # A failed run leaves the gaps in place, so the next run retries them.
    if unflushed:
        sys.exit(1)


if __name__ == "__main__":
    main()
