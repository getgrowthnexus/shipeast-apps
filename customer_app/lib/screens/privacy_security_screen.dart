import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

/// Privacy & security.
///
/// Reads top to bottom as: here is what we hold, here is how you secure it,
/// here is how you end it. The destructive action stays last and stays plain —
/// it is a real option, not a trap and not a dare.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _sendingReset = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  Future<void> _sendPasswordReset() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;
    setState(() => _sendingReset = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      if (mounted) {
        SeToast.success(context, 'Password reset email sent to ${user.email}');
      }
    } catch (_) {
      if (mounted) {
        SeToast.error(context, 'Failed to send reset email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await SeConfirmSheet.show(
      context,
      title: 'Delete account',
      message: 'This permanently deletes your account and all your data. '
          'It cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirm) return;
    setState(() => _deleting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final uid = user.uid;
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      } catch (_) {}
      await user.delete();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        final msg = e.code == 'requires-recent-login'
            ? 'Please sign out and sign back in, then try again.'
            : 'Failed to delete account. Please try again.';
        SeToast.error(context, msg);
      }
    } catch (_) {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: 'Privacy & security',
      subtitle: 'What we hold, and what you control',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 28),
        children: [
          const SeSectionTitle(title: 'What we hold'),
          const SizedBox(height: 10),
          const SeRowGroup(
            children: [
              SeRow(
                icon: SeIcons.user,
                hue: SeColors.info,
                label: 'Profile',
                subtitle: 'Name, phone number, email address',
              ),
              SeRow(
                icon: SeIcons.location,
                hue: SeColors.info,
                label: 'Delivery addresses',
                subtitle: 'The places you have saved',
              ),
              SeRow(
                icon: SeIcons.orders,
                hue: SeColors.info,
                label: 'Order history',
                subtitle: 'Your past and current orders',
              ),
              SeRow(
                icon: SeIcons.starOutline,
                hue: SeColors.info,
                label: 'Ratings',
                subtitle: 'The scores you give drivers and merchants',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SeNotice.info(
            'We never sell your data. It is used to run ShipEast and nothing '
            'else.',
          ),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Security'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'We send a reset link to your registered email address; you '
                  'set the new password there.',
                  style: SeType.bodyS
                      .copyWith(color: SeColors.ink500, height: 1.5),
                ),
                const SizedBox(height: 14),
                SeButton(
                  label: 'Send password reset email',
                  icon: SeIcons.lock,
                  variant: SeButtonVariant.secondary,
                  loading: _sendingReset,
                  onPressed: _sendingReset ? null : _sendPasswordReset,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Delete account'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Permanently deletes your ShipEast account and everything '
                  'attached to it. This cannot be undone.',
                  style: SeType.bodyS
                      .copyWith(color: SeColors.ink500, height: 1.5),
                ),
                const SizedBox(height: 14),
                SeButton(
                  label: 'Delete my account',
                  variant: SeButtonVariant.destructive,
                  loading: _deleting,
                  onPressed: _deleting ? null : _deleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
