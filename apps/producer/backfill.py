"""Fills gaps in the trades table from Binance's REST API, through the producer's own Kafka path.

Binance trade IDs increase by one per symbol, so a jump between consecutive IDs in PostgreSQL is a
range of trades that never landed. Each run finds those ranges, fetches the trades over REST and
publishes them exactly as the live stream does. The consumer inserts them like any other trade, and
its primary key absorbs any overlap.
"""

import json
import logging
import os
import sys
import urllib.parse
import urllib.request

import boto3
import psycopg

from producer import kafka_config, new_producer, publish, setting

log = logging.getLogger("backfill")

REST_URL = os.environ.get("BINANCE_REST_URL", "https://api.binance.com/api/v3/historicalTrades")
# Far enough back to repair what the data probe flagged and has since stopped looking at.
LOOKBACK_SECONDS = 6 * 3600
# Rows this recent may still be in flight, as in the data probe.
SETTLE_SECONDS = 30
PAGE_SIZE = 1000
# Each call weighs 25 of Binance's 6,000 per minute per IP; a larger gap finishes in later runs.
MAX_CALLS_PER_RUN = 100

GAPS_SQL = """
SELECT symbol, prev_id + 1, trade_id - 1
FROM (
    SELECT symbol, trade_id, lag(trade_id) OVER (PARTITION BY symbol ORDER BY trade_id) AS prev_id
    FROM trades
    WHERE ingested_at > now() - %s * interval '1 second' AND ingested_at <= now() - %s * interval '1 second'
) ordered
WHERE trade_id > prev_id + 1
ORDER BY symbol, trade_id
"""


def find_gaps(conn: psycopg.Connection) -> list[tuple[str, int, int]]:
    return conn.execute(GAPS_SQL, (LOOKBACK_SECONDS, SETTLE_SECONDS)).fetchall()


def fetch_page(symbol: str, from_id: int, limit: int) -> list[dict]:
    query = urllib.parse.urlencode({"symbol": symbol, "fromId": from_id, "limit": limit})
    with urllib.request.urlopen(f"{REST_URL}?{query}", timeout=10) as response:
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


def backfill(gaps, fetch, send, max_calls: int = MAX_CALLS_PER_RUN) -> int:
    """Fetches each missing range page by page and sends every trade in it; returns how many."""
    sent = calls = 0
    for symbol, first, last in gaps:
        from_id = first
        while from_id <= last:
            if calls == max_calls:
                log.warning("reached %d REST calls; the rest waits for the next run", max_calls)
                return sent
            page = fetch(symbol, from_id, min(PAGE_SIZE, last - from_id + 1))
            calls += 1
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
    return psycopg.connect(host=host, port=port, dbname=setting("PGDATABASE"), user=user, password=token)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    with connect() as conn:
        gaps = find_gaps(conn)
    if not gaps:
        log.info("no missing trades in the last %d hours", LOOKBACK_SECONDS // 3600)
        return
    log.info("found %d missing ranges: %s", len(gaps), gaps[:20])
    producer = new_producer(kafka_config(), "binance-backfill")
    sent = backfill(gaps, fetch_page, lambda raw: publish(producer, raw))
    unflushed = producer.flush(30)
    log.info("published %d trades, %d not acknowledged", sent, unflushed)
    # A failed run leaves the gaps in place, so the next run retries them.
    if unflushed:
        sys.exit(1)


if __name__ == "__main__":
    main()
