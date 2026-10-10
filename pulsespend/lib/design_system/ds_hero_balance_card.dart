import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_tokens.dart';
import 'ds_controls.dart';
import 'ds_foundations.dart';

/// One point on the hero chart.
class DsSeriesPoint {
  const DsSeriesPoint({required this.label, required this.value});

  /// Shown in the tooltip bubble — "18, Sep".
  final String label;
  final double value;
}

/// A stat in the row beneath the hero figure — Income / Expense / Shift.
class DsHeroStat {
  const DsHeroStat({
    required this.label,
    required this.value,
    required this.color,
    required this.direction,
  });

  final String label;
  final String value;
  final Color color;

  /// 1 up, -1 down, 0 bidirectional (the reference's "shift" arrows).
  final int direction;
}

/// The balance / portfolio hero: gradient surface, oversized figure, a period
/// filter, a dual-line chart with a tooltip you can drag along the series, and
/// a stat row on a floating white shelf.
///
/// This is the single most emphasised object in the app. Nothing else should
/// carry this much visual weight — that hierarchy is the point.
class DsHeroBalanceCard extends StatefulWidget {
  const DsHeroBalanceCard({
    super.key,
    required this.balanceLabel,
    required this.balance,
    this.series = const [],
    this.comparisonSeries = const [],
    this.stats = const [],
    this.filterLabel,
    this.onFilterTap,
    this.periodLabel,
    this.trailing,
    this.margin = const EdgeInsets.symmetric(horizontal: AppTokens.screenPadding),
    this.chartHeight = 130,
    this.valueFormatter,
    this.onPointSelected,
  });

  final String balanceLabel;
  final String balance;

  /// Primary line — solid, with a gradient fill beneath it.
  final List<DsSeriesPoint> series;

  /// Optional dashed comparison line (previous period, budget, projection).
  final List<DsSeriesPoint> comparisonSeries;

  final List<DsHeroStat> stats;
  final String? filterLabel;
  final VoidCallback? onFilterTap;
  final String? periodLabel;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final double chartHeight;

  /// Formats the tooltip value. Defaults to the raw number so the card works
  /// before a currency formatter is wired in.
  final String Function(double)? valueFormatter;

  /// Fires as the user drags along the series, with the index of the point
  /// under their finger — or null when they let go. Lets a screen keep its
  /// headline figure in step with the chart selection.
  final ValueChanged<int?>? onPointSelected;

  @override
  State<DsHeroBalanceCard> createState() => _DsHeroBalanceCardState();
}

class _DsHeroBalanceCardState extends State<DsHeroBalanceCard> {
  /// Index the user is currently dragging the tooltip to. Null = resting, in
  /// which case the last point is shown so the card is never bare.
  int? _touchedIndex;

  bool get _hasChart => widget.series.length > 1;

  /// How far the stat shelf hangs below the gradient card. Reserved as real
  /// layout space so the next section on screen starts clear of it.
  static const double _shelfOverhang = 34;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasStats = widget.stats.isNotEmpty;

