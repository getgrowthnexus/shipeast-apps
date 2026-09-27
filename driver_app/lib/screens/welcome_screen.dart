import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'splash_screen.dart' show SeEditionBadge;

/// First screen a signed-out driver sees.
///
/// The driver app went straight from launch to a sign-in form. That is the
/// right screen for the drivers already on the road and the wrong one for
/// everybody else: a courier sent this app by a friend arrived at two empty
/// fields and a password they had never set, with "Apply to drive" a small
/// grey line at the bottom. Applying is the only thing a new driver can
/// actually do here, so it is now the one button on the page.
///
/// Built as the customer app's welcome screen is — brand shell carrying the
/// promise, blush sheet carrying the actions, exactly ONE button, signing in
/// as a text link — because welcome → apply → sign in has to read as one
/// surface being pulled up rather than three unrelated screens. What differs
/// is what it promises: the customer screen sells the delivery, this one sells
/// the work, and the three pills name things this app genuinely does rather
/// than things a recruiter would say.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// Room the copy block wants before the rider is allowed any: lockup, two-line
/// headline, three-line subcopy and a wrapped pill row, at the tightest rhythm.
const double _copyFloor = 270;

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // The headline is the one thing allowed to be loud, so it is also the one
    // thing that has to survive a 320dp phone without wrapping into four lines.
    // Sized as a share of the width rather than off a breakpoint: two phones
    // 8dp apart should not get headlines 6dp apart.
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.09).clamp(28.0, 37.0);

    return Scaffold(
      backgroundColor: SeColors.shell,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned(top: -110, right: -90, child: _disc(240, 0.06)),
                Positioned(bottom: -70, right: -50, child: _disc(230, 0.05)),
                SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, shell) {
                      // The rider owns a band at the foot of the shell so the
                      // copy above can never push it off: 46% of the shell,
                      // less whatever the copy needs.
                      //
                      // It collapses to NOTHING rather than to a floor. The
                      // customer app keeps a 96dp minimum here, and on a
                      // 320×568 phone that minimum is what sliced this screen's
                      // pill row in half — 96dp reserved for a mark that
                      // `_CourierMark` then refuses to draw, because at that
                      // size it is a smudge. This app's headline and subcopy
                      // are two lines longer than the customer's, so it cannot
                      // afford to pay for a rider nobody sees. Below the mark's
                      // own legibility floor the band goes to zero and the copy
                      // gets the whole shell.
                      final band = math.min(
                        _CourierMark.maxWidth * _CourierMark.ratio,
                        math.min(shell.maxHeight * 0.46,
                            shell.maxHeight - _copyFloor),
                      );
                      final markBand =
                          band >= _CourierMark.minWidth * _CourierMark.ratio
                              ? band
                              : 0.0;
                      // Vertical rhythm scales with the room the shell has.
                      // A short phone gets the SAME composition, tighter.
                      final air = shell.maxHeight >= 480
                          ? 1.0
                          : (shell.maxHeight >= 380 ? 0.6 : 0.35);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  SeSpacing.gutter,
                                  16 * air,
                                  SeSpacing.gutter,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Wordmark and edition on one line, legal
                                    // name beneath: the full signature, on the
                                    // one screen with room to carry it.
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        SeWordmark(size: 26, onDark: true),
                                        SizedBox(width: 9),
                                        SeEditionBadge(),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      SeBrand.legalName,
                                      style: SeType.label.copyWith(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.1,
                                        color: SeColors.shellInk
                                            .withValues(alpha: 0.72),
                                      ),
                                    ),
                                    SizedBox(height: 26 * air),
                                    Text.rich(
                                      TextSpan(
                                        style: SeType.hero(titleSize).copyWith(
                                          color: SeColors.shellInk,
                                        ),
                                        children: const [
                                          TextSpan(text: 'Earn on\n'),
                                          TextSpan(
                                            text: 'your own time.',
                                            style: TextStyle(
                                              color: SeColors.shellMark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 12 * air),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 330),
                                      child: Text(
                                        'Run deliveries across St. Thomas & '
                                        'Kingston on your own bike or car. '
                                        'Go online when it suits you.',
                                        style: SeType.bodyS.copyWith(
                                          color: SeColors.shellInk
                                              .withValues(alpha: 0.78),
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 16 * air),
                                    // Three promises, each one a screen in this
                                    // app rather than a line of recruitment
                                    // copy: the presence toggle, the job offer
                                    // with its distance, the earnings week.
                                    const Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _Pill(
                                          icon: SeIcons.power,
                                          label: 'Go online anytime',
                                        ),
                                        _Pill(
                                          icon: SeIcons.navigation,
                                          label: 'Jobs near you',
                                        ),
                                        _Pill(
                                          icon: SeIcons.wallet,
                                          label: 'Track every dollar',
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12 * air),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: markBand,
                            width: double.infinity,
                            child: const _CourierMark(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const _ActionSheet(),
        ],
      ),
    );
  }

  Widget _disc(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: alpha),
          shape: BoxShape.circle,
        ),
      );
}

