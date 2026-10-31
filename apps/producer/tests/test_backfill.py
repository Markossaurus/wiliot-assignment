import io
import json
import threading
import urllib.error

import backfill as b
from backfill import Exchange, backfill, new_watermarks, to_stream_message
from producer import to_kafka_record

REST_TRADE = {
    "id": 4456165857,
    "price": "2458.32000000",
    "qty": "0.00900000",
    "quoteQty": "22.12488",
    "time": 1792576123962,
    "isBuyerMaker": False,
    "isBestMatch": True,
}


def test_rest_trade_becomes_the_same_record_the_stream_produces():
    key, value, trade_time_ms = to_kafka_record(to_stream_message("ETHUSDT", REST_TRADE))
    assert key == "ETHUSDT"
    assert trade_time_ms == 1792576123962
    assert json.loads(value) == {
        "e": "trade",
        "E": 1792576123962,
        "s": "ETHUSDT",
        "t": 4456165857,
        "p": "2458.32000000",
        "q": "0.00900000",
        "T": 1792576123962,
        "m": False,
    }


def fake_exchange(first_id, count):
    """Pages of consecutive trades, like historicalTrades with fromId and limit."""
    calls = []

    def fetch(symbol, from_id, limit):
        calls.append((symbol, from_id, limit))
        end = min(from_id + limit, first_id + count)
        return [dict(REST_TRADE, id=i) for i in range(from_id, end)]

    return fetch, calls


def test_each_missing_id_is_sent_once_across_pages():
    fetch, calls = fake_exchange(first_id=1, count=10_000)
    sent = []
    total = backfill([("BTCUSDT", 100, 2599)], fetch, sent.append, threading.Event())
    ids = [json.loads(m)["t"] for m in sent]
    assert total == 2500 and ids == list(range(100, 2600))
    assert calls == [("BTCUSDT", 100, 1000), ("BTCUSDT", 1100, 1000), ("BTCUSDT", 2100, 500)]


def test_stops_when_binance_rate_limits_and_keeps_what_it_sent():
    fetch, _ = fake_exchange(first_id=1, count=10_000)

    def limited(symbol, from_id, limit):
        if from_id > 1000:
            raise urllib.error.HTTPError("url", 429, "Too Many Requests", {}, None)
        return fetch(symbol, from_id, limit)

    assert backfill([("BTCUSDT", 1, 5000)], limited, lambda _: None, threading.Event()) == 1000


def test_stops_after_the_current_page_on_sigterm():
    fetch, calls = fake_exchange(first_id=1, count=10_000)
    stopping = threading.Event()

    def fetch_then_sigterm(symbol, from_id, limit):
        stopping.set()
        return fetch(symbol, from_id, limit)

    sent = []
    assert backfill([("BTCUSDT", 1, 5000), ("ETHUSDT", 1, 10)], fetch_then_sigterm, sent.append, stopping) == 1000
    assert len(calls) == 1 and len(sent) == 1000


def test_watermark_stops_before_the_first_gap_even_an_unsettled_one():
    gaps = [("BTCUSDT", 1501, 1799, True), ("BTCUSDT", 2001, 2001, True), ("ETHUSDT", 90, 90, False)]
    latest = {"BTCUSDT": 2100, "ETHUSDT": 95, "SOLUSDT": 7000}
    assert new_watermarks(latest, gaps) == {"BTCUSDT": 1500, "ETHUSDT": 89, "SOLUSDT": 7000}


class FakeResponse(io.BytesIO):
    def __init__(self, body, used_weight):
        super().__init__(json.dumps(body).encode())
        self.headers = {"x-mbx-used-weight-1m": str(used_weight)}


def test_waits_for_the_next_minute_before_going_over_the_weight_budget():
    weights = iter([b.WEIGHT_BUDGET - 2 * b.CALL_WEIGHT, b.WEIGHT_BUDGET - 10, b.CALL_WEIGHT])
    slept = []
    exchange = Exchange(
        urlopen=lambda url, timeout: FakeResponse([REST_TRADE], next(weights)),
        sleep=slept.append,
        now=lambda: 1_800_000_020.5,
    )
    for _ in range(3):
        exchange.fetch("BTCUSDT", 1, 1)
    # Only the third call would go over: it waits out the 39.5 s left in the minute, plus a second.
    assert slept == [40.5]
