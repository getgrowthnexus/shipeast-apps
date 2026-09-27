import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_text_field.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_skeleton.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_bottom_sheet.dart';

/// Saved addresses.
///
/// A short list that is edited rarely, so it is one grouped surface with the
/// add action docked — not a stack of cards each carrying its own pair of icon
/// buttons.
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
      statusBarIconBrightness: Brightness.light,
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

  void _showAddEditSheet({Map<String, dynamic>? existing}) {
    if (_uid.isEmpty) return;
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(
        text: isEdit ? existing['label'] as String? ?? '' : '');
    final addressCtrl = TextEditingController(
        text: isEdit ? existing['text'] as String? ?? '' : '');
    const quickLabels = ['Home', 'Work', 'Mom', 'Dad', 'School', 'Other'];
    String selectedQuick = isEdit && quickLabels.contains(existing['label'])
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
              const SizedBox(height: 14),
              Text(isEdit ? 'Edit address' : 'Add an address',
                  style: SeType.h2),
              const SizedBox(height: 18),
              const SeFieldLabel('LABEL'),
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
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? SeColors.brandSoft : SeColors.surface50,
                        borderRadius: SeRadius.pill,
                        border: Border.all(
                          color: sel ? SeColors.brandAction : SeColors.ink200,
                        ),
                      ),
                      child: Text(ql,
                          style: SeType.label.copyWith(
                              color:
                                  sel ? SeColors.brandInk : SeColors.ink500)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SeTextField(
                  controller: labelCtrl,
                  hint: 'Or type your own label…',
                  icon: SeIcons.tag),
              const SizedBox(height: 16),
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
                label: isEdit ? 'Save changes' : 'Add address',
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
      title: 'Delete address',
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
    final empty = !_loading && _addresses.isEmpty;
    return SePageScaffold(
      title: 'Saved addresses',
      subtitle: _loading || empty
          ? 'Where we bring your orders'
          : '${_addresses.length} '
              '${_addresses.length == 1 ? 'address' : 'addresses'} saved',
      bottomBar: _loading || empty
          ? null
          : SeBottomBar(
              child: SeButton(
                label: 'Add another address',
                icon: SeIcons.plus,
                variant: SeButtonVariant.secondary,
                onPressed: () => _showAddEditSheet(),
              ),
            ),
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return SeShimmer(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              SeSpacing.gutter, 20, SeSpacing.gutter, 24),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => Row(
            children: const [
              SeSkeleton(width: 34, height: 34, radius: 8),
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
        child: Padding(
          padding: const EdgeInsets.all(SeSpacing.gutter),
          child: SeEmptyState(
            icon: SeIcons.addresses,
            title: 'No saved addresses',
            message: 'Save a delivery address to check out faster.',
            ctaLabel: 'Add an address',
            onCta: () => _showAddEditSheet(),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          SeSpacing.gutter, 20, SeSpacing.gutter, 24),
      children: [
        SeRowGroup(
          children: [for (final addr in _addresses) _addressRow(addr)],
        ),
      ],
    );
  }

  Widget _addressRow(Map<String, dynamic> addr) {
    final label = addr['label'] as String? ?? '';
    final text = addr['text'] as String? ?? '';
    final icon = switch (label) {
      'Home' => SeIcons.home,
      'Work' => SeIcons.box,
      _ => SeIcons.location,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: SeColors.brandAction.withValues(alpha: 0.10),
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: Icon(icon, size: 18, color: SeColors.brandAction),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: SeType.title.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(text,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // Two quiet glyphs rather than two filled buttons: editing an address
          // is housekeeping, and housekeeping should not shout.
          _iconBtn(SeIcons.edit, SeColors.ink500,
              () => _showAddEditSheet(existing: addr)),
          _iconBtn(SeIcons.trash, SeColors.danger, () => _deleteAddress(addr)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: fg),
        ),
      );
}
