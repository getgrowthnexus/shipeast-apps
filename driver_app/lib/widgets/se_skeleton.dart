import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';

/// Skeleton loader — replaces bare spinners/gray boxes.
///
/// 2026 restyle: no gradients. A single [SeShimmer] wraps children built from
/// [SeSkeleton] shapes and breathes their opacity in unison (the admin's
/// `skpulse`) — cheaper to composite than a shader sweep and correct on a
/// tinted placeholder in either theme.
class SeShimmer extends StatefulWidget {
  final Widget child;
  const SeShimmer({super.key, required this.child});

  @override
  State<SeShimmer> createState() => _SeShimmerState();
}

class _SeShimmerState extends State<SeShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Breathe the whole subtree's opacity between 1 and .5, in unison.
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = (_ctrl.value * 2 - 1).abs(); // 0→1→0 triangle
        return Opacity(opacity: 1 - 0.5 * t, child: child);
      },
      child: widget.child,
    );
  }
}

/// A single skeleton block. A blush placeholder tone sits a step above the card
/// so it reads on either surface; the parent [SeShimmer] breathes it.
class SeSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const SeSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = SeRadius.xs,
    this.margin,
  });

  const SeSkeleton.circle({super.key, required double size, this.margin})
      : width = size,
        height = size,
        radius = SeRadius.full;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: dark ? SeColors.darkCardRaised : SeColors.ink200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
