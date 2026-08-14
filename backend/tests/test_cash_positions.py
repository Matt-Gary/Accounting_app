"""
Cash positions.

A deposit carries no share count — the form does not even show a quantity field
for it. These tests pin the rule that the amount becomes the quantity, so a cash
balance is a real position rather than a row that evaluates to zero and vanishes
from the app.
"""

from datetime import date

import pytest

from service.portfolio.cost_basis import (
    OversellError,
    Transaction,
    effective_quantity,
    replay,
)
from service.portfolio.fx import RateTable

APPROX = 1e-9


def deposit(day, amount, currency='BRL', rate=None, fee=0.0, seq=''):
    return Transaction(
        transaction_date=date(2024, 5, day), transaction_type='deposit',
        quantity=0, original_amount=amount, fees_original=fee,
        original_currency=currency, exchange_rate=rate,
        id=seq or f'dep-{day}', created_at=seq,
    )


def withdraw(day, amount, currency='BRL', rate=None, fee=0.0, seq=''):
    return Transaction(
        transaction_date=date(2024, 5, day), transaction_type='withdrawal',
        quantity=0, original_amount=amount, fees_original=fee,
        original_currency=currency, exchange_rate=rate,
        id=seq or f'wd-{day}', created_at=seq,
    )


# ── The regression that started this ───────────────────────────────────────

def test_cash_deposit_without_quantity_is_not_lost():
    """Deriving invested as avg x qty made a quantity-less deposit vanish."""
    state, _ = replay([deposit(1, 1000.0)])
    assert state.quantity == pytest.approx(1000.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(1.0, abs=APPROX)
    assert state.invested_brl == pytest.approx(1000.0, abs=APPROX)


def test_multiple_deposits_accumulate():
    state, _ = replay([deposit(1, 1000.0), deposit(2, 500.0), deposit(3, 250.0)])
    assert state.invested_brl == pytest.approx(1750.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(1.0, abs=APPROX)


def test_withdrawal_reduces_the_balance():
    state, _ = replay([deposit(1, 1000.0), withdraw(2, 300.0)])
    assert state.quantity == pytest.approx(700.0, abs=APPROX)
    assert state.invested_brl == pytest.approx(700.0, abs=APPROX)
    # Same currency in and out, so no gain is manufactured.
    assert state.realized_brl == pytest.approx(0.0, abs=APPROX)


def test_withdrawing_more_than_held_raises():
    with pytest.raises(OversellError):
        replay([deposit(1, 100.0), withdraw(2, 500.0)])


def test_explicit_quantity_is_respected():
    """A caller that does supply a quantity keeps it."""
    tx = Transaction(
        transaction_date=date(2024, 5, 1), transaction_type='deposit',
        quantity=7, original_amount=1000.0, original_currency='BRL',
    )
    state, _ = replay([tx])
    assert state.quantity == pytest.approx(7.0, abs=APPROX)


def test_securities_are_unaffected_by_the_cash_rule():
    """A buy with no quantity must NOT have its amount treated as a share count."""
    assert effective_quantity('buy', 0, 1000.0) == 0.0
    assert effective_quantity('sell', 0, 1000.0) == 0.0
    assert effective_quantity('dividend', 0, 50.0) == 0.0


# ── Foreign-currency cash carries FX exposure ──────────────────────────────

def test_usd_cash_records_the_purchase_day_rate():
    state, _ = replay([deposit(1, 1000.0, currency='USD', rate=5.00)])
    assert state.quantity == pytest.approx(1000.0, abs=APPROX)
    assert state.avg_orig == pytest.approx(1.0, abs=APPROX)     # $1 per unit
    assert state.avg_brl == pytest.approx(5.00, abs=APPROX)     # R$5 per unit
    assert state.invested_brl == pytest.approx(5000.0, abs=APPROX)


def test_usd_cash_revalues_when_the_rate_moves():
    """
    $1000 deposited at 5.00 is worth R$6000 once the rate reaches 6.00. Valuing
    cash at cost would have frozen it at R$5000 and hidden the FX gain.
    """
    state, _ = replay([deposit(1, 1000.0, currency='USD', rate=5.00)])
    today = RateTable(usd_brl=6.00)
    value_brl = today.to_brl(state.quantity, 'USD')
    assert value_brl == pytest.approx(6000.0, abs=APPROX)
    assert value_brl - state.invested_brl == pytest.approx(1000.0, abs=APPROX)


def test_withdrawing_foreign_cash_realizes_the_fx_gain():
    state, trail = replay([
        deposit(1, 1000.0, currency='USD', rate=5.00),
        withdraw(10, 200.0, currency='USD', rate=6.00),
    ])
    # 200 units cost R$5 each, taken out at R$6 each.
    assert trail[1].realized_brl == pytest.approx(200.0, abs=APPROX)
    assert trail[1].realized_orig == pytest.approx(0.0, abs=APPROX)
    assert state.quantity == pytest.approx(800.0, abs=APPROX)
    # The average is untouched by a withdrawal, as for any sale.
    assert state.avg_brl == pytest.approx(5.00, abs=APPROX)


def test_deposits_at_different_rates_blend_the_brl_average():
    state, _ = replay([
        deposit(1, 1000.0, currency='USD', rate=5.00),
        deposit(2, 1000.0, currency='USD', rate=6.00),
    ])
    assert state.avg_orig == pytest.approx(1.0, abs=APPROX)
    assert state.avg_brl == pytest.approx(5.50, abs=APPROX)
    assert state.invested_brl == pytest.approx(11000.0, abs=APPROX)


# ── Fees on cash movements ─────────────────────────────────────────────────

def test_withdrawal_fee_shows_up_as_a_small_loss():
    """
    Quantity is the gross amount, so a fee on the way out lands as a realized
    loss equal to the fee rather than disappearing.
    """
    state, trail = replay([deposit(1, 1000.0), withdraw(2, 200.0, fee=1.0)])
    assert trail[1].quantity_delta == pytest.approx(-200.0, abs=APPROX)
    assert trail[1].proceeds_brl == pytest.approx(199.0, abs=APPROX)
    assert state.realized_brl == pytest.approx(-1.0, abs=APPROX)
    assert state.quantity == pytest.approx(800.0, abs=APPROX)


def test_audit_trail_covers_cash_movements():
    _, trail = replay([deposit(1, 1000.0), withdraw(2, 300.0)])
    assert len(trail) == 2
    assert trail[0].qty_before == 0.0
    assert trail[0].qty_after == pytest.approx(1000.0, abs=APPROX)
    assert trail[1].qty_after == pytest.approx(700.0, abs=APPROX)
