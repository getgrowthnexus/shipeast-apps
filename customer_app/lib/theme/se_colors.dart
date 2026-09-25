import 'package:flutter/material.dart';

/// ShipEast Design System — Color tokens (SEDS §1.2).
///
/// Single source of truth for every colour in the customer app. Screens must
/// never hardcode a raw hex — pull from here (or from [SeTheme] semantic roles).
class SeColors {
  SeColors._();

  // ── Primary red ramp (replaces the single flat #C8102E) ──────────────────
  static const Color red50 = Color(0xFFFFF1F3); // tint bg, selected chip fill
  static const Color red100 = Color(0xFFFFE0E5); // hover tint, badges
  static const Color red200 = Color(0xFFF7B9C2); // disabled-on-tint
  static const Color red300 = Color(0xFFEE8492); // subtle accents
  static const Color red400 = Color(0xFFE1495F); // gradient lift, focus on dark
  static const Color red500 = Color(0xFFC8102E); // BRAND CORE (unchanged)
  static const Color red600 = Color(0xFFA80D26); // pressed / hover on solid
  static const Color red700 = Color(0xFF86091E); // text-on-tint, deep
  static const Color red800 = Color(0xFF5F0615); // gradient tail
  static const Color red900 = Color(0xFF3D0410); // on-dark surfaces

  static const Color brand = red500;

  // ── Signature gradients (the "realism" upgrade) ──────────────────────────
  /// Ember — default brand gradient (heroes, primary CTAs, FAB, splash).
  static const List<Color> ember = [
    Color(0xFFE11D34),
    Color(0xFFC8102E),
    Color(0xFF9A0B22),
  ];
  static const List<double> emberStops = [0.0, 0.52, 1.0];

  /// Sunset — energy moments (order confirmed, promo, earnings win).
  static const List<Color> sunset = [
    Color(0xFFFF6A3D),
    Color(0xFFE11D34),
    Color(0xFFC8102E),
  ];
  static const List<double> sunsetStops = [0.0, 0.55, 1.0];

  /// Ember gradient (135°) ready to drop into a [BoxDecoration].
  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: ember,
    stops: emberStops,
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: sunset,
    stops: sunsetStops,
  );

  /// Ink scrim — over photos/maps for legibility (top→bottom).
  static const LinearGradient inkScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0014120F), Color(0xB814120F)],
  );

  // ── Supporting hues (the ONLY two; used sparingly) ───────────────────────
  static const Color gold500 = Color(0xFFF5A524); // rating, premium, earnings
  static const Color goldTint = Color(0xFFFEF3E2);
  static const Color ocean500 = Color(0xFF0E9488); // live/track/info/links
  static const Color oceanTint = Color(0xFFE5F6F4);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF16A34A);
  static const Color successTint = Color(0xFFE6F6EC);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningTint = Color(0xFFFEF3E2);
  static const Color danger = Color(0xFFD92D20); // destructive — NOT brand red
  static const Color dangerTint = Color(0xFFFDECEA);
  static const Color info = Color(0xFF0E9488);
  static const Color infoTint = Color(0xFFE5F6F4);

  // ── Neutrals — warm-biased (reads premium; not cold #F5F5F7) ──────────────
  static const Color ink900 = Color(0xFF1C1A17); // primary text, near-black
  static const Color ink700 = Color(0xFF3A362F); // headings on light
  static const Color ink500 = Color(0xFF6B6459); // secondary text
  static const Color ink400 = Color(0xFF938C7F); // placeholder, disabled text
  static const Color ink300 = Color(0xFFC7C0B4); // icons-muted
  static const Color ink200 = Color(0xFFE4E0D9); // dividers/borders
  static const Color ink100 = Color(0xFFECEAE6); // strong divider
  static const Color surface50 = Color(0xFFFAF9F7); // app background (warm)
  static const Color surface0 = Color(0xFFFFFFFF); // cards

  // ── Dark theme roles ─────────────────────────────────────────────────────
  static const Color darkBg = Color(0xFF141310);
  static const Color darkCard = Color(0xFF201E1A);
  static const Color darkCardRaised = Color(0xFF2A2823);
  static const Color darkTextHi = Color(0xFFF5F2EC);
  static const Color darkTextLo = Color(0xFFA49E92);
  static const Color darkBorder = Color(0xFF33302A);
  static const Color brandOnDark = Color(0xFFF04A5E); // lift for AA on dark

  // ── Per-category hues (duotone chips, SEDS §1.5) ─────────────────────────
  static const Color catFood = red500;
  static const Color catFoodTint = red50;
  static const Color catGrocery = success;
  static const Color catGroceryTint = successTint;
  static const Color catPharmacy = ocean500;
  static const Color catPharmacyTint = oceanTint;
  static const Color catPackages = gold500;
  static const Color catPackagesTint = goldTint;
}
