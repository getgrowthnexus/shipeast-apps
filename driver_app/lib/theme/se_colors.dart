import 'package:flutter/material.dart';

/// ShipEast Design System — Color tokens.
///
/// Single source of truth for every colour in the driver app. Screens must
/// never hardcode a raw hex — pull from here (or from [SeTheme] semantic roles).
///
/// ── 2026 BRAND RESTYLE ────────────────────────────────────────────────────
/// Re-cut to match the admin panel exactly. Three ideas carry it:
///
///  1. TWO-TIER RED. The identity red [red500] (#F72B54, straight off the app
///     icon) is bright and NEVER carries small white text — it is for large
///     fills, plates, accents and focus rings. The action red [red600]
///     (#E30D3B) is the one that takes white on it (4.79:1) — buttons, links,
///     active states. A third, deeper [shell] (#B00D33) paints big permanent
///     brand SURFACES (hero headers, splash, auth) under warm-white ink.
///
///  2. BLUSH NEUTRALS. Surfaces are no longer white — they are a rose-tinted
///     white ([surface0] #FFF6F8 card, [surface50] #F8ECF0 ground). The hue is
///     the brand's at 3–6% saturation, so the red belongs to the same family as
///     its background instead of floating on a white sheet. Pure white survives
///     only as [surfaceRaised] (a focused field, an elevated pill).
///
///  3. NO GRADIENTS. Every ember/sunset gradient is retired to a FLAT brand
///     surface; depth comes from rose-black shadows + hairline rings, never a
///     sheen. The old gradient tokens survive as flat fills so call sites keep
///     compiling and render flat. (The one exception is [inkScrim] — a
///     legibility scrim over photos is a function, not a decoration.)
class SeColors {
  SeColors._();

  // ── Primary red ramp (two-tier — see class doc) ──────────────────────────
  static const Color red50 = Color(0xFFFFE8EE); // wash — must be visible on blush
  static const Color red100 = Color(0xFFFFD8E1); // hover tint, badges
  static const Color red200 = Color(0xFFFEC3CF); // disabled-on-tint
  static const Color red300 = Color(0xFFFC92A6); // subtle accents
  static const Color red400 = Color(0xFFFA5775); // brand text on dark (5.37:1)
  static const Color red500 = Color(0xFFF72B54); // IDENTITY — never small white text
  static const Color red600 = Color(0xFFE30D3B); // ACTION — white 4.79:1
  static const Color red700 = Color(0xFFB60C31); // red text on a red tint (5.84:1)
  static const Color red800 = Color(0xFF890B28); // deep
  static const Color red900 = Color(0xFF5C0A1F); // ramp floor

  /// Brand IDENTITY tone. Large fills, icon plates, accents, focus rings.
  /// NOT for small white text — use [brandAction] for anything with white on it.
  static const Color brand = red500;

  /// Brand ACTION tone. Primary buttons, links, active states — white on it
  /// clears AA (4.79:1).
  static const Color brandAction = red600;

  /// Red text sitting on a red tint (on [red50] / [brandSoft]).
  static const Color brandInk = red700;

  // ── The shell: a big FLAT brand surface ──────────────────────────────────
  /// The calm deep red for permanent brand surfaces — hero headers, splash,
  /// the auth hero. A field of the bright identity red would vibrate; this is
  /// the tone that carries warm-white text at 7.12:1. Mirrors the admin rail.
  static const Color shell = Color(0xFFB00D33);
  static const Color shellInk = Color(0xFFFFF4F7); // warm white ON the shell
  static const Color shellMark = Color(0xFFFFC9D6); // accent word on the shell

  // ── Retired gradients → flat brand surfaces ──────────────────────────────
  // The names survive so the ~20 screens that reference them keep compiling and
  // render FLAT. There are no gradients in the brand any more; a two-stop list
  // of one colour is a flat fill. Point new code at [shell] / [brandAction].
  static const List<Color> ember = [shell, shell, shell];
  static const List<double> emberStops = [0.0, 0.52, 1.0];
  static const List<Color> sunset = [shell, shell, shell];
  static const List<double> sunsetStops = [0.0, 0.55, 1.0];

