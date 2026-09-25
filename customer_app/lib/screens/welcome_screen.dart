import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_button.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatCtrl;
  late Animation<double> _floatAnim;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => Navigator.pushNamed(context, '/privacy-security');
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => Navigator.pushNamed(context, '/privacy-security');
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface0,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ember hero
          SizedBox(
            height: 320,
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(gradient: SeColors.emberGradient),
                ),
                Positioned(
                  top: -35,
                  right: -35,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                          width: 30),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 40,
                  left: -40,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Center(child: SeWordmark(size: 30, onDark: true)),
                  ),
                ),
                Positioned.fill(
                  child: Align(
                    alignment: const Alignment(0, 0.25),
                    child: AnimatedBuilder(
                      animation: _floatAnim,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _floatAnim.value),
                        child: child,
                      ),
                      child: const _ParcelMark(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -1,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 40,
                    decoration: const BoxDecoration(
                      color: SeColors.surface0,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(SeRadius.xl),
                        topRight: Radius.circular(SeRadius.xl),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, 20, SeSpacing.gutter, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RichText(
                    text: TextSpan(
                      style: SeType.display.copyWith(height: 1.15),
                      children: const [
                        TextSpan(
                            text: 'Delivery,\n',
                            style: TextStyle(color: SeColors.ink900)),
                        TextSpan(
                            text: 'Done Right.',
                            style: TextStyle(color: SeColors.red500)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Order from local restaurants, groceries & merchants in St. Thomas & Kingston — delivered straight to your door.',
                    style: SeType.body.copyWith(color: SeColors.ink500),
                  ),
                  const Spacer(),
                  SeButton(
                    label: 'Get Started',
                    icon: SeIcons.arrowRight,
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                  ),
                  const SizedBox(height: 10),
                  SeButton(
                    label: 'I Already Have an Account',
                    variant: SeButtonVariant.ghost,
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                  ),
                  const SizedBox(height: 16),
                  Text.rich(
                    TextSpan(
                      style: SeType.bodyS.copyWith(color: SeColors.ink400),
                      children: [
                        const TextSpan(text: 'By continuing you agree to our '),
                        TextSpan(
                          text: 'Terms',
                          style: const TextStyle(
                              color: SeColors.red500,
                              fontWeight: FontWeight.w600),
                          recognizer: _termsTap,
                        ),
                        const TextSpan(text: ' & '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                              color: SeColors.red500,
                              fontWeight: FontWeight.w600),
                          recognizer: _privacyTap,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Branded parcel + motion streak mark (replaces the CustomPaint motorcycle).
class _ParcelMark extends StatelessWidget {
  const _ParcelMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Motion streaks
          Positioned(
            left: 4,
            top: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _streak(44, 0.28),
                const SizedBox(height: 10),
                _streak(30, 0.20),
                const SizedBox(height: 10),
                _streak(52, 0.28),
              ],
            ),
          ),
          // Parcel card
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(SeRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: SeColors.red900.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(SeIcons.box, size: 54, color: SeColors.red500),
          ),
          // Location pin badge
          Positioned(
            top: 6,
            right: 26,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeColors.gold500,
                shape: BoxShape.circle,
                boxShadow: SeElevation.e2,
              ),
              child: const Icon(SeIcons.locationFill,
                  size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streak(double w, double opacity) => Container(
        width: w,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}
