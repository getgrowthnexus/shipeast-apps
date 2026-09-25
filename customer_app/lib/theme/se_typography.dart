import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'se_colors.dart';

/// ShipEast Design System — Typography (SEDS §1.3).
///
/// Two families only: **Plus Jakarta Sans** for display/UI, **Inter** for
/// body/data. Retires Montserrat, Nunito and Dancing Script. Prices, stats and
/// timers use `tabular-nums` via [tabular].
class SeType {
  SeType._();

  static const _ink = SeColors.ink900;

  /// Feature: forces figures to a fixed width — use on prices/stats/timers.
  static const List<FontFeature> _tnum = [FontFeature.tabularFigures()];

  static TextStyle _jakarta({
    required double size,
    required double height,
    required FontWeight weight,
    Color? color,
    double? spacing,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? _ink,
      );

  static TextStyle _inter({
    required double size,
    required double height,
    required FontWeight weight,
    Color? color,
    double? spacing,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color ?? _ink,
      );

  // ── Scale ──────────────────────────────────────────────────────────────
  static TextStyle get display =>
      _jakarta(size: 32, height: 38, weight: FontWeight.w800, spacing: -0.6);
  static TextStyle get h1 =>
      _jakarta(size: 26, height: 32, weight: FontWeight.w800, spacing: -0.5);
  static TextStyle get h2 =>
      _jakarta(size: 22, height: 28, weight: FontWeight.w800, spacing: -0.4);
  static TextStyle get h3 =>
      _jakarta(size: 18, height: 24, weight: FontWeight.w700, spacing: -0.2);

  /// In-page section heading ("Categories", "Order History", …). Heavier and
  /// tighter than [h3] so section titles read like a real storefront, not a
  /// uniform-weight template. (SEDS §1.3)
  static TextStyle get section =>
      _jakarta(size: 19, height: 24, weight: FontWeight.w800, spacing: -0.35);

  static TextStyle get title =>
      _jakarta(size: 16, height: 22, weight: FontWeight.w700, spacing: -0.1);

  static TextStyle get body =>
      _inter(size: 15, height: 22, weight: FontWeight.w400, color: SeColors.ink700);
  static TextStyle get bodyS =>
      _inter(size: 13, height: 18, weight: FontWeight.w400, color: SeColors.ink500);
  static TextStyle get label => _inter(
      size: 12, height: 16, weight: FontWeight.w600, spacing: 0.4);
  static TextStyle get eyebrow => _inter(
        size: 11,
        height: 14,
        weight: FontWeight.w700,
        spacing: 0.8,
        color: SeColors.ink500,
      );

  /// Apply tabular figures to any price/stat/timer style.
  static TextStyle tabular(TextStyle base) =>
      base.copyWith(fontFeatures: _tnum);

  /// Convenience: a Jakarta text style at an arbitrary size/weight when the
  /// scale roles don't fit (kept rare — prefer the roles above).
  static TextStyle jakarta(double size, FontWeight weight, {Color? color}) =>
      _jakarta(size: size, height: size * 1.25, weight: weight, color: color);

  static TextStyle inter(double size, FontWeight weight,
          {Color? color, double? spacing}) =>
      _inter(
          size: size, height: size * 1.4, weight: weight, color: color, spacing: spacing);
}
