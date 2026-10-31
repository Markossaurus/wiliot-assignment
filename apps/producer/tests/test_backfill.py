import json

from backfill import backfill, to_stream_message
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
    total = backfill([("BTCUSDT", 100, 2599)], fetch, sent.append)
    ids = [json.loads(m)["t"] for m in sent]
    assert total == 2500 and ids == list(range(100, 2600))
    assert calls == [("BTCUSDT", 100, 1000), ("BTCUSDT", 1100, 1000), ("BTCUSDT", 2100, 500)]


def test_stops_at_the_call_budget_and_leaves_the_rest_for_the_next_run():
    fetch, calls = fake_exchange(first_id=1, count=10_000)
    sent = []
    assert backfill([("BTCUSDT", 1, 5000), ("ETHUSDT", 1, 10)], fetch, sent.append, max_calls=2) == 2000
    assert len(calls) == 2
