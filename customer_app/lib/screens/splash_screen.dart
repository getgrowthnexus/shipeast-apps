import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_typography.dart';

/// Launch screen.
///
/// 2026 rebuild. The old version put `assets/logo.png` inside a white rounded
/// tile on the red field: a logo in a box on a box, which reads as a
/// placeholder rather than a brand. That is gone. What is left is the name
/// doing the work at display size on the flat brand shell, an accent rule that
/// draws itself under it, and a hairline progress track — no card, no crop, no
/// second surface competing with the wordmark.
///
/// The entrance is staged rather than simultaneous (mark, then rule, then
/// strapline) because arrival in sequence is what makes a two-second wait feel
/// composed instead of merely spent.
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
        parent: _intro, curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)));
    _markScale = Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(
        parent: _intro, curve: const Interval(0, 0.7, curve: Curves.easeOutCubic)));
    _ruleGrow = CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.34, 0.85, curve: Curves.easeOutCubic));
    _strapFade = CurvedAnimation(
        parent: _intro, curve: const Interval(0.55, 1, curve: Curves.easeOut));
    _intro.forward();

    _load = AnimationController(vsync: this, duration: _hold)..forward();
    _load.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        Navigator.pushReplacementNamed(
            context, user != null ? '/home' : '/welcome');
      }
    });
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
                  const SizedBox(height: 20),
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
