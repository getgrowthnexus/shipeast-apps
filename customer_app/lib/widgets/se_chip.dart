import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// Small pill chip — used for filters, tags and info bits (SEDS §1.4).
class SeChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color fg;
  final Color bg;
  final bool selected;
  final VoidCallback? onTap;

  const SeChip({
    super.key,
    required this.label,
    this.icon,
    this.fg = SeColors.ink700,
    this.bg = SeColors.surface0,
    this.selected = false,
    this.onTap,
  });

  /// A soft status/semantic pill (e.g. Open / Closed / Delivered).
  factory SeChip.status({
    required String label,
    required Color color,
    required Color tint,
  }) =>
      SeChip(label: label, fg: color, bg: tint);

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: SeRadius.pill,
        border: selected
            ? Border.all(color: SeColors.red500, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: SeType.label.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(onTap: onTap, child: chip);
  }
}

/// Category tile — 56dp duotone glyph on a soft tinted circle (SEDS §1.5).
class SeCategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color hue;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  const SeCategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.hue,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Squircle tile, not a bare floating circle: an unselected tile carries a
    // soft tint fill + hairline so it reads as a *surface* sitting on the page,
    // and the selected tile fills with its hue and lifts a touch. This is the
    // difference between "icons dropped on a blank page" and a real storefront.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(hue, Colors.white, 0.18)!, hue],
                    )
                  : null,
              color: selected ? null : tint,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? null
                  : Border.all(color: hue.withValues(alpha: 0.14), width: 1),
              boxShadow: selected
                  ? SeElevation.glowColor(hue, opacity: 0.24)
                  : SeElevation.e0,
            ),
            child: Icon(icon, size: 27, color: selected ? Colors.white : hue),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: SeType.label.copyWith(
              color: selected ? SeColors.ink900 : SeColors.ink500,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
