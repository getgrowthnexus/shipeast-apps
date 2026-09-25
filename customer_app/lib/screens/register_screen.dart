import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../utils/phone.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_button.dart';
import '../widgets/se_toast.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    // DR-25: store the number in the one app-wide format.
    final phone = SePhone.format(_phoneController.text);
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || pass.isEmpty) {
      SeToast.error(context, 'Please fill in all fields');
      return;
    }
    if (pass.length < 6) {
      SeToast.error(context, 'Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
        'name': name,
        'phone': phone,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await NotificationService.onSignedIn(cred.user!.uid);
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        SeToast.error(
            context, e.message ?? 'Registration failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 8, SeSpacing.gutter, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                        color: SeColors.surface50, shape: BoxShape.circle),
                    child: const Icon(SeIcons.arrowLeft,
                        size: 20, color: SeColors.ink900),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Ember brand lockup — matches the sign-in screen so the whole
              // onboarding flow feels like one branded product.
              Container(
                padding: const EdgeInsets.all(SeSpacing.x5),
                decoration: BoxDecoration(
                  gradient: SeColors.emberGradient,
                  borderRadius: SeRadius.all(SeRadius.lg),
                  boxShadow: SeElevation.glow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: SeRadius.all(SeRadius.md),
                      ),
                      child: const Icon(SeIcons.packages,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: SeSpacing.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SeWordmark(size: 24, onDark: true),
                          const SizedBox(height: 4),
                          Text(
                            SeBrand.tagline,
                            style: SeType.bodyS.copyWith(
                                color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text('Create account', style: SeType.display),
              const SizedBox(height: 6),
              Text('Join ShipEast in a few quick steps',
                  style: SeType.body.copyWith(color: SeColors.ink500)),
              const SizedBox(height: 22),
              SeTextField(
                controller: _nameController,
                label: 'FULL NAME',
                hint: 'Your full name',
                icon: SeIcons.user,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              SeTextField(
                controller: _phoneController,
                label: 'PHONE NUMBER',
                hint: '1-876-000-0000',
                icon: SeIcons.phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              SeTextField(
                controller: _emailController,
                label: 'EMAIL ADDRESS',
                hint: 'your@email.com',
                icon: SeIcons.envelope,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              SeTextField(
                controller: _passwordController,
                label: 'PASSWORD',
                hint: 'Create a password',
                icon: SeIcons.lock,
                obscure: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleRegister(),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: SeColors.red50,
                  border: Border.all(color: SeColors.red100, width: 1.5),
                  borderRadius: SeRadius.all(SeRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(SeIcons.shield,
                        size: 18, color: SeColors.red700),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Your info is encrypted and never shared',
                        style: SeType.bodyS.copyWith(color: SeColors.red700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SeButton(
                label: 'Create My Account',
                icon: SeIcons.arrowRight,
                loading: _isLoading,
                onPressed: _isLoading ? null : _handleRegister,
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Already have an account?  ',
                        style: SeType.body.copyWith(color: SeColors.ink500),
                      ),
                      TextSpan(
                        text: 'Sign In',
                        style: SeType.body.copyWith(
                            color: SeColors.red500, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
