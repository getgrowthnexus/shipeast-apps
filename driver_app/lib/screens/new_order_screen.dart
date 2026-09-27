import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../driver_constants.dart';
import '../models/order_type.dart';
import '../services/driver_firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../widgets/se_button.dart';
import '../widgets/se_countdown_ring.dart';
import '../widgets/se_empty_state.dart';
import '../widgets/se_toast.dart';
import 'pickup_confirmation_screen.dart';

/// Incoming-order screen — the highest-urgency surface in the app.
///
/// Rendered full-bleed on the Sunset gradient so it is unmistakable when it
/// interrupts the driver, with the countdown as the visual anchor.
class NewOrderScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  /// Straight-line distance from the driver to the pickup, in metres, when the
  /// dashboard could compute it. Null when the driver's location or the order's
  /// pickup coordinates are unknown, in which case no distance is shown.
  final double? pickupDistanceMeters;

  const NewOrderScreen({
    super.key,
    required this.order,
    this.pickupDistanceMeters,
  });

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  static const int _window = 60;

  int _remainingSeconds = _window;
  Timer? _timer;
  bool _expired = false;
  bool _accepting = false;

  String get _orderId => widget.order['id'] as String? ?? '';
  bool get _isPackage => OrderType.isPackage(widget.order['type']);
  String get _merchantName =>
      widget.order['merchantName'] as String? ?? 'Merchant';
  String get _customerName =>
      widget.order['customerName'] as String? ?? 'Customer';
  String get _deliveryAddress =>
      widget.order['deliveryAddress'] as String? ?? '—';
  String get _merchantAddress =>
      // SCHEMA.md §orders names this `merchantAddr`; only this reader used the
      // longer spelling, so a pickup address written by the customer app
      // resolved to '—' and the driver had no address to navigate to.
      widget.order['merchantAddr'] as String? ??
      widget.order['merchantAddress'] as String? ??
      widget.order['address'] as String? ??
      '—';
  int get _total => (widget.order['total'] as num?)?.toInt() ?? 0;
  String get _paymentMethod =>
      widget.order['paymentMethod'] as String? ?? 'COD';
  List _getItems() => widget.order['items'] as List? ?? [];

  /// A short "how far to collect" label, or null when the distance is unknown.
  String? get _pickupDistanceLabel {
    final m = widget.pickupDistanceMeters;
    if (m == null) return null;
    return m < 950 ? '${m.round()} m away' : '${(m / 1000).toStringAsFixed(1)} km away';
  }

  String get _shortId => _orderId.length > 8
      ? _orderId.substring(0, 8).toUpperCase()
      : _orderId.toUpperCase();

  @override
  void initState() {
    super.initState();
    // A job landing deserves a physical cue, not just a screen swap.
    HapticFeedback.heavyImpact();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
          // Tick harder over the last ten seconds.
          if (_remainingSeconds <= 10) HapticFeedback.selectionClick();
        } else {
          _expired = true;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _acceptOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _orderId.isEmpty) return;
    setState(() => _accepting = true);
    try {
      await DriverFirestoreService.acceptOrder(_orderId, uid);
      HapticFeedback.mediumImpact();
      _timer?.cancel();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PickupConfirmationScreen(
              orderId: _orderId,
              order: widget.order,
            ),
          ),
        );
      }
    } on StateError catch (e) {
      // Another driver claimed it first — say so plainly instead of a generic
      // failure, and close the screen since the job is gone.
      if (!mounted) return;
      setState(() => _accepting = false);
      if (e.message == DriverFirestoreService.orderTakenCode) {
        SeToast.info(context, 'Another driver took this order.');
        _timer?.cancel();
        Navigator.pop(context);
      } else {
        SeToast.error(context, 'Failed to accept order. Try again.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _accepting = false);
      SeToast.error(context, 'Failed to accept order. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_expired) return _expiredView();

    // The one screen that is deliberately NOT the calm shell red. An incoming
    // job is the only thing in this app that expires, so it gets the brighter
    // action red — the same tone the presence slab uses while delivering.
    return Scaffold(
      backgroundColor: SeColors.brandAction,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: SeColors.brandAction),
        // `bottom: false`, because the decision bar takes the gesture inset
        // itself. Consumed out here it was painted in the Scaffold's red,
        // leaving a red stripe under a white bar — which reads as a rendering
        // fault rather than a design.
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(SeSpacing.gutter,
                    SeSpacing.x4, SeSpacing.gutter, SeSpacing.x2),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(SeIcons.box,
                          color: SeColors.shellInk, size: 21),
                    ),
                    const SizedBox(width: SeSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NEW DELIVERY REQUEST',
                              style: SeType.eyebrow.copyWith(
                                  color:
                                      SeColors.shellInk.withValues(alpha: 0.85))),
                          Text('Order #$_shortId',
                              style: SeType.tabular(SeType.h3)
                                  .copyWith(color: SeColors.shellInk)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Countdown ───────────────────────────────────────────────
              const SizedBox(height: SeSpacing.x2),
              SeCountdownRing(
                remaining: _remainingSeconds,
                total: _window,
              ),
              const SizedBox(height: SeSpacing.x3),
              Text(
                _remainingSeconds <= 10
                    ? 'Expiring — decide now'
                    : 'Respond before the timer runs out',
                style: SeType.body.copyWith(
                  color: SeColors.shellInk.withValues(alpha: 0.90),
                  fontWeight:
                      _remainingSeconds <= 10 ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: SeSpacing.x5),

              // ── Detail sheet ────────────────────────────────────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: SeColors.surface50,
                    borderRadius: SeRadius.sheetTop,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(70, 8, 24, 0.22),
                        blurRadius: 28,
                        offset: Offset(0, -8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(SeSpacing.gutter,
                        SeSpacing.x5, SeSpacing.gutter, SeSpacing.x5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _payoutRow(),
                        const SizedBox(height: SeSpacing.x5),
                        _routeBlock(),
                        const SizedBox(height: SeSpacing.x5),
                        _itemsBlock(),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Decision bar ────────────────────────────────────────────
              ColoredBox(
                color: SeColors.surface0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(SeSpacing.gutter,
                    SeSpacing.x3, SeSpacing.gutter, SeSpacing.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: SeButton(
                        label: 'Reject',
                        variant: SeButtonVariant.ghost,
                        onPressed:
                            _accepting ? null : () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: SeSpacing.x3),
                    Expanded(
                      flex: 2,
                      child: SeButton(
                        label: 'Accept',
                        icon: SeIcons.checkCircle,
                        loading: _accepting,
                        onPressed: _accepting ? null : _acceptOrder,
                      ),
                    ),
                  ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expiredView() => Scaffold(
        backgroundColor: SeColors.surface50,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SeEmptyState(
                    icon: SeIcons.timer,
                    title: 'Order expired',
                    message:
                        'This request timed out and has gone back to dispatch. You will be shown the next one automatically.',
                    hue: SeColors.warning,
                    tint: SeColors.warningTint,
                  ),
                  const SizedBox(height: SeSpacing.x4),
                  SeButton(
                    label: 'Back to Dashboard',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// The number the driver actually decides on: their own cut.
  Widget _payoutRow() {
    final items = _getItems();
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(SeSpacing.x4),
            decoration: BoxDecoration(
              color: SeColors.successTint,
              borderRadius: SeRadius.all(SeRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOU EARN', style: SeType.eyebrow),
                const SizedBox(height: SeSpacing.x1),
                Text(
                  Money.format(DriverPay.commissionOn(_total)),
                  style: SeType.tabular(SeType.h2)
                      .copyWith(color: SeColors.success),
                ),
                Text(
                  '${DriverPay.commissionLabel} of ${Money.format(_total)}',
                  style: SeType.bodyS.copyWith(color: SeColors.ink500),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: SeSpacing.x3),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(SeSpacing.x4),
            decoration: BoxDecoration(
              color: SeColors.surface50,
              borderRadius: SeRadius.all(SeRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ORDER', style: SeType.eyebrow),
                const SizedBox(height: SeSpacing.x1),
                Text(
                  '${items.length} item${items.length == 1 ? '' : 's'}',
                  style: SeType.h3,
                ),
                Text(_paymentMethod,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _routeBlock() => Container(
        padding: const EdgeInsets.all(SeSpacing.x4),
        decoration: BoxDecoration(
          color: SeColors.surface0,
          borderRadius: SeRadius.all(SeRadius.md),
          border: Border.all(color: SeColors.ink200, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                const Icon(SeIcons.storefront,
                    color: SeColors.brandAction, size: 20),
                Container(
                  width: 2,
                  height: 38,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: SeColors.ink200,
                ),
                const Icon(SeIcons.locationFill,
                    color: SeColors.success, size: 20),
              ],
            ),
            const SizedBox(width: SeSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_isPackage ? 'COLLECT FROM' : 'PICKUP',
                          style: SeType.eyebrow),
                      // A package job is collected from an address, not a
                      // shop, and there is no menu to check the order against.
                      if (_isPackage) ...[
                        const SizedBox(width: SeSpacing.x2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: SeColors.ink100,
                            borderRadius: SeRadius.all(SeRadius.xs),
                          ),
                          child: Text(OrderType.label(widget.order['type']),
                              style: SeType.eyebrow
                                  .copyWith(color: SeColors.ink700)),
                        ),
                      ],
                    ],
                  ),
                  Text(_merchantName, style: SeType.title),
                  if (_merchantAddress != '—')
                    Text(_merchantAddress,
                        style:
                            SeType.bodyS.copyWith(color: SeColors.ink500)),
                  if (_pickupDistanceLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(SeIcons.navigation,
                              size: 13, color: SeColors.info),
                          const SizedBox(width: 4),
                          Text(_pickupDistanceLabel!,
                              style: SeType.bodyS.copyWith(
                                  color: SeColors.info,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(height: SeSpacing.x4),
                  Text('DELIVER TO', style: SeType.eyebrow),
                  Text(_customerName, style: SeType.title),
                  Text(_deliveryAddress,
                      style: SeType.bodyS.copyWith(color: SeColors.ink500)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Describes what the driver is actually carrying.
  ///
  /// A package order has an empty `items` array by design — there are no line
  /// items, only a parcel — so summarising it the food way would tell the
  /// driver "No items listed" about a job that is entirely about the item.
  String _packageSummary() {
    final pkg = widget.order['package'];
    if (pkg is! Map) return 'Package';
    final parts = <String>[
      if ((pkg['itemCategory'] as String?)?.isNotEmpty ?? false)
        pkg['itemCategory'] as String,
      if (pkg['weightKg'] != null) '${pkg['weightKg']} kg',
      if (pkg['packingRequired'] == true) 'packing required',
    ];
    final instructions = (pkg['instructions'] as String?)?.trim() ?? '';
    final head = parts.isEmpty ? 'Package' : parts.join(' · ');
    return instructions.isEmpty ? head : '$head\n$instructions';
  }

  Widget _itemsBlock() {
    if (_isPackage) return _summaryTile(_packageSummary());
    final items = _getItems();
    final summary = items.isNotEmpty
        ? items
            .map((i) {
              final name = (i is Map) ? (i['name'] as String? ?? '') : '$i';
              final qty = (i is Map) ? (i['quantity'] as int? ?? 1) : 1;
              return qty > 1 ? '$name ×$qty' : name;
            })
            .where((s) => s.isNotEmpty)
            .join(', ')
        : 'No items listed';

    return _summaryTile(summary);
  }

  Widget _summaryTile(String summary) {
    return Container(
      padding: const EdgeInsets.all(SeSpacing.x4),
      decoration: BoxDecoration(
        color: SeColors.surface50,
        borderRadius: SeRadius.all(SeRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SeColors.brandSoft,
              borderRadius: SeRadius.all(SeRadius.xs),
            ),
            child: const Icon(SeIcons.box, color: SeColors.brandInk, size: 18),
          ),
          const SizedBox(width: SeSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What you are carrying', style: SeType.title),
                const SizedBox(height: 2),
                Text(summary,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
