import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/backend_service.dart';
import '../../utils/money_format.dart';

/// Daily-close line chart for one priced asset, in the instrument's own
/// currency — historical prices are never converted at today's FX rate
/// (re-pricing history invents gains; same rule as `asset_display.dart`).
///
/// Single series: no legend (the header names it), a thin recessive line,
/// horizontal grid only, and a touch tooltip carrying date + close. The
/// average cost is drawn as a dashed reference line so "am I above or below
/// my cost" is visible without reading any number.
class PriceHistoryChart extends StatefulWidget {
  final InvestmentAsset asset;

  const PriceHistoryChart({super.key, required this.asset});

  @override
  State<PriceHistoryChart> createState() => _PriceHistoryChartState();
}

class _PriceHistoryChartState extends State<PriceHistoryChart> {
  static const _ranges = ['1mo', '6mo', '1y', '5y', 'max'];

  final _backendService = BackendService();

  String _range = '1y';
  bool _loading = true;
  String? _error;
  List<MapEntry<DateTime, double>> _points = const [];
  String _currency = 'BRL';

  String _rangeLabel(String r) => 'investments.chart.ranges.$r'.tr();

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
      final data = await _backendService.getAssetPriceHistory(
          widget.asset.id!, _range);
      if (!mounted) return;
      setState(() {
        _currency = (data['currency'] as String?) ?? 'BRL';
        _points = [
          for (final p in (data['points'] as List? ?? const []))
            MapEntry(DateTime.parse(p['date'] as String),
                (p['close'] as num).toDouble()),
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

  /// Bottom axis labels for first / middle / last trading day. Index-based X
  /// keeps the line continuous across weekends and holidays.
  String _dateLabel(DateTime d) => _range == '1mo' || _range == '6mo'
      ? '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'
      : '${d.month.toString().padLeft(2, '0')}/${d.year % 100}';

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
                Icon(Icons.show_chart, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'investments.chart.title'
                      .tr(namedArgs: {'currency': _currency}),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(height: 180, child: _buildChartArea(scheme)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final r in _ranges)
                  ChoiceChip(
                    label: Text(_rangeLabel(r),
                        style: const TextStyle(fontSize: 11)),
                    selected: r == _range,
                    onSelected: (_) => _setRange(r),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
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
    if (_points.length < 2) {
      return Center(
        child: Text('investments.chart.no_data'.tr(),
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }

    final closes = _points.map((p) => p.value).toList();
    var minY = closes.reduce((a, b) => a < b ? a : b);
    var maxY = closes.reduce((a, b) => a > b ? a : b);

    // The average cost only earns a reference line when it falls near the
    // visible price range — a cost far outside would flatten the series.
    final avgCost = widget.asset.avgCostOriginal;
    final span = maxY - minY;
    final showAvg = avgCost > 0 &&
        avgCost > minY - span * 0.25 &&
        avgCost < maxY + span * 0.25;
    if (showAvg) {
      minY = minY < avgCost ? minY : avgCost;
      maxY = maxY > avgCost ? maxY : avgCost;
    }
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    final lastIndex = (_points.length - 1).toDouble();

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
              reservedSize: 52,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  formatPrice(v, _currency, context.locale.toString()),
                  textAlign: TextAlign.right,
                  style:
                      TextStyle(fontSize: 9, color: Colors.grey.shade600),
                ),
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
                if (i < 0 || i >= _points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_dateLabel(_points[i].key),
                      style: TextStyle(
                          fontSize: 9, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
        ),
        extraLinesData: showAvg
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: avgCost,
                  color: Colors.grey.withValues(alpha: 0.6),
                  strokeWidth: 1,
                  dashArray: const [5, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade600),
                    labelResolver: (_) =>
                        'investments.chart.avg_cost'.tr(),
                  ),
                ),
              ])
            : const ExtraLinesData(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${_dateLabel(_points[s.x.round()].key)}\n'
                  '${formatPrice(s.y, _currency, context.locale.toString())}',
                  const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _points.length; i++)
                FlSpot(i.toDouble(), _points[i].value),
            ],
            isCurved: false,
            barWidth: 2,
            color: scheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}
