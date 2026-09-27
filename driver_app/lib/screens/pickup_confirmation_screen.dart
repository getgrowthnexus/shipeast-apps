import 'package:flutter/material.dart';
import '../driver_constants.dart';
import '../services/driver_firestore_service.dart';
import '../services/phone_call.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_page.dart';
import '../widgets/se_button.dart';
import '../widgets/se_card.dart';
import '../widgets/se_step_tracker.dart';
import '../widgets/se_toast.dart';
import 'delivery_confirmation_screen.dart';

class PickupConfirmationScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> order;

  const PickupConfirmationScreen({
    super.key,
    required this.orderId,
    required this.order,
  });

  @override
  State<PickupConfirmationScreen> createState() =>
      _PickupConfirmationScreenState();
}

class _PickupConfirmationScreenState extends State<PickupConfirmationScreen> {
  bool _confirming = false;

  String get _merchantName =>
      widget.order['merchantName'] as String? ?? 'Merchant';
  String get _merchantAddress =>
      // SCHEMA.md §orders names this `merchantAddr`; this screen used to read
      // only the longer spellings, so even an order that carried a pickup
      // address showed '—' here. Read the canonical field first, mirroring
      // new_order_screen.
      widget.order['merchantAddr'] as String? ??
      widget.order['merchantAddress'] as String? ??
      widget.order['address'] as String? ??
      '—';
  String get _customerName =>
      widget.order['customerName'] as String? ?? 'Customer';
  String get _customerPhone =>
      widget.order['customerPhone'] as String? ?? '';
  String get _deliveryAddress =>
      widget.order['deliveryAddress'] as String? ?? '—';
  int get _total => (widget.order['total'] as num?)?.toInt() ?? 0;
  String get _paymentMethod =>
      widget.order['paymentMethod'] as String? ?? 'COD';
  List _getItems() => widget.order['items'] as List? ?? [];

  Future<void> _confirmPickup() async {
    setState(() => _confirming = true);
    try {
      await DriverFirestoreService.confirmPickup(widget.orderId);
      // Immediately advance to `in_transit`. Delivery can ONLY be confirmed
      // from in_transit — the confirmDelivery function rejects a
      // picked_up → delivered jump (failed-precondition), so without this the
      // order was stranded in picked_up and "Mark as Delivered" always failed.
      // It is also what makes the customer's "On the Way" tracker step
      // reachable: the driver now has the goods and is heading to them.
      await DriverFirestoreService.startTransit(widget.orderId);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DeliveryConfirmationScreen(
              orderId: widget.orderId,
              order: widget.order,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _confirming = false);
        SeToast.error(context, 'Failed to confirm pickup. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItems();

    return SePageScaffold(
      title: 'Pickup',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, SeSpacing.x2, SeSpacing.gutter, SeSpacing.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Where we are in the job ─────────────────────────────────
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: const SeStepTracker(
                current: 1,
                steps: [
                  SeStep('Order accepted', caption: 'The job is yours'),
                  SeStep('Collect from merchant',
                      caption: 'Check the items before you leave'),
                  SeStep('Deliver to customer',
                      caption: 'Capture proof on arrival'),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x4),

            _addressCard(
              icon: SeIcons.storefront,
              hue: SeColors.brand,
              tint: SeColors.brandSoft,
              eyebrow: 'PICK UP FROM',
              name: _merchantName,
              detail: _merchantAddress,
            ),
            const SizedBox(height: SeSpacing.x3),
            _addressCard(
              icon: SeIcons.locationFill,
              hue: SeColors.success,
              tint: SeColors.successTint,
              eyebrow: 'THEN DELIVER TO',
              name: _customerName,
              detail: _deliveryAddress,
            ),
            if (_customerPhone.isNotEmpty) ...[
              const SizedBox(height: SeSpacing.x3),
              SeButton(
                label: 'Call customer',
                icon: SeIcons.phone,
                variant: SeButtonVariant.ghost,
                onPressed: () =>
                    callPhone(context, _customerPhone, label: 'Customer'),
              ),
            ],
            const SizedBox(height: SeSpacing.x3),

            // ── Itemised manifest ───────────────────────────────────────
            SeCard(
              padding: const EdgeInsets.all(SeSpacing.x5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: SeColors.brandSoft,
                          borderRadius: SeRadius.all(SeRadius.xs),
                        ),
                        child: const Icon(SeIcons.box,
                            color: SeColors.brandInk, size: 18),
                      ),
                      const SizedBox(width: SeSpacing.x3),
                      Text('Check these items', style: SeType.title),
                    ],
                  ),
                  const SizedBox(height: SeSpacing.x4),
                  if (items.isEmpty)
                    Text('No items listed on this order.',
                        style: SeType.bodyS.copyWith(color: SeColors.ink500))
                  else
                    ...items.map((item) {
                      final name = (item is Map)
                          ? (item['name'] as String? ?? '—')
                          : '$item';
                      final qty =
                          (item is Map) ? (item['quantity'] as int? ?? 1) : 1;
                      final price = (item is Map)
                          ? (item['price'] as num?)?.toInt()
                          : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: SeSpacing.x3),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: SeColors.surface50,
                                borderRadius: SeRadius.all(SeRadius.xs),
                              ),
                              child: Text('$qty',
                                  style: SeType.tabular(SeType.label)
                                      .copyWith(color: SeColors.ink700)),
                            ),
                            const SizedBox(width: SeSpacing.x3),
                            Expanded(child: Text(name, style: SeType.body)),
                            if (price != null)
                              Text(
                                Money.format(price * qty),
                                style: SeType.tabular(SeType.body).copyWith(
                                    color: SeColors.ink700,
                                    fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      );
                    }),
                  const Divider(color: SeColors.ink200, height: SeSpacing.x6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Order total · $_paymentMethod',
                          style:
                              SeType.bodyS.copyWith(color: SeColors.ink500)),
                      Text(
                        Money.format(_total),
                        style: SeType.tabular(SeType.h3)
                            .copyWith(color: SeColors.ink900),
                      ),
                    ],
                  ),
                  const SizedBox(height: SeSpacing.x2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your commission',
                          style:
                              SeType.bodyS.copyWith(color: SeColors.ink500)),
                      Text(
                        Money.format(DriverPay.commissionOn(_total)),
                        style: SeType.tabular(SeType.title)
                            .copyWith(color: SeColors.success),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SeSpacing.x6),

            SeButton(
              label: 'Confirm Pickup',
              icon: SeIcons.checkCircle,
              loading: _confirming,
              onPressed: _confirming ? null : _confirmPickup,
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard({
    required IconData icon,
    required Color hue,
    required Color tint,
    required String eyebrow,
    required String name,
    required String detail,
  }) =>
      SeCard(
        padding: const EdgeInsets.all(SeSpacing.x5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, color: hue, size: 21),
            ),
            const SizedBox(width: SeSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: SeType.eyebrow),
                  const SizedBox(height: 2),
                  Text(name, style: SeType.title),
                  if (detail != '—') ...[
                    const SizedBox(height: 2),
                    Text(detail,
                        style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
