"""
Dividend metrics: trailing income and yield on cost.

Income figures are taken from the replay engine's audit trail, so they are net
of withholding by construction, and the date used is the booking date the user
entered (`transaction_date`) — not the ex-date, which this ledger does not know.
"""

from datetime import date

from dateutil.relativedelta import relativedelta

from .cost_basis import INCOME_TYPES


def trailing_income_brl(trail, as_of: date, months: int = 12) -> float:
    """
    Net income (dividends + coupons) booked in the window (as_of − months, as_of].

    The lower bound is exclusive: an event dated exactly twelve months ago has
    rolled out of the trailing year. Future-dated events never count.
    """
    return trailing_income(trail, as_of, months, 'income_brl')


def trailing_income(trail, as_of: date, months: int = 12,
                    attr: str = 'income_brl') -> float | None:
    """
    Same window as `trailing_income_brl`, over any income field of the trail
    (`income_orig` is in the replay's asset currency). None when a step in the
    window has no figure — a partial sum would understate the income.
    """
    cutoff = as_of - relativedelta(months=months)
    total = 0.0
    for step in trail:
        if (step.transaction_type in INCOME_TYPES
                and cutoff < step.transaction_date <= as_of):
            value = getattr(step, attr)
            if value is None:
                return None
            total += value
    return total


def yield_on_cost_pct(income_brl: float, invested_brl) -> float | None:
    """
    Trailing income as a percentage of invested capital.

    None, not zero, when there is no invested capital — a closed position has
    no yield rather than a 0% yield.
    """
    if not invested_brl or invested_brl <= 0:
        return None
    return income_brl / invested_brl * 100
