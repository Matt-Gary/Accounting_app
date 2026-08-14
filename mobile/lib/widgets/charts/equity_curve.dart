import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/backend_service.dart';
import '../../utils/money_format.dart';

/// Portfolio value over time — the equity curve — with the invested capital
/// as a second, recessive line, so a rising value can be told apart from
/// "I merely deposited more".
///
/// Follows the screen's BRL/USD toggle. The USD series is honest: each day is
/// converted at the USD/BRL close *recorded on that day's snapshot* — never at
/// today's rate, which would re-price the past. Days whose snapshot carried no
/// rate simply have no USD point. Two series → a legend row; touch tooltip
/// carries the date and both figures in full (axis ticks are compact for
/// space — they orient, the tooltip reconciles).
class EquityCurve extends StatefulWidget {
  /// True renders the USD view (per-day historical rates), false the BRL one.
  final bool showUsd;

  const EquityCurve({super.key, this.showUsd = false});

  @override
  State<EquityCurve> createState() => _EquityCurveState();
}

class _EquityCurveState extends State<EquityCurve> {
  static const _ranges = ['3mo', '1y', 'all'];
  static const _investedColor = Color(0xFF9E9E9E);

  final _backendService = BackendService();

  String _range = '3mo';
  bool _loading = true;
  String? _error;
  List<DateTime> _dates = const [];
  List<double> _values = const [];
  List<double> _invested = const [];
  List<double?> _valuesUsd = const [];
  List<double?> _investedUsd = const [];

  String _rangeLabel(String r) => 'investments.equity.ranges.$r'.tr();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _backendService.getPortfolioHistory(_range);
      if (!mounted) return;
      final points = (data['points'] as List? ?? const []);
      setState(() {
        _dates = [
          for (final p in points) DateTime.parse(p['date'] as String)
        ];
        _values = [
          for (final p in points) (p['total_value_brl'] as num).toDouble()
        ];
        _invested = [
          for (final p in points) (p['total_invested_brl'] as num).toDouble()
        ];
        _valuesUsd = [
          for (final p in points) (p['total_value_usd'] as num?)?.toDouble()
        ];
        _investedUsd = [
          for (final p in points)
            (p['total_invested_usd'] as num?)?.toDouble()
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '');
        _loading = false;
      });
    }
  }

  void _setRange(String r) {
    if (r == _range) return;
    setState(() => _range = r);
    _load();
  }

  String _dateLabel(DateTime d) => _range == 'all'
      ? '${d.month.toString().padLeft(2, '0')}/${d.year % 100}'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// Compact axis tick ("120 k"): orientation only — the tooltip and the
  /// cards elsewhere carry full figures per the no-abbreviation rule.
  String _axisLabel(double v) =>
      NumberFormat.compact(locale: context.locale.toString()).format(v);

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                    'investments.equity.title'.tr(namedArgs: {
                      'currency': widget.showUsd ? 'USD' : 'BRL'
                    }),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                _legendDot(scheme.primary, 'investments.equity.value'.tr()),
                const SizedBox(width: 10),
                _legendDot(
                    _investedColor, 'investments.equity.invested'.tr()),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 170, child: _buildChartArea(scheme)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final r in _ranges) ...[
                  ChoiceChip(
                    label: Text(_rangeLabel(r),
                        style: const TextStyle(fontSize: 11)),
                    selected: r == _range,
                    onSelected: (_) => _setRange(r),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartArea(ColorScheme scheme) {
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    // Select the series for the active currency. The USD view keeps only the
    // days whose snapshot recorded a rate — absence stays absent.
    final dates = <DateTime>[];
    final values = <double>[];
    final invested = <double>[];
    if (widget.showUsd) {
      for (var i = 0; i < _dates.length; i++) {
        final v = _valuesUsd[i];
        final inv = _investedUsd[i];
        if (v != null && inv != null) {
          dates.add(_dates[i]);
          values.add(v);
          invested.add(inv);
        }
      }
    } else {
      dates.addAll(_dates);
      values.addAll(_values);
      invested.addAll(_invested);
    }
    final currency = widget.showUsd ? 'USD' : 'BRL';

    if (values.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('investments.equity.empty'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    final all = [...values, ...invested];
    var minY = all.reduce((a, b) => a < b ? a : b);
    var maxY = all.reduce((a, b) => a > b ? a : b);
    if (maxY - minY < 1) maxY = minY + 1; // flat series still needs a scale
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    final lastIndex = (values.length - 1).toDouble();
    final locale = context.locale.toString();

    LineChartBarData series(List<double> ys, Color color,
            {double alpha = 0}) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < ys.length; i++)
              FlSpot(i.toDouble(), ys[i]),
          ],
          isCurved: false,
          barWidth: 2,
          color: color,
          dotData: const FlDotData(show: false),
          belowBarData: alpha > 0
              ? BarAreaData(
                  show: true, color: color.withValues(alpha: alpha))
              : BarAreaData(show: false),
        );

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        minX: 0,
        maxX: lastIndex,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(_axisLabel(v),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade600)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: lastIndex / 2 <= 0 ? 1 : lastIndex / 2,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= dates.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_dateLabel(dates[i]),
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              if (spots.isEmpty) return const [];
              final i = spots.first.x.round();
              // One combined tooltip on the first spot; blank for the second
              // so the same information is not printed twice.
              return [
                LineTooltipItem(
                  '${_dateLabel(dates[i])}\n'
                  '${formatMoney(values[i], currency, locale)}\n'
                  '${'investments.equity.invested'.tr()}: '
                  '${formatMoney(invested[i], currency, locale)}',
                  const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
                if (spots.length > 1)
                  const LineTooltipItem('', TextStyle(fontSize: 0)),
              ];
            },
          ),
        ),
        lineBarsData: [
          series(values, scheme.primary, alpha: 0.06),
          series(invested, _investedColor),
        ],
      ),
    );
  }
}
