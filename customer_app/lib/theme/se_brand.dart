import 'package:flutter/material.dart';
import 'se_colors.dart';
import 'se_typography.dart';

/// Brand constants (SEDS §1.1). Single source for the app version string.
class SeBrand {
  SeBrand._();

  /// Keep in lockstep with pubspec `version:` (before the `+build`).
  static const String version = '1.0.2';
  static const String tagline = 'Couriers & Bearer Service · Jamaica';
}

/// ShipEast wordmark — `Ship` in ink + `East` in brand red, one weight.
/// Retires the Dancing Script script look from the UI.
class SeWordmark extends StatelessWidget {
  final double size;

  /// When true, `Ship` renders white (for use on the Ember gradient).
  final bool onDark;

  const SeWordmark({super.key, this.size = 26, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final shipColor = onDark ? Colors.white : SeColors.ink900;
    final eastColor = onDark ? Colors.white : SeColors.red500;
    return RichText(
      text: TextSpan(
        style: SeType.jakarta(size, FontWeight.w800),
        children: [
          TextSpan(text: 'Ship', style: TextStyle(color: shipColor)),
          TextSpan(
            text: 'East',
            style: TextStyle(
              color: eastColor,
              decoration: onDark ? TextDecoration.none : null,
            ),
          ),
        ],
      ),
    );
  }
}
