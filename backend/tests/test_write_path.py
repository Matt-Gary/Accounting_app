"""
Write-path tests: the backend derives `brl_amount`, the client never supplies it.

These cover the formula shared by the storage layer and the replay engine, so a
stored row and a recomputed position can never disagree.
"""

import pytest

from service.portfolio.cost_basis import brl_amount_for, net_amount_original
from service.portfolio.fx import MissingRateError


# ── RFB fee treatment ──────────────────────────────────────────────────────

def test_buy_adds_fee_before_conversion():
    brl, rate = brl_amount_for('buy', 200.0, 1.0, 'USD', 5.0)
    assert rate == 5.0
    assert brl == pytest.approx(1005.0)      # (200 + 1) x 5


def test_sell_deducts_fee_before_conversion():
    brl, _ = brl_amount_for('sell', 200.0, 1.0, 'USD', 5.0)
    assert brl == pytest.approx(995.0)       # (200 - 1) x 5


def test_deposit_behaves_like_a_buy():
    assert net_amount_original('deposit', 200.0, 1.0) == pytest.approx(201.0)


def test_withdrawal_behaves_like_a_sell():
    assert net_amount_original('withdrawal', 200.0, 1.0) == pytest.approx(199.0)


def test_income_ignores_fees():
    assert net_amount_original('dividend', 50.0, 3.0) == pytest.approx(50.0)


def test_zero_fee_leaves_amount_untouched():
    brl, _ = brl_amount_for('buy', 200.0, 0.0, 'USD', 5.0)
    assert brl == pytest.approx(1000.0)


# ── Round trip: buy then sell the same size at the same price ──────────────

def test_round_trip_costs_exactly_two_fees():
    """
    Buying and immediately selling at an unchanged price should lose precisely
    the two commissions — this is the arithmetic the old 'always subtract'
    behaviour got wrong by reporting a phantom gain.
    """
    bought, _ = brl_amount_for('buy', 200.0, 1.0, 'USD', 5.0)
    sold, _ = brl_amount_for('sell', 200.0, 1.0, 'USD', 5.0)
    assert sold - bought == pytest.approx(-10.0)      # 2 x $1 x 5


# ── BRL and missing rates ──────────────────────────────────────────────────

def test_brl_transaction_uses_rate_one():
    brl, rate = brl_amount_for('buy', 200.0, 1.0, 'BRL', None)
    assert rate == 1.0
    assert brl == pytest.approx(201.0)


def test_missing_rate_raises_on_write():
    with pytest.raises(MissingRateError):
        brl_amount_for('buy', 200.0, 0.0, 'USD', None)


def test_zero_rate_raises_on_write():
    with pytest.raises(MissingRateError):
        brl_amount_for('buy', 200.0, 0.0, 'USD', 0)
