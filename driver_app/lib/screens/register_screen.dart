import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../services/inline_image.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_motion.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_auth_scaffold.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_photo_tile.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import 'pending_approval_screen.dart';

/// Driver application.
///
/// Client checklist (driver round, Sep 2026) — what an applicant provides:
/// profile photo, TRN, driver's licence (number, expiry, photo), vehicle type
/// and year, insurance (photo, expiry), service areas, bank/payment details,
/// two references, and agreement to the driver terms. Sections: Personal
/// Details · Vehicle Information · Documents · Service Areas · Payment Details
/// · References · Agreement.
///
/// Where it is stored (SCHEMA.md §drivers):
/// - `drivers/{uid}` — what customers and the admin roster may see: name,
///   phone, vehicle, service areas, avatar, document expiry dates (so the
///   admin can flag an expired licence or insurance without opening files).
/// - `drivers/{uid}/private/identity` — licence number, TRN, bank details,
///   references: readable by the driver and admins only.
/// - `drivers/{uid}/private/doc_{licence|vehicle|insurance}` — the photos,
///   inline, one per document (free plan: no Cloud Storage).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Personal details
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _trnController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _avatar;

  // Vehicle
  String _selectedVehicle = 'Motorcycle';
  final _vehicleModelController = TextEditingController();
  final _vehicleYearController = TextEditingController();
  final _licencePlateController = TextEditingController();

  // Documents
  final _licenceNumberController = TextEditingController();
  final _licenceExpiryController = TextEditingController();
  final _insuranceExpiryController = TextEditingController();
  DateTime? _licenceExpiry;
  DateTime? _insuranceExpiry;
  File? _licenceDoc;
  File? _vehicleDoc;
  File? _insuranceDoc;

  // Service areas — the two parishes ShipEast serves.
  static const _areaOptions = ['St. Thomas', 'Kingston'];
  final Set<String> _areas = {};

  // Payment
  final _bankNameController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _branchController = TextEditingController();

  // References
  final _ref1NameController = TextEditingController();
  final _ref1PhoneController = TextEditingController();
  final _ref2NameController = TextEditingController();
  final _ref2PhoneController = TextEditingController();

  bool _agreed = false;
  bool _isLoading = false;

  // Per-field inline errors — replaces the old stack of blocking snackbars.
  final Map<String, String?> _errors = {};

  static const List<Map<String, dynamic>> _vehicleTypes = [
    {'label': 'Motorcycle', 'icon': SeIcons.bike},
    {'label': 'Car', 'icon': SeIcons.car},
    {'label': 'Van', 'icon': SeIcons.van},
    {'label': 'Truck', 'icon': SeIcons.truck},
  ];

  List<TextEditingController> get _controllers => [
        _nameController, _phoneController, _emailController, _trnController,
        _passwordController, _confirmPasswordController,
        _vehicleModelController, _vehicleYearController,
        _licencePlateController, _licenceNumberController,
        _licenceExpiryController, _insuranceExpiryController,
        _bankNameController, _accountNameController,
        _accountNumberController, _branchController,
        _ref1NameController, _ref1PhoneController,
        _ref2NameController, _ref2PhoneController,
      ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
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

  // ── Photos ────────────────────────────────────────────────────────────────

  /// Camera or gallery, then [onPicked]. Profile photos are picked small;
  /// document photos large enough to read.
  void _pickPhoto({
    required String title,
    required bool avatar,
    required ValueChanged<File> onPicked,
  }) {
    Future<void> pick(BuildContext ctx, ImageSource source) async {
      Navigator.pop(ctx);
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: avatar ? InlineImage.avatarMaxWidth : InlineImage.docMaxWidth,
        imageQuality: avatar ? InlineImage.avatarQuality : InlineImage.docQuality,
        preferredCameraDevice:
            avatar ? CameraDevice.front : CameraDevice.rear,
      );
      if (x != null && mounted) onPicked(File(x.path));
    }

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
            Text(title, style: SeType.h3, textAlign: TextAlign.center),
            const SizedBox(height: SeSpacing.x5),
            SeButton(
              label: 'Take Photo',
              icon: SeIcons.camera,
              onPressed: () => pick(ctx, ImageSource.camera),
            ),
            const SizedBox(height: SeSpacing.x3),
            SeButton(
              label: 'Choose from Gallery',
              icon: SeIcons.image,
              variant: SeButtonVariant.ghost,
              onPressed: () => pick(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _pickDoc(String which) {
    final title = switch (which) {
      'licence' => 'Photo of your driver\'s licence',
      'insurance' => 'Photo of your insurance certificate',
      _ => 'Photo of your vehicle and plate',
    };
    _pickPhoto(
      title: title,
      avatar: false,
      onPicked: (f) => setState(() {
        switch (which) {
          case 'licence':
            _licenceDoc = f;
          case 'insurance':
            _insuranceDoc = f;
          default:
            _vehicleDoc = f;
        }
        _errors['${which}Doc'] = null;
      }),
    );
  }

  Future<void> _pickExpiry(String which) async {
    final now = DateTime.now();
    final current = which == 'licence' ? _licenceExpiry : _insuranceExpiry;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 15),
      helpText: which == 'licence'
          ? 'Driver\'s licence expiry date'
          : 'Insurance expiry date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (which == 'licence') {
        _licenceExpiry = picked;
        _licenceExpiryController.text = SeDate.long(picked);
      } else {
        _insuranceExpiry = picked;
        _insuranceExpiryController.text = SeDate.long(picked);
      }
      _errors['${which}Expiry'] = null;
    });
  }

  // ── Validation ────────────────────────────────────────────────────────────

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String? _required(TextEditingController c, String message) =>
      c.text.trim().isEmpty ? message : null;

  static String? _phoneError(TextEditingController c) {
    final d = _digits(c.text);
    if (d.isEmpty) return 'Enter a phone number';
    return d.length < 7 ? 'Enter a full phone number' : null;
  }

  String? _expiryError(DateTime? expiry, String what) {
    if (expiry == null) return 'Pick the $what expiry date';
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return expiry.isBefore(startOfToday)
        ? 'This $what has expired — renew it before applying'
        : null;
  }

  bool _validate() {
    final year = int.tryParse(_vehicleYearController.text.trim());
    final maxYear = DateTime.now().year + 1;
    final account = _digits(_accountNumberController.text);
    setState(() {
      _errors['avatar'] = _avatar == null ? 'Add a profile photo' : null;
      _errors['name'] = _required(_nameController, 'Enter your full name');
      _errors['phone'] = _phoneError(_phoneController);
      _errors['email'] = _required(_emailController, 'Enter your email');
      // Jamaica's TRN is nine digits; dashes and spaces are fine.
      _errors['trn'] = _digits(_trnController.text).length == 9
          ? null
          : 'Enter your 9-digit TRN';
      _errors['password'] = _passwordController.text.length < 6
          ? 'At least 6 characters'
          : null;
      _errors['confirm'] =
          _passwordController.text != _confirmPasswordController.text
              ? 'Passwords do not match'
              : null;
      // Required, not optional. A driver the customer cannot identify at the
      // kerb is a safety problem, not a data-completeness one (SCHEMA.md
      // §drivers).
      _errors['vehicleModel'] = _required(
          _vehicleModelController, 'Enter your vehicle make and model');
      _errors['vehicleYear'] = (year == null || year < 1980 || year > maxYear)
          ? 'Enter the year, e.g. 2018'
          : null;
      _errors['licencePlate'] =
          _required(_licencePlateController, 'Enter your licence plate');
      _errors['licenceNumber'] =
          _required(_licenceNumberController, 'Enter your licence number');
      _errors['licenceExpiry'] = _expiryError(_licenceExpiry, 'licence');
      _errors['insuranceExpiry'] = _expiryError(_insuranceExpiry, 'insurance');
      // The admin approves against these photos, so they are required.
      _errors['licenceDoc'] =
          _licenceDoc == null ? 'Add a photo of your driver\'s licence' : null;
      _errors['insuranceDoc'] =
          _insuranceDoc == null ? 'Add a photo of your insurance' : null;
      _errors['vehicleDoc'] =
          _vehicleDoc == null ? 'Add a photo of your vehicle and plate' : null;
      _errors['areas'] =
          _areas.isEmpty ? 'Choose at least one area you will drive in' : null;
      _errors['bankName'] = _required(_bankNameController, 'Enter your bank');
      _errors['accountName'] =
          _required(_accountNameController, 'Enter the name on the account');
      _errors['accountNumber'] = (account.length < 5 || account.length > 20)
          ? 'Enter your account number'
          : null;
      _errors['ref1Name'] = _required(_ref1NameController, 'Enter a name');
      _errors['ref1Phone'] = _phoneError(_ref1PhoneController);
      _errors['ref2Name'] = _required(_ref2NameController, 'Enter a name');
      _errors['ref2Phone'] = _phoneError(_ref2PhoneController);
      _errors['agreed'] =
          _agreed ? null : 'You must agree to the driver terms to apply';
    });
    return _errors.values.every((e) => e == null);
  }

  /// Photos are checked before the account exists: an oversized photo found
  /// after sign-up would leave an account with no application behind it.
  Future<bool> _photosFit() async {
    for (final f in [_avatar, _licenceDoc, _insuranceDoc, _vehicleDoc]) {
      if (f != null && await f.length() > InlineImage.maxBytes) return false;
    }
    return true;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _createAccount() async {
    if (!_validate()) {
      SeToast.error(context, 'Please complete the highlighted fields.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (!await _photosFit()) {
        if (mounted) SeToast.error(context, const InlineImageTooLarge().toString());
        return;
      }
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final uid = credential.user!.uid;
      final db = FirebaseFirestore.instance;
      final avatarUrl =
          await DriverFirestoreService.uploadProfilePhoto(uid, _avatar!);

      await db.collection('drivers').doc(uid).set({
        'name': _nameController.text.trim(),
        'phone': SePhone.format(_phoneController.text),
        'email': _emailController.text.trim(),
        'avatarUrl': avatarUrl,
        'vehicleType': _selectedVehicle,
        'vehicleModel': _vehicleModelController.text.trim(),
        'vehicleYear': int.parse(_vehicleYearController.text.trim()),
        'licencePlate': _licencePlateController.text.trim(),
        'serviceAreas': _areaOptions.where(_areas.contains).toList(),
        // On the parent document so the admin roster can flag an expired
        // licence or insurance without reading anyone's private files.
        'licenceExpiresAt': Timestamp.fromDate(_licenceExpiry!),
        'insuranceExpiresAt': Timestamp.fromDate(_insuranceExpiry!),
        'agreedToTermsAt': FieldValue.serverTimestamp(),
        // licenceNumber, TRN, bank details and references are deliberately
        // absent — see private/identity below.
        'status': 'pending',
        'isOnline': false,
        'rating': 5.0,
        'totalTrips': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final docs = <String, String>{
        'licence': await DriverFirestoreService.uploadDriverDocument(
            uid, 'licence', _licenceDoc!,
            expiresAt: _licenceExpiry),
        'insurance': await DriverFirestoreService.uploadDriverDocument(
            uid, 'insurance', _insuranceDoc!,
            expiresAt: _insuranceExpiry),
        'vehicle': await DriverFirestoreService.uploadDriverDocument(
            uid, 'vehicle', _vehicleDoc!),
      };

      // The parent document is readable by every signed-in user — the
      // customer's tracking card shows the driver's name and vehicle — so
      // anything identifying or financial lives here instead (P4-05).
      final trn = _digits(_trnController.text);
      await db
          .collection('drivers')
          .doc(uid)
          .collection('private')
          .doc('identity')
          .set({
        'licenceNumber': _licenceNumberController.text.trim(),
        'trn': '${trn.substring(0, 3)}-${trn.substring(3, 6)}-${trn.substring(6)}',
        'bank': {
          'bankName': _bankNameController.text.trim(),
          'accountName': _accountNameController.text.trim(),
          'accountNumber': _digits(_accountNumberController.text),
          'branch': _branchController.text.trim(),
        },
        'references': [
          {
            'name': _ref1NameController.text.trim(),
            'phone': SePhone.format(_ref1PhoneController.text),
          },
          {
            'name': _ref2NameController.text.trim(),
            'phone': SePhone.format(_ref2PhoneController.text),
          },
        ],
        'documents': docs,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
    } on InlineImageTooLarge catch (e) {
      if (!mounted) return;
      SeToast.error(context, e.toString());
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

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // No banner under the cap. The cap is already the brand surface, and the
    // old ember block sat directly beneath it — two reds, one on top of the
    // other, telling the applicant the same thing twice.
    return SeAuthScaffold(
      // Header copy per the client review round: the recruiting line lives on
      // the welcome screen; this screen asks for the application itself.
      title: 'Become a Shipeast driver',
      subtitle: 'Tell us about yourself and your vehicle. Every application is '
          'reviewed before approval.',
      children: [
        // ── Personal Details ───────────────────────────────────────────────
        _sectionLabel('Personal Details'),
        _avatarPicker(),
        const SizedBox(height: SeSpacing.x4),
        _field(_nameController, 'name', 'Full Name', 'e.g. Andre Campbell',
            SeIcons.userCircle),
        _field(_phoneController, 'phone', 'Phone Number', '1-876-000-0000',
            SeIcons.phone,
            keyboard: TextInputType.phone),
        _field(_emailController, 'email', 'Email', 'you@example.com',
            SeIcons.envelope,
            keyboard: TextInputType.emailAddress),
        _field(_trnController, 'trn', 'TRN #', '000-000-000', SeIcons.badge,
            keyboard: TextInputType.number),
        _field(_passwordController, 'password', 'Password',
            'At least 6 characters', SeIcons.lock,
            obscure: true),
        _field(_confirmPasswordController, 'confirm', 'Confirm Password',
            'Re-enter your password', SeIcons.lock,
            obscure: true, last: true),

        // ── Vehicle Information ───────────────────────────────────────────
        _sectionLabel('Vehicle information'),
        _VehiclePicker(
          types: _vehicleTypes,
          selected: _selectedVehicle,
          onSelect: (label) => setState(() => _selectedVehicle = label),
        ),
        const SizedBox(height: SeSpacing.x4),
        _field(_vehicleModelController, 'vehicleModel', 'Vehicle Make & Model',
            'Toyota Corolla', SeIcons.car),
        _field(_vehicleYearController, 'vehicleYear', 'Vehicle Year', '2018',
            SeIcons.clock,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ]),
        _field(_licencePlateController, 'licencePlate', 'Licence Plate',
            'ABC 1234', SeIcons.creditCard,
            last: true),

        // ── Documents ──────────────────────────────────────────────────────
        _sectionLabel('Documents'),
        Text(
          'Our team checks these before approving your account, and we will '
          'remind you before your licence or insurance expires.',
          style: SeType.bodyS.copyWith(color: SeColors.ink500),
        ),
        const SizedBox(height: SeSpacing.x3),
        _field(_licenceNumberController, 'licenceNumber', 'Licence Number',
            'DL-XXXXXXXX', SeIcons.badge),
        _dateField(_licenceExpiryController, 'licenceExpiry',
            'Licence Expiry Date', () => _pickExpiry('licence')),
        _docTile('licence', _licenceDoc, 'Driver\'s licence',
            'A clear photo of the front'),
        const SizedBox(height: SeSpacing.x5),
        _dateField(_insuranceExpiryController, 'insuranceExpiry',
            'Insurance Expiry Date', () => _pickExpiry('insurance')),
        _docTile('insurance', _insuranceDoc, 'Insurance',
            'Your certificate of insurance, all of it readable'),
        const SizedBox(height: SeSpacing.x5),
        _docTile('vehicle', _vehicleDoc, 'Vehicle & plate',
            'Show the whole vehicle with the plate readable'),

        // ── Service Areas ──────────────────────────────────────────────────
        const SizedBox(height: SeSpacing.x8),
        _sectionLabel('Service areas'),
        Wrap(
          spacing: SeSpacing.x2,
          runSpacing: SeSpacing.x2,
          children: [
            for (final area in _areaOptions)
              SeChip(
                label: area,
                icon: SeIcons.location,
                selected: _areas.contains(area),
                onTap: () => setState(() {
                  _areas.contains(area) ? _areas.remove(area) : _areas.add(area);
                  _errors['areas'] = null;
                }),
              ),
          ],
        ),
        _errorLine('areas'),

        // ── Payment Details ────────────────────────────────────────────────
        const SizedBox(height: SeSpacing.x8),
        _sectionLabel('Payment details'),
        Text(
          'Where we pay your earnings. Only the ShipEast team can see this.',
          style: SeType.bodyS.copyWith(color: SeColors.ink500),
        ),
        const SizedBox(height: SeSpacing.x3),
        _field(_bankNameController, 'bankName', 'Bank', 'e.g. NCB, Scotiabank',
            SeIcons.wallet),
        _field(_accountNameController, 'accountName', 'Account Holder Name',
            'Name on the account', SeIcons.userCircle),
        _field(_accountNumberController, 'accountNumber', 'Account Number',
            'Digits only', SeIcons.creditCard,
            keyboard: TextInputType.number),
        _field(_branchController, 'branch', 'Branch (optional)',
            'e.g. Morant Bay', SeIcons.location,
            last: true),

        // ── References ─────────────────────────────────────────────────────
        _sectionLabel('References'),
        Text(
          'Two people who can vouch for you — not family members.',
          style: SeType.bodyS.copyWith(color: SeColors.ink500),
        ),
        const SizedBox(height: SeSpacing.x3),
        _field(_ref1NameController, 'ref1Name', 'Reference 1 — Name',
            'Full name', SeIcons.userCircle),
        _field(_ref1PhoneController, 'ref1Phone', 'Reference 1 — Phone',
            '1-876-000-0000', SeIcons.phone,
            keyboard: TextInputType.phone),
        _field(_ref2NameController, 'ref2Name', 'Reference 2 — Name',
            'Full name', SeIcons.userCircle),
        _field(_ref2PhoneController, 'ref2Phone', 'Reference 2 — Phone',
            '1-876-000-0000', SeIcons.phone,
            keyboard: TextInputType.phone, last: true),

        // ── Agreement ──────────────────────────────────────────────────────
        _sectionLabel('Agreement'),
        GestureDetector(
          onTap: () => setState(() {
            _agreed = !_agreed;
            _errors['agreed'] = null;
          }),
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _agreed,
                activeColor: SeColors.brand,
                onChanged: (v) => setState(() {
                  _agreed = v ?? false;
                  _errors['agreed'] = null;
                }),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'I agree to the ShipEast driver terms and policies, and '
                    'confirm the information above is true.',
                    style: SeType.bodyS.copyWith(color: SeColors.ink700),
                  ),
                ),
              ),
            ],
          ),
        ),
        _errorLine('agreed'),
        const SizedBox(height: SeSpacing.x8),
        SeButton(
          label: 'Submit application',
          loading: _isLoading,
          onPressed: _isLoading ? null : _createAccount,
        ),
        const SizedBox(height: SeSpacing.x6),
        SeAuthSwitch(
          prompt: 'Already have an account?',
          action: 'Sign in',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: SeSpacing.x3),
        child: Text(text.toUpperCase(), style: SeType.eyebrow),
      );

  /// A text field plus the gap after it; [last] closes a section instead.
  Widget _field(
    TextEditingController controller,
    String key,
    String label,
    String hint,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    bool last = false,
    List<TextInputFormatter>? formatters,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: last ? SeSpacing.x8 : SeSpacing.x4),
        child: SeTextField(
          controller: controller,
          label: label,
          hint: hint,
          icon: icon,
          obscure: obscure,
          keyboardType: keyboard,
          inputFormatters: formatters,
          textInputAction: TextInputAction.next,
          errorText: _errors[key],
          onChanged: (_) => _clearError(key),
        ),
      );

  /// A read-only field that opens the date picker.
  Widget _dateField(TextEditingController controller, String key, String label,
          VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: SeSpacing.x4),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AbsorbPointer(
            child: SeTextField(
              controller: controller,
              label: label,
              hint: 'Tap to choose a date',
              icon: SeIcons.clock,
              errorText: _errors[key],
            ),
          ),
        ),
      );

  Widget _docTile(String which, File? photo, String label, String hint) =>
      SePhotoTile(
        photo: photo,
        onCapture: () => _pickDoc(which),
        emptyLabel: label,
        emptyHint: _errors['${which}Doc'] ?? hint,
        height: 150,
        errored: _errors['${which}Doc'] != null,
      );

  Widget _avatarPicker() {
    final error = _errors['avatar'];
    return GestureDetector(
      onTap: () => _pickPhoto(
        title: 'Your profile photo',
        avatar: true,
        onPicked: (f) => setState(() {
          _avatar = f;
          _errors['avatar'] = null;
        }),
      ),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: SeColors.brandSoft,
              shape: BoxShape.circle,
              border: Border.all(
                color: error != null ? SeColors.danger : SeColors.brand,
                width: 2,
              ),
              image: _avatar == null
                  ? null
                  : DecorationImage(
                      image: FileImage(_avatar!), fit: BoxFit.cover),
            ),
            child: _avatar == null
                ? const Icon(SeIcons.camera, color: SeColors.brandInk)
                : null,
          ),
          const SizedBox(width: SeSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_avatar == null ? 'Add a profile photo' : 'Change photo',
                    style: SeType.title),
                const SizedBox(height: 2),
                Text(
                  error ??
                      'A clear photo of your face — customers see it when you '
                          'deliver.',
                  style: SeType.bodyS.copyWith(
                      color: error != null ? SeColors.danger : SeColors.ink500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorLine(String key) => _errors[key] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: SeSpacing.x2),
          child: Text(_errors[key]!,
              style: SeType.bodyS.copyWith(color: SeColors.danger)),
        );
}

