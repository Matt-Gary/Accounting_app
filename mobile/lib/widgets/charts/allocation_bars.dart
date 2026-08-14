import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../models/models.dart';

/// Ranked share of the active broker portfolio.
///
/// Horizontal bars rather than a line: there is no time dimension here — this
/// is composition at a moment, and horizontal bars leave room for full position
/// names without rotating labels.
///
/// One colour for every bar on purpose. Positions are nominal categories, so
/// shading them by size would encode the magnitude twice (length already says
/// it) and spend the only free channel on information the chart already shows.
class AllocationBars extends StatelessWidget {
  final List<InvestmentAsset> positions;

  /// Formats a BRL value in whatever currency the screen is displaying.
  final String Function(double brlValue) formatValue;

  /// True when every position in the base could be valued. When false the
  /// shares are computed over an incomplete total and the chart says so.
  final bool complete;

  const AllocationBars({
    super.key,
    required this.positions,
    required this.formatValue,
    this.complete = true,
  });

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    // A single position is not a chart — the bar would just be full width and
    // say nothing. Fall back to plain rows.
    final showBars = positions.length > 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'investments.allocation.title'.tr(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'investments.allocation.subtitle'.tr(),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            if (!complete) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: scheme.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'investments.allocation.incomplete'.tr(),
                      style: TextStyle(fontSize: 11, color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ...positions.map((p) => _row(context, p, showBars)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, InvestmentAsset p, bool showBars) {
    final scheme = Theme.of(context).colorScheme;
    final pct = p.portfolioPct ?? 0;

    return Padding(
      // 10px between rows keeps the 2px surface gap the marks need and then
      // some, so adjacent bars never read as one block.
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Labels sit outside the bar so they can never be clipped by a short
          // one, and the values stay readable without relying on colour.
          Row(
            children: [
              Expanded(
                child: Text(
                  p.symbol ?? p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${pct.toStringAsFixed(1)}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 10),
              Text(
                formatValue(p.currentValueBrl),
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          if (showBars) ...[
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth * (pct.clamp(0, 100) / 100);
                return Stack(
                  children: [
                    // Recessive track, one shade off the surface.
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Container(
                      height: 6,
                      // A hairline stays visible for a sub-1% position instead
                      // of vanishing into the track.
                      width: width < 3 ? 3 : width,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
