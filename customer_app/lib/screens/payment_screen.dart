import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../services/notification_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../services/firestore_service.dart';
import '../utils/money.dart';
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int _selectedPayment = 1; // 0 = PayPal (disabled), 1 = COD
  final _promoController = TextEditingController();
  bool _promoApplied = false;
  bool _validatingPromo = false;
  bool _placingOrder = false;
  int _discount = 0;
  String? _appliedCode;

  String _merchantId = '';
  String _merchantName = '';
  List<Map<String, dynamic>> _items = [];
  int _subtotal = 0;
  int _deliveryFee = 0;
  int _serviceFee = 0;
  /// Pre-discount total as passed from checkout. Kept for the "Order total"
  /// line above the discount row; the charged figure is [_finalTotal].
  int _total = 0;
  String _deliveryAddress = '';
  bool _argsLoaded = false;

  /// Derived from the components, not from the passed-in `_total`, so what is
  /// displayed and what is charged cannot drift apart (P3-02).
  int get _gross => _subtotal + _deliveryFee + _serviceFee;
  int get _finalTotal => (_gross - _discount).clamp(0, _gross);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _merchantId = args['merchantId'] as String? ?? '';
        _merchantName = args['merchantName'] as String? ?? '';
        _items = (args['items'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        _subtotal = args['subtotal'] as int? ?? 0;
        _deliveryFee = args['deliveryFee'] as int? ?? 0;
        _serviceFee = args['serviceFee'] as int? ?? 0;
        _total = args['total'] as int? ?? 0;
        _deliveryAddress = args['deliveryAddress'] as String? ?? '';
      }
    }
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    setState(() => _validatingPromo = true);
    try {
      // A preview only. The discount that reaches the order is whatever
      // redeemPromo returns at placement (P3-03). PR-5: pass along what this
      // checkout already knows — merchant and delivery area — so a code
      // scoped to a specific merchant or area previews as ineligible here
      // rather than only failing at Place Order.
      final result = await FirestoreService.previewPromoCode(
        code,
        _subtotal,
        merchantId: _merchantId.isEmpty ? null : _merchantId,
        deliveryArea: _deliveryAddress.isEmpty ? null : _deliveryAddress,
        deliveryFee: _deliveryFee,
      );
      if (!mounted) return;
      if (!result.isValid) {
        setState(() {
          _discount = 0;
          _promoApplied = false;
          _appliedCode = null;
          _validatingPromo = false;
        });
        // Say WHY. "Invalid or expired" for an under-minimum order sends the
        // customer looking for a new code instead of adding one more item.
        SeToast.error(context, result.message ?? 'That promo code is not valid.');
        return;
      }
      setState(() {
        _discount = result.discount;
        _promoApplied = true;
        _appliedCode = code.toUpperCase();
        _validatingPromo = false;
      });
      SeToast.success(
          context, 'Promo applied! You saved ${Money.format(result.discount)}');
    } catch (_) {
      if (mounted) {
        setState(() => _validatingPromo = false);
        SeToast.error(context, 'Error validating promo code');
      }
    }
  }

  Future<bool> _showOrderConfirmation() async {
    final res = await showSeBottomSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: SeSpacing.gutter,
          right: SeSpacing.gutter,
          top: 4,
          bottom: MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SeSheetHandle(),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: SeColors.sunsetGradient,
                  borderRadius: SeRadius.all(SeRadius.lg),
                  boxShadow: SeElevation.glow,
                ),
                child: const Icon(SeIcons.orders, size: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text('Confirm Your Order',
                style: SeType.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'You are placing an order from $_merchantName for ${Money.format(_finalTotal)}.',
              textAlign: TextAlign.center,
              style: SeType.body.copyWith(color: SeColors.ink500),
            ),
            if (_deliveryAddress.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Delivering to: $_deliveryAddress',
                  textAlign: TextAlign.center,
                  style: SeType.bodyS.copyWith(color: SeColors.ink400)),
            ],
            const SizedBox(height: 22),
            SeButton(
              label: 'Place Order',
              icon: SeIcons.check,
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 10),
            SeButton(
              label: 'Cancel',
              variant: SeButtonVariant.ghost,
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    return res ?? false;
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SeSpacing.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPaymentCard(),
                    const SizedBox(height: 14),
                    _buildSecurityCard(),
                    const SizedBox(height: 14),
                    _buildPromoCard(),
                    const SizedBox(height: 14),
                    _buildTotalCard(),
                    const SizedBox(height: 20),
                    _buildPlaceOrderButton(),
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
            Text('Payment Method', style: SeType.h2),
          ],
        ),
      );

  Widget _buildPaymentCard() => SeCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _coHead('Select Payment'),
            Opacity(
              opacity: 0.45,
              child: IgnorePointer(
                child: _paymentRow(
                  index: 0,
                  icon: _paypalLogo(),
                  name: 'PayPal',
                  sub: 'Pay securely via PayPal',
                  iconBg: const Color(0xFFF0F4FF),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: SeColors.ink400,
                        borderRadius: SeRadius.all(SeRadius.xs)),
                    child: Text('Soon',
                        style: SeType.inter(9, FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _selectedPayment = 1),
              behavior: HitTestBehavior.opaque,
              child: _paymentRow(
                index: 1,
                icon: const Icon(SeIcons.cash,
                    size: 24, color: SeColors.success),
                name: 'Cash on Delivery',
                sub: 'Pay when your order arrives',
                iconBg: SeColors.successTint,
                isLast: true,
              ),
            ),
          ],
        ),
      );

  Widget _paymentRow({
    required int index,
    required Widget icon,
    required String name,
    required String sub,
    required Color iconBg,
    bool isLast = false,
    Widget? trailing,
  }) {
    final selected = _selectedPayment == index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? SeColors.red50 : Colors.transparent,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: SeColors.ink100)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: SeRadius.all(SeRadius.sm)),
            child: Center(child: icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: SeType.title),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(sub,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
          Container(
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
          ),
        ],
      ),
    );
  }

  Widget _paypalLogo() => RichText(
        text: TextSpan(
          style: SeType.jakarta(15, FontWeight.w800),
          children: const [
            TextSpan(text: 'Pay', style: TextStyle(color: Color(0xFF003087))),
            TextSpan(text: 'Pal', style: TextStyle(color: Color(0xFF009CDE))),
          ],
        ),
      );

  Widget _buildSecurityCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your payment is protected', style: SeType.title),
            const SizedBox(height: 12),
            _securityRow(SeIcons.shield, SeColors.success,
                '256-bit SSL Encryption'),
            const SizedBox(height: 10),
            _securityRow(SeIcons.lock, SeColors.ocean500,
                '100% Secure Payment'),
            const SizedBox(height: 10),
            _securityRow(SeIcons.checkCircle, SeColors.red500,
                'ShipEast Buyer Protection'),
          ],
        ),
      );

  Widget _securityRow(IconData icon, Color color, String label) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: SeType.body.copyWith(color: SeColors.ink500)),
        ],
      );

  Widget _buildPromoCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(SeIcons.tag, size: 16, color: SeColors.gold500),
                const SizedBox(width: 8),
                Text('Promo Code', style: SeType.title),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: _promoApplied
                          ? SeColors.successTint
                          : SeColors.surface50,
                      borderRadius: SeRadius.inputRadius,
                      border: Border.all(
                          color: _promoApplied
                              ? SeColors.success
                              : SeColors.ink200,
                          width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promoController,
                            enabled: !_promoApplied,
                            textCapitalization:
                                TextCapitalization.characters,
                            style:
                                SeType.body.copyWith(color: SeColors.ink900),
                            cursorColor: SeColors.red500,
                            decoration: InputDecoration(
                              hintText: _promoApplied
                                  ? 'Promo applied!'
                                  : 'Enter promo code...',
                              hintStyle: SeType.body.copyWith(
                                  color: _promoApplied
                                      ? SeColors.success
                                      : SeColors.ink400),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                        if (_promoApplied)
                          const Icon(SeIcons.checkCircle,
                              size: 20, color: SeColors.success),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _promoApplied
                      ? () => setState(() {
                            _promoApplied = false;
                            _discount = 0;
                            _promoController.clear();
                          })
                      : _validatingPromo
                          ? null
                          : _applyPromo,
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _promoApplied ? null : SeColors.emberGradient,
                      color: _promoApplied ? SeColors.ink100 : null,
                      borderRadius: SeRadius.all(SeRadius.sm),
                    ),
                    child: _validatingPromo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.2))
                        : Text(_promoApplied ? 'Remove' : 'Apply',
                            style: SeType.jakarta(14, FontWeight.w700,
                                color: _promoApplied
                                    ? SeColors.ink700
                                    : Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildTotalCard() => SeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_discount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Original Total',
                      style: SeType.body.copyWith(color: SeColors.ink400)),
                  Text(Money.format(_total),
                      style: SeType.tabular(SeType.body).copyWith(
                          color: SeColors.ink400,
                          decoration: TextDecoration.lineThrough)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(SeIcons.tag,
                          size: 14, color: SeColors.success),
                      const SizedBox(width: 5),
                      Text('Promo Discount',
                          style:
                              SeType.body.copyWith(color: SeColors.success)),
                    ],
                  ),
                  Text('- ${Money.format(_discount)}',
                      style: SeType.tabular(SeType.body)
                          .copyWith(color: SeColors.success)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: SeColors.ink100),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total to Pay', style: SeType.h3),
                Text(Money.format(_finalTotal),
                    style: SeType.tabular(SeType.h3)
                        .copyWith(color: SeColors.red600)),
              ],
            ),
          ],
        ),
      );

  Widget _buildPlaceOrderButton() => SeButton(
        label: 'Place Order · ${Money.format(_finalTotal)}',
        icon: SeIcons.lock,
        loading: _placingOrder,
        onPressed: _placingOrder ? null : _placeOrder,
      );

  Future<void> _placeOrder() async {
    if (_placingOrder) return;

    final confirmed = await _showOrderConfirmation();
    if (!confirmed) return;

    setState(() => _placingOrder = true);

    /* Redeem BEFORE writing the order, and use what the server returns.
       The preview shown above is advisory: between typing the code and tapping
       Place Order it may have expired or been exhausted by someone else. This
       is also the only thing that increments `usedCount`, which is what makes
       the usage cap real rather than advisory (P3-03). */
    var discount = 0;
    var promoCode = _appliedCode;
    if (promoCode != null) {
      try {
        discount = await FirestoreService.redeemPromo(
          promoCode,
          _subtotal,
          merchantId: _merchantId.isEmpty ? null : _merchantId,
          deliveryAddress: _deliveryAddress.isEmpty ? null : _deliveryAddress,
          deliveryFee: _deliveryFee,
        );
      } catch (e) {
        if (!mounted) return;
        // The order still goes through at full price — refusing to sell
        // because a coupon lapsed is worse than the lost discount.
        setState(() {
          _discount = 0;
          _promoApplied = false;
          _appliedCode = null;
        });
        discount = 0;
        promoCode = null;
        SeToast.info(context,
            'That promo code could no longer be applied — placing your order at full price.');
      }
    }

    final total = (_subtotal + _deliveryFee + _serviceFee - discount)
        .clamp(0, _subtotal + _deliveryFee + _serviceFee);

    try {
      final paymentMethod =
          _selectedPayment == 0 ? 'PayPal' : 'Cash on Delivery';
      String orderId;
      if (_merchantId.isNotEmpty && _items.isNotEmpty) {
        orderId = await FirestoreService.placeOrder(
          merchantId: _merchantId,
          merchantName: _merchantName,
          items: _items,
          subtotal: _subtotal,
          deliveryFee: _deliveryFee,
          serviceFee: _serviceFee,
          discount: discount,
          promoCode: promoCode,
          total: total,
          paymentMethod: paymentMethod,
          deliveryAddress: _deliveryAddress,
        );
      } else {
        orderId = '';
      }
      // The one permission prompt, spent here (P4-03). The order exists, so
      // "we'll tell you when your driver is on the way" is an offer rather
      // than an interruption from an app the customer has not used yet.
      // Deliberately not awaited: the confirmation screen must not wait on a
      // system dialog, and the result changes nothing about this order.
      unawaited(NotificationService.maybeRequestAfterOrder());
      if (!mounted) return;
      Provider.of<CartProvider>(context, listen: false).clearCart();
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/order-confirmed',
        (route) => route.settings.name == '/home',
        arguments: {
          'orderId': orderId,
          'merchantName': _merchantName,
          'items': _items,
          'subtotal': _subtotal,
          'deliveryFee': _deliveryFee,
          'serviceFee': _serviceFee,
          'discount': discount,
          'total': total,
          'deliveryAddress': _deliveryAddress,
          'paymentMethod': paymentMethod,
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _placingOrder = false);
        SeToast.error(context, 'Could not place order. Please try again.');
      }
    }
  }

  Widget _coHead(String title) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SeColors.ink100)),
        ),
        child: Text(title, style: SeType.title),
      );
}
