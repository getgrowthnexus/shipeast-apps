import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'se_colors.dart';

/// ShipEast Design System — Typography.
///
/// ── 2026 BRAND RESTYLE ────────────────────────────────────────────────────
/// ONE FACE: **Figtree**, and nothing else. This matches the admin panel, which
/// went through three pairings before landing here — the lesson being that a
/// display/UI family split (Jakarta over Inter) puts a SEAM through every
/// screen: two different ideas of what a letter is, read as two products glued
/// together. Figtree is a warm geometric sans whose heavy weights hold their
/// counters at display sizes and whose 400 is quiet enough for body copy, so it
/// carries both jobs alone.
///
/// The hierarchy that used to be carried by SWAPPING FACES is now carried by
/// the WEIGHT LADDER — and the ladder is the system:
///
///   800  display, page titles, big figures — the things allowed to be loud.
///   700  card / sheet / section titles (≥ [title]). The heaviest a heading gets.
///   600  ALL emphasis below title: buttons, labels, tabs, badges, eyebrows.
///   500  secondary values, the one step below normal emphasis.
///   400  body, descriptions, help text.
///
/// The two legacy constructors [jakarta] and [inter] are kept as call-site
/// aliases — both now return Figtree — so the whole app converges on one face
/// without editing every reference. Prices/stats/timers use [tabular].
class SeType {
  SeType._();

  static const _ink = SeColors.ink900;

  /// Feature: forces figures to a fixed width — use on prices/stats/timers.
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static TextStyle _fig({
    required double size,
    required double height,
    required FontWeight weight,
    Color? color,
    double? spacing,
  }) =>
      GoogleFonts.figtree(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? _ink,
      );

  // ── Scale ──────────────────────────────────────────────────────────────
  static TextStyle get display =>
      _fig(size: 32, height: 38, weight: FontWeight.w800, spacing: -0.7);

  /// The signed-out hero, and only that. One step past [display] in both size
  /// and weight: Figtree **Black**, the ninth weight, bundled for this line
  /// alone. It earns the exception because the welcome screen has exactly one
  /// thing to say and the whole screen is built around it — everywhere else,
  /// reaching past 800 would flatten the ladder rather than extend it.
  ///
  /// Leading is set near 1.05 because a two-line headline at this size wants
  /// the lines locked together as a single shape; the default 1.19 pulls them
  /// apart into two separate sentences.
  static TextStyle hero(double size) => _fig(
        size: size,
        height: size * 1.05,
        weight: FontWeight.w900,
        spacing: -size * 0.028,
      );
  static TextStyle get h1 =>
      _fig(size: 26, height: 32, weight: FontWeight.w800, spacing: -0.6);
  static TextStyle get h2 =>
      _fig(size: 22, height: 28, weight: FontWeight.w800, spacing: -0.5);
  static TextStyle get h3 =>
      _fig(size: 18, height: 24, weight: FontWeight.w700, spacing: -0.3);

  /// In-page section heading ("Categories", "Order History", …). The heaviest
  /// heading — loud enough to read like a real storefront, not a template.
  static TextStyle get section =>
      _fig(size: 19, height: 24, weight: FontWeight.w800, spacing: -0.4);

  static TextStyle get title =>
      _fig(size: 16, height: 22, weight: FontWeight.w700, spacing: -0.2);

  static TextStyle get body =>
      _fig(size: 15, height: 22, weight: FontWeight.w400, color: SeColors.ink700);
  static TextStyle get bodyS =>
      _fig(size: 13, height: 18, weight: FontWeight.w400, color: SeColors.ink500);
  static TextStyle get label =>
      _fig(size: 12, height: 16, weight: FontWeight.w600, spacing: 0.3);
  static TextStyle get eyebrow => _fig(
        size: 11,
        height: 14,
        weight: FontWeight.w600,
        spacing: 0.7,
        color: SeColors.ink500,
      );

  /// Apply tabular figures to any price/stat/timer style.
  static TextStyle tabular(TextStyle base) =>
      base.copyWith(fontFeatures: _tnum);

  /// Legacy alias — was Plus Jakarta Sans, now Figtree. A display-weight face
  /// at an arbitrary size/weight when the scale roles don't fit (kept rare).
  static TextStyle jakarta(double size, FontWeight weight, {Color? color}) =>
      _fig(size: size, height: size * 1.25, weight: weight, color: color);

  /// Legacy alias — was Inter, now Figtree. Body-weight face at an arbitrary
  /// size/weight.
  static TextStyle inter(double size, FontWeight weight,
          {Color? color, double? spacing}) =>
      _fig(
          size: size, height: size * 1.4, weight: weight, color: color, spacing: spacing);
}
