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
import '../utils/names.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../theme/se_brand.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';
import 'help_support_screen.dart';
import 'notifications_screen.dart';
import 'privacy_security_screen.dart';
import 'saved_addresses_screen.dart';
import 'coming_soon_screen.dart';

/// Profile.
///
/// The identity block sits in the brand cap — photo, name, contact — and the
/// sheet holds everything you can DO. Settings are one hairlined group rather
/// than five separately shadowed cards, which is what stops a settings page
/// from reading as a pile of unrelated boxes.
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
          _name = SeName.title(data['name'] as String?);
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

  void _showEditSheet() {
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
            const SizedBox(height: 14),
            Text('Edit profile', style: SeType.h2),
            const SizedBox(height: 18),
            SeTextField(
                controller: nameCtrl,
                label: 'Full name',
                icon: SeIcons.user,
                keyboardType: TextInputType.name),
            const SizedBox(height: 14),
            SeTextField(
                controller: phoneCtrl,
                label: 'Phone number',
                hint: '1-876-000-0000',
                icon: SeIcons.phone,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 14),
            SeTextField(
                controller: emailCtrl,
                label: 'Email address',
                icon: SeIcons.envelope,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 22),
            SeButton(
              label: 'Save changes',
              onPressed: () {
                final name = SeName.title(nameCtrl.text);
                // DR-25: normalise to the one app-wide format on save.
                final phone = SePhone.format(phoneCtrl.text);
                final email = emailCtrl.text.trim();
                if (name.isEmpty) {
                  SeToast.error(ctx, 'Name can\'t be empty');
                  return;
                }
                _saveProfile(name, phone, email);
                Navigator.pop(ctx);
                SeToast.success(context, 'Profile saved');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      showBack: false,
      capTitle: _identity(),
      trailing: SeCapButton(icon: SeIcons.edit, onTap: _showEditSheet),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 110),
        children: [
          _stats(),
          const SizedBox(height: 20),
          SeRowGroup(
            children: [
              SeRow(
                icon: SeIcons.addresses,
                label: 'Saved addresses',
                subtitle: 'Where we deliver to',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SavedAddressesScreen())),
              ),
              SeRow(
                icon: SeIcons.bell,
                label: 'Notifications',
                subtitle: 'Order updates and offers',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              ),
              SeRow(
                icon: SeIcons.creditCard,
                label: 'Payment methods',
                subtitle: 'Cards, cash, other',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            const ComingSoonScreen(title: 'Payment Methods'))),
              ),
              SeRow(
                icon: SeIcons.shield,
                label: 'Privacy & security',
                subtitle: 'Password, account and permissions',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrivacySecurityScreen())),
              ),
              SeRow(
                icon: SeIcons.help,
                label: 'Help & support',
                subtitle: 'FAQs, WhatsApp, phone and email',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SeButton(
            label: 'Sign out',
            variant: SeButtonVariant.destructive,
            onPressed: _handleSignOut,
          ),
          const SizedBox(height: 18),
          Center(
            child: Text('ShipEast · v${SeBrand.version}',
                style: SeType.bodyS.copyWith(color: SeColors.ink400)),
          ),
        ],
      ),
    );
  }

  Widget _identity() => Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35), width: 2),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: _avatarUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _avatarUrl!,
                              fit: BoxFit.cover,
                              placeholder: (ctx, url) => _initials(25),
                              errorWidget: (ctx, url, err) => _initials(25),
                            )
                          : _initials(25),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: SeColors.shellInk,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(SeIcons.camera,
                        size: 12, color: SeColors.shell),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _name.isNotEmpty ? _name : 'ShipEast customer',
                  style: SeType.h2.copyWith(color: SeColors.shellInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // One contact line, not two. Whichever we have is enough to
                // confirm "this is my account"; both is a stack of grey text.
                if (_phone.isNotEmpty || _email.isNotEmpty)
                  Text(
                    _phone.isNotEmpty ? SePhone.format(_phone) : _email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SeType.bodyS.copyWith(
                        color: SeColors.shellInk.withValues(alpha: 0.76)),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _initials(double size) {
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
                  color: SeColors.shellInk))
          : Icon(SeIcons.user, size: size, color: SeColors.shellInk),
    );
  }

  Widget _stats() {
    return Row(
      children: [
        Expanded(
          child: SeStat(
            icon: SeIcons.orders,
            value: _statsLoaded ? '$_orderCount' : '–',
            label: 'Orders',
            hue: SeColors.brand,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SeStat(
            // Client checklist: "Orders · Rewards · Saved". There is no rewards
            // programme yet, so the tile says so rather than inventing a figure.
            icon: SeIcons.gift,
            value: 'Soon',
            label: 'Rewards',
            hue: SeColors.star,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SeStat(
            icon: SeIcons.heartFill,
            value: _statsLoaded ? '$_savedCount' : '–',
            label: 'Saved',
            hue: SeColors.info,
          ),
        ),
      ],
    );
  }
}
