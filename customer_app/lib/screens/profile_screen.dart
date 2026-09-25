import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../utils/phone.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_stat_tile.dart';
import '../widgets/se_bottom_sheet.dart';
import 'help_support_screen.dart';
import 'notifications_screen.dart';
import 'privacy_security_screen.dart';
import 'saved_addresses_screen.dart';
import 'coming_soon_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _phone = '';
  String _email = '';
  String? _avatarUrl;

  int _orderCount = 0;
  double _avgRating = 0;
  int _savedCount = 0;
  bool _statsLoaded = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _email = user.email ?? '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _name = data['name'] as String? ?? '';
          _phone = data['phone'] as String? ?? '';
          _email = data['email'] as String? ?? user.email ?? '';
          _avatarUrl = data['avatarUrl'] as String?;
        });
      }
    } catch (_) {}

    try {
      final stats = await FirestoreService.getUserStats(user.uid);
      if (mounted) {
        setState(() {
          _orderCount = stats['orderCount'] as int? ?? 0;
          _avgRating = (stats['avgRating'] as num?)?.toDouble() ?? 0;
          _savedCount = stats['savedCount'] as int? ?? 0;
          _statsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoaded = true);
    }
  }

  Future<void> _saveProfile(String name, String phone, String email) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'name': name,
      'phone': phone,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      _name = name;
      _phone = phone;
      _email = email;
    });
  }

  Future<void> _pickImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;

    try {
      final url =
          await FirestoreService.uploadAvatar(user.uid, File(picked.path));
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      if (mounted) SeToast.error(context, 'Failed to upload photo');
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await SeConfirmSheet.show(
      context,
      title: 'Sign out?',
      message: 'You\'ll need to sign in again to place orders.',
      confirmLabel: 'Sign Out',
      destructive: true,
    );
    if (!confirmed) return;
    // Before signOut, while the uid is still valid: leaving the token behind
    // means the next person to sign in on this phone receives the previous
    // customer's order notifications (P4-03).
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await NotificationService.onSignedOut(uid);
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
    }
  }

  void _showEditDialog() {
    final nameCtrl = TextEditingController(text: _name);
    final phoneCtrl = TextEditingController(text: _phone);
    final emailCtrl = TextEditingController(text: _email);

    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: 12),
            Text('Edit Profile', style: SeType.h2),
            const SizedBox(height: 18),
            SeTextField(
                controller: nameCtrl,
                label: 'Full Name',
                icon: SeIcons.user,
                keyboardType: TextInputType.name),
            const SizedBox(height: 14),
            SeTextField(
                controller: phoneCtrl,
                label: 'Phone Number',
                hint: '1-876-000-0000',
                icon: SeIcons.phone,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 14),
            SeTextField(
                controller: emailCtrl,
                label: 'Email Address',
                icon: SeIcons.envelope,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 22),
            SeButton(
              label: 'Save Changes',
              icon: SeIcons.check,
              onPressed: () {
                final name = nameCtrl.text.trim();
                // DR-25: normalise to the one app-wide format on save.
                final phone = SePhone.format(phoneCtrl.text);
                final email = emailCtrl.text.trim();
                if (name.isEmpty) {
                  SeToast.error(ctx, 'Name can\'t be empty');
                  return;
                }
                _saveProfile(name, phone, email);
                Navigator.pop(ctx);
                SeToast.success(context, 'Profile saved!');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStats(),
                  const SizedBox(height: 16),
                  _buildMenuCard(context),
                  const SizedBox(height: 16),
                  SeButton(
                    label: 'Sign Out',
                    icon: SeIcons.signOut,
                    variant: SeButtonVariant.destructive,
                    onPressed: _handleSignOut,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text('ShipEast · v${SeBrand.version}',
                        style:
                            SeType.bodyS.copyWith(color: SeColors.ink400)),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 18,
          bottom: 24,
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
        ),
        decoration: const BoxDecoration(gradient: SeColors.emberGradient),
        child: Row(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 2),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: _avatarUrl != null
                            ? CachedNetworkImage(
                                imageUrl: _avatarUrl!,
                                fit: BoxFit.cover,
                                placeholder: (ctx, url) => _initialsWidget(26),
                                errorWidget: (ctx, url, err) =>
                                    _initialsWidget(26),
                              )
                            : _initialsWidget(26),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: SeElevation.e1,
                      ),
                      child: const Icon(SeIcons.camera,
                          size: 12, color: SeColors.red500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.isNotEmpty ? _name : 'ShipEast User',
                    style: SeType.h3.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  if (_phone.isNotEmpty)
                    Text(SePhone.format(_phone),
                        style: SeType.bodyS.copyWith(
                            color: Colors.white.withValues(alpha: 0.85))),
                  if (_email.isNotEmpty)
                    Text(_email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SeType.bodyS.copyWith(
                            color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            ),
            GestureDetector(
              onTap: _showEditDialog,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: SeRadius.all(SeRadius.sm),
                ),
                child: const Icon(SeIcons.edit, size: 19, color: Colors.white),
              ),
            ),
          ],
        ),
      );

  Widget _initialsWidget(double size) {
    final initials = _name.isNotEmpty
        ? _name
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : '';
    return Center(
      child: initials.isNotEmpty
          ? Text(initials,
              style: SeType.jakarta(size * 0.62, FontWeight.w800,
                  color: Colors.white))
          : Icon(SeIcons.user, size: size, color: Colors.white),
    );
  }

  Widget _buildStats() {
    if (!_statsLoaded) {
      return SeCard(
        child: SizedBox(
          height: 60,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: SeColors.red500, strokeWidth: 2.4),
            ),
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: SeStatTile(
            icon: SeIcons.orders,
            label: 'Orders',
            value: _orderCount,
            hue: SeColors.red500,
            tint: SeColors.red50,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _ratingTile()),
        const SizedBox(width: 12),
        Expanded(
          child: SeStatTile(
            icon: SeIcons.heartFill,
            label: 'Saved',
            value: _savedCount,
            hue: SeColors.ocean500,
            tint: SeColors.oceanTint,
          ),
        ),
      ],
    );
  }

  Widget _ratingTile() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(color: SeColors.ink200, width: 1),
          boxShadow: SeElevation.e1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                  color: SeColors.goldTint, shape: BoxShape.circle),
              child: const Icon(SeIcons.star, size: 20, color: SeColors.gold500),
            ),
            const SizedBox(height: 12),
            Text(
              _avgRating > 0 ? _avgRating.toStringAsFixed(1) : '—',
              style: SeType.tabular(SeType.h2).copyWith(color: SeColors.ink900),
            ),
            const SizedBox(height: 2),
            Text('Rating', style: SeType.bodyS.copyWith(color: SeColors.ink500)),
          ],
        ),
      );

  Widget _buildMenuCard(BuildContext context) {
    final menuItems = [
      {
        'icon': SeIcons.addresses,
        'label': 'Saved Addresses',
        'sub': 'Manage your delivery locations',
        'action': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SavedAddressesScreen())),
      },
      {
        'icon': SeIcons.bell,
        'label': 'Notifications',
        'sub': 'Push alerts & order updates',
        'action': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      },
      {
        'icon': SeIcons.creditCard,
        'label': 'Payment Methods',
        'sub': 'Cards, PayPal & Cash',
        'action': () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    const ComingSoonScreen(title: 'Payment Methods'))),
      },
      {
        'icon': SeIcons.shield,
        'label': 'Privacy & Security',
        'sub': 'Password, data & permissions',
        'action': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PrivacySecurityScreen())),
      },
      {
        'icon': SeIcons.help,
        'label': 'Help & Support',
        'sub': 'FAQs, WhatsApp & Email',
        'action': () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
      },
    ];

    return SeCard(
      padding: EdgeInsets.zero,
      clip: true,
      shadow: SeElevation.e1,
      border: Border.all(color: SeColors.ink200, width: 1),
      child: Column(
        children: menuItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == menuItems.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: item['action'] as VoidCallback,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: SeColors.surface50,
                          borderRadius: SeRadius.all(SeRadius.sm),
                        ),
                        child: Icon(item['icon'] as IconData,
                            size: 20, color: SeColors.ink700),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['label'] as String, style: SeType.title),
                            const SizedBox(height: 1),
                            Text(item['sub'] as String,
                                style: SeType.bodyS
                                    .copyWith(color: SeColors.ink400)),
                          ],
                        ),
                      ),
                      const Icon(SeIcons.caretRight,
                          size: 18, color: SeColors.ink300),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Divider(height: 1, indent: 70, color: SeColors.ink100),
            ],
          );
        }).toList(),
      ),
    );
  }
}
