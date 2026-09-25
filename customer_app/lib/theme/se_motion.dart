import 'package:flutter/material.dart';

/// ShipEast Design System — Motion tokens (SEDS §1.7).
///
/// Durations and curves used by every transition, press and entrance so the
/// whole app moves with one rhythm. Reduced-motion is honoured at call sites
/// via [MediaQuery.disableAnimationsOf].
class SeMotion {
  SeMotion._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration deliberate = Duration(milliseconds: 520);

  /// Emphasized standard curve (most transitions).
  static const Cubic emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Decelerate — entering elements.
  static const Cubic decelerate = Cubic(0.0, 0.0, 0.0, 1.0);

  /// Accelerate — exiting elements.
  static const Cubic accelerate = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Whether the platform/user has requested reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
