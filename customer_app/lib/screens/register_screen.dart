import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';
import '../utils/phone.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_typography.dart';
import '../widgets/se_auth_scaffold.dart';
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
    // The page is capped in brand red, so the status bar glyphs go light.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
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
    return SeAuthScaffold(
      title: 'Create your account',
      subtitle: 'It takes about a minute — then you can order.',
      children: [
        SeTextField(
          controller: _nameController,
          label: 'Full name',
          hint: 'e.g. Andre Brown',
          icon: SeIcons.user,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        SeTextField(
          controller: _phoneController,
          label: 'Phone number',
          hint: '1-876-000-0000',
          icon: SeIcons.phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        SeTextField(
          controller: _emailController,
          label: 'Email address',
          hint: 'you@email.com',
          icon: SeIcons.envelope,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        SeTextField(
          controller: _passwordController,
          label: 'Password',
          hint: 'At least 6 characters',
          icon: SeIcons.lock,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleRegister(),
        ),
        const SizedBox(height: 22),
        SeButton(
          label: 'Create account',
          loading: _isLoading,
          onPressed: _isLoading ? null : _handleRegister,
        ),
        const SizedBox(height: 16),
        // Reassurance as one quiet line, not a card. It belongs next to the
        // button that submits the data, not floating above the fields.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(SeIcons.lock, size: 14, color: SeColors.ink400),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Encrypted and never shared',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SeType.bodyS.copyWith(color: SeColors.ink400)),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SeAuthSwitch(
          prompt: 'Already have an account?',
          action: 'Sign in',
          onTap: () => Navigator.pushReplacementNamed(context, '/login'),
        ),
      ],
    );
  }
}
