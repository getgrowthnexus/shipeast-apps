import 'package:flutter/material.dart';
import 'se_colors.dart';

/// ShipEast Design System — Spacing, radius & elevation tokens (SEDS §1.4).
class SeSpacing {
  SeSpacing._();

  // Strict 4pt grid.
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;

  /// Standard screen side gutter.
  static const double gutter = 20;
  static const double cardPad = 16;
}

/// Corner radii — a deliberately tight scale. Kept crisp rather than bubbly so
/// the UI reads as a sharp, modern product; `full` stays for genuine circles
/// (avatars, dots, FAB) and pill chips.
class SeRadius {
  SeRadius._();

  static const double xs = 5; // small chips, tiny controls
  static const double sm = 7; // inputs, list rows
  static const double md = 9; // cards, buttons
  static const double lg = 12; // large cards, sheets
  static const double xl = 16; // hero, bottom-sheet top
  static const double full = 999; // pills, avatars, FAB

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const BorderRadius cardRadius =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius inputRadius =
      BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pill =
      BorderRadius.all(Radius.circular(full));
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Layered, warm-tinted shadows (never a single flat black drop).
class SeElevation {
  SeElevation._();

  static const List<BoxShadow> e0 = [];

  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color(0x0A1C1A17), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F1C1A17), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color(0x141C1A17), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D1C1A17), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color(0x1F1C1A17), blurRadius: 28, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> e4 = [
    BoxShadow(color: Color(0x2E1C1A17), blurRadius: 48, offset: Offset(0, 20)),
  ];

  /// The signature red glow that makes the primary CTA/FAB float. Kept for the
  /// one hero action per screen — a softer, tighter drop than before so it reads
  /// as a lift, not a neon halo (the old 0x4D/22px halo was the biggest "AI"
  /// tell when stacked under buttons, toggles and pills at once).
  static const List<BoxShadow> glow = [
    BoxShadow(color: Color(0x33C8102E), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static List<BoxShadow> glowColor(Color c, {double opacity = 0.22}) => [
        BoxShadow(
          color: c.withValues(alpha: opacity),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  /// Resting-card border used with the [e0]/flat tier.
  static Border hairline = Border.all(color: SeColors.ink200, width: 1);
}
