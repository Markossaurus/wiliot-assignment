"""Writes trades from Kafka into PostgreSQL, exactly once per (symbol, trade_id)."""

import json
import logging
import os
import signal
import socket
import threading
import time
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg
from confluent_kafka import Consumer, KafkaException
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

log = logging.getLogger("consumer")

KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC", "binance.trades")
KAFKA_GROUP_ID = os.environ.get("KAFKA_GROUP_ID", "trades-writer")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "500"))
BATCH_WAIT_SECONDS = float(os.environ.get("BATCH_WAIT_SECONDS", "0.1"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "8000"))
HEALTHY_WITHIN_SECONDS = 60
LAG_UPDATE_SECONDS = 10

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

INSERT_SQL = """
INSERT INTO trades (symbol, trade_id, price, quantity, trade_time)
SELECT * FROM unnest(%s::text[], %s::bigint[], %s::numeric[], %s::numeric[], %s::timestamptz[])
ON CONFLICT (symbol, trade_id) DO NOTHING
RETURNING symbol, trade_time
"""

MESSAGES_CONSUMED = Counter("consumer_messages_consumed_total", "Messages read from Kafka")
ROWS_INSERTED = Counter("consumer_rows_inserted_total", "Trades inserted into PostgreSQL")
DUPLICATES_SKIPPED = Counter("consumer_duplicates_skipped_total", "Trades already present in PostgreSQL")
INVALID_MESSAGES = Counter("consumer_invalid_messages_total", "Messages that could not be parsed as trades")
DB_ERRORS = Counter("consumer_db_errors_total", "Failed database write attempts")
COMMIT_ERRORS = Counter("consumer_commit_errors_total", "Failed Kafka offset commits")
E2E_LATENCY = Histogram(
    "consumer_e2e_latency_seconds",
    "Time from trade execution to commit in PostgreSQL",
    buckets=(0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60, 300),
)
LAST_TRADE_TIME = Gauge("consumer_last_trade_time_seconds", "Trade time of the newest committed trade", ["symbol"])
CONSUMER_LAG = Gauge("consumer_lag_messages", "Messages between the committed position and the end", ["partition"])

heartbeat = time.monotonic()


def beat() -> None:
    global heartbeat
    heartbeat = time.monotonic()


def setting(name: str, default: str | None = None) -> str:
    """Reads NAME from the file that NAME_FILE points to (a Secrets Store CSI mount), else from NAME."""
    path = os.environ.get(f"{name}_FILE")
    if path:
        with open(path) as f:
            return f.read().strip()
    value = os.environ.get(name, default)
    if value is None:
        raise KeyError(name)
    return value


def kafka_config() -> dict:
    conf = {"bootstrap.servers": setting("KAFKA_BOOTSTRAP_SERVERS")}
    if os.environ.get("KAFKA_AUTH", "none") == "iam":
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        region = os.environ["AWS_REGION"]

        def oauth_cb(_config):
            token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
            return token, expiry_ms / 1000

        conf.update({"security.protocol": "SASL_SSL", "sasl.mechanism": "OAUTHBEARER", "oauth_cb": oauth_cb})
    return conf


def to_row(value: bytes) -> tuple[str, int, Decimal, Decimal, datetime]:
    trade = json.loads(value)
    price, quantity = Decimal(trade["p"]), Decimal(trade["q"])
    if not (price.is_finite() and quantity.is_finite() and price > 0 and quantity > 0):
        raise ValueError(f"invalid price or quantity: {trade['p']!r} x {trade['q']!r}")
    return (
        str(trade["s"]),
        int(trade["t"]),
        price,
        quantity,
        EPOCH + timedelta(milliseconds=int(trade["T"])),
    )


class Database:
    def __init__(self) -> None:
        self._conn: psycopg.Connection | None = None

    def _connect(self) -> psycopg.Connection:
        # Read on every connect, so a reconnect picks up a rotated endpoint file.
        kwargs = {"host": setting("PGHOST"), "port": int(setting("PGPORT", "5432")), "dbname": setting("PGDATABASE")}
        if os.environ.get("DB_AUTH", "password") == "iam":
            import boto3

            # Short-lived token used as the password; only needed when a connection is opened.
            kwargs["password"] = boto3.client("rds", region_name=os.environ["AWS_REGION"]).generate_db_auth_token(
                DBHostname=kwargs["host"],
                Port=kwargs["port"],
                DBUsername=os.environ["PGUSER"],
            )
        # User and TLS settings come from the standard PG* environment variables.
        return psycopg.connect(autocommit=True, **kwargs)

    def insert(self, rows: list[tuple]) -> list[tuple[str, datetime]]:
        """Inserts rows in one transaction, retrying until it succeeds; returns the rows actually inserted."""
        columns = [list(column) for column in zip(*rows)]
        delay = 0.5
        while True:
            try:
                if self._conn is None or self._conn.closed:
                    self._conn = self._connect()
                with self._conn.transaction():
                    return self._conn.execute(INSERT_SQL, columns).fetchall()
            except psycopg.Error as exc:
                DB_ERRORS.inc()
                log.error("database write failed (%s), retrying in %.1fs", exc, delay)
                if self._conn is not None:
                    self._conn.close()
                beat()
                time.sleep(delay)
                delay = min(delay * 2, 30)


