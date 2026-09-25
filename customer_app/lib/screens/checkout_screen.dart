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
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_toast.dart';
import 'saved_addresses_screen.dart';

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
      statusBarIconBrightness: Brightness.dark,
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: SeColors.red500))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(SeSpacing.gutter),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildAddressCard(),
                          const SizedBox(height: 14),
                          _buildOrderSummaryCard(),
                          const SizedBox(height: 20),
                          _buildChoosePaymentButton(),
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
            Text('Checkout', style: SeType.h2),
          ],
        ),
      );

  Widget _buildAddressCard() => SeCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _coHead('Delivery Address',
                actionLabel: 'Manage',
                onAction: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SavedAddressesScreen()))),
            if (_addresses.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(SeIcons.locationLine,
                        size: 32, color: SeColors.ink300),
                    const SizedBox(height: 10),
                    Text('No addresses saved',
                        style:
                            SeType.body.copyWith(color: SeColors.ink500)),
                    const SizedBox(height: 10),
                    SeButton(
                      label: 'Add New Address',
                      icon: SeIcons.plus,
                      variant: SeButtonVariant.secondary,
                      size: SeButtonSize.small,
                      expand: false,
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SavedAddressesScreen())),
                    ),
                  ],
                ),
              )
            else
              ..._addresses.asMap().entries.map((e) {
                final i = e.key;
                final addr = e.value;
                final selected = _selectedAddress == i;
                final isLast = i == _addresses.length - 1;
                final label = addr['label'] as String? ?? '';
                final iconData = label == 'Home'
                    ? SeIcons.home
                    : label == 'Work'
                        ? SeIcons.box
                        : SeIcons.location;
                return GestureDetector(
                  onTap: () => setState(() => _selectedAddress = i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? SeColors.red50 : Colors.transparent,
                      border: isLast
                          ? null
                          : const Border(
                              bottom:
                                  BorderSide(color: SeColors.ink100)),
                    ),
                    child: Row(
                      children: [
                        _radio(selected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(iconData,
                                      size: 14,
                                      color: selected
                                          ? SeColors.red500
                                          : SeColors.ink400),
                                  const SizedBox(width: 5),
                                  Text(label,
                                      style: SeType.label.copyWith(
                                          color: selected
                                              ? SeColors.red700
                                              : SeColors.ink500)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(addr['text'] as String? ?? '',
                                  style: SeType.bodyS
                                      .copyWith(color: SeColors.ink700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      );

  Widget _radio(bool selected) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? SeColors.red500 : SeColors.ink300,
            width: 2,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: SeColors.red500, shape: BoxShape.circle),
                ),
              )
            : null,
      );

  Widget _buildOrderSummaryCard() {
    final rawItems = _orderArgs['items'] as List? ?? [];
    final items =
        rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final deliveryFee = _orderArgs['deliveryFee'] as int? ?? 0;
    final serviceFee = _orderArgs['serviceFee'] as int? ?? 0;
    final total = _orderArgs['total'] as int? ?? 0;

    return SeCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _coHead('Order Summary'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                ...items.map((item) {
                  final name = item['name'] as String? ?? '';
                  final qty = item['quantity'] as int? ?? 1;
                  final price = item['price'] as int? ?? 0;
                  return _summaryLine(
                      '$name × $qty', Money.format(price * qty));
                }),
                _summaryLine('Delivery fee', Money.deliveryFee(deliveryFee)),
                _summaryLine(
                    'Service fee (10%)', Money.format(serviceFee)),
                const SizedBox(height: 4),
                const Divider(height: 1, color: SeColors.ink100),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: SeType.h3),
                    Text(Money.format(total),
                        style: SeType.tabular(SeType.h3)
                            .copyWith(color: SeColors.red600)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: SeType.body.copyWith(color: SeColors.ink500)),
            ),
            const SizedBox(width: 12),
            Text(value,
                style:
                    SeType.tabular(SeType.body).copyWith(color: SeColors.ink700)),
          ],
        ),
      );

  Widget _buildChoosePaymentButton() => SeButton(
        label: 'Choose Payment',
        icon: SeIcons.arrowRight,
        onPressed: () {
          if (_addresses.isEmpty) {
            SeToast.error(context, 'Please add a delivery address first');
            return;
          }
          Navigator.pushNamed(context, '/payment', arguments: {
            ..._orderArgs,
            'deliveryAddress': selectedAddressText,
          });
        },
      );

  Widget _coHead(String title, {String? actionLabel, VoidCallback? onAction}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SeColors.ink100)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: SeType.title),
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Row(
                  children: [
                    const Icon(SeIcons.edit, size: 14, color: SeColors.red500),
                    const SizedBox(width: 4),
                    Text(actionLabel,
                        style: SeType.label.copyWith(color: SeColors.red500)),
                  ],
                ),
              ),
          ],
        ),
      );
}
