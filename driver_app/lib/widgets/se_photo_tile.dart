import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// Proof-of-delivery photo control (PLAN §3.2 — Pickup / Delivery).
///
/// Empty state is an inviting dashed camera tile; once a photo exists it
/// cross-fades to a full-bleed preview with an ink scrim and a Retake action,
/// so the driver can always see what they actually captured before submitting.
class SePhotoTile extends StatelessWidget {
  final File? photo;
  final VoidCallback onCapture;
  final String emptyLabel;
  final String emptyHint;
  final double height;

  /// Draws the tile in a danger tone when the form was submitted without it.
  final bool errored;

  const SePhotoTile({
    super.key,
    required this.photo,
    required this.onCapture,
    this.emptyLabel = 'Take a photo',
    this.emptyHint = 'Required as proof of delivery',
    this.height = 200,
    this.errored = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: SeMotion.reduced(context) ? Duration.zero : SeMotion.base,
      switchInCurve: SeMotion.decelerate,
      child: photo == null ? _empty(context) : _preview(context),
    );
  }

  Widget _empty(BuildContext context) {
    final hue = errored ? SeColors.danger : SeColors.red500;
    final tint = errored ? SeColors.dangerTint : SeColors.red50;

    return GestureDetector(
      key: const ValueKey('empty'),
      onTap: onCapture,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(color: hue.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: hue.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(SeIcons.camera, size: 30, color: hue),
            ),
            const SizedBox(height: SeSpacing.x3),
            Text(emptyLabel, style: SeType.title.copyWith(color: hue)),
            const SizedBox(height: SeSpacing.x1),
            Text(
              emptyHint,
              style: SeType.bodyS.copyWith(
                  color: errored ? SeColors.danger : SeColors.ink500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    return Container(
      key: const ValueKey('preview'),
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: SeRadius.all(SeRadius.md),
        boxShadow: SeElevation.e2,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(photo!, fit: BoxFit.cover),
          // Scrim so the Retake chip stays legible over any photo.
          const DecoratedBox(
            decoration: BoxDecoration(gradient: SeColors.inkScrim),
          ),
          Positioned(
            left: SeSpacing.x3,
            bottom: SeSpacing.x3,
            child: Row(
              children: [
                const Icon(SeIcons.checkCircle,
                    size: 18, color: SeColors.success),
                const SizedBox(width: 6),
                Text('Photo captured',
                    style: SeType.label.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Positioned(
            right: SeSpacing.x3,
            bottom: SeSpacing.x3,
            child: GestureDetector(
              onTap: onCapture,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: SeRadius.pill,
                  boxShadow: SeElevation.e1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(SeIcons.retake, size: 16, color: SeColors.ink900),
                    const SizedBox(width: 6),
                    Text('Retake',
                        style: SeType.label.copyWith(color: SeColors.ink900)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