def record_batch(batch_size: int, inserted: list[tuple[str, datetime]]) -> None:
    now = time.time()
    newest: dict[str, float] = {}
    for symbol, trade_time in inserted:
        trade_ts = trade_time.timestamp()
        E2E_LATENCY.observe(now - trade_ts)
        newest[symbol] = max(newest.get(symbol, 0.0), trade_ts)
    for symbol, trade_ts in newest.items():
        LAST_TRADE_TIME.labels(symbol).set(trade_ts)
    ROWS_INSERTED.inc(len(inserted))
    DUPLICATES_SKIPPED.inc(batch_size - len(inserted))


def update_lag(consumer: Consumer) -> None:
    assignment = consumer.assignment()
    if not assignment:
        return
    for tp in consumer.position(assignment):
        _, high = consumer.get_watermark_offsets(tp, cached=True)
        if tp.offset >= 0 and high >= 0:
            CONSUMER_LAG.labels(str(tp.partition)).set(high - tp.offset)


def on_assign(_consumer, partitions) -> None:
    log.info("assigned partitions %s", sorted(p.partition for p in partitions))


def on_revoke(_consumer, partitions) -> None:
    log.info("revoked partitions %s", sorted(p.partition for p in partitions))
    for p in partitions:
        try:
            CONSUMER_LAG.remove(str(p.partition))
        except KeyError:
            pass


def commit(consumer: Consumer) -> None:
    try:
        consumer.commit(asynchronous=False)
    except KafkaException as exc:
        # The rows are already in PostgreSQL; whoever owns the partition next re-reads and skips them.
        COMMIT_ERRORS.inc()
        log.warning("offset commit failed: %s", exc)


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            status, ctype, body = 200, CONTENT_TYPE_LATEST, generate_latest()
        elif self.path == "/healthz":
            healthy = time.monotonic() - heartbeat < HEALTHY_WITHIN_SECONDS
            status, ctype, body = (200, "text/plain", b"ok") if healthy else (503, "text/plain", b"stalled")
        else:
            status, ctype, body = 404, "text/plain", b"not found"
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


def run(consumer: Consumer, db: Database, stopping: threading.Event) -> None:
    last_lag_update = 0.0
    while not stopping.is_set():
        beat()
        messages = consumer.consume(num_messages=BATCH_SIZE, timeout=BATCH_WAIT_SECONDS)
        rows = []
        for msg in messages:
            if msg.error():
                log.warning("consume error: %s", msg.error())
                continue
            try:
                rows.append(to_row(msg.value()))
            except (ValueError, KeyError, TypeError, ArithmeticError) as exc:
                INVALID_MESSAGES.inc()
                log.warning("skipping invalid message %s[%d]@%d: %s", msg.topic(), msg.partition(), msg.offset(), exc)
        MESSAGES_CONSUMED.inc(len(messages))

        if rows:
            record_batch(len(rows), db.insert(rows))
        # Offsets are committed only after the rows are committed in PostgreSQL.
        if messages:
            commit(consumer)

        if time.monotonic() - last_lag_update > LAG_UPDATE_SECONDS:
            update_lag(consumer)
            last_lag_update = time.monotonic()


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    consumer = Consumer(
        {
            **kafka_config(),
            "group.id": KAFKA_GROUP_ID,
            "client.id": socket.gethostname(),
            "enable.auto.commit": False,
            "auto.offset.reset": "earliest",
            "partition.assignment.strategy": "cooperative-sticky",
            "session.timeout.ms": 10000,
        }
    )
    consumer.subscribe([KAFKA_TOPIC], on_assign=on_assign, on_revoke=on_revoke)

    stopping = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stopping.set())

    server = ThreadingHTTPServer(("", HTTP_PORT), HealthHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    try:
        run(consumer, Database(), stopping)
    finally:
        # Leaving the group explicitly lets the remaining consumers rebalance immediately.
        consumer.close()
        log.info("shut down")


if __name__ == "__main__":
    main()
