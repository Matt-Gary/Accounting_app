"""
Per-family investment settings.

The `investment_settings` row is created lazily: until a family saves anything,
`DEFAULT_SETTINGS` is what the API serves. `sanitize_settings` is the single
gate between a client payload and the upsert — anything the database would
accept but the domain would not (0% thresholds, negative reminders, stray or
spoofed keys) must be rejected here with a ValueError so the route can answer
400 instead of persisting nonsense.
"""

# Mirrors the column defaults in migrations/portfolio_analytics_stage_a.sql.
DEFAULT_SETTINGS = {
    'max_position_pct': 20,
    'max_sector_pct': 25,
    'max_currency_pct': 60,
    'max_country_pct': 60,
    'report_reminder_days': 7,
}

_PCT_KEYS = frozenset(
    {'max_position_pct', 'max_sector_pct', 'max_currency_pct',
     'max_country_pct'})


def _is_number(value) -> bool:
    # bool is an int subclass; a client sending `true` must not become 1%.
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def sanitize_settings(data: dict) -> dict:
    """Validate a partial update; returns only the keys that were provided."""
    if not data:
        raise ValueError('No settings provided.')
    unknown = set(data) - set(DEFAULT_SETTINGS)
    if unknown:
        raise ValueError(
            f'Unknown settings: {sorted(unknown)}. '
            f'Allowed: {sorted(DEFAULT_SETTINGS)}.')
    clean = {}
    for key, value in data.items():
        if key in _PCT_KEYS:
            if not _is_number(value) or not 0 < value <= 100:
                raise ValueError(
                    f'{key} must be a number in (0, 100], got {value!r}.')
            clean[key] = value
        else:  # report_reminder_days
            if not _is_number(value) or value != int(value) or value < 0:
                raise ValueError(
                    f'{key} must be a whole number >= 0, got {value!r}.')
            clean[key] = int(value)
    return clean
