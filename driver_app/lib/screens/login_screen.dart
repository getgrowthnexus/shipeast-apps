import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import 'register_screen.dart';
import 'pending_approval_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  late final AnimationController _intro;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: SeMotion.deliberate)
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Try again shortly.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _emailError = email.isEmpty ? 'Enter your email' : null;
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final uid = credential.user!.uid;
      final doc =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
      if (!mounted) return;
      final status = doc.data()?['status'] as String? ?? 'pending';
      if (status == 'approved') {
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      SeToast.error(context, _authErrorMessage(e.code));
    } catch (_) {
      if (!mounted) return;
      SeToast.error(context, 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Audit §7.6: this affordance was previously an empty `onTap`. It now sends
  /// a real reset email to whatever is in the email field.
  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Enter your email first, then tap reset');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      SeToast.success(context, 'Password reset link sent to $email');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      SeToast.error(context, _authErrorMessage(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = SeMotion.reduced(context);

    return Scaffold(
      backgroundColor: SeColors.red500,
      body: Column(
        children: [
          // ── Ember hero ───────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: SeColors.emberGradient),
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: FadeTransition(
                    opacity: _intro,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(SeSpacing.x4),
                          decoration: BoxDecoration(
                            color: SeColors.surface0,
                            borderRadius: SeRadius.all(SeRadius.lg),
                            boxShadow: SeElevation.e4,
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            height: 70,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: SeSpacing.x4),
                        const SeWordmark(size: 28, onDark: true),
                        const SizedBox(height: SeSpacing.x2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: SeRadius.pill,
                          ),
                          child: Text(
                            'DRIVER PORTAL',
                            style: SeType.eyebrow.copyWith(
                                color: Colors.white, letterSpacing: 1.0),
                          ),
                        ),
                        const SizedBox(height: SeSpacing.x3),
                        Text(
                          SeBrand.tagline,
                          style: SeType.bodyS.copyWith(
                              color: Colors.white.withValues(alpha: 0.82)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Form sheet ───────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: SeColors.surface0,
                borderRadius: SeRadius.sheetTop,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SeSpacing.x6),
                  child: SlideTransition(
                    position: Tween(
                      begin: reduced ? Offset.zero : const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: _intro, curve: SeMotion.decelerate)),
                    child: FadeTransition(
                      opacity: _intro,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: SeSpacing.x2),
                          Text('Welcome back', style: SeType.display),
                          const SizedBox(height: SeSpacing.x1),
                          Text(
                            'Sign in to your driver account',
                            style:
                                SeType.body.copyWith(color: SeColors.ink500),
                          ),
                          const SizedBox(height: SeSpacing.x6),
                          SeTextField(
                            controller: _emailController,
                            label: 'Email',
                            hint: 'you@example.com',
                            icon: SeIcons.envelope,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            errorText: _emailError,
                            onChanged: (_) {
                              if (_emailError != null) {
                                setState(() => _emailError = null);
                              }
                            },
                          ),
                          const SizedBox(height: SeSpacing.x4),
                          SeTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: 'Your password',
                            icon: SeIcons.lock,
                            obscure: true,
                            textInputAction: TextInputAction.done,
                            errorText: _passwordError,
                            onChanged: (_) {
                              if (_passwordError != null) {
                                setState(() => _passwordError = null);
                              }
                            },
                            onSubmitted: (_) => _signIn(),
                          ),
                          const SizedBox(height: SeSpacing.x3),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: _forgotPassword,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: SeSpacing.x1),
                                child: Text(
                                  'Forgot password?',
                                  style: SeType.label
                                      .copyWith(color: SeColors.red700),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: SeSpacing.x5),
                          SeButton(
                            label: 'Sign In',
                            loading: _isLoading,
                            onPressed: _isLoading ? null : _signIn,
                          ),
                          const SizedBox(height: SeSpacing.x4),
                          Center(
                            child: GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const RegisterScreen()),
                              ),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.all(SeSpacing.x2),
                                child: RichText(
                                  text: TextSpan(
                                    style: SeType.bodyS
                                        .copyWith(color: SeColors.ink500),
                                    children: [
                                      const TextSpan(
                                          text: "Don't have an account? "),
                                      TextSpan(
                                        text: 'Become a Shipeast driver',
                                        style: SeType.bodyS.copyWith(
                                          color: SeColors.red700,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
        ],
      ),
    );
  }
}
