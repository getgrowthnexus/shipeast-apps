import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../services/inline_image.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_button.dart';
import '../widgets/se_card.dart';
import '../widgets/se_chip.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';

/// The driver's licence and insurance, with their expiry dates — and the way
/// to replace one before or after it runs out (client checklist: "make sure
/// expired documents can be flagged in the system").
///
/// Replacing a document writes the new photo to
/// `drivers/{uid}/private/doc_{licence|insurance}` and the new expiry to
/// `drivers/{uid}.{licence|insurance}ExpiresAt`, where the admin roster flags
/// it. `documentsUpdatedAt` tells the admin there is something new to check.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  DateTime? _licenceExpiry;
  DateTime? _insuranceExpiry;
  bool _loaded = false;
  String? _saving;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (_uid.isEmpty) return;
    _sub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(_uid)
        .snapshots()
        .listen((snap) {
      final d = snap.data() ?? const {};
      if (!mounted) return;
      setState(() {
        _licenceExpiry = (d['licenceExpiresAt'] as Timestamp?)?.toDate();
        _insuranceExpiry = (d['insuranceExpiresAt'] as Timestamp?)?.toDate();
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _replace(String which) async {
    final label = which == 'licence' ? 'driver\'s licence' : 'insurance';
    final source = await showSeBottomSheet<ImageSource>(
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
            Text('New photo of your $label',
                style: SeType.h3, textAlign: TextAlign.center),
            const SizedBox(height: SeSpacing.x5),
            SeButton(
              label: 'Take Photo',
              icon: SeIcons.camera,
              onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: SeSpacing.x3),
            SeButton(
              label: 'Choose from Gallery',
              icon: SeIcons.image,
              variant: SeButtonVariant.ghost,
              onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: InlineImage.docMaxWidth,
      imageQuality: InlineImage.docQuality,
    );
    if (x == null || !mounted) return;

    final now = DateTime.now();
    final expiry = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 15),
      helpText: 'New $label expiry date',
    );
    if (expiry == null || !mounted) return;

    setState(() => _saving = which);
    try {
      await DriverFirestoreService.uploadDriverDocument(
          _uid, which, File(x.path),
          expiresAt: expiry);
      await FirebaseFirestore.instance.collection('drivers').doc(_uid).update({
        '${which}ExpiresAt': Timestamp.fromDate(expiry),
        'documentsUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        SeToast.success(context,
            'Saved. Our team will check your new $label.');
      }
    } on InlineImageTooLarge catch (e) {
      if (mounted) SeToast.error(context, e.toString());
    } catch (_) {
      if (mounted) SeToast.error(context, 'Could not save. Try again.');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: 'My documents',
      subtitle: 'Keep your licence and insurance up to date',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x5, SeSpacing.gutter, SeSpacing.x8),
        children: [
          _docCard('licence', 'Driver\'s licence', SeIcons.badge,
              _licenceExpiry),
          const SizedBox(height: SeSpacing.x4),
          _docCard('insurance', 'Insurance', SeIcons.shield, _insuranceExpiry),
        ],
      ),
    );
  }

  Widget _docCard(
      String which, String title, IconData icon, DateTime? expiresAt) {
    final state = DocExpiry.of(expiresAt);
    final (label, hue, tint) = switch (state) {
      DocState.expired => ('Expired', SeColors.danger, SeColors.dangerSoft),
      DocState.expiringSoon =>
        ('Expires soon', SeColors.warningInk, SeColors.warningSoft),
      DocState.missing => ('Not on file', SeColors.ink500, SeColors.ink100),
      DocState.valid => ('Valid', SeColors.successInk, SeColors.successSoft),
    };
    return SeCard(
      padding: const EdgeInsets.all(SeSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: SeColors.ink500),
              const SizedBox(width: SeSpacing.x3),
              Expanded(child: Text(title, style: SeType.title)),
              SeChip.status(label: label, color: hue, tint: tint),
            ],
          ),
          const SizedBox(height: SeSpacing.x2),
          Text(
            !_loaded
                ? 'Loading…'
                : expiresAt == null
                    ? 'No expiry date on file.'
                    : '${state == DocState.expired ? 'Expired' : 'Expires'} '
                        '${SeDate.long(expiresAt)}',
            style: SeType.bodyS.copyWith(color: SeColors.ink500),
          ),
          const SizedBox(height: SeSpacing.x4),
          SeButton(
            label: 'Upload a new one',
            icon: SeIcons.camera,
            variant: state == DocState.expired || state == DocState.expiringSoon
                ? SeButtonVariant.primary
                : SeButtonVariant.secondary,
            loading: _saving == which,
            onPressed: _saving != null ? null : () => _replace(which),
          ),
        ],
      ),
    );
  }
}
