import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// The chrome every in-app screen is built on — the app-wide counterpart to
/// `SeAuthScaffold`, and the reason the signed-in app now reads as the same
/// product as the sign-up path.
///
/// Two surfaces, always the same two. A flat brand **cap** says where you are
/// and gives you the way out; a blush **sheet** lifted over it holds the task.
/// The cap never scrolls and the sheet always does, so the answer to "where am
/// I" stays on screen while the content moves under it.
///
/// Why a shared shell at all: before this, thirteen screens each invented their
/// own header — some a gradient hero, some a white app bar, some nothing — and
/// the app read as a set of pages built by different people on different days.
/// One shell is what makes it feel like software rather than a collection of
/// screens.
///
/// The sheet's top radius and its upward shadow are the whole trick. The
/// shadow is cast UP onto the red, which is what makes the sheet look like a
/// card lying on the brand rather than a region where the colour stops.
class SePageScaffold extends StatelessWidget {
  /// The page title, in the cap. Kept short — this is a label, not a sentence.
  final String title;

  /// One quiet line under the title. Omit it rather than pad it out.
  final String? subtitle;

  /// Sits opposite the title — an avatar, a count, one icon action.
  final Widget? trailing;

  /// Occupies the foot of the cap, below the title: a search field, a
  /// segmented control, a row of filters. It sits ON the red, so its contents
  /// must be styled for the shell.
  final Widget? capBottom;

  /// Shown instead of [title] when the screen leads with something richer
  /// (the home greeting block, a merchant identity). Replaces the whole
  /// title/subtitle stack.
  final Widget? capTitle;

  final bool showBack;
  final VoidCallback? onBack;

  /// The sheet body. Pass a scrollable — this does not add one, because half
  /// these screens need a `CustomScrollView` or a `ListView.builder` and
  /// wrapping those in a `SingleChildScrollView` is how you get an unbounded
  /// height crash.
  final Widget child;

  /// Docked to the bottom of the sheet, above the safe area and outside the
  /// scroll: a cart total, a "Place order" bar.
  final Widget? bottomBar;

  final Widget? floatingActionButton;

  const SePageScaffold({
    super.key,
    this.title = '',
    this.subtitle,
    this.trailing,
    this.capBottom,
    this.capTitle,
    this.showBack = true,
    this.onBack,
    required this.child,
    this.bottomBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showsBack = showBack && (canPop || onBack != null);

    return Scaffold(
      backgroundColor: SeColors.shell,
      floatingActionButton: floatingActionButton,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                SeSpacing.gutter,
                showsBack ? 6 : 12,
                SeSpacing.gutter,
                capBottom == null ? 22 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showsBack) ...[
                    SeCapButton(
                      icon: SeIcons.arrowLeft,
                      onTap: onBack ?? () => Navigator.maybePop(context),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: capTitle ??
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  style: SeType.h1.copyWith(
                                    color: SeColors.shellInk,
                                    height: 1.15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    subtitle!,
                                    style: SeType.bodyS.copyWith(
                                      color: SeColors.shellInk
                                          .withValues(alpha: 0.76),
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 12),
                        trailing!,
                      ],
                    ],
                  ),
                  if (capBottom != null) ...[
                    const SizedBox(height: 16),
                    capBottom!,
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: SeSheet(bottomBar: bottomBar, child: child)),
        ],
      ),
    );
  }
}

/// The blush sheet, lifted over the brand. Split out so screens that build
/// their own cap (a merchant hero, a live-tracking header) still get the exact
/// same sheet edge as everything else.
class SeSheet extends StatelessWidget {
  final Widget child;
  final Widget? bottomBar;

  const SeSheet({super.key, required this.child, this.bottomBar});

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: SeColors.surface50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(SeRadius.xl)),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(70, 8, 24, 0.22),
              blurRadius: 28,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: child),
            if (bottomBar != null)
              // The gesture inset below the bar has to be painted in the BAR's
              // colour, not the sheet's, or a docked bar sits on a stripe of a
              // slightly different pink and reads as a rendering fault.
              ColoredBox(
                color: SeColors.surface0,
                child: SafeArea(top: false, child: bottomBar!),
              ),
          ],
        ),
      );
}

