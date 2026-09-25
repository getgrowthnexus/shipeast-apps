import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// A single node in [SeStepTracker].
class SeStep {
  final String label;
  final String? caption;
  const SeStep(this.label, {this.caption});
}

/// Vertical progress tracker (PLAN §3.2 — Pending approval, delivery flow).
///
/// The connector between nodes fills as the step advances rather than snapping,
/// so an approval landing while the screen is open reads as forward motion. The
/// active node carries a soft brand halo; completed nodes go solid success.
class SeStepTracker extends StatelessWidget {
  final List<SeStep> steps;

  /// Index of the in-progress step. Everything before it is complete.
  final int current;

  /// Renders every node in success tone (e.g. approval granted).
  final bool allComplete;

  const SeStepTracker({
    super.key,
    required this.steps,
    required this.current,
    this.allComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    final reduced = SeMotion.reduced(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length, (i) {
        final done = allComplete || i < current;
        final active = !allComplete && i == current;
        final last = i == steps.length - 1;

        final Color hue = done
            ? SeColors.success
            : active
                ? SeColors.red500
                : SeColors.ink300;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _Node(hue: hue, done: done, active: active, reduced: reduced),
                  if (!last)
                    Expanded(
                      child: AnimatedContainer(
                        duration: reduced ? Duration.zero : SeMotion.slow,
                        curve: SeMotion.emphasized,
                        width: 2.5,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: done ? SeColors.success : SeColors.ink200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: SeSpacing.x3),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 0 : SeSpacing.x5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        steps[i].label,
                        style: SeType.title.copyWith(
                          color: done || active
                              ? SeColors.ink900
                              : SeColors.ink400,
                        ),
                      ),
                      if (steps[i].caption != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          steps[i].caption!,
                          style: SeType.bodyS.copyWith(
                            color: done || active
                                ? SeColors.ink500
                                : SeColors.ink400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Node extends StatelessWidget {
  final Color hue;
  final bool done;
  final bool active;
  final bool reduced;

  const _Node({
    required this.hue,
    required this.done,
    required this.active,
    required this.reduced,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: reduced ? Duration.zero : SeMotion.base,
      curve: SeMotion.emphasized,
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: done ? SeColors.success : (active ? SeColors.red50 : SeColors.ink100),
        shape: BoxShape.circle,
        border: active ? Border.all(color: SeColors.red500, width: 2.5) : null,
        boxShadow: active ? SeElevation.glowColor(hue, opacity: 0.22) : null,
      ),
      child: done
          ? const Icon(SeIcons.check, size: 17, color: Colors.white)
          : active
              ? const _Pulse()
              : null,
    );
  }
}

/// Slow breathing dot marking "this is happening now".
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SeMotion.reduced(context)) {
      return const Center(
        child: SizedBox(
          width: 10,
          height: 10,
          child: DecoratedBox(
            decoration:
                BoxDecoration(color: SeColors.red500, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return Center(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_ctrl),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1.0).animate(_ctrl),
          child: const SizedBox(
            width: 10,
            height: 10,
            child: DecoratedBox(
              decoration:
                  BoxDecoration(color: SeColors.red500, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}
