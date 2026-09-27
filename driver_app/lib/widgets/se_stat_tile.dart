import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_motion.dart';

/// Stat tile with a count-up value and a tinted icon plate.
///
/// 2026 restyle: flat + hairline (it sits inside the lifted sheet), and the
/// icon rides a rounded SQUARE plate rather than a circle — the same plate
/// shape [SeRow] uses, so a figure and a menu row read as one family.
class SeStatTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Numeric value that will count up on first paint.
  final num value;

  /// Optional prefix/suffix wrapped around the (formatted) number.
  final String prefix;
  final String suffix;
  final int decimals;

  /// Group the whole part with thousands separators.
  ///
  /// On by default, because every figure this tile carries is money or a count
  /// and both are read faster grouped. Without it a week's earnings rendered as
  /// `$18640`, which is the one number on the screen you have to stop and
  /// count digits in — and it disagreed with `Money.format` everywhere else.
  final bool grouped;
  final Color hue;
  final Color tint;

  const SeStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.grouped = true,
    this.hue = SeColors.brandAction,
    this.tint = SeColors.brandSoft,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(color: SeColors.ink200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: Icon(icon, size: 20, color: hue),
          ),
          const SizedBox(height: 12),
          _CountUp(
            value: value.toDouble(),
            decimals: decimals,
            grouped: grouped,
            builder: (v) => Text(
              '$prefix$v$suffix',
              style: SeType.tabular(SeType.h2).copyWith(color: SeColors.ink900),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: SeType.bodyS.copyWith(color: SeColors.ink500)),
        ],
      ),
    );
  }
}

/// Animated number that counts from 0 → [value] once on mount.
class _CountUp extends StatefulWidget {
  final double value;
  final int decimals;
  final bool grouped;
  final Widget Function(String formatted) builder;
  const _CountUp({
    required this.value,
    required this.decimals,
    required this.grouped,
    required this.builder,
  });

  @override
  State<_CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<_CountUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0, end: widget.value)
        .animate(CurvedAnimation(parent: _ctrl, curve: SeMotion.decelerate));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _CountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _anim.value, end: widget.value)
          .animate(CurvedAnimation(parent: _ctrl, curve: SeMotion.decelerate));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => widget.builder(_format(_anim.value)),
    );
  }

  String _format(double v) {
    final text = v.toStringAsFixed(widget.decimals);
    if (!widget.grouped) return text;
    final dot = text.indexOf('.');
    final whole = dot == -1 ? text : text.substring(0, dot);
    final rest = dot == -1 ? '' : text.substring(dot);
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return '$buf$rest';
  }
}
