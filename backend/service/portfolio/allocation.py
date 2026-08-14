"""
Concentration — what share of the active portfolio each position represents.

The base is deliberately narrow: only what is actually working at the broker.
Physical cash, bank balances and bonds are reserves; folding them in would
understate how concentrated the live portfolio really is, which is the opposite
of what a concentration measure is for.
"""

from .categories import ALLOCATION_CATEGORIES  # noqa: F401  (re-exported)


def allocation_base(assets, categories=ALLOCATION_CATEGORIES) -> float:
    """
    Denominator for every share figure.

    Positions whose price could not be fetched are excluded rather than counted
    as zero — treating an unpriced holding as worthless would silently inflate
    every other position's share.
    """
    return sum(
        float(a.get('current_value_brl') or 0)
        for a in assets
        if a.get('category') in categories and a.get('value_available')
    )


def is_complete(assets, categories=ALLOCATION_CATEGORIES) -> bool:
    """False when a position that belongs in the base could not be valued."""
    return not any(
        a.get('category') in categories and not a.get('value_available')
        for a in assets
    )


def position_share(asset, base: float,
                   categories=ALLOCATION_CATEGORIES) -> float | None:
    """
    Share of the active portfolio, or None when it does not apply.

    None means "no share to show" — the asset is a reserve, or its value is
    unknown. It never means zero.

    The figure is a ratio, so it is identical whichever currency the caller
    displays; there is no per-currency variant to keep in sync.
    """
    if asset.get('category') not in categories:
        return None
    if not asset.get('value_available') or base <= 0:
        return None
    return float(asset.get('current_value_brl') or 0) / base * 100


def annotate(assets, categories=ALLOCATION_CATEGORIES) -> tuple[float, bool]:
    """
    Add `in_allocation_base` and `portfolio_pct` to each asset in place.

    Returns ``(base, complete)``. Mutates because the caller is building one
    response dict and copying every asset again would be wasteful.
    """
    base = allocation_base(assets, categories)
    for asset in assets:
        asset['in_allocation_base'] = asset.get('category') in categories
        asset['portfolio_pct'] = position_share(asset, base, categories)
    return base, is_complete(assets, categories)


UNKNOWN_GROUP = 'unknown'


def group_totals(assets, key: str,
                 categories=ALLOCATION_CATEGORIES) -> dict:
    """
    Aggregate the allocation base along one labelling axis
    (``native_currency``, ``sector``, ``country``).

    Only priced positions inside the base are counted — the same exclusions as
    `allocation_base`, so group values always sum to the base. Positions with
    no label land in the ``'unknown'`` bucket rather than polluting a real
    group. ``pct`` is None whenever the base is incomplete: a share computed on
    a partial denominator would mislead.
    """
    base = allocation_base(assets, categories)
    complete = is_complete(assets, categories)
    groups: dict = {}
    for a in assets:
        if a.get('category') not in categories or not a.get('value_available'):
            continue
        label = a.get(key) or UNKNOWN_GROUP
        entry = groups.setdefault(label, {'value_brl': 0.0, 'pct': None})
        entry['value_brl'] += float(a.get('current_value_brl') or 0)
    if complete and base > 0:
        for entry in groups.values():
            entry['pct'] = entry['value_brl'] / base * 100
    return groups


def group_breaches(groups: dict, max_pct: float) -> list:
    """
    Groups above the concentration threshold, largest first.

    The ``'unknown'`` bucket never breaches — missing data is not evidence of
    concentration — and neither does a group whose share could not be computed.
    """
    over = [
        {'group': name, **entry}
        for name, entry in groups.items()
        if name != UNKNOWN_GROUP
        and entry.get('pct') is not None
        and entry['pct'] > max_pct
    ]
    return sorted(over, key=lambda g: g['pct'], reverse=True)


def concentration_breaches(assets, max_position_pct: float) -> list:
    """
    Positions above the concentration threshold, largest first.

    Kept separate from the share calculation so the threshold can come from
    per-family settings later without touching how shares are computed.
    """
    over = [
        a for a in assets
        if a.get('portfolio_pct') is not None
        and a['portfolio_pct'] > max_position_pct
    ]
    return sorted(over, key=lambda a: a['portfolio_pct'], reverse=True)
