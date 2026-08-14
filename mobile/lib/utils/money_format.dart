import 'package:easy_localization/easy_localization.dart';

const _symbols = {
  'BRL': 'R\$',
  'USD': '\$',
  'EUR': '€',
  'PLN': 'zł',
};

String currencySymbol(String code) => _symbols[code] ?? code;

/// Money, in full, with locale-aware thousands separators.
///
/// Deliberately no K/M abbreviation: "R$ 4,8K" hides the digits you need when
/// reconciling a position against a broker statement, and rounds away up to
/// R$99 in the process.
String formatMoney(double value, String currencyCode, String locale) {
  final sign = value < 0 ? '-' : '';
  final digits = NumberFormat('#,##0.00', locale).format(value.abs());
  return '$sign${currencySymbol(currencyCode)} $digits';
}

/// Share counts: no forced decimals on whole units, up to 6 places for
/// fractional ones (crypto, fractional shares).
String formatQuantity(double value, String locale) {
  final pattern = value == value.roundToDouble() ? '#,##0' : '#,##0.######';
  return NumberFormat(pattern, locale).format(value);
}

/// A per-unit price. Same grouping as money so a five-figure crypto quote stays
/// readable, but without forcing a currency symbol on the caller.
String formatPrice(double value, String currencyCode, String locale) =>
    formatMoney(value, currencyCode, locale);
