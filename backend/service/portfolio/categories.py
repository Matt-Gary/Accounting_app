"""
Asset categories — one definition, used everywhere.

These were previously spread across three module-level constants that had to be
kept in sync by hand, and they drifted: `etf` was added to the database CHECK
constraint but not to the display order, which would raise KeyError on the first
ETF, and not to the priced set, which would have valued it at cost instead of
fetching its quote. `test_categories.py` now enforces the invariants.
"""

# Display order: risk assets, then liquidity, then reserves.
CATEGORY_ORDER = [
    'stock',
    'etf',
    'crypto',
    'bond',
    'cash_equivalent',
    'cash_broker',
    'cash_home',
    'cash_bank',
]

# Carry a ticker and are valued from a live quote.
PRICED_CATEGORIES = frozenset({'stock', 'etf', 'crypto', 'cash_equivalent'})

# Held as N units of their own currency at a price of 1.0.
CASH_CATEGORIES = frozenset({'cash_broker', 'cash_home', 'cash_bank'})

# Counted in the concentration base: capital actively deployed as investments.
#
# `cash_equivalent` belongs here for the same reason `cash_broker` does — a
# short-duration treasury ETF held as dry powder is broker cash that happens to
# earn yield. Excluding it would make the portfolio look more concentrated than
# it is, because the buying power parked there would vanish from the total.
#
# `crypto` is deployed capital too, merely held at a different venue. Leaving it
# out gave the odd result of a market-priced position with no portfolio share
# and no concentration check.
ALLOCATION_CATEGORIES = frozenset(
    {'stock', 'etf', 'crypto', 'cash_equivalent', 'cash_broker'})

# Top-level UI split: what trades on a stock exchange vs everything else.
# Crypto is deployed capital (it IS in the allocation base) but a different
# venue, so it sits off-exchange. Every category must appear in exactly one
# group — a category in none would vanish from the screen, in two it would be
# double-counted in the section totals (enforced by test_categories.py).
GROUPS = {
    'exchange': frozenset({'stock', 'etf'}),
    'off_exchange': frozenset({'crypto', 'bond', 'cash_equivalent',
                               'cash_broker', 'cash_home', 'cash_bank'}),
}


def group_of(category: str) -> str | None:
    """The UI group a category belongs to, or None for an unknown category."""
    for name, members in GROUPS.items():
        if category in members:
            return name
    return None


# Portuguese labels for the Excel report. The app localises its own.
CATEGORY_LABELS = {
    'stock': 'Ações',
    'etf': 'ETFs',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_equivalent': 'Caixa Equivalente',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
}
