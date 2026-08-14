"""
Closed positions.

Selling out of a position must not erase it. Its realized gain is exactly what
the yearly tax report is built from, so the history has to stay reachable — the
UI previously dropped any asset whose quantity, cost and value were all zero,
which is every fully-sold position.
"""

import pytest

from service.investment_service import _compute_position
from service.portfolio.cost_basis import QTY_EPSILON


def row(day, kind, qty, amount, rate=5.0, fee=0.0, month=1):
    return {
        'id': f'{kind}-{month}-{day}',
        'created_at': f'2024-{month:02d}-{day:02d}T00:00:00',
        'transaction_date': f'2024-{month:02d}-{day:02d}',
        'transaction_type': kind,
        'quantity': qty,
        'original_amount': amount,
        'original_currency': 'USD',
        'exchange_rate': rate,
        'fees_original': fee,
    }


def sold_out():
    """Bought twice, sold the lot."""
    return [
        row(10, 'buy', 10, 1000.0, rate=5.0),
        row(20, 'buy', 10, 1400.0, rate=5.2, month=3),
        row(15, 'sell', 20, 3000.0, rate=5.5, month=8),
    ]


def test_position_is_flat_after_selling_out():
    pos = _compute_position(sold_out())
    assert pos['quantity'] <= QTY_EPSILON
    assert pos['total_invested_brl'] == pytest.approx(0.0, abs=1e-6)


def test_realized_gain_survives_the_position():
    """The number the tax report needs must outlive the holding."""
    pos = _compute_position(sold_out())
    cost_brl = 1000.0 * 5.0 + 1400.0 * 5.2
    proceeds_brl = 3000.0 * 5.5
    assert pos['realized_gains_brl'] == pytest.approx(
        proceeds_brl - cost_brl, abs=1e-6)
    assert pos['realized_gains_brl'] != 0


def test_realized_gain_available_in_both_currencies():
    pos = _compute_position(sold_out())
    assert pos['realized_gains_original'] == pytest.approx(
        3000.0 - 2400.0, abs=1e-6)


def test_audit_trail_survives_the_position():
    """Every transaction stays traceable after the position is gone."""
    pos = _compute_position(sold_out())
    assert len(pos['audit_trail']) == 3
    assert [s.transaction_type for s in pos['audit_trail']] == [
        'buy', 'buy', 'sell']


def test_closed_detection_needs_history():
    """
    Zero quantity alone is not 'closed' — an asset created but never traded
    also has zero, and the two are different things.
    """
    never_traded = _compute_position([])
    assert never_traded['quantity'] == 0
    assert never_traded['audit_trail'] == []

    closed = _compute_position(sold_out())
    assert closed['quantity'] <= QTY_EPSILON
    assert closed['audit_trail'] != []


def test_partial_sale_is_not_closed():
    pos = _compute_position([
        row(10, 'buy', 10, 1000.0),
        row(20, 'sell', 4, 500.0, month=6),
    ])
    assert pos['quantity'] == pytest.approx(6.0)


def test_reopened_position_is_not_closed():
    """Sold out then bought back — a live position again, not an archive entry."""
    pos = _compute_position(sold_out() + [
        row(1, 'buy', 5, 800.0, rate=5.6, month=11),
    ])
    assert pos['quantity'] == pytest.approx(5.0)
    # The earlier realized gain is untouched by the re-entry.
    cost_brl = 1000.0 * 5.0 + 1400.0 * 5.2
    assert pos['realized_gains_brl'] == pytest.approx(
        3000.0 * 5.5 - cost_brl, abs=1e-6)
    # And the new average reflects only the new purchase.
    assert pos['avg_cost_original'] == pytest.approx(160.0, abs=1e-6)


def test_dividends_survive_a_closed_position():
    txs = sold_out() + [{
        'id': 'div-1', 'created_at': '2024-05-01T00:00:00',
        'transaction_date': '2024-05-01', 'transaction_type': 'dividend',
        'quantity': 0, 'original_amount': 40.0, 'original_currency': 'USD',
        'exchange_rate': 5.3, 'withholding_tax_original': 6.0,
    }]
    pos = _compute_position(txs)
    assert pos['quantity'] <= QTY_EPSILON
    assert pos['dividends_original'] == pytest.approx(34.0, abs=1e-6)
    assert pos['dividends_brl'] == pytest.approx(34.0 * 5.3, abs=1e-6)
