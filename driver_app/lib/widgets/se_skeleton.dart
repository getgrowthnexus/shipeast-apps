import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';

/// Warm-tinted shimmer skeleton (SEDS §1.7) — replaces bare spinners/gray boxes.
///
/// A single [SeShimmer] wraps children built from [SeSkeleton] shapes and drives
/// one 1200ms sweep across all of them.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? SeColors.darkCardRaised : const Color(0xFFEDEAE4);
    final hi = dark ? const Color(0xFF3A362F) : const Color(0xFFF7F5F1);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = (bounds.width + 200) * _ctrl.value - 100;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, hi, base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideGradient(dx / bounds.width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double t;
  const _SlideGradient(this.t);
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t, 0, 0);
}

/// A single skeleton block. Colour is provided by the parent [SeShimmer].
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
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEAE4),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