/// The courier from the ShipEast logo, riding out of the bottom-right corner.
///
/// Lifted straight from the mark rather than drawn fresh, so the screen is
/// carrying the actual silhouette the business already uses. It bleeds past the
/// right gutter on purpose — a mascot pinned neatly inside the margin reads as
/// a sticker, one that runs off the edge reads as moving. It is also the one
/// place in this app where the rider IS the audience rather than the service.
///
/// The blurred copy underneath is the only shadow on this screen; it is what
/// stops the silhouette from looking like a flat sticker laid on the red.
///
/// It idles: the bike rises about 3dp and rolls a third of a degree over a slow
/// two-and-a-half second breath while the shadow stays put. A silhouette that
/// holds perfectly still on an otherwise static screen reads as a decal; the
/// smallest amount of parallax between subject and shadow is what makes it read
/// as an object standing on ground instead.
class _CourierMark extends StatefulWidget {
  static const String _asset = 'assets/brand/rider.png';

  /// Height ÷ width of the exported PNG (900 × 832).
  static const double ratio = 832 / 900;

  /// A ceiling, so a tablet gets a mark rather than a billboard.
  static const double maxWidth = 270;

  /// Below this the silhouette is an illegible smudge and is not drawn at all.
  /// Public because the layout above has to reserve the band BEFORE this widget
  /// gets a chance to decline it.
  static const double minWidth = 92;

  const _CourierMark();

  @override
  State<_CourierMark> createState() => _CourierMarkState();
}

class _CourierMarkState extends State<_CourierMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle;
  late final Animation<double> _breath;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _breath = CurvedAnimation(parent: _idle, curve: Curves.easeInOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the system's reduce-motion switch, and honour it by STOPPING the
    // ticker rather than by zeroing the output — someone who has turned
    // animation off should not be paying for a frame callback either.
    if (MediaQuery.disableAnimationsOf(context)) {
      _idle
        ..stop()
        ..value = 0;
    } else if (!_idle.isAnimating) {
      _idle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          // Bounded by the band it was handed, then by a share of the width.
          final markWidth = math.min(
            _CourierMark.maxWidth,
            math.min(c.maxWidth * 0.68, c.maxHeight / _CourierMark.ratio),
          );
          // A clean empty corner is better than a tiny smudge.
          if (markWidth < _CourierMark.minWidth) return const SizedBox.shrink();

          // Both images are built ONCE, out here, and handed to the builders
          // as their `child`. A frame of the idle then costs two Transforms
          // and one compositor opacity — nothing re-decodes and, crucially,
          // nothing re-blurs.
          final shadow = RepaintBoundary(
            child: Transform.translate(
              offset: const Offset(2, 12),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
                child: const Image(
                  image: AssetImage(_CourierMark._asset),
                  fit: BoxFit.contain,
                  color: Color.fromRGBO(58, 4, 18, 0.55),
                ),
              ),
            ),
          );
          const rider = Image(
            image: AssetImage(_CourierMark._asset),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            color: SeColors.shellInk,
          );

          return Align(
            alignment: Alignment.bottomRight,
            // Bleeds past the right gutter, and lifts just clear of the sheet
            // so the ground shadow has somewhere to land.
            child: Transform.translate(
              offset: const Offset(16, -6),
              child: SizedBox(
                width: markWidth,
                height: markWidth * _CourierMark.ratio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The shadow does NOT ride along — that gap IS the effect.
                    AnimatedBuilder(
                      animation: _breath,
                      child: shadow,
                      builder: (context, child) => Opacity(
                        opacity: 1 - _breath.value * 0.22,
                        child: child,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _breath,
                      child: rider,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -_breath.value * 3),
                        // Pivot at the rear wheel, not the centre: a bike that
                        // rotates about its middle looks like it is tipping,
                        // one that rotates about its back wheel looks like it
                        // is pulling away.
                        child: Transform.rotate(
                          angle: -_breath.value * 0.006,
                          alignment: const Alignment(-0.6, 1),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

/// What the job actually offers, said in three words rather than a paragraph.
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          borderRadius: SeRadius.pill,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: SeColors.shellMark),
            const SizedBox(width: 6),
            Text(label, style: SeType.label.copyWith(color: SeColors.shellInk)),
          ],
        ),
      );
}

/// The blush sheet: one primary action, one text link, one line of small print.
class _ActionSheet extends StatelessWidget {
  const _ActionSheet();

  @override
  Widget build(BuildContext context) {
    // A short phone cannot afford the full sheet: every dp of padding here is
    // a dp the shell above does not get, and the shell is where the rider and
    // the last pill are already fighting for room.
    final tight = MediaQuery.sizeOf(context).height < 720;
    return Container(
      decoration: const BoxDecoration(
        color: SeColors.surface0,
        borderRadius: BorderRadius.vertical(top: Radius.circular(SeRadius.xl)),
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
        child: Padding(
          // Generous, deliberately. The sheet is the only white on the screen
          // and it carries the only button; sized to its contents it reads as a
          // strip pushed against the bottom edge rather than as a surface the
          // page comes to rest on.
          padding: EdgeInsets.fromLTRB(
            SeSpacing.gutter,
            tight ? 26 : 40,
            SeSpacing.gutter,
            tight ? 18 : 26,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SeButton(
                label: 'Apply to drive',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Already driving with us?  ',
                          style: SeType.body.copyWith(color: SeColors.ink500),
                        ),
                        TextSpan(
                          text: 'Sign in',
                          style: SeType.body.copyWith(
                            color: SeColors.brandAction,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Plain text, not links. The customer app can point its Terms at
              // a real screen; this app has no such screen, and a tappable word
              // that does nothing is worse than an untappable one that is
              // honest about it.
              Text(
                'Applications are reviewed by dispatch before your first shift.',
                textAlign: TextAlign.center,
                style: SeType.bodyS.copyWith(color: SeColors.ink400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
