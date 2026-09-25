import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import 'se_button.dart';

/// Empty / error state — tinted glyph medallion + copy + optional CTA
/// (SEDS §1.6). Replaces one-off icons and CustomPaint blanks.
class SeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color hue;
  final Color tint;
  final EdgeInsetsGeometry padding;

  const SeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.ctaLabel,
    this.onCta,
    this.hue = SeColors.red500,
    this.tint = SeColors.red50,
    this.padding = const EdgeInsets.symmetric(
        horizontal: SeSpacing.gutter, vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Layered medallion for a bit of depth (not a flat grey glyph).
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: hue.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 38, color: hue),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: SeType.h3,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
          ],
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 20),
            SeButton(
              label: ctaLabel!,
              onPressed: onCta,
              expand: false,
              size: SeButtonSize.medium,
            ),
          ],
        ],
      ),
    );
  }
}
