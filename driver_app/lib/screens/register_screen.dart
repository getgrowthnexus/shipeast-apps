import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_app_bar.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_photo_tile.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import 'pending_approval_screen.dart';

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
  final _confirmPasswordController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _licencePlateController = TextEditingController();
  final _licenceNumberController = TextEditingController();

  bool _isLoading = false;
  String _selectedVehicle = 'Motorcycle';

  // DV-5: credential photos the admin reviews before approving.
  File? _licenceDoc;
  File? _vehicleDoc;

  // Per-field inline errors — replaces the old stack of blocking snackbars.
  final Map<String, String?> _errors = {};

  static const List<Map<String, dynamic>> _vehicleTypes = [
    {'label': 'Motorcycle', 'icon': SeIcons.bike},
    {'label': 'Car', 'icon': SeIcons.car},
    {'label': 'Van', 'icon': Icons.airport_shuttle_rounded},
    {'label': 'Truck', 'icon': Icons.local_shipping_rounded},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehicleModelController.dispose();
    _licencePlateController.dispose();
    _licenceNumberController.dispose();
    super.dispose();
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak (minimum 6 characters).';
      default:
        return 'Registration failed. Please try again.';
    }
  }

  void _pickDoc(String which) {
    void set(File f) => setState(() {
          if (which == 'licence') {
            _licenceDoc = f;
            _errors['licenceDoc'] = null;
          } else {
            _vehicleDoc = f;
            _errors['vehicleDoc'] = null;
          }
        });
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
            Text(
              which == 'licence'
                  ? 'Photo of your driver\'s licence'
                  : 'Photo of your vehicle and plate',
              style: SeType.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SeSpacing.x5),
            SeButton(
              label: 'Take Photo',
              icon: SeIcons.camera,
              onPressed: () async {
                Navigator.pop(ctx);
                final x = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 82,
                    maxWidth: 1600);
                if (x != null && mounted) set(File(x.path));
              },
            ),
            const SizedBox(height: SeSpacing.x3),
            SeButton(
              label: 'Choose from Gallery',
              icon: SeIcons.image,
              variant: SeButtonVariant.ghost,
              onPressed: () async {
                Navigator.pop(ctx);
                final x = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 82,
                    maxWidth: 1600);
                if (x != null && mounted) set(File(x.path));
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _validate() {
    setState(() {
      _errors['name'] =
          _nameController.text.trim().isEmpty ? 'Enter your full name' : null;
      _errors['email'] =
          _emailController.text.trim().isEmpty ? 'Enter your email' : null;
      _errors['password'] = _passwordController.text.length < 6
          ? 'At least 6 characters'
          : null;
      _errors['confirm'] =
          _passwordController.text != _confirmPasswordController.text
              ? 'Passwords do not match'
              : null;
      // Required, not optional. A driver the customer cannot identify at the
      // kerb is a safety problem, not a data-completeness one (SCHEMA.md
      // §drivers). The admin form has always demanded both; registration did
      // not, which is why the two paths disagreed.
      _errors['vehicleModel'] = _vehicleModelController.text.trim().isEmpty
          ? 'Enter your vehicle make and model'
          : null;
      _errors['licencePlate'] = _licencePlateController.text.trim().isEmpty
          ? 'Enter your licence plate'
          : null;
      // DV-5: the admin approves against these, so they are required.
      _errors['licenceDoc'] =
          _licenceDoc == null ? 'Add a photo of your driver\'s licence' : null;
      _errors['vehicleDoc'] =
          _vehicleDoc == null ? 'Add a photo of your vehicle and plate' : null;
    });
    return _errors.values.every((e) => e == null);
  }

  Future<void> _createAccount() async {
    if (!_validate()) return;

    setState(() => _isLoading = true);
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final uid = credential.user!.uid;
      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'name': _nameController.text.trim(),
        'phone': SePhone.format(_phoneController.text),
        'email': _emailController.text.trim(),
        'vehicleType': _selectedVehicle,
        'vehicleModel': _vehicleModelController.text.trim(),
        'licencePlate': _licencePlateController.text.trim(),
        // licenceNumber is deliberately absent — see below.
        'status': 'pending',
        'isOnline': false,
        'rating': 5.0,
        'totalTrips': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // The licence number goes to the private subcollection, never onto
      // drivers/{uid} (P4-05). The parent document is readable by every
      // signed-in user — it has to be, because the customer's tracking card
      // shows the driver's name and vehicle — so a licence number there was
      // readable by every customer who had ever placed an order.
      final licence = _licenceNumberController.text.trim();
      // DV-5: credential photos go to the same private subdoc as the licence
      // number — the parent document is readable by every signed-in user.
      final docs = <String, String>{};
      if (_licenceDoc != null) {
        docs['licence'] = await DriverFirestoreService.uploadDriverDocument(
            uid, 'licence', _licenceDoc!);
      }
      if (_vehicleDoc != null) {
        docs['vehicle'] = await DriverFirestoreService.uploadDriverDocument(
            uid, 'vehicle', _vehicleDoc!);
      }
      if (licence.isNotEmpty || docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .collection('private')
            .doc('identity')
            .set({
          if (licence.isNotEmpty) 'licenceNumber': licence,
          if (docs.isNotEmpty) 'documents': docs,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        // Client request: confirm the submission explicitly before the driver
        // lands on the pending-approval screen.
        SeToast.success(
          context,
          'Application submitted successfully. Our team will review your '
          'information and contact you once a decision is made.',
        );
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
      SeToast.error(context, 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearError(String key) {
    if (_errors[key] != null) setState(() => _errors[key] = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeColors.surface50,
      appBar: const SeTopBar(title: 'Create Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x2, SeSpacing.gutter, SeSpacing.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Ember intro banner ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(SeSpacing.x5),
              margin: const EdgeInsets.only(bottom: SeSpacing.x6),
              decoration: BoxDecoration(
                gradient: SeColors.emberGradient,
                borderRadius: SeRadius.all(SeRadius.lg),
                boxShadow: SeElevation.glow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(SeIcons.bike,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: SeSpacing.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Earn while driving with Shipeast',
                            style: SeType.h3.copyWith(color: Colors.white)),
                        const SizedBox(height: SeSpacing.x1),
                        Text(
                          'Complete deliveries across St. Thomas and Kingston using your own motorcycle or car.',
                          style: SeType.bodyS.copyWith(
                              color: Colors.white.withValues(alpha: 0.82)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            _sectionLabel('Your details'),
            SeTextField(
              controller: _nameController,
              label: 'Full Name',
              hint: 'e.g. Andre Campbell',
              icon: SeIcons.userCircle,
              textInputAction: TextInputAction.next,
              errorText: _errors['name'],
              onChanged: (_) => _clearError('name'),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: '1-876-000-0000',
              icon: SeIcons.phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'you@example.com',
              icon: SeIcons.envelope,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              errorText: _errors['email'],
              onChanged: (_) => _clearError('email'),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'At least 6 characters',
              icon: SeIcons.lock,
              obscure: true,
              textInputAction: TextInputAction.next,
              errorText: _errors['password'],
              onChanged: (_) => _clearError('password'),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              icon: SeIcons.lock,
              obscure: true,
              textInputAction: TextInputAction.next,
              errorText: _errors['confirm'],
              onChanged: (_) => _clearError('confirm'),
            ),

            const SizedBox(height: SeSpacing.x6),
            _sectionLabel('Vehicle information'),

            // ── Vehicle type selector ───────────────────────────────────────
            Row(
              children: List.generate(_vehicleTypes.length, (i) {
                final vehicle = _vehicleTypes[i];
                final selected = _selectedVehicle == vehicle['label'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(
                        () => _selectedVehicle = vehicle['label'] as String),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: SeMotion.fast,
                      curve: SeMotion.emphasized,
                      margin: EdgeInsets.only(
                          right: i < _vehicleTypes.length - 1 ? SeSpacing.x2 : 0),
                      padding: const EdgeInsets.symmetric(
                          vertical: SeSpacing.x3, horizontal: SeSpacing.x1),
                      decoration: BoxDecoration(
                        color: selected ? SeColors.red50 : SeColors.surface0,
                        borderRadius: SeRadius.all(SeRadius.sm),
                        border: Border.all(
                          color:
                              selected ? SeColors.red500 : SeColors.ink200,
                          width: selected ? 2 : 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            vehicle['icon'] as IconData,
                            color:
                                selected ? SeColors.red700 : SeColors.ink400,
                            size: 22,
                          ),
                          const SizedBox(height: SeSpacing.x1),
                          Text(
                            vehicle['label'] as String,
                            textAlign: TextAlign.center,
                            style: SeType.eyebrow.copyWith(
                              color: selected
                                  ? SeColors.red700
                                  : SeColors.ink500,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _vehicleModelController,
              label: 'Vehicle Make & Model',
              hint: 'Toyota Corolla',
              icon: SeIcons.car,
              textInputAction: TextInputAction.next,
              errorText: _errors['vehicleModel'],
              onChanged: (_) => _clearError('vehicleModel'),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _licencePlateController,
              label: 'Licence Plate',
              hint: 'ABC 1234',
              icon: SeIcons.creditCard,
              textInputAction: TextInputAction.next,
              errorText: _errors['licencePlate'],
              onChanged: (_) => _clearError('licencePlate'),
            ),
            const SizedBox(height: SeSpacing.x4),
            SeTextField(
              controller: _licenceNumberController,
              label: 'Licence Number',
              hint: 'DL-XXXXXXXX',
              icon: SeIcons.badge,
              textInputAction: TextInputAction.done,
            ),

            // ── DV-5: credential photos the ShipEast team reviews ──────────
            const SizedBox(height: SeSpacing.x6),
            Text('Documents', style: SeType.label.copyWith(color: SeColors.ink700)),
            const SizedBox(height: SeSpacing.x1),
            Text(
              'Our team checks these before approving your account.',
              style: SeType.bodyS.copyWith(color: SeColors.ink500),
            ),
            const SizedBox(height: SeSpacing.x3),
            SePhotoTile(
              photo: _licenceDoc,
              onCapture: () => _pickDoc('licence'),
              emptyLabel: 'Driver\'s licence',
              emptyHint: _errors['licenceDoc'] ?? 'A clear photo of the front',
              height: 150,
              errored: _errors['licenceDoc'] != null,
            ),
            const SizedBox(height: SeSpacing.x4),
            SePhotoTile(
              photo: _vehicleDoc,
              onCapture: () => _pickDoc('vehicle'),
              emptyLabel: 'Vehicle & plate',
              emptyHint: _errors['vehicleDoc'] ??
                  'Show the whole vehicle with the plate readable',
              height: 150,
              errored: _errors['vehicleDoc'] != null,
            ),

            const SizedBox(height: SeSpacing.x6),
            SeButton(
              label: 'Create Account',
              loading: _isLoading,
              onPressed: _isLoading ? null : _createAccount,
            ),
            const SizedBox(height: SeSpacing.x4),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(SeSpacing.x2),
                  child: RichText(
                    text: TextSpan(
                      style: SeType.bodyS.copyWith(color: SeColors.ink500),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign In',
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
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: SeSpacing.x3),
        child: Text(text.toUpperCase(), style: SeType.eyebrow),
      );
}
