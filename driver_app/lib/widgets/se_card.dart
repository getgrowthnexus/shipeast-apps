import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_spacing.dart';
import '../theme/se_motion.dart';

/// A content card. Optional press feedback when [onTap] is set.
///
/// 2026 restyle: the default tier is now **flat + hairline**, not a drop
/// shadow. Every card in this app sits inside the lifted blush sheet, and
/// stacking shadows on a surface that is already raised is what made the old
/// screens read as a pile of receipts. Pass an explicit [shadow] for the rare
/// thing that genuinely floats (a docked bar, a sheet).
class SeCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow> shadow;
  final double radius;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;
  final bool clip;

  const SeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SeSpacing.cardPad),
    this.margin,
    this.shadow = SeElevation.e0,
    this.radius = SeRadius.md,
    this.color,
    this.border,
    this.onTap,
    this.clip = false,
  });

  @override
  State<SeCard> createState() => _SeCardState();
}

class _SeCardState extends State<SeCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Neutral surface cards get a hairline edge by default so they read as a
    // crafted surface, not a floating shadow blob (the "AI" look). Cards that
    // pass an explicit colour (coloured hero/status cards) are left alone.
    final border =
        widget.border ?? (widget.color == null ? SeElevation.hairline : null);
    final deco = BoxDecoration(
      color: widget.color ?? scheme.surface,
      borderRadius: SeRadius.all(widget.radius),
      boxShadow: _down ? SeElevation.e0 : widget.shadow,
      border: border,
    );

    Widget card = AnimatedContainer(
      duration: SeMotion.instant,
      curve: SeMotion.emphasized,
      padding: widget.padding,
      decoration: deco,
      clipBehavior: widget.clip ? Clip.antiAlias : Clip.none,
      child: widget.child,
    );

    if (widget.onTap == null) {
      return widget.margin == null
          ? card
          : Padding(padding: widget.margin!, child: card);
    }

    final scale = (_down && !SeMotion.reduced(context)) ? 0.985 : 1.0;
    card = GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: scale,
        duration: SeMotion.instant,
        child: card,
      ),
    );

    return widget.margin == null
        ? card
        : Padding(padding: widget.margin!, child: card);
  }
}
