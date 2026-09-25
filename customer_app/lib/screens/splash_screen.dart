import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;
  late AnimationController _markCtrl;
  late Animation<double> _markScale;
  late Animation<double> _markFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _markCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 620));
    _markScale = Tween<double>(begin: 0.86, end: 1.0).animate(
        CurvedAnimation(parent: _markCtrl, curve: Curves.easeOutBack));
    _markFade = CurvedAnimation(parent: _markCtrl, curve: Curves.easeOut);
    _markCtrl.forward();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _progressAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOut),
    );
    _progressCtrl.forward();
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        Navigator.pushReplacementNamed(
          context,
          user != null ? '/home' : '/welcome',
        );
      }
    });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _markCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: SeColors.emberGradient),
        child: Stack(
          children: [
            Positioned(
                top: -50,
                right: -50,
                child: _circle(200, Colors.white.withValues(alpha: 0.08))),
            Positioned(
                bottom: -80,
                left: -60,
                child: _circle(240, Colors.white.withValues(alpha: 0.06))),
            Positioned(
                top: 60,
                left: -30,
                child: _circle(130, Colors.white.withValues(alpha: 0.05))),
            Center(
              child: FadeTransition(
                opacity: _markFade,
                child: ScaleTransition(
                  scale: _markScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: SeColors.red900.withValues(alpha: 0.35),
                              blurRadius: 32,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Image.asset('assets/logo.png',
                            fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 20),
                      const SeWordmark(size: 34, onDark: true),
                      const SizedBox(height: 10),
                      Text(
                        'Fast · Reliable · Yours',
                        style: SeType.label.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 34,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Center(
                    child: SizedBox(
                      width: 140,
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedBuilder(
                          animation: _progressAnim,
                          builder: (_, __) => LinearProgressIndicator(
                            value: _progressAnim.value,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'v${SeBrand.version}',
                    style: SeType.bodyS.copyWith(
                        color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
