import 'package:flutter/material.dart';
import 'se_colors.dart';
import 'se_typography.dart';

/// Brand constants (SEDS §1.1). Single source for the app version string.
class SeBrand {
  SeBrand._();

  /// Keep in lockstep with pubspec `version:` (before the `+build`).
  static const String version = '1.2.7';
  static const String tagline = 'Packages • Groceries • Errands';

  /// The registered company, spelled the way it is on paper. Set under the
  /// wordmark on the signed-out screen — a delivery app asking for an address
  /// and a phone number should say who is actually collecting them.
  static const String legalName = 'ShipEast Couriers & Bearer Service Ltd.';

  /// Tracked-out strap for the launch screen. Short enough to hold one line on
  /// a 320dp phone at the wide letter-spacing the lockup needs.
  static const String strapline = 'PACKAGES • GROCERIES • ERRANDS';
}

/// ShipEast wordmark — `Ship` + `East` in one face, two tones.
///
/// On light ground the accent is the identity red; on the brand shell it is
/// [SeColors.shellMark], the pink that reads as a highlight against deep red
/// instead of vanishing into it. Tracking tightens as the mark grows, which is
/// what keeps it looking drawn rather than typed at display sizes.
class SeWordmark extends StatelessWidget {
  final double size;

  /// When true, renders for the brand shell (warm white + pink accent).
  final bool onDark;

  const SeWordmark({super.key, this.size = 26, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final shipColor = onDark ? SeColors.shellInk : SeColors.ink900;
    final eastColor = onDark ? SeColors.shellMark : SeColors.red500;
    return Text.rich(
      TextSpan(
        // Built from [SeType.display] rather than a loose `jakarta()` call, so
        // the mark is demonstrably the same face and weight as the headline it
        // sits above. Only the size and the tracking are the mark's own.
        style: SeType.display.copyWith(
          fontSize: size,
          letterSpacing: -size * 0.032,
          height: 1.1,
        ),
        children: [
          TextSpan(
            text: 'Ship',
            style: TextStyle(color: shipColor),
          ),
          TextSpan(
            text: 'East',
            style: TextStyle(color: eastColor),
          ),
        ],
      ),
    );
  }
}

/// [SeWordmark] with [SeBrand.legalName] set beneath it.
///
/// The two lines are a lockup, not a heading and a caption: the small line is
/// tucked tight under the mark and tracked out a little, which is what keeps
/// it reading as part of the signature instead of as the first line of copy.
class SeBrandLockup extends StatelessWidget {
  final double size;
  final bool onDark;

  const SeBrandLockup({super.key, this.size = 26, this.onDark = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      SeWordmark(size: size, onDark: onDark),
      const SizedBox(height: 3),
      Text(
        SeBrand.legalName,
        style: SeType.label.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: (onDark ? SeColors.shellInk : SeColors.ink500).withValues(
            alpha: onDark ? 0.72 : 1,
          ),
        ),
      ),
    ],
  );
}
