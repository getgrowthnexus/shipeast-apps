import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';

/// First screen a signed-out customer sees.
///
/// 2026 rebuild. The old layout was a 320px hero with a floating parcel
/// illustration stacked over a block of copy and two identical full-width
/// buttons — three competing focal points and a stack of button mass at the
/// bottom. This is one composition instead: the brand shell carries the
/// promise, a blush sheet carries the actions, and there is exactly ONE
/// button on the page. Signing in is a text link, because a second filled
/// pill of equal weight only asks the customer to choose between two things
/// that look the same.
///
/// The red-over-sheet shape continues straight into [SeAuthScaffold], so
/// welcome → sign up → sign in reads as one surface being pulled up rather
/// than three unrelated screens.
///
/// The copy sits at the TOP of the shell and the courier mark anchors the
/// bottom-right corner, which leaves the lower-left of the shell deliberately
/// empty — the rider needs room to read as a subject rather than as a texture,
/// and a block of type stacked directly above it would close that room off.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => Navigator.pushNamed(context, '/privacy-security');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => Navigator.pushNamed(context, '/privacy-security');
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
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
                      // The rider owns a fixed band at the foot of the shell so
                      // the copy above can never push it off — it takes 46% of
                      // the shell, but never so much that the copy is left
                      // under ~260dp. The copy gets a scroll view for the case
                      // where even that is not enough (320dp phone, large
                      // system text size): a short scroll is a better failure
                      // than a yellow overflow stripe.
                      final markBand = math.min(
                        _CourierMark.maxWidth * _CourierMark.ratio,
                        math.min(
                          shell.maxHeight * 0.46,
                          math.max(96.0, shell.maxHeight - 260),
                        ),
                      );
                      // Vertical rhythm scales with the room the shell has.
                      // A short phone gets the SAME composition, tighter —
                      // which beats the same spacing with the pill row half
                      // sliced off by the scroll edge. The third step is for
                      // the 568dp floor, where the pills wrap to two rows and
                      // those two rows have to be paid for out of the gaps.
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SeBrandLockup(size: 26, onDark: true),
                                    SizedBox(height: 26 * air),
                                    Text.rich(
                                      TextSpan(
                                        style: SeType.hero(
                                          titleSize,
                                        ).copyWith(color: SeColors.shellInk),
                                        children: const [
                                          TextSpan(text: 'Delivery,\n'),
                                          TextSpan(
                                            text: 'done right.',
                                            style: TextStyle(
                                              color: SeColors.shellMark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 12 * air),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 330,
                                      ),
                                      child: Text(
                                        'Restaurants, groceries and pharmacy '
                                        'runs across St. Thomas & Kingston — '
                                        'at your door.',
                                        style: SeType.bodyS.copyWith(
                                          color: SeColors.shellInk.withValues(
                                            alpha: 0.78,
                                          ),
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 16 * air),
                                    const Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _Pill(
                                          icon: SeIcons.food,
                                          label: 'Restaurants',
                                        ),
                                        _Pill(
                                          icon: SeIcons.grocery,
                                          label: 'Groceries',
                                        ),
                                        _Pill(
                                          icon: SeIcons.pharmacy,
                                          label: 'Pharmacy',
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
          _ActionSheet(termsTap: _termsTap, privacyTap: _privacyTap),
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
/// Lifted straight from `assets/logo.png` rather than drawn fresh, so the
/// welcome screen is carrying the actual mark the business already uses. It
/// bleeds past the right gutter on purpose — a mascot pinned neatly inside the
/// margin reads as a sticker, one that runs off the edge reads as moving.
///
/// The blurred copy underneath is the only shadow on this screen; it is what
/// stops the silhouette from looking like a flat sticker laid on the red.
///
/// It also idles. The bike rises about 3dp and rolls a third of a degree over
/// a slow two-and-a-half second breath while the shadow stays put, tightening
/// and darkening as the bike settles back onto it. That is the whole effect —
/// no speed lines, no wheel spin, no bounce at the ends. A silhouette that
/// holds perfectly still on an otherwise static screen reads as a decal; the
/// smallest amount of parallax between subject and shadow is what makes it
/// read as an object standing on ground instead.
class _CourierMark extends StatefulWidget {
  static const String _asset = 'assets/brand/rider.png';

  /// Height ÷ width of the exported PNG (900 × 832).
  static const double ratio = 832 / 900;

  /// A ceiling, so a tablet gets a mark rather than a billboard.
  static const double maxWidth = 270;

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
      // Below this it is an illegible smudge; a clean empty corner is
      // better than a tiny one.
      if (markWidth < 92) return const SizedBox.shrink();

      // Both images are built ONCE, out here, and handed to the builders as
      // their `child`. A frame of the idle then costs two Transforms and one
      // compositor opacity — nothing re-decodes and, crucially, nothing
      // re-blurs. Animating the blur's sigma (which is what "the shadow
      // tightens as it lifts" really wants) would rasterise a 13px gaussian
      // over a 270dp image sixty times a second, on phones that have no
      // frame budget to spare for it.
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
        // Bleeds past the right gutter, and lifts just clear of the sheet so
        // the ground shadow has somewhere to land.
        child: Transform.translate(
          offset: const Offset(16, -6),
          child: SizedBox(
            width: markWidth,
            height: markWidth * _CourierMark.ratio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The shadow does NOT ride along — that gap IS the effect.
                // It only lightens as the bike lifts off it.
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
                    // rotates about its middle looks like it is tipping, one
                    // that rotates about its back wheel looks like it is
                    // pulling away.
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

/// What ShipEast actually carries, said in three words rather than a paragraph.
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
  final TapGestureRecognizer termsTap;
  final TapGestureRecognizer privacyTap;

  const _ActionSheet({required this.termsTap, required this.privacyTap});

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
                label: 'Create an account',
                onPressed: () => Navigator.pushNamed(context, '/register'),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/login'),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Already have an account?  ',
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
              Text.rich(
                TextSpan(
                  style: SeType.bodyS.copyWith(color: SeColors.ink400),
                  children: [
                    const TextSpan(text: 'By continuing you agree to our '),
                    TextSpan(
                      text: 'Terms',
                      style: const TextStyle(
                        color: SeColors.brandAction,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: termsTap,
                    ),
                    const TextSpan(text: ' & '),
                    TextSpan(
                      text: 'Privacy',
                      style: const TextStyle(
                        color: SeColors.brandAction,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: privacyTap,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
