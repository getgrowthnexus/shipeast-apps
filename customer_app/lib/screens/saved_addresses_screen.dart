import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_bottom_sheet.dart';

class SavedAddressesScreen extends StatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    if (_uid.isNotEmpty) {
      _sub = FirestoreService.addressStream(_uid).listen((addrs) {
        if (mounted) {
          setState(() {
            _addresses = addrs;
            _loading = false;
          });
        }
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _showAddEditDialog({Map<String, dynamic>? existing}) {
    if (_uid.isEmpty) return;
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(
        text: isEdit ? existing['label'] as String? ?? '' : '');
    final addressCtrl = TextEditingController(
        text: isEdit ? existing['text'] as String? ?? '' : '');
    const quickLabels = ['Home', 'Work', 'Mom', 'Dad', 'School', 'Other'];
    String selectedQuick =
        isEdit && quickLabels.contains(existing['label'])
            ? existing['label'] as String
            : '';

    showSeBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
              Text(isEdit ? 'Edit Address' : 'Add New Address',
                  style: SeType.h2),
              const SizedBox(height: 16),
              Text('LABEL', style: SeType.eyebrow),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: quickLabels.map((ql) {
                  final sel = selectedQuick == ql;
                  return GestureDetector(
                    onTap: () {
                      setModalState(() => selectedQuick = ql);
                      labelCtrl.text = ql;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? SeColors.red50 : SeColors.surface50,
                        borderRadius: SeRadius.pill,
                        border: Border.all(
                          color: sel ? SeColors.red500 : SeColors.ink200,
                          width: 1.5,
                        ),
                      ),
                      child: Text(ql,
                          style: SeType.label.copyWith(
                              color:
                                  sel ? SeColors.red700 : SeColors.ink500,
                              fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SeTextField(
                  controller: labelCtrl,
                  hint: 'Or type a custom label...',
                  icon: SeIcons.tag),
              const SizedBox(height: 14),
              SeTextField(
                controller: addressCtrl,
                label: 'ADDRESS',
                hint: 'e.g. 14 Yallahs Main Road, St. Thomas',
                icon: SeIcons.location,
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SeButton(
                label: isEdit ? 'Save Changes' : 'Add Address',
                icon: SeIcons.check,
                onPressed: () async {
                  final label = labelCtrl.text.trim();
                  final text = addressCtrl.text.trim();
                  if (label.isEmpty || text.isEmpty) {
                    SeToast.error(ctx, 'Please fill in both fields');
                    return;
                  }
                  Navigator.pop(ctx);
                  if (isEdit) {
                    await FirestoreService.updateAddress(
                        _uid, existing['id'] as String, label, text);
                  } else {
                    await FirestoreService.addAddress(_uid, label, text);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAddress(Map<String, dynamic> addr) async {
    if (_uid.isEmpty) return;
    final confirm = await SeConfirmSheet.show(
      context,
      title: 'Delete Address',
      message: 'Remove "${addr['label']}" from your saved addresses?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirm) {
      await FirestoreService.deleteAddress(_uid, addr['id'] as String);
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
            Expanded(child: _buildBody()),
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
            Expanded(child: Text('Saved Addresses', style: SeType.h3)),
            GestureDetector(
              onTap: () => _showAddEditDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    gradient: SeColors.emberGradient,
                    borderRadius: SeRadius.pill,
                    boxShadow: SeElevation.glow),
                child: Row(
                  children: [
                    const Icon(SeIcons.plus, size: 15, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Add',
                        style: SeType.label.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildBody() {
    if (_loading) {
      return SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => Row(
            children: const [
              SeSkeleton(width: 42, height: 42, radius: 11),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeSkeleton(width: 80, height: 12, radius: 5),
                    SizedBox(height: 8),
                    SeSkeleton(width: 200, height: 10, radius: 5),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_addresses.isEmpty) {
      return Center(
        child: SeEmptyState(
          icon: SeIcons.addresses,
          title: 'No saved addresses',
          message: 'Save a delivery address to check out faster.',
          ctaLabel: 'Add New Address',
          onCta: () => _showAddEditDialog(),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(SeSpacing.gutter),
      itemCount: _addresses.length,
      separatorBuilder: (ctx, idx) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildAddressCard(_addresses[i]),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> addr) {
    final label = addr['label'] as String? ?? '';
    final text = addr['text'] as String? ?? '';
    final iconData = label == 'Home'
        ? SeIcons.home
        : label == 'Work'
            ? SeIcons.box
            : SeIcons.location;

    return SeCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SeColors.red50,
              borderRadius: SeRadius.all(SeRadius.sm),
            ),
            child: Icon(iconData, size: 20, color: SeColors.red500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SeType.title),
                const SizedBox(height: 3),
                Text(text,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
          _iconBtn(SeIcons.edit, SeColors.surface50, SeColors.ink700,
              () => _showAddEditDialog(existing: addr)),
          const SizedBox(width: 8),
          _iconBtn(SeIcons.trash, SeColors.dangerTint, SeColors.danger,
              () => _deleteAddress(addr)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration:
              BoxDecoration(color: bg, borderRadius: SeRadius.all(SeRadius.sm)),
          child: Icon(icon, size: 17, color: fg),
        ),
      );
}
