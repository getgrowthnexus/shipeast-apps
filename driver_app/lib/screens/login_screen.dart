import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_auth_scaffold.dart';
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

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    // The page is capped in brand red, so the status bar glyphs go light.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
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
    return SeAuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to start your shift.',
      children: [
        SeTextField(
          controller: _emailController,
          label: 'Email',
          hint: 'you@example.com',
          icon: SeIcons.envelope,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          errorText: _emailError,
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
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
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onSubmitted: (_) => _signIn(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: _forgotPassword,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text('Forgot password?',
                  style: SeType.label.copyWith(color: SeColors.brandAction)),
            ),
          ),
        ),
        const SizedBox(height: SeSpacing.x5),
        SeButton(
          label: 'Sign in',
          loading: _isLoading,
          onPressed: _isLoading ? null : _signIn,
        ),
        const SizedBox(height: SeSpacing.x6),
        SeAuthSwitch(
          prompt: "Don't have an account?",
          action: 'Become a Shipeast driver',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen()),
          ),
        ),
      ],
    );
  }
}