/// A control that has to survive on the red: a translucent well rather than a
/// bare glyph, so it stays legible without punching a white hole in the brand.
class SeCapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  const SeCapButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: SeColors.shellInk),
            ),
            if (badge > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: SeColors.shellMark,
                    borderRadius: SeRadius.pill,
                    border: Border.all(color: SeColors.shell, width: 1.5),
                  ),
                  child: Text(
                    badge > 9 ? '9+' : '$badge',
                    textAlign: TextAlign.center,
                    style: SeType.tabular(
                      SeType.inter(9, FontWeight.w800, color: SeColors.shell),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// A white pill field that sits ON the brand cap.
///
/// Home shows a non-interactive one as a doorway into search; search shows a
/// live one. Both come from here, so tapping the first lands on something that
/// looks identical rather than something that merely resembles it.
class SeShellField extends StatelessWidget {
  final String hint;

  /// Null makes it a button: the whole field is tappable and there is no cursor.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool showClear;

  const SeShellField({
    super.key,
    required this.hint,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onTap,
    this.onClear,
    this.showClear = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: SeColors.surfaceRaised,
        borderRadius: SeRadius.pill,
      ),
      child: Row(
        children: [
          const Icon(SeIcons.search, size: 20, color: SeColors.ink400),
          const SizedBox(width: 10),
          Expanded(
            child: controller == null
                ? Text(hint,
                    style: SeType.body.copyWith(color: SeColors.ink400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)
                : TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: SeType.body.copyWith(color: SeColors.ink900),
                    cursorColor: SeColors.brandAction,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: SeType.body.copyWith(color: SeColors.ink400),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: onChanged,
                  ),
          ),
          if (showClear)
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(SeIcons.close, size: 18, color: SeColors.ink400),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// A filter chip on the brand cap. Selected goes solid warm-white; unselected
/// is a translucent well — the same language as the cap's back button.
class SeShellChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const SeShellChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? SeColors.shellInk
                : Colors.white.withValues(alpha: 0.14),
            borderRadius: SeRadius.pill,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: selected ? SeColors.shell : SeColors.shellMark),
              const SizedBox(width: 6),
              Text(
                label,
                style: SeType.label.copyWith(
                  color: selected ? SeColors.shell : SeColors.shellInk,
                ),
              ),
            ],
          ),
        ),
      );
}

/// A segmented control that lives on the brand cap.
///
/// One track, no shadows, no lift animation. The previous version was a row of
/// gradient pills that grew a glow and dropped it again on every tap — the
/// loudest "generated UI" tell in the app, and genuinely distracting to use.
class SeShellTabs extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  const SeShellTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: SeRadius.pill,
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final on = i == selected;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: on ? SeColors.shellInk : Colors.transparent,
                    borderRadius: SeRadius.pill,
                  ),
                  child: Center(
                    child: Text(
                      tabs[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeType.label.copyWith(
                        fontSize: 12,
                        color: on
                            ? SeColors.shell
                            : SeColors.shellInk.withValues(alpha: 0.82),
                        fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      );
}

/// In-sheet section heading, with an optional text action on the right.
///
/// The action is text, never a second button: a screen gets one filled pill and
/// the rest of its affordances are words.
class SeSectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SeSectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: SeType.section)),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: SeType.label.copyWith(color: SeColors.brandAction),
                    ),
                    const Icon(SeIcons.caretRight,
                        size: 15, color: SeColors.brandAction),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// The sheet's own docked action bar — one hairline, then the action.
///
/// It carries the hairline itself (rather than the caller adding a Divider) so
/// every screen's docked bar detaches from the scrolling content the same way.
class SeBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const SeBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
        SeSpacing.gutter, 14, SeSpacing.gutter, 14),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(top: BorderSide(color: SeColors.ink200)),
        ),
        child: child,
      );
}