    // The stat shelf overlaps the hero's lower edge and protrudes below it —
    // a Stack rather than a Transform, so the overhang occupies real layout
    // space and whatever follows on the screen is not overlapped.
    return Container(
      margin: widget.margin,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: hasStats ? _shelfOverhang : 0),
            child: DsHeroSurface(
              padding: EdgeInsets.fromLTRB(
              AppTokens.space20,
              AppTokens.space20,
              AppTokens.space20,
              widget.stats.isEmpty ? AppTokens.space20 : AppTokens.space32 + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.balanceLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.balance,
                              style: theme.textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) widget.trailing!,
                  ],
                ),
                if (widget.filterLabel != null || widget.periodLabel != null) ...[
                  const SizedBox(height: AppTokens.space16),
                  Row(
                    children: [
                      if (widget.filterLabel != null)
                        DsFilterChip(
                          label: widget.filterLabel!,
                          onTap: widget.onFilterTap,
                          onHero: true,
                          showChevron: widget.onFilterTap != null,
                        ),
                      if (widget.periodLabel != null) ...[
                        const SizedBox(width: AppTokens.space12),
                        Text(
                          widget.periodLabel!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (_hasChart) ...[
                    const SizedBox(height: AppTokens.space20),
                    SizedBox(height: widget.chartHeight, child: _buildChart()),
                  ],
                ],
              ),
            ),
          ),
          // Anchored to the stack's bottom edge, so it straddles the hero's
          // lower boundary — attached to the card, not stacked beneath it.
          if (hasStats)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _StatShelf(stats: widget.stats),
            ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final spots = <FlSpot>[];
    for (var i = 0; i < widget.series.length; i++) {
      spots.add(FlSpot(i.toDouble(), widget.series[i].value));
    }

    final compSpots = <FlSpot>[];
    for (var i = 0; i < widget.comparisonSeries.length; i++) {
      compSpots.add(FlSpot(i.toDouble(), widget.comparisonSeries[i].value));
    }

    final allValues = <double>[
      ...widget.series.map((p) => p.value),
      ...widget.comparisonSeries.map((p) => p.value),
    ];
    var minY = allValues.reduce((a, b) => a < b ? a : b);
    var maxY = allValues.reduce((a, b) => a > b ? a : b);
    // Breathing room so the line never grazes the card edge, and a guard
    // against a flat series collapsing the axis to zero height.
    final span = (maxY - minY).abs();
    final pad = span < 0.0001 ? (maxY.abs() * 0.2 + 1) : span * 0.25;
    minY -= pad;
    maxY += pad;

    final highlight = _touchedIndex ?? widget.series.length - 1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (widget.series.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchSpotThreshold: 40,
          getTouchedSpotIndicator: (barData, indexes) {
            return indexes.map((i) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: Colors.white.withValues(alpha: 0.45),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                    radius: 6,
                    color: AppColors.accentCyan,
                    strokeWidth: 3,
                    strokeColor: Colors.white,
                  ),
                ),
              );
            }).toList();
          },
          touchCallback: (event, response) {
            final spot = response?.lineBarSpots;
            if (spot == null || spot.isEmpty || !event.isInterestedForInteractions) {
              if (_touchedIndex != null) {
                setState(() => _touchedIndex = null);
                widget.onPointSelected?.call(null);
              }
              return;
            }
            final i = spot.first.spotIndex;
            if (i != _touchedIndex) {
              setState(() => _touchedIndex = i);
              widget.onPointSelected?.call(i);
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorderRadius: BorderRadius.circular(AppTokens.radiusBadge),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            tooltipMargin: 12,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                // Only the primary series gets a bubble — two overlapping
                // tooltips is noise, not information.
                if (s.barIndex != 0) return null;
                final i = s.spotIndex;
                final label = i >= 0 && i < widget.series.length
                    ? widget.series[i].label
                    : '';
                final value = widget.valueFormatter?.call(s.y) ??
                    s.y.toStringAsFixed(2);
                return LineTooltipItem(
                  '$label\n',
                  const TextStyle(
                    color: AppColors.lightTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        color: AppColors.lightTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                  textAlign: TextAlign.center,
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          // Primary — solid, gradient-filled.
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.32,
            preventCurveOverShooting: true,
            color: Colors.white,
            barWidth: 2.6,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, bar) => spot.x == highlight.toDouble(),
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 5,
                color: AppColors.accentCyan,
                strokeWidth: 3,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.30),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
          // Comparison — dashed, no fill, deliberately quieter.
          if (compSpots.length > 1)
            LineChartBarData(
              spots: compSpots,
              isCurved: true,
              curveSmoothness: 0.32,
              preventCurveOverShooting: true,
              color: Colors.white.withValues(alpha: 0.55),
              barWidth: 1.8,
              isStrokeCapRound: true,
              dashArray: const [6, 5],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: AppTokens.motionSlow,
      curve: AppTokens.motionCurve,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// STAT SHELF
// ══════════════════════════════════════════════════════════════════════

class _StatShelf extends StatelessWidget {
  const _StatShelf({required this.stats});

  final List<DsHeroStat> stats;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);

    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        children.add(
          Container(width: 1, height: 30, color: t.border),
        );
      }
      children.add(Expanded(child: _StatCell(stat: stats[i])));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.space16),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCardSm),
        border: Border.all(color: t.border),
        boxShadow: t.cardShadow,
      ),
      child: Row(children: children),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final DsHeroStat stat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final IconData arrow;
    switch (stat.direction) {
      case 1:
        arrow = Icons.arrow_upward_rounded;
        break;
      case -1:
        arrow = Icons.arrow_downward_rounded;
        break;
      default:
        arrow = Icons.swap_vert_rounded;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stat.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: t.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stat.value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: stat.color,
                ),
              ),
              const SizedBox(width: 2),
              Icon(arrow, size: 13, color: stat.color),
            ],
          ),
        ),
      ],
    );
  }
}
