import json
from datetime import datetime, timezone
from decimal import Decimal

import pytest

from consumer import to_row

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


def encode(**overrides) -> bytes:
    return json.dumps({**TRADE, **overrides}).encode()


def test_trade_maps_to_row():
    symbol, trade_id, price, quantity, trade_time = to_row(encode())

    assert symbol == "ETHUSDT"
    assert trade_id == 4456165857
    assert price == Decimal("2458.32000000")
    assert quantity == Decimal("0.00900000")
    assert trade_time == datetime(2026, 10, 21, 9, 48, 43, 962000, tzinfo=timezone.utc)


def test_decimals_are_exact():
    _, _, price, quantity, _ = to_row(encode(p="0.10000000", q="0.20000000"))

    assert price * quantity == Decimal("0.02")


@pytest.mark.parametrize(
    "overrides",
    [{"p": "NaN"}, {"q": "Infinity"}, {"p": "0"}, {"q": "-1"}, {"p": "abc"}, {"T": None}],
)
def test_invalid_values_are_rejected(overrides):
    with pytest.raises((ValueError, TypeError, ArithmeticError)):
        to_row(encode(**overrides))


def test_missing_field_is_rejected():
    trade = dict(TRADE)
    del trade["t"]

    with pytest.raises(KeyError):
        to_row(json.dumps(trade).encode())
