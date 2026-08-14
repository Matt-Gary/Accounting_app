"""
Per-family investment settings — validation of the concentration thresholds.

The table row is created lazily; until a family saves anything, DEFAULT_SETTINGS
is what the API serves. `sanitize_settings` is the only gate between the client
payload and the upsert, so everything the database would accept but the domain
would not (0% thresholds, negative reminders, stray keys) must die here.
"""

import pytest

from service.portfolio.settings import DEFAULT_SETTINGS, sanitize_settings


def test_defaults_match_the_migration():
    assert DEFAULT_SETTINGS == {
        'max_position_pct': 20,
        'max_sector_pct': 25,
        'max_currency_pct': 60,
        'max_country_pct': 60,
        'report_reminder_days': 7,
    }


def test_valid_subset_passes_through():
    assert sanitize_settings({'max_position_pct': 15.5}) == {
        'max_position_pct': 15.5}


def test_full_payload_passes_through():
    data = {'max_position_pct': 10, 'max_sector_pct': 20,
            'max_currency_pct': 50, 'max_country_pct': 50,
            'report_reminder_days': 3}
    assert sanitize_settings(data) == data


def test_unknown_keys_are_rejected():
    with pytest.raises(ValueError):
        sanitize_settings({'max_position_pct': 15, 'family_id': 'spoofed'})


def test_empty_update_is_rejected():
    with pytest.raises(ValueError):
        sanitize_settings({})


@pytest.mark.parametrize('bad', [0, -5, 101, 1000])
def test_thresholds_outside_zero_exclusive_to_hundred_are_rejected(bad):
    with pytest.raises(ValueError):
        sanitize_settings({'max_sector_pct': bad})


def test_a_hundred_percent_threshold_is_allowed():
    """100% means 'never warn' — a legitimate way to mute one dimension."""
    assert sanitize_settings({'max_sector_pct': 100}) == {'max_sector_pct': 100}


@pytest.mark.parametrize('bad', ['20', None, True])
def test_non_numeric_threshold_is_rejected(bad):
    """Booleans are ints in Python; a client sending true must still get a 400."""
    with pytest.raises(ValueError):
        sanitize_settings({'max_position_pct': bad})


def test_reminder_days_zero_is_allowed():
    assert sanitize_settings({'report_reminder_days': 0}) == {
        'report_reminder_days': 0}


@pytest.mark.parametrize('bad', [-1, 1.5, '7', True, None])
def test_reminder_days_must_be_a_whole_non_negative_number(bad):
    with pytest.raises(ValueError):
        sanitize_settings({'report_reminder_days': bad})
