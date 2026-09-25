import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

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
      statusBarIconBrightness: Brightness.dark,
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
      title: 'Delete Account',
      message:
          'This will permanently delete your account and all your data. This action cannot be undone.',
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
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDataCard(),
                    const SizedBox(height: 14),
                    _buildSecurityCard(),
                    const SizedBox(height: 14),
                    _buildDeleteCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, SeSpacing.gutter, 12),
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(bottom: BorderSide(color: SeColors.ink100)),
        ),
        child: Row(
          children: [
            GestureDetector(
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
            const SizedBox(width: 12),
            Text('Privacy & Security', style: SeType.h3),
          ],
        ),
      );

  Widget _buildDataCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Data We Collect'),
            _dataItem(SeIcons.user, 'Profile Information',
                'Name, phone number, email address'),
            _dataItem(SeIcons.location, 'Delivery Addresses',
                'Your saved delivery locations'),
            _dataItem(SeIcons.orders, 'Order History',
                'Your past and current orders'),
            _dataItem(SeIcons.starOutline, 'Ratings & Reviews',
                'Ratings you give to drivers and merchants'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SeColors.oceanTint,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(SeIcons.info, size: 16, color: SeColors.ocean500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'We never sell your data. Information is used solely to provide and improve ShipEast services.',
                      style: SeType.bodyS.copyWith(color: SeColors.ocean500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _dataItem(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: SeColors.surface50,
                  borderRadius: SeRadius.all(SeRadius.sm)),
              child: Icon(icon, size: 19, color: SeColors.ink700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SeType.title),
                  Text(sub,
                      style: SeType.bodyS.copyWith(color: SeColors.ink400)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildSecurityCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Security'),
            Text(
              'Change your account password. A reset link will be sent to your registered email address.',
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
            const SizedBox(height: 16),
            SeButton(
              label: 'Send Password Reset Email',
              icon: SeIcons.lock,
              loading: _sendingReset,
              onPressed: _sendingReset ? null : _sendPasswordReset,
            ),
          ],
        ),
      );

  Widget _buildDeleteCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Delete Account'),
            Text(
              'Permanently delete your ShipEast account and all associated data. This action cannot be undone.',
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
            const SizedBox(height: 16),
            SeButton(
              label: 'Delete My Account',
              icon: SeIcons.trash,
              variant: SeButtonVariant.destructive,
              loading: _deleting,
              onPressed: _deleting ? null : _deleteAccount,
            ),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t, style: SeType.h3),
      );
}