/// The four vehicle types, as one row of equal-width tiles.
///
/// Each tile is laid out in an `Expanded` slot and its label clamped to one
/// line: sized to its own content, "Motorcycle" is nearly twice the width of
/// "Car" and the row stops being a set of choices you can compare at a glance.
class _VehiclePicker extends StatelessWidget {
  final List<Map<String, dynamic>> types;
  final String selected;
  final ValueChanged<String> onSelect;

  const _VehiclePicker({
    required this.types,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(types.length, (i) {
          final vehicle = types[i];
          final label = vehicle['label'] as String;
          final on = selected == label;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(label),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: SeMotion.fast,
                curve: SeMotion.emphasized,
                margin:
                    EdgeInsets.only(right: i < types.length - 1 ? SeSpacing.x2 : 0),
                padding: const EdgeInsets.symmetric(
                    vertical: SeSpacing.x3, horizontal: SeSpacing.x1),
                decoration: BoxDecoration(
                  color: on ? SeColors.brandSoft : SeColors.surface0,
                  borderRadius: SeRadius.all(SeRadius.sm),
                  border: Border.all(
                    color: on ? SeColors.brand : SeColors.ink200,
                    width: on ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      vehicle['icon'] as IconData,
                      color: on ? SeColors.brandInk : SeColors.ink400,
                      size: 22,
                    ),
                    const SizedBox(height: SeSpacing.x1),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeType.eyebrow.copyWith(
                        color: on ? SeColors.brandInk : SeColors.ink500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      );
}
