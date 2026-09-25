import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// Gradient hero header (SEDS §2.2) — Ember ground with a back button, title
/// and optional subtitle/trailing. Use for detail screens that want brand depth.
class SeGradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showBack;
  final VoidCallback? onBack;
  final Gradient gradient;
  final EdgeInsets padding;

  const SeGradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBack = true,
    this.onBack,
    this.gradient = SeColors.emberGradient,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 16, 20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showBack)
                _CircleButton(
                  icon: SeIcons.arrowLeft,
                  onTap: onBack ?? () => Navigator.maybePop(context),
                )
              else
                const SizedBox(width: 4),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: SeType.h3.copyWith(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: SeType.bodyS.copyWith(
                              color: Colors.white.withValues(alpha: 0.82)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Plain white app bar with a bordered back button (the "white + back" variant).
class SeTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> actions;
  final bool showBack;

  const SeTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.showBack = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: showBack ? 4 : SeSpacing.gutter,
      leading: showBack
          ? Center(
              child: _CircleButton(
                icon: SeIcons.arrowLeft,
                bg: SeColors.surface50,
                fg: SeColors.ink900,
                onTap: () => Navigator.maybePop(context),
              ),
            )
          : null,
      title: Text(title, style: SeType.h3.copyWith(color: scheme.onSurface)),
      actions: actions,
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color fg;
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.bg = const Color(0x33FFFFFF),
    this.fg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: fg),
      ),
    );
  }
}
