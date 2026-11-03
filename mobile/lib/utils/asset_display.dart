/// Choosing which representation of a figure to show.
///
/// The BRL/USD toggle decides the currency of every figure, whatever currency
/// the asset is quoted in or each trade was paid in. The backend computes both
/// representations exactly: BRL accumulated at each trade's own rate, and USD
/// accumulated at each trade's own USD/BRL close. Present-day values (a quote,
/// a market value) are converted at today's rate, which is correct for them.
///
/// Dividing a historical BRL figure by today's rate does NOT reconstruct the
/// USD one — it re-prices the past at present-day FX. On a $1,900 deposit made
/// at 5.11 and viewed at 5.1873 that produced a $28.31 gain out of thin air,
/// present in neither currency. This module exists so that mistake has one
/// place to be made and one place to be tested.
library;

/// A figure ready to render, with the currency it is expressed in.
class DisplayAmount {
  final double value;
  final String currency;

  /// True when the value came straight from a field denominated in
  /// [currency]. False when it had to be converted at today's rate, which
  /// makes it an approximation of a past amount.
  final bool exact;

  const DisplayAmount({
    required this.value,
    required this.currency,
    required this.exact,
  });

  @override
  String toString() =>
      'DisplayAmount($value $currency, exact: $exact)';

  @override
  bool operator ==(Object other) =>
      other is DisplayAmount &&
      other.value == value &&
      other.currency == currency &&
      other.exact == exact;

  @override
  int get hashCode => Object.hash(value, currency, exact);
}

/// Picks the representation that matches [displayCurrency].
///
/// * BRL → [brl], exact.
/// * USD with a [usd] figure → that figure, exact.
/// * USD without one (the backend lacked a trade-date close) → [brl] at
///   [usdBrlRate], marked inexact so it cannot pass for the real figure.
///
/// A non-positive [usdBrlRate] means the rate is unavailable, so no conversion
/// is invented — the BRL figure is returned as BRL and the caller can see the
/// currency it actually got.
DisplayAmount pickAmount({
  required String displayCurrency,
  required double brl,
  required double? usd,
  required double usdBrlRate,
}) {
  if (displayCurrency == 'USD') {
    if (usd != null) {
      return DisplayAmount(value: usd, currency: 'USD', exact: true);
    }
    if (usdBrlRate > 0) {
      return DisplayAmount(
          value: brl / usdBrlRate, currency: 'USD', exact: false);
    }
  }
  // BRL view, or a USD view with no rate: hand back what we have.
  return DisplayAmount(value: brl, currency: 'BRL', exact: true);
}

/// The currency one asset's own figures are shown in.
///
/// The toggle has two states, BRL and foreign. Foreign is USD for BRL and USD
/// assets, but an asset in a third currency (EUR, PLN) keeps its own: a euro
/// position is read in euros, not re-expressed in dollars. Portfolio totals
/// are not per asset and stay in [displayCurrency].
String assetDisplayCurrency(String displayCurrency, String nativeCurrency) {
  if (displayCurrency == 'BRL') return 'BRL';
  return nativeCurrency == 'BRL' || nativeCurrency == 'USD'
      ? 'USD'
      : nativeCurrency;
}

/// [pickAmount] for one asset's figure: [native] is the exact figure in
/// [nativeCurrency], used when [assetDisplayCurrency] lands on it.
///
/// [nativeAvailable] false (a trade-date close was missing) means [native] is
/// a placeholder; the figure then degrades to the USD path — its label shows
/// it is not in the asset's currency, and no rate is invented.
DisplayAmount pickAssetAmount({
  required String displayCurrency,
  required String nativeCurrency,
  required double brl,
  required double? usd,
  required double native,
  bool nativeAvailable = true,
  required double usdBrlRate,
}) {
  final view = assetDisplayCurrency(displayCurrency, nativeCurrency);
  if (view != 'BRL' && view != 'USD' && nativeAvailable) {
    return DisplayAmount(value: native, currency: view, exact: true);
  }
  return pickAmount(
    displayCurrency: view == 'BRL' ? 'BRL' : 'USD',
    brl: brl,
    usd: usd,
    usdBrlRate: usdBrlRate,
  );
}