  static const LinearGradient emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [shell, shell],
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [shell, shell],
  );

  /// Ink scrim — over photos/maps for legibility (top→bottom). KEPT: a scrim is
  /// a legibility device, not a brand gradient.
  static const LinearGradient inkScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00140F12), Color(0xB8140F12)],
  );

  // ── Supporting hues (retired → point at the new system) ──────────────────
  /// The one surviving gold — RATINGS ONLY.
  static const Color star = Color(0xFFE8A317);
  // Legacy aliases: `gold*` now means star/ratings, `ocean*` now means info.
  static const Color gold500 = star;
  static const Color goldTint = Color(0xFFFDF4E7); // → warningSoft
  static const Color ocean500 = Color(0xFF1F6BC1); // → info
  static const Color oceanTint = Color(0xFFEFF4FC); // → infoSoft

  // ── Semantic (muted, admin-matched) ──────────────────────────────────────
  static const Color success = Color(0xFF1C8252);
  static const Color successTint = Color(0xFFE4F6EC);
  static const Color successInk = Color(0xFF196B45);
  static const Color warning = Color(0xFFD37A0D);
  static const Color warningTint = Color(0xFFFCEFDC);
  static const Color warningInk = Color(0xFFAD640B);
  static const Color warningOn = Color(0xFF3D2A05); // dark ink on a solid warning fill
  static const Color danger = Color(0xFFA51D2F); // deep maroon — NOT brand red
  static const Color dangerTint = Color(0xFFFCE6E9);
  static const Color dangerInk = Color(0xFF821725);
  static const Color info = Color(0xFF1F6BC1);
  static const Color infoTint = Color(0xFFE6F0FB);
  static const Color infoInk = Color(0xFF1A579E);

  // ── Soft tones — a quieter step than the *Tint badges; legitimate SURFACES
  //    you may put text on (primary ink ≥12.5:1, tertiary ≥4.7:1). ──────────
  static const Color brandSoft = Color(0xFFFFF0F4);
  static const Color successSoft = Color(0xFFEFF8F2);
  static const Color warningSoft = Color(0xFFFDF4E7);
  static const Color infoSoft = Color(0xFFEFF4FC);
  static const Color dangerSoft = Color(0xFFFDEFF1);

  // ── Neutrals — rose-tinted (reads warm, not coloured) ────────────────────
  static const Color ink900 = Color(0xFF33292E); // primary text (14.0:1 on card)
  static const Color ink700 = Color(0xFF463940); // headings / body
  static const Color ink500 = Color(0xFF79676F); // secondary text (5.27:1)
  static const Color ink400 = Color(0xFF9C8B93); // placeholder / disabled (3.22:1)
  static const Color ink300 = Color(0xFFC9BAC1); // muted icons, faint
  static const Color ink200 = Color(0xFFE6DAE0); // dividers / borders (line)
  static const Color ink100 = Color(0xFFF0E6EB); // strong-but-light divider
  static const Color surface50 = Color(0xFFF8ECF0); // page ground (blush)
  static const Color surface0 = Color(0xFFFFF6F8); // cards (blush white)
  static const Color surfaceRaised = Color(0xFFFFFFFF); // lifted OFF a card: focused field, pill
  static const Color field = Color(0xFFFBEFF4); // a well you type into (sunken)

  // ── Dark theme roles (brand-hued surfaces, admin-matched) ────────────────
  static const Color darkBg = Color(0xFF140F12);
  static const Color darkCard = Color(0xFF241C21);
  static const Color darkCardRaised = Color(0xFF2F272B);
  static const Color darkTextHi = Color(0xFFF8ECF0);
  static const Color darkTextLo = Color(0xFFA99AA1);
  static const Color darkBorder = Color(0xFF3C3237);
  static const Color brandOnDark = Color(0xFFFA5775); // red400 — lift for AA on dark

  // ── Per-category hues (duotone chips) ─────────────────────────────────────
  static const Color catFood = red500;
  static const Color catFoodTint = brandSoft;
  static const Color catGrocery = success;
  static const Color catGroceryTint = successSoft;
  static const Color catPharmacy = info;
  static const Color catPharmacyTint = infoSoft;
  static const Color catPackages = warning;
  static const Color catPackagesTint = warningSoft;
}
