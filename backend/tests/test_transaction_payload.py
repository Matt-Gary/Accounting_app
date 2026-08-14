"""
Tests for the row the backend actually stores.

`_build_transaction_payload` is the single write path for both creating and
editing a transaction, so it decides the authoritative `brl_amount` and the
derived cash quantity.
"""

import pytest

from service.investment_service import _build_transaction_payload
from service.portfolio.fx import MissingRateError


def base(**over):
    data = {
        'transaction_type': 'buy',
        'transaction_date': '2024-05-01',
        'original_amount': 200.0,
        'original_currency': 'USD',
        'exchange_rate': 5.0,
        'quantity': 2,
    }
    data.update(over)
    return data


# ── brl_amount is derived, never trusted from the client ───────────────────

def test_client_supplied_brl_amount_is_ignored():
    payload = _build_transaction_payload(
        base(fees_original=1.0, brl_amount=999999.0))
    assert payload['brl_amount'] == pytest.approx(1005.0)   # (200 + 1) x 5


def test_sell_deducts_the_fee():
    payload = _build_transaction_payload(
        base(transaction_type='sell', fees_original=1.0))
    assert payload['brl_amount'] == pytest.approx(995.0)


def test_fee_is_stored_in_both_units():
    payload = _build_transaction_payload(base(fees_original=1.0))
    assert payload['fees_original'] == pytest.approx(1.0)
    assert payload['fees_brl'] == pytest.approx(5.0)


def test_missing_rate_raises_on_write():
    with pytest.raises(MissingRateError):
        _build_transaction_payload(base(exchange_rate=None))


def test_brl_transaction_needs_no_rate():
    payload = _build_transaction_payload(
        base(original_currency='BRL', exchange_rate=None, fees_original=1.0))
    assert payload['brl_amount'] == pytest.approx(201.0)
    assert payload['fees_brl'] == pytest.approx(1.0)


# ── Legacy clients that only sent the converted fee ────────────────────────

def test_legacy_fees_brl_is_converted_back():
    payload = _build_transaction_payload(base(fees_brl=5.0))
    assert payload['fees_original'] == pytest.approx(1.0)
    assert payload['brl_amount'] == pytest.approx(1005.0)


def test_fees_original_wins_over_fees_brl():
    payload = _build_transaction_payload(base(fees_original=2.0, fees_brl=5.0))
    assert payload['fees_original'] == pytest.approx(2.0)
    assert payload['fees_brl'] == pytest.approx(10.0)


# ── Cash quantity derivation ───────────────────────────────────────────────

def test_cash_deposit_gets_quantity_from_amount():
    payload = _build_transaction_payload(base(
        transaction_type='deposit', quantity=0,
        original_amount=1000.0, original_currency='BRL', exchange_rate=None))
    assert payload['quantity'] == pytest.approx(1000.0)


def test_cash_withdrawal_gets_quantity_from_amount():
    payload = _build_transaction_payload(base(
        transaction_type='withdrawal', quantity=0,
        original_amount=300.0, original_currency='BRL', exchange_rate=None))
    assert payload['quantity'] == pytest.approx(300.0)


def test_editing_a_cash_amount_rederives_the_quantity():
    """
    The form sends quantity 0 for cash, so changing the amount on an edit must
    move the quantity with it rather than leaving the old figure in place.
    """
    first = _build_transaction_payload(base(
        transaction_type='deposit', quantity=0, original_amount=1000.0,
        original_currency='BRL', exchange_rate=None))
    edited = _build_transaction_payload(base(
        transaction_type='deposit', quantity=0, original_amount=250.0,
        original_currency='BRL', exchange_rate=None))
    assert first['quantity'] == pytest.approx(1000.0)
    assert edited['quantity'] == pytest.approx(250.0)


def test_buy_quantity_is_not_derived_from_amount():
    payload = _build_transaction_payload(base(quantity=2))
    assert payload['quantity'] == pytest.approx(2.0)


# ── Optional fields ────────────────────────────────────────────────────────

def test_cleared_note_is_stored_as_null():
    payload = _build_transaction_payload(base(notes=None))
    assert payload['notes'] is None


def test_withholding_defaults_to_zero():
    payload = _build_transaction_payload(base())
    assert payload['withholding_tax_original'] == 0.0
    assert payload['fx_spread_original'] == 0.0


def test_dividend_keeps_gross_amount():
    payload = _build_transaction_payload(base(
        transaction_type='dividend', quantity=0,
        original_amount=50.0, withholding_tax_original=7.5))
    assert payload['original_amount'] == pytest.approx(50.0)
    assert payload['withholding_tax_original'] == pytest.approx(7.5)
    assert payload['brl_amount'] == pytest.approx(250.0)     # gross x 5


def test_coupon_is_income_like_a_dividend():
    """Same contract as a dividend: gross in the row, fee never applied."""
    payload = _build_transaction_payload(base(
        transaction_type='coupon', quantity=0,
        original_amount=80.0, fees_original=1.0,
        withholding_tax_original=12.0))
    assert payload['brl_amount'] == pytest.approx(400.0)     # gross x 5
    assert payload['withholding_tax_original'] == pytest.approx(12.0)
