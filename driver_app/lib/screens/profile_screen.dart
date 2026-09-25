import 'dart:io';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../theme/se_brand.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_card.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<String> driverNameNotifier;
  const ProfileScreen({super.key, required this.driverNameNotifier});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = 'Driver';
  String _phone = '';
  String _email = '';
  String _vehicle = 'Motorcycle';
  String _licence = '';
  String? _avatarUrl;
  double _rating = 5.0;
  int _totalTrips = 0;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _licenceCtrl;
  String _editVehicle = 'Motorcycle';

  static const _vehicleTypes = ['Motorcycle', 'Car', 'Van', 'Truck'];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _licenceCtrl = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _licenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _name = data['name'] as String? ?? 'Driver';
          _phone = data['phone'] as String? ?? '';
          _email = data['email'] as String? ?? '';
          _vehicle = data['vehicleType'] as String? ?? 'Motorcycle';
          _licence = data['licencePlate'] as String? ?? '';
          _avatarUrl = data['avatarUrl'] as String?;
          _rating = (data['rating'] as num?)?.toDouble() ?? 5.0;
          _totalTrips = (data['totalTrips'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      if (mounted) SeToast.error(context, 'Could not load your profile.');
    }
  }

  void _startEditing() {
    _nameCtrl.text = _name;
    _phoneCtrl.text = _phone;
    _emailCtrl.text = _email;
    _licenceCtrl.text = _licence;
    _editVehicle = _vehicle;
    setState(() => _isEditing = true);
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      SeToast.error(context, 'Your name cannot be empty.');
      return;
    }
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .update({
          'name': _nameCtrl.text.trim(),
          // DR-25: store the number in the one app-wide format.
          'phone': SePhone.format(_phoneCtrl.text),
          'email': _emailCtrl.text.trim(),
          'vehicleType': _editVehicle,
          'licencePlate': _licenceCtrl.text.trim(),
        });
      } catch (_) {
        // Don't claim a local save when the write failed.
        if (mounted) {
          setState(() => _isSaving = false);
          SeToast.error(context, 'Could not save your profile. Try again.');
        }
        return;
      }
    }
    setState(() {
      _name = _nameCtrl.text.trim();
      _phone = SePhone.format(_phoneCtrl.text);
      _email = _emailCtrl.text.trim();
      _vehicle = _editVehicle;
      _licence = _licenceCtrl.text.trim();
      _isEditing = false;
      _isSaving = false;
    });
    widget.driverNameNotifier.value = _name;
    if (mounted) SeToast.success(context, 'Profile saved');
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final url = await DriverFirestoreService.uploadProfilePhoto(
          user.uid, File(picked.path));
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .update({'avatarUrl': url});
      if (mounted) setState(() => _avatarUrl = url);
    } catch (_) {
      if (mounted) SeToast.error(context, 'Photo upload failed. Try again.');
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _showPhotoOptions() {
    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          bottom: MediaQuery.of(ctx).padding.bottom + SeSpacing.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: SeSpacing.x3),
            Text('Profile photo',
                style: SeType.h3, textAlign: TextAlign.center),
            const SizedBox(height: SeSpacing.x5),
            SeButton(
              label: 'Take Photo',
              icon: SeIcons.camera,
              onPressed: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            const SizedBox(height: SeSpacing.x3),
            SeButton(
              label: 'Choose from Gallery',
              icon: SeIcons.image,
              variant: SeButtonVariant.ghost,
              onPressed: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await SeConfirmSheet.show(
      context,
      title: 'Sign out?',
      message: 'You will stop receiving order requests until you sign back in.',
      confirmLabel: 'Sign Out',
      destructive: true,
    );
    if (ok) _signOut();
  }

  /// Honest placeholder for features that genuinely do not exist yet.
  void _showNotBuiltYet(String feature, String detail) {
    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SeSheetHandle(),
            SeEmptyState(
              icon: SeIcons.rocket,
              title: feature,
              message: detail,
              ctaLabel: 'Got it',
              onCta: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showSeBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          bottom: MediaQuery.of(ctx).padding.bottom + SeSpacing.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: SeSpacing.x4),
            const SeWordmark(size: 30),
            const SizedBox(height: SeSpacing.x2),
            Text('Driver App · v${SeBrand.version}',
                style: SeType.bodyS.copyWith(color: SeColors.ink500)),
            const SizedBox(height: SeSpacing.x5),
            Text(
              SeBrand.tagline,
              textAlign: TextAlign.center,
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
            const SizedBox(height: SeSpacing.x3),
            Text(
              'Connecting drivers with customers across Jamaica.',
              textAlign: TextAlign.center,
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
            const SizedBox(height: SeSpacing.x6),
            SeButton(
              label: 'Close',
              variant: SeButtonVariant.ghost,
              onPressed: () => Navigator.pop(ctx),
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
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEditing) _editForm() else _viewMode(),
                  const SizedBox(height: SeSpacing.x4),
                  _settingsCard(),
                  const SizedBox(height: SeSpacing.x4),
                  SeButton(
                    label: 'Sign Out',
                    icon: SeIcons.signOut,
                    variant: SeButtonVariant.destructive,
                    onPressed: _confirmSignOut,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
        decoration: const BoxDecoration(gradient: SeColors.emberGradient),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SeSpacing.gutter, SeSpacing.x3,
                SeSpacing.gutter, SeSpacing.x6),
            child: Column(
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Text('Driver Profile',
                        style: SeType.h3.copyWith(color: Colors.white)),
                    const Spacer(),
                    GestureDetector(
                      onTap: _isEditing
                          ? () => setState(() => _isEditing = false)
                          : _startEditing,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isEditing ? SeIcons.close : SeIcons.edit,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SeSpacing.x5),
                GestureDetector(
                  onTap: _showPhotoOptions,
                  child: Stack(
                    children: [
                      _avatar(),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: SeElevation.e1,
                          ),
                          child: const Icon(SeIcons.camera,
                              size: 15, color: SeColors.red500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SeSpacing.x3),
                Text(_name, style: SeType.h2.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  '$_vehicle · ShipEast Driver',
                  style: SeType.bodyS
                      .copyWith(color: Colors.white.withValues(alpha: 0.82)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _avatar() {
    const size = 92.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.55), width: 2.5),
      ),
      child: _isUploadingPhoto
          ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            )
          : ClipOval(
              child: _avatarUrl != null
                  ? Image.network(
                      _avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                          SeIcons.userFill,
                          size: 44,
                          color: Colors.white),
                    )
                  : const Icon(SeIcons.userFill,
                      size: 44, color: Colors.white),
            ),
    );
  }

  Widget _viewMode() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Rating ring + trips ─────────────────────────────────────────
          //
          // Audit §7.3: the old third stat was a "Completion" percentage
          // computed as totalTrips/(totalTrips+1)*100 — a number that only ever
          // climbed toward 100% and measured nothing. It is gone; what remains
          // are two figures the backend actually stores.
          SeCard(
            padding: const EdgeInsets.all(SeSpacing.x5),
            child: Row(
              children: [
                _RatingRing(rating: _rating),
                const SizedBox(width: SeSpacing.x5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR RATING', style: SeType.eyebrow),
                      const SizedBox(height: SeSpacing.x1),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(_rating.toStringAsFixed(1),
                              style: SeType.tabular(SeType.display)),
                          const SizedBox(width: SeSpacing.x1),
                          Text('/ 5.0',
                              style: SeType.body
                                  .copyWith(color: SeColors.ink400)),
                        ],
                      ),
                      const SizedBox(height: SeSpacing.x2),
                      Text(
                        _totalTrips == 0
                            ? 'No completed deliveries yet'
                            : 'Across $_totalTrips completed deliver${_totalTrips == 1 ? 'y' : 'ies'}',
                        style: SeType.bodyS.copyWith(color: SeColors.ink500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SeSpacing.x4),

          SeCard(
            clip: true,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _infoRow(SeIcons.phone, 'Phone', SePhone.format(_phone)),
                _rowDivider(),
                _infoRow(SeIcons.envelope, 'Email', _email),
                _rowDivider(),
                _infoRow(SeIcons.bike, 'Vehicle', _vehicle),
                _rowDivider(),
                _infoRow(SeIcons.creditCard, 'Licence plate', _licence),
              ],
            ),
          ),
        ],
      );

  Widget _rowDivider() => const Divider(
      height: 1,
      color: SeColors.ink100,
      indent: SeSpacing.x5,
      endIndent: SeSpacing.x5);

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SeSpacing.x5, vertical: SeSpacing.x4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: SeColors.ink400),
            const SizedBox(width: SeSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: SeType.eyebrow),
                  const SizedBox(height: 2),
                  Text(value.isEmpty ? '—' : value, style: SeType.body),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _editForm() => SeCard(
        padding: const EdgeInsets.all(SeSpacing.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit profile', style: SeType.h3),
            const SizedBox(height: SeSpacing.x5),
            SeTextField(
              controller: _nameCtrl,
              label: 'Full Name',
              icon: SeIcons.userCircle,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _phoneCtrl,
              label: 'Phone Number',
              hint: '1-876-000-0000',
              icon: SeIcons.phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _emailCtrl,
              label: 'Email',
              icon: SeIcons.envelope,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SeSpacing.x5),
            Text('VEHICLE TYPE', style: SeType.eyebrow),
            const SizedBox(height: SeSpacing.x3),
            Row(
              children: List.generate(_vehicleTypes.length, (i) {
                final v = _vehicleTypes[i];
                final selected = _editVehicle == v;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _editVehicle = v),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: SeMotion.fast,
                      curve: SeMotion.emphasized,
                      margin: EdgeInsets.only(
                          right:
                              i < _vehicleTypes.length - 1 ? SeSpacing.x2 : 0),
                      padding:
                          const EdgeInsets.symmetric(vertical: SeSpacing.x3),
                      decoration: BoxDecoration(
                        color:
                            selected ? SeColors.red50 : SeColors.surface50,
                        borderRadius: SeRadius.all(SeRadius.sm),
                        border: Border.all(
                          color:
                              selected ? SeColors.red500 : SeColors.ink200,
                          width: selected ? 2 : 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          v,
                          style: SeType.eyebrow.copyWith(
                            color: selected
                                ? SeColors.red700
                                : SeColors.ink500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: SeSpacing.x5),
            SeTextField(
              controller: _licenceCtrl,
              label: 'Licence Plate',
              icon: SeIcons.creditCard,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: SeSpacing.x6),
            SeButton(
              label: 'Save Changes',
              loading: _isSaving,
              onPressed: _isSaving ? null : _saveProfile,
            ),
          ],
        ),
      );

  Widget _settingsCard() => SeCard(
        clip: true,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _settingsTile(
              SeIcons.bell,
              'Notifications',
              () => _showNotBuiltYet(
                'Notification settings',
                'Per-alert controls are not built yet. For now the app follows your Android notification settings for ShipEast Driver.',
              ),
            ),
            _rowDivider(),
            _settingsTile(
              SeIcons.shield,
              'Privacy & Security',
              () => _showNotBuiltYet(
                'Privacy & Security',
                'In-app privacy controls are still being built. To change your password, use "Forgot password?" on the sign-in screen.',
              ),
            ),
            _rowDivider(),
            _settingsTile(
              SeIcons.help,
              'Help & Support',
              () => _showNotBuiltYet(
                'Help & Support',
                'In-app support chat is on the way. For anything urgent, call the ShipEast dispatch desk on the number in your driver pack.',
              ),
            ),
            _rowDivider(),
            _settingsTile(SeIcons.info, 'About ShipEast', _showAbout),
          ],
        ),
      );

  Widget _settingsTile(IconData icon, String title, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SeSpacing.x5, vertical: SeSpacing.x4),
          child: Row(
            children: [
              Icon(icon, size: 21, color: SeColors.ink500),
              const SizedBox(width: SeSpacing.x4),
              Expanded(child: Text(title, style: SeType.body)),
              const Icon(SeIcons.caretRight,
                  size: 20, color: SeColors.ink300),
            ],
          ),
        ),
      );
}

/// Gold rating arc — a real 0–5 reading, not a decorative ring.
class _RatingRing extends StatelessWidget {
  final double rating;
  const _RatingRing({required this.rating});

  @override
  Widget build(BuildContext context) {
    final reduced = SeMotion.reduced(context);
    return SizedBox(
      width: 78,
      height: 78,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (rating / 5).clamp(0.0, 1.0)),
        duration: reduced ? Duration.zero : SeMotion.deliberate,
        curve: SeMotion.decelerate,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(value),
          child: const Center(
            child: Icon(SeIcons.star, color: SeColors.gold500, size: 30),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = SeColors.goldTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = SeColors.gold500
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}
