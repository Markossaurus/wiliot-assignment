"""Measures how fresh and how complete the trades table is, and publishes it to CloudWatch.

It reads only what actually landed in PostgreSQL, so it also catches what the pipeline itself
can't see, such as trades that never arrived: Binance trade IDs increase by one per symbol, so
a missing ID is a lost trade.
"""

import logging
import os
import signal
import threading
import time

import boto3
import psycopg

log = logging.getLogger("data_probe")

NAMESPACE = os.environ.get("METRICS_NAMESPACE", "Trades")
INTERVAL_SECONDS = 60
# A gap counts once the trade after it landed this long ago: with several producers, a trade can
# land just after the one that followed it.
SETTLE_SECONDS = 30

STALENESS_SQL = "SELECT extract(epoch FROM now() - max(ingested_at)) FROM trades"

# Only trades executed recently count: backfilled trades land now but executed long ago, and are
# history being repaired rather than a sign that live data is slow.
LATENCY_SQL = """
SELECT count(*), percentile_cont(0.99) WITHIN GROUP (ORDER BY extract(epoch FROM ingested_at - trade_time))
FROM trades
WHERE ingested_at > now() - interval '1 minute' AND trade_time > now() - interval '2 minutes'
"""

# Each jump between consecutive trade IDs of a symbol is a range of trades that never landed. The scan
# starts at the backfill's watermarks, which never pass a gap, so a gap counts however old it is. It
# reads only the primary key; the table itself only for the trade after each gap.
GAPS_SQL = """
SELECT g.symbol, g.prev_id + 1, g.trade_id - 1
FROM trade_watermarks w
CROSS JOIN LATERAL (
    SELECT symbol, trade_id, lag(trade_id, 1, w.verified_through_id) OVER (ORDER BY trade_id) AS prev_id
    FROM trades
    WHERE symbol = w.symbol AND trade_id > w.verified_through_id
) g
WHERE g.trade_id > g.prev_id + 1
  AND (SELECT ingested_at FROM trades t WHERE t.symbol = g.symbol AND t.trade_id = g.trade_id)
      <= now() - %s * interval '1 second'
ORDER BY g.symbol, g.trade_id
"""
# A long outage is one range per symbol; scattered losses could be many, so the log is capped.
MAX_LOGGED_GAPS = 50


def setting(name: str, default: str | None = None) -> str:
    """Reads NAME from the file that NAME_FILE points to (a mounted Secret), else from NAME."""
    path = os.environ.get(f"{name}_FILE")
    if path:
        with open(path) as f:
            return f.read().strip()
    value = os.environ.get(name, default)
    if value is None:
        raise KeyError(name)
    return value


def metric_data(staleness, ingested, latency_p99, missing) -> list[dict]:
    """Builds the CloudWatch datapoints; values that can't be measured yet are left out."""
    data = [
        {"MetricName": "TradesIngested", "Value": float(ingested), "Unit": "Count"},
        {"MetricName": "MissingTrades", "Value": float(missing), "Unit": "Count"},
    ]
    # Empty table: no last trade to measure from.
    if staleness is not None:
        data.append({"MetricName": "SecondsSinceLastTrade", "Value": float(staleness), "Unit": "Seconds"})
    # No trades in the last minute: no latency to report; staleness covers that case.
    if latency_p99 is not None:
        data.append({"MetricName": "IngestLatencyP99", "Value": float(latency_p99), "Unit": "Seconds"})
    return data


def missing_trades(gaps: list[tuple[str, int, int]]) -> int:
    return sum(last - first + 1 for _, first, last in gaps)


def measure(conn: psycopg.Connection) -> tuple[list[dict], list[tuple[str, int, int]]]:
    """Returns the datapoints, and the (symbol, first missing ID, last missing ID) ranges."""
    (staleness,) = conn.execute(STALENESS_SQL).fetchone()
    ingested, latency_p99 = conn.execute(LATENCY_SQL).fetchone()
    gaps = conn.execute(GAPS_SQL, (SETTLE_SECONDS,)).fetchall()
    return metric_data(staleness, ingested, latency_p99, missing_trades(gaps)), gaps


def connect(rds) -> psycopg.Connection:
    host, port, user = setting("PGHOST"), int(setting("PGPORT", "5432")), os.environ["PGUSER"]
    # IAM authentication: a short-lived token instead of a password. TLS settings come from PG*.
    token = rds.generate_db_auth_token(DBHostname=host, Port=port, DBUsername=user)
    return psycopg.connect(
        host=host,
        port=port,
        dbname=setting("PGDATABASE"),
        user=user,
        password=token,
        autocommit=True,
        connect_timeout=10,
        options="-c statement_timeout=20000",
    )


def main() -> None:
    # Python runs as PID 1, which ignores SIGTERM unless it has a handler.
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    region = os.environ["AWS_REGION"]
    rds = boto3.client("rds", region_name=region)
    cloudwatch = boto3.client("cloudwatch", region_name=region)
    while not stopping.is_set():
        started = time.monotonic()
        try:
            with connect(rds) as conn:
                data, gaps = measure(conn)
            cloudwatch.put_metric_data(Namespace=NAMESPACE, MetricData=data)
            log.info("published %s", {d["MetricName"]: round(d["Value"], 3) for d in data})
            # The exact ranges, for whoever investigates or backfills them.
            for symbol, first, last in gaps[:MAX_LOGGED_GAPS]:
                log.warning("missing trades: %s %d-%d (%d)", symbol, first, last, last - first + 1)
        # Keep probing whatever fails: the missing datapoints are what raise the staleness alarm.
        except Exception:
            log.exception("probe failed")
        # Ends at once on SIGTERM, unlike time.sleep.
        stopping.wait(max(0.0, INTERVAL_SECONDS - (time.monotonic() - started)))
    log.info("shut down")


if __name__ == "__main__":
    main()
