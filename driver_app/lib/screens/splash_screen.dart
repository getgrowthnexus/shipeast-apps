import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import 'dashboard_host.dart';
import 'pending_approval_screen.dart';
import 'welcome_screen.dart';

/// Launch screen.
///
/// The driver app did not have one. `main()` awaited Firebase, then a push
/// permission prompt, then a Firestore read of the driver's approval status —
/// all of it BEFORE `runApp`, so the first thing a driver saw on a cold start
/// was the bare window the OS had allocated: white, or black in dark mode, for
/// as long as the depot's signal took. The permission dialog appeared over
/// that nothing. This screen is what that wait looks like now.
///
/// Composed as the customer app's splash is — the name doing the work at
/// display size on the flat brand shell, an accent rule that draws itself under
/// it, a hairline progress track — with the edition badge added, because the
/// two apps share a wordmark, an icon and a red, and this is the first moment
/// to say which one just opened.
///
/// The entrance is staged rather than simultaneous (mark, then rule, then
/// strapline) because arrival in sequence is what makes a two-second wait feel
/// composed instead of merely spent.
///
/// The wait is a floor, not a fixed cost: [_hold] and the status lookup run
/// side by side and the screen leaves when the slower of the two is done. A
/// driver on hotel wifi waits for the network; nobody waits for the animation
/// twice.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Duration _hold = Duration(milliseconds: 2200);

  late final AnimationController _intro;
  late final AnimationController _load;

  late final Animation<double> _markFade;
  late final Animation<double> _markLift;
  late final Animation<double> _markScale;
  late final Animation<double> _ruleGrow;
  late final Animation<double> _strapFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _markFade = CurvedAnimation(
        parent: _intro, curve: const Interval(0, 0.5, curve: Curves.easeOut));
    _markLift = Tween<double>(begin: 20, end: 0).animate(CurvedAnimation(
        parent: _intro,
        curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)));
    _markScale = Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(
        parent: _intro,
        curve: const Interval(0, 0.7, curve: Curves.easeOutCubic)));
    _ruleGrow = CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.34, 0.85, curve: Curves.easeOutCubic));
    _strapFade = CurvedAnimation(
        parent: _intro, curve: const Interval(0.55, 1, curve: Curves.easeOut));
    _intro.forward();

    _load = AnimationController(vsync: this, duration: _hold)..forward();
    _go();
  }

  /// Work out where this driver belongs, and leave once the hold is also up.
  Future<void> _go() async {
    final results = await Future.wait([
      _destination(),
      Future<Widget?>.delayed(_hold, () => null),
    ]);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      // No slide. The splash and every screen it hands off to are the same
      // flat brand red at the top, so a page transition would slide one red
      // over another and read as a stutter rather than as movement.
      PageRouteBuilder(
        pageBuilder: (_, _, _) => results.first!,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }

  Future<Widget?> _destination() async {
    // The whole lookup is guarded, not just the Firestore read. Anything that
    // throws out here — Firebase not up, a plugin missing on some OEM build —
    // would otherwise leave the driver on a splash screen that never ends,
    // which is the one failure a launch screen must not have. Welcome is the
    // only screen in the app that needs nothing from the network.
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const WelcomeScreen();
      try {
        final doc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        if (doc.exists && doc.data()?['status'] == 'approved') {
          return const DriverShell();
        }
      } catch (_) {
        // Offline, or rules said no. Either way we cannot claim they are
        // approved — the pending screen streams the real status and moves
        // them on by itself the moment it can read it.
      }
      return const PendingApprovalScreen();
    } catch (_) {
      return const WelcomeScreen();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _load.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.shell,
      body: Stack(
        children: [
          // Quiet geometry. Flat brand field + a few soft shapes bleeding off
          // the edges: depth without a gradient, per the 2026 tokens.
          Positioned(top: -110, right: -90, child: _disc(280, 0.06)),
          Positioned(bottom: -140, left: -100, child: _disc(340, 0.05)),
          Positioned(top: 150, left: -70, child: _ring(180, 0.10)),
          Center(
            child: AnimatedBuilder(
              animation: _intro,
              builder: (_, child) => Opacity(
                opacity: _markFade.value,
                child: Transform.translate(
                  offset: Offset(0, _markLift.value),
                  child: Transform.scale(scale: _markScale.value, child: child),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SeWordmark(size: 46, onDark: true),
                  const SizedBox(height: 14),
                  const SeEditionBadge(),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _ruleGrow,
                    builder: (_, _) => Container(
                      width: 78 * _ruleGrow.value,
                      height: 3,
                      decoration: BoxDecoration(
                        color: SeColors.shellMark,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _strapFade,
                    child: Text(
                      SeBrand.strapline,
                      style: SeType.eyebrow.copyWith(
                        color: SeColors.shellInk.withValues(alpha: 0.72),
                        letterSpacing: 2.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 132,
                    height: 3,
                    child: AnimatedBuilder(
                      animation: _load,
                      builder: (_, _) => LinearProgressIndicator(
                        value: _load.value,
                        backgroundColor:
                            SeColors.shellInk.withValues(alpha: 0.16),
                        valueColor:
                            const AlwaysStoppedAnimation(SeColors.shellMark),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'v${SeBrand.version}',
                  style: SeType.eyebrow.copyWith(
                      color: SeColors.shellInk.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
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

  Widget _ring(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: Colors.white.withValues(alpha: alpha), width: 26),
        ),
      );
}

/// `DRIVER`, in a translucent well on the brand shell.
///
/// Not decoration. The customer and driver apps ship the same wordmark, the
/// same launcher icon and the same red; a driver who has both installed and
/// opens the wrong one has nothing else to tell them apart.
class SeEditionBadge extends StatelessWidget {
  const SeEditionBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: SeRadius.pill,
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Text(
          SeBrand.edition.toUpperCase(),
          style: SeType.eyebrow.copyWith(
            color: SeColors.shellMark,
            letterSpacing: 1.6,
          ),
        ),
      );
}
