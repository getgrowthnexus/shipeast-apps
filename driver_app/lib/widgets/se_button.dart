import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_motion.dart';

enum SeButtonVariant { primary, secondary, ghost, destructive }
enum SeButtonSize { large, medium, small }

/// SEDS button — one button for the whole app.
///
/// 2026 restyle: flat, pill-shaped, no gradients.
/// - `primary`: flat ACTION red (#E30D3B, white text 4.79:1) + a restrained lift.
/// - `secondary`: brand-soft fill, brand-ink text, no lift.
/// - `ghost`: bordered, transparent.
/// - `destructive`: danger-soft fill, deep-maroon text.
///
/// Press feedback: scale 0.97 + light haptic, honouring reduced-motion.
class SeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final SeButtonVariant variant;
  final SeButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  const SeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SeButtonVariant.primary,
    this.size = SeButtonSize.large,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  @override
  State<SeButton> createState() => _SeButtonState();
}

class _SeButtonState extends State<SeButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  double get _height => switch (widget.size) {
        SeButtonSize.large => 50,
        SeButtonSize.medium => 44,
        SeButtonSize.small => 36,
      };

  double get _fontSize => switch (widget.size) {
        SeButtonSize.large => 16,
        SeButtonSize.medium => 15,
        SeButtonSize.small => 13,
      };

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;

    final Color fg = switch (v) {
      SeButtonVariant.primary => Colors.white,
      SeButtonVariant.secondary => SeColors.brandInk,
      SeButtonVariant.ghost => SeColors.ink700,
      SeButtonVariant.destructive => SeColors.danger,
    };

    // Buttons are PILLS now, and flat: the signature CTA is the ACTION red as a
    // solid fill with a restrained lift — no ember gradient, no neon glow.
    final BoxDecoration deco = switch (v) {
      SeButtonVariant.primary => BoxDecoration(
          color: _enabled ? SeColors.brandAction : SeColors.red200,
          borderRadius: SeRadius.pill,
          boxShadow: _enabled && !_down ? SeElevation.glow : SeElevation.e0,
        ),
      SeButtonVariant.secondary => const BoxDecoration(
          color: SeColors.brandSoft,
          borderRadius: SeRadius.pill,
        ),
      SeButtonVariant.ghost => BoxDecoration(
          color: Colors.transparent,
          borderRadius: SeRadius.pill,
          border: Border.all(color: SeColors.ink200, width: 1.5),
        ),
      SeButtonVariant.destructive => const BoxDecoration(
          color: SeColors.dangerSoft,
          borderRadius: SeRadius.pill,
        ),
    };

    final content = widget.loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: _fontSize + 4, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  // Weight ladder: buttons sit at 600 (see SeType).
                  style: SeType.jakarta(_fontSize, FontWeight.w600, color: fg),
                ),
              ),
            ],
          );

    final scale = (_down && !SeMotion.reduced(context)) ? 0.97 : 1.0;

    return Opacity(
      opacity: _enabled ? 1 : 0.6,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        onTap: _enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedScale(
          scale: scale,
          duration: SeMotion.instant,
          curve: SeMotion.emphasized,
          child: AnimatedContainer(
            duration: SeMotion.fast,
            width: widget.expand ? double.infinity : null,
            height: _height,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: deco,
            child: content,
          ),
        ),
      ),
    );
  }
}
