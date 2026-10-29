import json

import pytest

from producer import setting, to_kafka_record

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


def test_setting_prefers_the_mounted_file(tmp_path, monkeypatch):
    path = tmp_path / "bootstrap-brokers"
    path.write_text("b-1:9098,b-2:9098\n")
    monkeypatch.setenv("KAFKA_BOOTSTRAP_SERVERS_FILE", str(path))
    monkeypatch.setenv("KAFKA_BOOTSTRAP_SERVERS", "ignored:9092")

    assert setting("KAFKA_BOOTSTRAP_SERVERS") == "b-1:9098,b-2:9098"


def test_setting_falls_back_to_the_environment(monkeypatch):
    monkeypatch.delenv("KAFKA_BOOTSTRAP_SERVERS_FILE", raising=False)
    monkeypatch.setenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")

    assert setting("KAFKA_BOOTSTRAP_SERVERS") == "kafka:9092"


def test_missing_setting_is_an_error(monkeypatch):
    monkeypatch.delenv("KAFKA_BOOTSTRAP_SERVERS_FILE", raising=False)
    monkeypatch.delenv("KAFKA_BOOTSTRAP_SERVERS", raising=False)

    with pytest.raises(KeyError):
        setting("KAFKA_BOOTSTRAP_SERVERS")
