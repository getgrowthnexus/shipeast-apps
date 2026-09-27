import 'package:flutter/material.dart';
import '../driver_constants.dart';
import '../theme/se_colors.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// Design-grade earnings chart (PLAN §3.2 — Earnings).
///
/// Rebuilds the old flat `_BarChartPainter`: bars grow in on a staggered
/// decelerate curve, sit on a faint gridline scale with real currency axis labels,
/// and the peak bar is emphasised with the Ember gradient plus a gold cap so
/// the best earning window is readable without a legend.
///
/// When the period has no earnings the chart shows honest flat ghost bars and
/// an explicit "no data" caption — it never fabricates a shape.
class SeEarningsChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final double height;

  const SeEarningsChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 180,
  });

  @override
  State<SeEarningsChart> createState() => _SeEarningsChartState();
}

class _SeEarningsChartState extends State<SeEarningsChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: SeMotion.deliberate)
      ..forward();
  }

  @override
  void didUpdateWidget(covariant SeEarningsChart old) {
    super.didUpdateWidget(old);
    // Re-grow when the period tab changes so the switch feels like new data.
    if (old.values != widget.values) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final maxVal =
        values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final hasData = maxVal > 0;
    final peak = hasData
        ? values.asMap().entries.reduce((a, b) => a.value >= b.value ? a : b).key
        : -1;
    final reduced = SeMotion.reduced(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              // Faint 4-line grid with currency scale labels.
              Positioned.fill(
                bottom: 22,
                child: _Grid(maxVal: hasData ? maxVal : 0),
              ),
              // The bars are inset by the axis gutter, or the last one is
              // drawn straight through the scale labels — which is how the
              // Sunday bar came to sit on top of "1,400".
              Positioned.fill(
                right: _axisWidth + 6,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(values.length, (i) {
                        // 40ms stagger left→right.
                        final delay = (i * 0.06).clamp(0.0, 0.5);
                        final raw = reduced
                            ? 1.0
                            : ((_ctrl.value - delay) / (1 - delay))
                                .clamp(0.0, 1.0);
                        final t = Curves.easeOutCubic.transform(raw);
                        final frac = hasData ? values[i] / maxVal : 0.0;

                        return Expanded(
                          child: _Bar(
                            fraction: frac * t,
                            label: widget.labels.length > i
                                ? widget.labels[i]
                                : '',
                            emphasised: i == peak,
                            ghost: !hasData,
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SeSpacing.x3),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: hasData ? SeColors.brandAction : SeColors.ink300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: SeSpacing.x2),
            Text(
              hasData
                  ? 'Peak: ${Money.format(maxVal)} · ${widget.labels.length > peak && peak >= 0 ? widget.labels[peak] : ''}'
                  : 'No earnings recorded for this period',
              style: SeType.bodyS.copyWith(color: SeColors.ink500),
            ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final String label;
  final bool emphasised;
  final bool ghost;

  const _Bar({
    required this.fraction,
    required this.label,
    required this.emphasised,
    required this.ghost,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              // Ghost bars keep a visible floor so the axis reads as a chart.
              heightFactor: ghost ? 0.04 : fraction.clamp(0.02, 1.0),
              widthFactor: 0.52,
              child: Container(
                // Two flat tones and nothing else. The peak used to be marked
                // three times over — a gradient, a red glow AND a gold cap —
                // which is two more than a bar chart of seven bars needs. The
                // peak is now simply the only bar in the action red; the rest
                // sit in the pale ramp step, which stays visible on blush.
                decoration: BoxDecoration(
                  color: ghost
                      ? SeColors.ink200
                      : emphasised
                          ? SeColors.brandAction
                          : SeColors.red200,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(SeRadius.xs),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 16,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: SeType.eyebrow.copyWith(
              color: emphasised && !ghost ? SeColors.ink900 : SeColors.ink400,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Four faint horizontal rules with currency values on the right edge.
/// Width reserved for the scale labels down the right edge. Fixed rather than
/// intrinsic so the bars do not shift sideways when a period's peak gains a
/// digit.
const double _axisWidth = 46;

class _Grid extends StatelessWidget {
  final double maxVal;
  const _Grid({required this.maxVal});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (i) {
        final value = maxVal * (3 - i) / 3;
        return Row(
          children: [
            Expanded(
              child: Container(height: 1, color: SeColors.ink100),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: _axisWidth,
              child: Text(
                maxVal > 0 ? Money.plain(value) : '—',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: SeType.tabular(SeType.eyebrow)
                    .copyWith(color: SeColors.ink300, letterSpacing: 0),
              ),
            ),
          ],
        );
      }),
    );
  }
}
