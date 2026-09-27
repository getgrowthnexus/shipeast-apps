import 'package:flutter/material.dart';
import 'se_colors.dart';

/// ShipEast Design System — Spacing, radius & elevation tokens.
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

/// Corner radii.
///
/// ── 2026 BRAND RESTYLE ────────────────────────────────────────────────────
/// Re-widened to the admin's scale and, crucially, BUTTONS ARE NOW PILLS. Next
/// to a pill chip, a pill tab and a pill toggle, a chamfered button was the odd
/// one out; every consumer brand this app is measured against has been fully
/// rounded for years. `full` stays for genuine circles (avatars, dots, FAB).
class SeRadius {
  SeRadius._();

  static const double xs = 8;  // small chips, tiny controls
  static const double sm = 12; // inputs, list rows
  static const double md = 16; // cards, tiles
  static const double lg = 22; // large cards, sheets
  static const double xl = 28; // hero, bottom-sheet top
  static const double full = 999; // pills, avatars, FAB, BUTTONS

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

/// Layered, rose-black shadows — the admin's "light clay" depth.
///
/// Shadows are cast in ROSE-BLACK (a deep plum, not neutral black): over a
/// blush ground a neutral shadow turns grey and fights the palette. Each level
/// pairs a tight contact shadow with a wider soft pool (negative spread keeps
/// the pool under the card, not haloing sideways).
class SeElevation {
  SeElevation._();

  // Rose-black shadow ink — Color.fromRGBO is a const constructor, so these
  // lists stay `const` and remain usable inside const decorations.
  static const List<BoxShadow> e0 = [];

  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .05), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .07), blurRadius: 6, spreadRadius: -2, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .05), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .08), blurRadius: 12, spreadRadius: -3, offset: Offset(0, 6)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .09), blurRadius: 28, spreadRadius: -10, offset: Offset(0, 14)),
  ];

  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .06), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .11), blurRadius: 24, spreadRadius: -6, offset: Offset(0, 12)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .15), blurRadius: 56, spreadRadius: -18, offset: Offset(0, 28)),
  ];

  static const List<BoxShadow> e4 = [
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .07), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .15), blurRadius: 40, spreadRadius: -8, offset: Offset(0, 20)),
    BoxShadow(color: Color.fromRGBO(110, 26, 48, .24), blurRadius: 88, spreadRadius: -28, offset: Offset(0, 48)),
  ];

  /// The lift under the ONE hero action per screen. The old neon halo is gone
  /// (it was the biggest "AI" tell) — this is a restrained brand-tinted drop
  /// that reads as a lift, not a glow. Matches the admin's flat-fill ethos.
  /// (227,13,59 = brandAction #E30D3B.)
  static const List<BoxShadow> glow = [
    BoxShadow(
      color: Color.fromRGBO(227, 13, 59, 0.20),
      blurRadius: 18,
      spreadRadius: -4,
      offset: Offset(0, 8),
    ),
  ];

  /// A restrained tinted lift in an arbitrary hue (category tiles, etc.).
  static List<BoxShadow> glowColor(Color c, {double opacity = 0.18}) => [
        BoxShadow(
          color: c.withValues(alpha: opacity),
          blurRadius: 18,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
      ];

  /// Resting-card hairline used with the [e0]/flat tier — the "ring" edge.
  static Border hairline = Border.all(color: SeColors.ink200, width: 1);
}
