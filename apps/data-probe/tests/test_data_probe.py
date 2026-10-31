from decimal import Decimal

from data_probe import metric_data, missing_trades, setting


def by_name(data):
    return {d["MetricName"]: d for d in data}


def test_all_metrics_are_published_as_floats_with_units():
    data = by_name(metric_data(Decimal("1.5"), 120, Decimal("0.42"), 0))
    assert set(data) == {"TradesIngested", "MissingTrades", "SecondsSinceLastTrade", "IngestLatencyP99"}
    assert data["IngestLatencyP99"] == {"MetricName": "IngestLatencyP99", "Value": 0.42, "Unit": "Seconds"}
    assert all(isinstance(d["Value"], float) for d in data.values())


def test_quiet_minute_publishes_staleness_but_no_latency():
    data = by_name(metric_data(Decimal("75"), 0, None, 0))
    assert "IngestLatencyP99" not in data
    assert data["SecondsSinceLastTrade"]["Value"] == 75.0


def test_empty_table_publishes_only_counts():
    assert set(by_name(metric_data(None, 0, None, 0))) == {"TradesIngested", "MissingTrades"}


def test_setting_prefers_the_mounted_file(tmp_path, monkeypatch):
    path = tmp_path / "db-host"
    path.write_text("db.example\n")
    monkeypatch.setenv("PGHOST_FILE", str(path))
    monkeypatch.setenv("PGHOST", "ignored")
    assert setting("PGHOST") == "db.example"


def test_missing_trades_counts_every_id_in_every_range():
    assert missing_trades([("ETHUSDT", 3000, 3001), ("BTCUSDT", 10, 10)]) == 3
    assert missing_trades([]) == 0
