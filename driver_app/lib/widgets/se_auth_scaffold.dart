import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';

/// The chrome every auth screen is built on: a flat brand cap carrying the
/// page title, and a blush sheet lifted over it that holds the form.
///
/// Why this shape. The previous auth screens centred a small emblem, a title
/// and the fields as one floating group, which left the page reading as a
/// column of unrelated parts with dead air around them. Splitting the screen
/// into TWO surfaces gives every element a job: the red cap is brand and
/// context (where am I, how do I get back), the sheet is the task. The eye
/// lands on the title, drops into the sheet, and finds the button at the end
/// of it. It also matches the welcome screen's red-over-sheet composition, so
/// the whole sign-up path reads as one continuous piece.
///
/// The cap collapses to a single line while the keyboard is up — on a small
/// phone a fixed hero would push the last field under the keyboard.
class SeAuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Sheet contents, laid out in a stretched column.
  final List<Widget> children;

  const SeAuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    // Two steps down, not one. `compact` is the keyboard case — the hero drops
    // to a single line because the fields need every pixel. `tight` is a short
    // phone with no keyboard: keep the subtitle, but stop spending 30dp of
    // padding on a screen that has none to spare, or the button at the end of
    // a four-field form ends up flush against the bottom edge.
    final size = MediaQuery.sizeOf(context);
    final compact = MediaQuery.viewInsetsOf(context).bottom > 120;
    final tight = !compact && size.height < 720;

    // The cap is sized against the VIEWPORT, not against its own text.
    //
    // Sized by its contents it came out at roughly a fifth of the screen,
    // which left the sheet running nearly the full height — so the form read
    // as the page and the brand read as a band stuck on top of it. Holding
    // the seam near 28% gives the title red to sit in rather than red to sit
    // on, and gives the sheet a top edge you can see.
    //
    // It is a MINIMUM, so nothing is ever clipped: a wrapped title, a large
    // system text size or a short phone all push straight past it, and on a
    // 568dp phone the intrinsic height already exceeds it. The status bar
    // comes out of the budget because the seam is measured from the top of
    // the screen, which is where the eye measures it from too.
    final safeTop = MediaQuery.paddingOf(context).top;
    final capFloor =
        compact ? 0.0 : math.max(0.0, size.height * 0.285 - safeTop);

    return Scaffold(
      backgroundColor: SeColors.shell,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: capFloor),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(SeSpacing.gutter, 8,
                      SeSpacing.gutter, compact ? 18 : (tight ? 18 : 28)),
                  // Two children and `spaceBetween`: the back control stays
                  // pinned under the status bar and the title block sinks to
                  // the foot of the cap, so every pixel the cap gains lands
                  // as air between them instead of below the subtitle.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _CapBackButton(),
                      Padding(
                        padding: EdgeInsets.only(
                            top: compact ? 12 : (tight ? 14 : 22)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: SeType.display.copyWith(
                                color: SeColors.shellInk,
                                fontSize: compact ? 22 : (tight ? 26 : 30),
                                height: 1.15,
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: SeType.body.copyWith(
                                  color:
                                      SeColors.shellInk.withValues(alpha: 0.78),
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(
                color: SeColors.surface0,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(SeRadius.xl)),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(70, 8, 24, 0.22),
                    blurRadius: 28,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      SeSpacing.gutter, tight ? 22 : 28, SeSpacing.gutter, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Back control for the brand cap — a translucent well rather than a bare
/// glyph, so it stays legible on the red without punching a white hole in it.
class _CapBackButton extends StatelessWidget {
  const _CapBackButton();

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox(height: 40);
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(SeIcons.arrowLeft,
              size: 20, color: SeColors.shellInk),
        ),
      ),
    );
  }
}

/// "or" rule used between the primary action and a federated sign-in.
class SeAuthDivider extends StatelessWidget {
  final String label;
  const SeAuthDivider({super.key, this.label = 'or'});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(child: Divider(color: SeColors.ink200, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child:
                Text(label, style: SeType.bodyS.copyWith(color: SeColors.ink400)),
          ),
          const Expanded(child: Divider(color: SeColors.ink200, height: 1)),
        ],
      );
}

/// Footer swap link ("Already have an account?  Sign in").
class SeAuthSwitch extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const SeAuthSwitch({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                    text: '$prompt  ',
                    style: SeType.body.copyWith(color: SeColors.ink500)),
                TextSpan(
                  text: action,
                  style: SeType.body.copyWith(
                      color: SeColors.brandAction, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
}