/// A label/amount row. Shared by every total block in the app so a subtotal
/// looks the same in the cart, at checkout and on a receipt.
class SeMoneyLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  const SeMoneyLine({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: strong
                      ? SeType.title
                      : SeType.bodyS.copyWith(color: SeColors.ink500)),
            ),
            Text(value,
                style: SeType.tabular(strong ? SeType.title : SeType.bodyS)
                    .copyWith(
                        color: valueColor ??
                            (strong ? SeColors.ink900 : SeColors.ink700))),
          ],
        ),
      );
}

/// A tinted advisory block — the app's one shape for "here is something you
/// need to know before you continue".
class SeNotice extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final Color tint;
  final String message;

  const SeNotice({
    super.key,
    required this.icon,
    required this.tone,
    required this.tint,
    required this.message,
  });

  /// The common case: something the customer should read, nothing is wrong.
  factory SeNotice.info(String message) => SeNotice(
        icon: SeIcons.info,
        tone: SeColors.infoInk,
        tint: SeColors.infoSoft,
        message: message,
      );

  factory SeNotice.warning(String message) => SeNotice(
        icon: SeIcons.warning,
        tone: SeColors.warningInk,
        tint: SeColors.warningSoft,
        message: message,
      );

  factory SeNotice.danger(String message) => SeNotice(
        icon: SeIcons.warningCircle,
        tone: SeColors.dangerInk,
        tint: SeColors.dangerSoft,
        message: message,
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: SeRadius.all(SeRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: tone),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: SeType.bodyS.copyWith(color: tone, height: 1.45)),
            ),
          ],
        ),
      );
}

/// The small caps-ish label that sits over a field or a block of detail.
class SeFieldLabel extends StatelessWidget {
  final String text;
  const SeFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: SeType.label.copyWith(color: SeColors.ink700)),
      );
}

/// A plain content card in the sheet: flat, hairlined, no shadow.
///
/// The sheet is already a lifted surface; stacking shadowed cards on top of a
/// lifted surface is what made the old screens look like a pile of receipts.
class SePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final VoidCallback? onTap;

  const SePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(color: SeColors.ink200),
      ),
      child: child,
    );
    if (onTap != null) {
      panel = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: panel,
      );
    }
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}

/// A flat, hairlined row group — the sheet's standard way of holding a list of
/// related rows (profile menu, addresses, settings) as ONE surface instead of a
/// stack of individually shadowed cards.
class SeRowGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  const SeRowGroup({super.key, required this.children, this.margin});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 54),
          child: Divider(height: 1, thickness: 1, color: SeColors.ink100),
        ));
      }
      rows.add(children[i]);
    }
    final group = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SeColors.surface0,
        borderRadius: SeRadius.all(SeRadius.md),
        border: Border.all(color: SeColors.ink200),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
    return margin == null ? group : Padding(padding: margin!, child: group);
  }
}

/// One row inside a [SeRowGroup]: tinted glyph, label, optional second line,
/// optional trailing value, caret.
class SeRow extends StatelessWidget {
  final IconData icon;
  final Color? hue;
  final String label;

  /// A quiet second line. Use it for what the row DOES, not to restate it.
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  const SeRow({
    super.key,
    required this.icon,
    required this.label,
    this.hue,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = danger ? SeColors.danger : (hue ?? SeColors.brandAction);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.10),
                borderRadius: SeRadius.all(SeRadius.xs),
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: SeType.title.copyWith(
                      fontSize: 15,
                      color: danger ? SeColors.danger : SeColors.ink900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!,
                        style: SeType.bodyS.copyWith(color: SeColors.ink400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ),
            ?trailing,
            if (trailing == null && onTap != null)
              const Icon(SeIcons.caretRight, size: 18, color: SeColors.ink300),
          ],
        ),
      ),
    );
  }
}

/// A compact figure: glyph, number, label. Three of these fit a phone row.
class SeStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color hue;

  const SeStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.hue,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(color: SeColors.ink200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: hue),
            const SizedBox(height: 10),
            Text(value,
                style: SeType.tabular(SeType.h2)
                    .copyWith(color: SeColors.ink900, fontSize: 21),
                maxLines: 1),
            const SizedBox(height: 1),
            Text(label,
                style: SeType.bodyS.copyWith(color: SeColors.ink500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}
