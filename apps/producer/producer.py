"""Streams Binance trades from the WebSocket API into a Kafka topic."""

import asyncio
import json
import logging
import os
import random
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from confluent_kafka import KafkaError, KafkaException, Producer
from confluent_kafka.admin import AdminClient, NewTopic
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from websockets.asyncio.client import connect
from websockets.exceptions import WebSocketException

log = logging.getLogger("producer")

BINANCE_WS_URL = os.environ.get("BINANCE_WS_URL", "wss://stream.binance.com:9443/stream")
SYMBOLS = os.environ.get(
    "SYMBOLS",
    "btcusdt,ethusdt,solusdt,bnbusdt,xrpusdt,adausdt,dogeusdt,avaxusdt,linkusdt,maticusdt",
).split(",")
KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC", "binance.trades")
TOPIC_PARTITIONS = int(os.environ.get("KAFKA_TOPIC_PARTITIONS", "6"))
TOPIC_REPLICATION = int(os.environ.get("KAFKA_TOPIC_REPLICATION", "3"))
TOPIC_RETENTION_MS = int(os.environ.get("KAFKA_TOPIC_RETENTION_MS", str(7 * 24 * 3600 * 1000)))
IDLE_TIMEOUT_SECONDS = float(os.environ.get("IDLE_TIMEOUT_SECONDS", "30"))
MAX_BACKOFF_SECONDS = float(os.environ.get("MAX_BACKOFF_SECONDS", "30"))
HTTP_PORT = int(os.environ.get("HTTP_PORT", "8000"))
HEALTHY_WITHIN_SECONDS = 120

TRADES_RECEIVED = Counter("producer_trades_received_total", "Trades received from Binance", ["symbol"])
TRADES_DELIVERED = Counter("producer_trades_delivered_total", "Trades acknowledged by Kafka")
DELIVERY_ERRORS = Counter("producer_delivery_errors_total", "Trades Kafka failed to acknowledge")
IGNORED_MESSAGES = Counter("producer_ignored_messages_total", "WebSocket messages that were not trades")
RECONNECTS = Counter("producer_websocket_reconnects_total", "WebSocket reconnects")
BINANCE_LATENCY = Histogram(
    "producer_binance_latency_seconds",
    "Time from trade execution to receipt by the producer",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)

heartbeat = time.monotonic()


def kafka_config() -> dict:
    conf = {"bootstrap.servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"]}
    if os.environ.get("KAFKA_AUTH", "none") == "iam":
        from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

        region = os.environ["AWS_REGION"]

        def oauth_cb(_config):
            token, expiry_ms = MSKAuthTokenProvider.generate_auth_token(region)
            return token, expiry_ms / 1000

        conf.update({"security.protocol": "SASL_SSL", "sasl.mechanism": "OAUTHBEARER", "oauth_cb": oauth_cb})
    return conf


def ensure_topic(conf: dict) -> None:
    admin = AdminClient(conf)
    if "oauth_cb" in conf:
        # Serves the IAM token callback before the first admin request.
        admin.poll(1)
    topic = NewTopic(
        KAFKA_TOPIC,
        num_partitions=TOPIC_PARTITIONS,
        replication_factor=TOPIC_REPLICATION,
        config={
            "retention.ms": str(TOPIC_RETENTION_MS),
            "min.insync.replicas": str(min(2, TOPIC_REPLICATION)),
        },
    )
    try:
        admin.create_topics([topic])[KAFKA_TOPIC].result(timeout=30)
        log.info("created topic %s", KAFKA_TOPIC)
    except KafkaException as exc:
        if exc.args[0].code() != KafkaError.TOPIC_ALREADY_EXISTS:
            raise


def to_kafka_record(raw: str) -> tuple[str, bytes, int] | None:
    """Returns (key, value, trade time in ms) for a trade message, or None for anything else."""
    payload = json.loads(raw)
    trade = payload.get("data", payload)
    if not isinstance(trade, dict) or trade.get("e") != "trade":
        return None
    return trade["s"], json.dumps(trade, separators=(",", ":")).encode(), trade["T"]


def on_delivery(err, _msg) -> None:
    if err:
        DELIVERY_ERRORS.inc()
        log.error("delivery failed: %s", err)
    else:
        TRADES_DELIVERED.inc()


def publish(producer: Producer, raw: str) -> None:
    try:
        record = to_kafka_record(raw)
    except (ValueError, KeyError):
        record = None
    if record is None:
        IGNORED_MESSAGES.inc()
        return

    key, value, trade_time_ms = record
    TRADES_RECEIVED.labels(key).inc()
    BINANCE_LATENCY.observe(max(0.0, time.time() - trade_time_ms / 1000))
    while True:
        try:
            producer.produce(KAFKA_TOPIC, key=key, value=value, on_delivery=on_delivery)
            break
        except BufferError:
            # Local queue is full (Kafka slow or unreachable): wait for deliveries to drain it.
            producer.poll(0.1)
    producer.poll(0)


async def stream(producer: Producer) -> None:
    global heartbeat
    url = f"{BINANCE_WS_URL}?streams=" + "/".join(f"{s}@trade" for s in SYMBOLS)
    backoff = 1.0
    while True:
        try:
            async with connect(url) as ws:
                log.info("connected to %s", url)
                backoff = 1.0
                while True:
                    # A silent socket is treated as dead: BTCUSDT alone trades many times per second.
                    raw = await asyncio.wait_for(ws.recv(), timeout=IDLE_TIMEOUT_SECONDS)
                    heartbeat = time.monotonic()
                    publish(producer, raw)
        except (TimeoutError, WebSocketException, OSError) as exc:
            log.warning("websocket lost (%r), reconnecting in ~%.0fs", exc, backoff)
        RECONNECTS.inc()
        heartbeat = time.monotonic()
        await asyncio.sleep(backoff + random.uniform(0, backoff))
        backoff = min(backoff * 2, MAX_BACKOFF_SECONDS)


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


async def run(producer: Producer) -> None:
    task = asyncio.create_task(stream(producer))
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, task.cancel)
    try:
        await task
    except asyncio.CancelledError:
        pass
    finally:
        unflushed = producer.flush(10)
        log.info("shut down, %d messages left unflushed", unflushed)


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    conf = kafka_config()
    ensure_topic(conf)
    producer = Producer(
        {
            **conf,
            "client.id": "binance-producer",
            "enable.idempotence": True,
            "acks": "all",
            "linger.ms": 5,
            "compression.type": "lz4",
        }
    )
    server = ThreadingHTTPServer(("", HTTP_PORT), HealthHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    asyncio.run(run(producer))


if __name__ == "__main__":
    main()
