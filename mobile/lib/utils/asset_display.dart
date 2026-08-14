/// Choosing which of a figure's two representations to show.
///
/// The backend computes every position twice: once in BRL, accumulated at the
/// exchange rate of each individual transaction, and once in the asset's own
/// currency. Both are exact; neither is derivable from the other.
///
/// Dividing a historical BRL figure by today's rate does NOT reconstruct the
/// native one — it re-prices the past at present-day FX. On a $1,900 deposit
/// made at 5.11 and viewed at 5.1873 that produced a $28.31 gain out of thin
/// air, present in neither currency. This module exists so that mistake has
/// one place to be made and one place to be tested.
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
/// * Display currency equals the asset's own → return [native] untouched.
///   This is the case that was broken: an exact figure was being thrown away
///   and reconstructed badly.
/// * Display currency is BRL → return [brl] untouched.
/// * Neither (a EUR asset viewed in USD) → convert the BRL figure at
///   [usdBrlRate] and mark it inexact. There is no exact answer to give.
///
/// A non-positive [usdBrlRate] means the rate is unavailable, so no conversion
/// is invented — the BRL figure is returned as BRL and the caller can see the
/// currency it actually got.
DisplayAmount pickAmount({
  required String displayCurrency,
  required String nativeCurrency,
  required double brl,
  required double native,
  required double usdBrlRate,
}) {
  if (displayCurrency == nativeCurrency) {
    return DisplayAmount(
        value: native, currency: nativeCurrency, exact: true);
  }
  if (displayCurrency == 'BRL') {
    return DisplayAmount(value: brl, currency: 'BRL', exact: true);
  }
  if (displayCurrency == 'USD' && usdBrlRate > 0) {
    return DisplayAmount(
        value: brl / usdBrlRate, currency: 'USD', exact: false);
  }
  // Rate unavailable: hand back what we have rather than a guessed number.
  return DisplayAmount(value: brl, currency: 'BRL', exact: true);
}

/// Whether an asset's figures can be shown exactly in [displayCurrency].
bool isNativeView(String displayCurrency, String nativeCurrency) =>
    displayCurrency == nativeCurrency;
