import 'package:flutter_test/flutter_test.dart';
import 'package:suas_financas/utils/asset_display.dart';

/// The reported case: $1,900 deposited at 5.11, viewed later at 5.1873.
const depositUsd = 1900.00;
const rateAtDeposit = 5.11;
const rateToday = 5.1873;
const investedBrl = depositUsd * rateAtDeposit; // 9709.00

void main() {
  group('USD view returns the exact USD figure', () {
    test('cost is not round-tripped through today rate', () {
      final r = pickAmount(
        displayCurrency: 'USD',
        brl: investedBrl,
        usd: depositUsd,
        usdBrlRate: rateToday,
      );
      expect(r.value, closeTo(1900.00, 1e-9));
      expect(r.currency, 'USD');
      expect(r.exact, isTrue);
    });

    test('the old behaviour is what we are protecting against', () {
      // Reproduce the bug so the regression is visible in the test itself:
      // dividing the historical BRL cost by today's rate loses $28.31.
      const broken = investedBrl / rateToday;
      expect(broken, closeTo(1871.69, 0.01));

      final fixed = pickAmount(
        displayCurrency: 'USD',
        brl: investedBrl,
        usd: depositUsd,
        usdBrlRate: rateToday,
      ).value;
      expect(fixed, closeTo(1900.00, 1e-9));
      expect(fixed - broken, closeTo(28.31, 0.01));
    });

    test('a BRL purchase of any asset shows its USD cost, not its BRL one', () {
      // R$ 550 000 paid when USD/BRL closed at 5.50: the backend sends $100 000.
      final r = pickAmount(
        displayCurrency: 'USD',
        brl: 550000.0,
        usd: 100000.0,
        usdBrlRate: rateToday,
      );
      expect(r.value, 100000.0);
      expect(r.exact, isTrue);
    });
  });

  group('BRL view keeps the historical rate', () {
    test('cost stays at the rate it was booked at', () {
      final r = pickAmount(
        displayCurrency: 'BRL',
        brl: investedBrl, usd: depositUsd, usdBrlRate: rateToday,
      );
      expect(r.value, closeTo(9709.00, 1e-9));
      expect(r.currency, 'BRL');
      expect(r.exact, isTrue);
    });

    test('the FX move is real and visible in BRL', () {
      final invested = pickAmount(
        displayCurrency: 'BRL',
        brl: investedBrl, usd: depositUsd, usdBrlRate: rateToday,
      ).value;
      final value = pickAmount(
        displayCurrency: 'BRL',
        brl: depositUsd * rateToday, usd: depositUsd,
        usdBrlRate: rateToday,
      ).value;
      expect(value - invested, closeTo(146.87, 0.05));
    });
  });

  group('missing USD figure', () {
    test('falls back to today rate and is flagged inexact', () {
      final r = pickAmount(
        displayCurrency: 'USD',
        brl: 6000.0, usd: null, usdBrlRate: 5.0,
      );
      expect(r.value, closeTo(1200.0, 1e-9));
      expect(r.currency, 'USD');
      expect(r.exact, isFalse,
          reason: 'converted from BRL, not read from a USD field');
    });

    test('a zero rate does not divide by zero or fabricate a number', () {
      final r = pickAmount(
        displayCurrency: 'USD',
        brl: 6000.0, usd: null, usdBrlRate: 0,
      );
      expect(r.value.isFinite, isTrue);
      expect(r.value, 6000.0);
      expect(r.currency, 'BRL',
          reason: 'caller must see it did not get USD');
    });

    test('negative rate is treated as unavailable', () {
      final r = pickAmount(
        displayCurrency: 'USD',
        brl: 6000.0, usd: null, usdBrlRate: -1,
      );
      expect(r.currency, 'BRL');
    });

    test('the BRL view never needs it', () {
      final r = pickAmount(
        displayCurrency: 'BRL',
        brl: 6000.0, usd: null, usdBrlRate: 5.0,
      );
      expect(r, const DisplayAmount(
          value: 6000.0, currency: 'BRL', exact: true));
    });
  });

  group('per-asset currency: EUR stays EUR in the foreign view', () {
    test('foreign view is USD for BRL and USD assets', () {
      expect(assetDisplayCurrency('USD', 'USD'), 'USD');
      expect(assetDisplayCurrency('USD', 'BRL'), 'USD');
    });

    test('foreign view keeps a third currency', () {
      expect(assetDisplayCurrency('USD', 'EUR'), 'EUR');
      expect(assetDisplayCurrency('USD', 'PLN'), 'PLN');
    });

    test('BRL view is BRL for every asset', () {
      expect(assetDisplayCurrency('BRL', 'EUR'), 'BRL');
      expect(assetDisplayCurrency('BRL', 'USD'), 'BRL');
    });

    test('EUR asset in USD view shows its exact EUR figure', () {
      final r = pickAssetAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, usd: 1100.0, native: 1000.0, usdBrlRate: 5.0,
      );
      expect(r, const DisplayAmount(
          value: 1000.0, currency: 'EUR', exact: true));
    });

    test('EUR asset in BRL view shows BRL', () {
      final r = pickAssetAmount(
        displayCurrency: 'BRL', nativeCurrency: 'EUR',
        brl: 6000.0, usd: 1100.0, native: 1000.0, usdBrlRate: 5.0,
      );
      expect(r.currency, 'BRL');
      expect(r.value, 6000.0);
    });

    test('BRL asset in USD view shows its USD figure, not the native one', () {
      final r = pickAssetAmount(
        displayCurrency: 'USD', nativeCurrency: 'BRL',
        brl: 5500.0, usd: 1000.0, native: 5500.0, usdBrlRate: 5.0,
      );
      expect(r, const DisplayAmount(
          value: 1000.0, currency: 'USD', exact: true));
    });

    test('unavailable EUR figure degrades to USD, labelled as such', () {
      final r = pickAssetAmount(
        displayCurrency: 'USD', nativeCurrency: 'EUR',
        brl: 6000.0, usd: 1100.0, native: 0.0, nativeAvailable: false,
        usdBrlRate: 5.0,
      );
      expect(r.currency, 'USD');
      expect(r.value, 1100.0);
    });
  });
}
