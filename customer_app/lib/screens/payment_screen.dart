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
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_toast.dart';
import '../widgets/se_bottom_sheet.dart';

/// The last screen before money changes hands.
///
/// One decision (how you pay), one optional extra (a code), one figure. The
/// previous version also carried a card of three trust badges — "256-bit SSL
/// Encryption" above a cash-on-delivery option, which is both untrue and the
/// kind of claim that makes a careful person trust an app less. It is now one
/// honest line about buyer protection.
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

  /// Pre-discount total as passed from checkout. Kept for the struck-through
  /// line above the discount row; the charged figure is [_finalTotal].
  int _total = 0;
  String _deliveryAddress = '';
  // The delivery address's map pin, when it has one (live tracking).
  double? _deliveryLat;
  double? _deliveryLng;
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
      statusBarIconBrightness: Brightness.light,
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
        _deliveryLat = (args['deliveryLat'] as num?)?.toDouble();
        _deliveryLng = (args['deliveryLng'] as num?)?.toDouble();
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
        SeToast.error(
            context, result.message ?? 'That promo code is not valid.');
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

  @override
  Widget build(BuildContext context) {
    return SePageScaffold(
      title: 'Payment',
      subtitle: _merchantName.isEmpty ? null : 'Order from $_merchantName',
      bottomBar: SeBottomBar(
        child: SeButton(
          label: 'Place order · ${Money.format(_finalTotal)}',
          loading: _placingOrder,
          onPressed: _placingOrder ? null : _placeOrder,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          const SeSectionTitle(title: 'How you will pay'),
          const SizedBox(height: 10),
          _methods(),
          if (_deliveryAddress.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SeSectionTitle(title: 'Delivering to'),
            const SizedBox(height: 10),
            _addressRecap(),
          ],
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Promo code'),
          const SizedBox(height: 10),
          _promo(),
          const SizedBox(height: 22),
          _totals(),
          const SizedBox(height: 16),
          _protection(),
        ],
      ),
    );
  }

  Widget _methods() => SeRowGroup(
        children: [
          _methodRow(
            index: 1,
            icon: SeIcons.cash,
            hue: SeColors.success,
            name: 'Cash on delivery',
            sub: 'Pay the rider when your order arrives',
            onTap: () => setState(() => _selectedPayment = 1),
          ),
          // Shown, not hidden: people look for the card option and need to know
          // the answer is "not yet" rather than "you missed it".
          _methodRow(
            index: 0,
            icon: SeIcons.creditCard,
            hue: SeColors.info,
            name: 'Card / PayPal',
            sub: 'Coming soon to ShipEast',
            disabled: true,
          ),
        ],
      );

  Widget _methodRow({
    required int index,
    required IconData icon,
    required Color hue,
    required String name,
    required String sub,
    VoidCallback? onTap,
    bool disabled = false,
  }) {
    final selected = !disabled && _selectedPayment == index;
    final row = Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      color: selected ? SeColors.brandSoft : Colors.transparent,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: hue.withValues(alpha: 0.10),
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: Icon(icon, size: 20, color: hue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: SeType.title.copyWith(
                        fontSize: 15,
                        color: disabled ? SeColors.ink500 : SeColors.ink900)),
                const SizedBox(height: 2),
                Text(sub,
                    style: SeType.bodyS.copyWith(color: SeColors.ink400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (disabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: SeColors.ink100,
                borderRadius: SeRadius.pill,
              ),
              child: Text('Soon',
                  style: SeType.eyebrow.copyWith(color: SeColors.ink500)),
            )
          else
            // A filled circle rather than a Material Radio: the whole row is
            // the target, and a stock radio invites people to aim at the 20dp
            // circle instead.
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
                            color: SeColors.brandAction, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
    if (disabled) return Opacity(opacity: 0.6, child: row);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }

  Widget _addressRecap() => SePanel(
        child: Row(
          children: [
            const Icon(SeIcons.location, size: 18, color: SeColors.brandAction),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_deliveryAddress,
                  style: SeType.bodyS.copyWith(color: SeColors.ink700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _promo() {
    final applied = _promoApplied;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: applied ? SeColors.successSoft : SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.md),
              border: Border.all(
                  color: applied ? SeColors.success : SeColors.ink200),
            ),
            child: Row(
              children: [
                Icon(SeIcons.tag,
                    size: 17,
                    color: applied ? SeColors.success : SeColors.ink400),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _promoController,
                    enabled: !applied,
                    textCapitalization: TextCapitalization.characters,
                    style: SeType.body.copyWith(color: SeColors.ink900),
                    cursorColor: SeColors.brandAction,
                    decoration: InputDecoration(
                      hintText:
                          applied ? '$_appliedCode applied' : 'Have a code?',
                      hintStyle: SeType.body.copyWith(
                          color:
                              applied ? SeColors.successInk : SeColors.ink400),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SeButton(
          label: applied ? 'Remove' : 'Apply',
          variant:
              applied ? SeButtonVariant.ghost : SeButtonVariant.secondary,
          size: SeButtonSize.medium,
          expand: false,
          loading: _validatingPromo,
          onPressed: applied
              ? () => setState(() {
                    _promoApplied = false;
                    _discount = 0;
                    _appliedCode = null;
                    _promoController.clear();
                  })
              : (_validatingPromo ? null : _applyPromo),
        ),
      ],
    );
  }

  Widget _totals() => SePanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SeMoneyLine(label: 'Items', value: Money.format(_subtotal)),
            SeMoneyLine(
                label: 'Delivery fee', value: Money.deliveryFee(_deliveryFee)),
            SeMoneyLine(
                label: 'Service fee', value: Money.format(_serviceFee)),
            if (_discount > 0)
              SeMoneyLine(
                label: 'Promo ${_appliedCode ?? ''}'.trim(),
                value: '− ${Money.format(_discount)}',
                valueColor: SeColors.success,
              ),
            const Divider(height: 20, color: SeColors.ink200),
            SeMoneyLine(
                label: 'Total to pay',
                value: Money.format(_finalTotal),
                strong: true),
            if (_discount > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('was ${Money.format(_total)}',
                      style: SeType.tabular(SeType.bodyS).copyWith(
                          color: SeColors.ink400,
                          decoration: TextDecoration.lineThrough)),
                ],
              ),
            ],
          ],
        ),
      );

  /// One line, not a badge wall. It says the only thing that is actually true
  /// of a cash order: if it does not arrive, we handle it.
  Widget _protection() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(SeIcons.shield, size: 15, color: SeColors.ink400),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Covered by ShipEast buyer protection',
              style: SeType.bodyS.copyWith(color: SeColors.ink400),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );

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
            const SizedBox(height: 18),
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: SeColors.brandSoft,
                  borderRadius: SeRadius.all(SeRadius.lg),
                ),
                child: const Icon(SeIcons.bike,
                    size: 30, color: SeColors.brandAction),
              ),
            ),
            const SizedBox(height: 16),
            Text('Place this order?',
                style: SeType.h2, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _merchantName.isEmpty
                  ? '${Money.format(_finalTotal)}, cash on delivery.'
                  : '$_merchantName · ${Money.format(_finalTotal)}, cash on delivery.',
              textAlign: TextAlign.center,
              style: SeType.body.copyWith(color: SeColors.ink500, height: 1.45),
            ),
            if (_deliveryAddress.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_deliveryAddress,
                  textAlign: TextAlign.center,
                  style: SeType.bodyS.copyWith(color: SeColors.ink400)),
            ],
            const SizedBox(height: 22),
            SeButton(
              label: 'Place order',
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            SeButton(
              label: 'Not yet',
              variant: SeButtonVariant.ghost,
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    return res ?? false;
  }

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
          deliveryLat: _deliveryLat,
          deliveryLng: _deliveryLng,
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
}
