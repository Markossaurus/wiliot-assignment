import json

from producer import to_kafka_record

TRADE = {
    "e": "trade",
    "E": 1792576123962,
    "s": "ETHUSDT",
    "t": 4456165857,
    "p": "2458.32000000",
    "q": "0.00900000",
    "T": 1792576123962,
    "m": False,
}


def test_combined_stream_envelope_is_unwrapped():
    raw = json.dumps({"stream": "ethusdt@trade", "data": TRADE})

    key, value, trade_time_ms = to_kafka_record(raw)

    assert key == "ETHUSDT"
    assert json.loads(value) == TRADE
    assert trade_time_ms == 1792576123962


def test_unwrapped_trade_is_accepted():
    key, _, _ = to_kafka_record(json.dumps(TRADE))

    assert key == "ETHUSDT"


def test_price_and_quantity_strings_are_preserved_exactly():
    _, value, _ = to_kafka_record(json.dumps({"data": TRADE}))

    assert json.loads(value)["p"] == "2458.32000000"
    assert json.loads(value)["q"] == "0.00900000"


def test_non_trade_messages_are_ignored():
    assert to_kafka_record(json.dumps({"result": None, "id": 1})) is None
    assert to_kafka_record(json.dumps({"data": {"e": "aggTrade"}})) is None
