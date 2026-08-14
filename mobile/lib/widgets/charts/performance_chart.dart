import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/backend_service.dart';

/// Portfolio performance vs the S&P 500: both series indexed to 100 at the
/// start of the window (TWR chain for the portfolio, closes for ^GSPC), plus
/// stat tiles for TWR (period), XIRR (annualized) and the benchmark return.
///
/// The portfolio index is flow-adjusted — deposits do not show as gains —
/// which is what makes the benchmark comparison legitimate. Backend warnings
/// (short history, FX note) are surfaced verbatim under the chart: the chart
/// must not look more precise than the data allows.
class PerformanceChart extends StatefulWidget {
  const PerformanceChart({super.key});

  @override
  State<PerformanceChart> createState() => _PerformanceChartState();
}

class _PerformanceChartState extends State<PerformanceChart> {
  static const _ranges = ['1y', 'all'];
  static const _benchmarkColor = Color(0xFFEF6C00);

  final _backendService = BackendService();

  String _range = '1y';
  bool _loading = true;
  String? _error;
  double? _twrPct;
  double? _xirrPct;
  double? _benchmarkPct;
  List<DateTime> _dates = const [];
  List<double> _portfolio = const [];
  List<double?> _benchmark = const [];
  List<String> _warnings = const [];

  String _rangeLabel(String r) => 'investments.performance.ranges.$r'.tr();

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
      final data = await _backendService.getPerformance(_range);
      if (!mounted) return;
      final series = (data['series'] as List? ?? const []);
      setState(() {
        _twrPct = (data['twr_pct'] as num?)?.toDouble();
        _xirrPct = (data['xirr_pct'] as num?)?.toDouble();
        _benchmarkPct =
            ((data['benchmark'] as Map<String, dynamic>?)?['return_pct']
                    as num?)
                ?.toDouble();
        _dates = [
          for (final p in series) DateTime.parse(p['date'] as String)
        ];
        _portfolio = [
          for (final p in series) (p['portfolio_index'] as num).toDouble()
        ];
        _benchmark = [
          for (final p in series)
            (p['benchmark_index'] as num?)?.toDouble()
        ];
        _warnings = [
          for (final w in (data['warnings'] as List? ?? const [])) '$w'
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

  String _dateLabel(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year % 100}';

  String _pctOrDash(double? v) =>
      v == null ? '—' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  Color _pctColor(double? v) => v == null
      ? Colors.grey
      : (v >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFC00000));

  Widget _tile(String labelKey, double? pct) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelKey.tr(),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(_pctOrDash(pct),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _pctColor(pct))),
        ],
      );

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
                Icon(Icons.speed, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text('investments.performance.title'.tr(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                _legendDot(
                    scheme.primary, 'investments.performance.portfolio'.tr()),
                const SizedBox(width: 10),
                _legendDot(_benchmarkColor, 'S&P 500'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _tile('investments.performance.twr', _twrPct),
                _tile('investments.performance.xirr', _xirrPct),
                _tile('investments.performance.benchmark', _benchmarkPct),
              ],
            ),
            const SizedBox(height: 10),
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
            if (_warnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_warnings.join('\n'),
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade600)),
            ],
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
    if (_portfolio.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('investments.performance.empty'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      );
    }

    final benchSpots = <FlSpot>[
      for (var i = 0; i < _benchmark.length; i++)
        if (_benchmark[i] != null) FlSpot(i.toDouble(), _benchmark[i]!),
    ];
    final all = [
      ..._portfolio,
      ...benchSpots.map((s) => s.y),
    ];
    var minY = all.reduce((a, b) => a < b ? a : b);
    var maxY = all.reduce((a, b) => a > b ? a : b);
    if (maxY - minY < 1) maxY = minY + 1;
    final pad = (maxY - minY) * 0.08;
    minY -= pad;
    maxY += pad;

    final lastIndex = (_portfolio.length - 1).toDouble();

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
              reservedSize: 34,
              interval: (maxY - minY) / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(v.toStringAsFixed(0),
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
                if (i < 0 || i >= _dates.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_dateLabel(_dates[i]),
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
              final bench = i < _benchmark.length ? _benchmark[i] : null;
              return [
                LineTooltipItem(
                  '${_dateLabel(_dates[i])}\n'
                  '${'investments.performance.portfolio'.tr()}: '
                  '${_portfolio[i].toStringAsFixed(1)}\n'
                  'S&P 500: ${bench?.toStringAsFixed(1) ?? '—'}',
                  const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
                ),
                for (var k = 1; k < spots.length; k++)
                  const LineTooltipItem('', TextStyle(fontSize: 0)),
              ];
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < _portfolio.length; i++)
                FlSpot(i.toDouble(), _portfolio[i]),
            ],
            isCurved: false,
            barWidth: 2,
            color: scheme.primary,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: benchSpots,
            isCurved: false,
            barWidth: 2,
            color: _benchmarkColor,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
