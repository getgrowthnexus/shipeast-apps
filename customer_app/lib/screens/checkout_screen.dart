import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';
import 'saved_addresses_screen.dart';

/// Checkout: where it goes, and what it comes to.
///
/// Two decisions and one confirmation, in that order. The address list is a
/// real choice so it comes first; the summary below it is a receipt, not a
/// control. The action is docked, because on a long order the button used to
/// end up below the fold on the one screen where hesitation costs an order.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _selectedAddress = 0;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _addrSub;

  Map<String, dynamic> _orderArgs = {};
  bool _argsLoaded = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _subscribeAddresses();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) _orderArgs = Map<String, dynamic>.from(args);
    }
  }

  void _subscribeAddresses() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _addresses = [];
        _loading = false;
      });
      return;
    }
    _addrSub = FirestoreService.addressStream(uid).listen((addrs) {
      if (mounted) {
        setState(() {
          _addresses = addrs;
          if (_selectedAddress >= _addresses.length) _selectedAddress = 0;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _addrSub?.cancel();
    super.dispose();
  }

  String get selectedAddressText {
    if (_addresses.isEmpty || _selectedAddress >= _addresses.length) return '';
    return _addresses[_selectedAddress]['text'] as String? ?? '';
  }

  void _openAddresses() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const SavedAddressesScreen()));

  @override
  Widget build(BuildContext context) {
    final total = _orderArgs['total'] as int? ?? 0;
    return SePageScaffold(
      title: 'Checkout',
      subtitle: _orderArgs['merchantName'] as String?,
      bottomBar: _loading
          ? null
          : SeBottomBar(
              child: SeButton(
                label: 'Choose payment · ${Money.format(total)}',
                onPressed: () {
                  if (_addresses.isEmpty) {
                    SeToast.error(
                        context, 'Please add a delivery address first');
                    return;
                  }
                  Navigator.pushNamed(context, '/payment', arguments: {
                    ..._orderArgs,
                    'deliveryAddress': selectedAddressText,
                  });
                },
              ),
            ),
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: SeColors.brandAction))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  SeSpacing.gutter, 20, SeSpacing.gutter, 24),
              children: [
                SeSectionTitle(
                  title: 'Deliver to',
                  actionLabel: _addresses.isEmpty ? null : 'Manage',
                  onAction: _addresses.isEmpty ? null : _openAddresses,
                ),
                const SizedBox(height: 10),
                if (_addresses.isEmpty) _noAddress() else _addressList(),
                const SizedBox(height: 22),
                const SeSectionTitle(title: 'Order summary'),
                const SizedBox(height: 10),
                _summary(),
              ],
            ),
    );
  }

  Widget _noAddress() => SePanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(SeIcons.locationLine, size: 30, color: SeColors.ink300),
            const SizedBox(height: 10),
            Text('No addresses saved',
                style: SeType.body.copyWith(color: SeColors.ink500)),
            const SizedBox(height: 4),
            Text('We need somewhere to bring this.',
                style: SeType.bodyS.copyWith(color: SeColors.ink400)),
            const SizedBox(height: 14),
            SeButton(
              label: 'Add an address',
              icon: SeIcons.plus,
              variant: SeButtonVariant.secondary,
              size: SeButtonSize.medium,
              expand: false,
              onPressed: _openAddresses,
            ),
          ],
        ),
      );

  Widget _addressList() => SeRowGroup(
        children: [
          for (var i = 0; i < _addresses.length; i++)
            _addressRow(i, _addresses[i]),
        ],
      );

  Widget _addressRow(int i, Map<String, dynamic> addr) {
    final selected = _selectedAddress == i;
    final label = addr['label'] as String? ?? '';
    final icon = switch (label) {
      'Home' => SeIcons.home,
      'Work' => SeIcons.box,
      _ => SeIcons.location,
    };
    return GestureDetector(
      onTap: () => setState(() => _selectedAddress = i),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        color: selected ? SeColors.brandSoft : Colors.transparent,
        child: Row(
          children: [
            // A filled circle, not a Material Radio: the whole row is the
            // target, and a stock radio next to dead text invites people to aim
            // at the 20dp circle instead.
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? SeColors.brandAction : SeColors.ink300,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: SeColors.brandAction,
                            shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon,
                          size: 13,
                          color:
                              selected ? SeColors.brandInk : SeColors.ink400),
                      const SizedBox(width: 5),
                      Text(label,
                          style: SeType.label.copyWith(
                              color: selected
                                  ? SeColors.brandInk
                                  : SeColors.ink500)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(addr['text'] as String? ?? '',
                      style: SeType.bodyS.copyWith(color: SeColors.ink700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final rawItems = _orderArgs['items'] as List? ?? [];
    final items =
        rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final deliveryFee = _orderArgs['deliveryFee'] as int? ?? 0;
    final serviceFee = _orderArgs['serviceFee'] as int? ?? 0;
    final total = _orderArgs['total'] as int? ?? 0;

    return SePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final item in items)
            SeMoneyLine(
              label: '${item['name'] ?? ''} × ${item['quantity'] ?? 1}',
              value: Money.format(
                  (item['price'] as int? ?? 0) * (item['quantity'] as int? ?? 1)),
            ),
          const Divider(height: 18, color: SeColors.ink100),
          SeMoneyLine(
              label: 'Delivery fee', value: Money.deliveryFee(deliveryFee)),
          SeMoneyLine(
              label: 'Service fee (10%)', value: Money.format(serviceFee)),
          const Divider(height: 18, color: SeColors.ink200),
          SeMoneyLine(
              label: 'Total', value: Money.format(total), strong: true),
        ],
      ),
    );
  }
}
