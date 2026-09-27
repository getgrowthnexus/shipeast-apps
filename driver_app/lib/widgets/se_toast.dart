import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_motion.dart';

enum SeToastKind { success, error, info, brand }

/// Top slide-in toast with icon + colour rail (SEDS §1.7) — replaces every
/// snackbar. Call `SeToast.show(context, 'Saved')`.
class SeToast {
  SeToast._();

  static void show(
    BuildContext context,
    String message, {
    SeToastKind kind = SeToast.defaultKind,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _SeToastWidget(
        message: message,
        kind: kind,
        duration: duration,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }

  static const SeToastKind defaultKind = SeToastKind.brand;

  static void success(BuildContext c, String m) =>
      show(c, m, kind: SeToastKind.success);
  static void error(BuildContext c, String m) =>
      show(c, m, kind: SeToastKind.error);
  static void info(BuildContext c, String m) =>
      show(c, m, kind: SeToastKind.info);
}

class _SeToastWidget extends StatefulWidget {
  final String message;
  final SeToastKind kind;
  final Duration duration;
  final VoidCallback onDismiss;

  const _SeToastWidget({
    required this.message,
    required this.kind,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_SeToastWidget> createState() => _SeToastWidgetState();
}

class _SeToastWidgetState extends State<_SeToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: SeMotion.base);
    _slide = Tween(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: SeMotion.decelerate));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  ({Color color, Color tint, IconData icon}) get _spec => switch (widget.kind) {
        SeToastKind.success => (
            color: SeColors.success,
            tint: SeColors.successTint,
            icon: SeIcons.checkCircle
          ),
        SeToastKind.error => (
            color: SeColors.danger,
            tint: SeColors.dangerTint,
            icon: SeIcons.warningCircle
          ),
        SeToastKind.info => (
            color: SeColors.info,
            tint: SeColors.infoTint,
            icon: SeIcons.info
          ),
        SeToastKind.brand => (
            color: SeColors.brand,
            tint: SeColors.brandSoft,
            icon: SeIcons.info
          ),
      };

  @override
  Widget build(BuildContext context) {
    final s = _spec;
    final media = MediaQuery.of(context);
    return Positioned(
      top: media.padding.top + 10,
      left: SeSpacing.gutter,
      right: SeSpacing.gutter,
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                decoration: BoxDecoration(
                  color: SeColors.surface0,
                  borderRadius: SeRadius.all(SeRadius.md),
                  boxShadow: SeElevation.e3,
                ),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 5, color: s.color),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: s.tint, shape: BoxShape.circle),
                          child: Icon(s.icon, size: 19, color: s.color),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                          child: Text(
                            widget.message,
                            style: SeType.body.copyWith(
                                color: SeColors.ink900,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
