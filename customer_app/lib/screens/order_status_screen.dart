import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/firestore_service.dart';
import '../theme/se_colors.dart';
import '../theme/se_icons.dart';
import '../theme/se_spacing.dart';
import '../theme/se_typography.dart';
import '../models/order_status.dart';
import '../utils/phone.dart';
import '../widgets/se_button.dart';
import '../widgets/se_page.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_toast.dart';

/// Tracking.
///
/// Ordered by how fresh the information is, not by how the data is shaped: what
/// is happening RIGHT NOW (the driver, the live distance) sits at the top, and
/// the step history — which the customer has mostly already lived through —
/// sits under it.
///
/// Every state uses the same brand cap. A cancelled order used to get a black
/// header and a delivered one a green header, which made three screens out of
/// one; the state now shows in the words, the route bar and the stepper.
class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  String _orderId = '';
  bool _argsLoaded = false;
  StreamSubscription<Map<String, dynamic>?>? _orderSub;
  StreamSubscription<Map<String, dynamic>?>? _driverSub;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _driver;
  String? _watchedDriverId;

  // ── Live distance (P5-05, no map tiles) ──────────────────────────────────
  // The driver streams real GPS to their doc while en route; we pair it with
  // the customer's own device location to say, truthfully, how far the driver
  // is from where the customer is right now.
  StreamSubscription<Position>? _mySub;
  Position? _myPos;
  bool _locStarted = false;
  bool _locDenied = false;
  double? _distanceM;
  double? _prevDistanceM;

  /// The driver only carries goods toward the customer once the order is picked
  /// up, so a "distance to you" is only meaningful from there on.
  bool get _isEnRoute =>
      _status == OrderStatus.pickedUp || _status == OrderStatus.inTransit;

  /// The driver's live position rides on this order document (`driverLoc`), not
  /// on the shared driver profile — the order is readable only by its own
  /// customer, so no one else can see where this driver is. The driver app
  /// writes it via DriverLocationService.
  Map<String, dynamic>? get _driverLoc {
    final loc = _order?['driverLoc'];
    return loc is Map<String, dynamic> ? loc : null;
  }

  String get _status => _order?['status'] as String? ?? OrderStatus.pending;

  int get _currentStep => OrderStatus.step(_status);

  /// Cancellation is not a step on the tracker.
  ///
  /// [OrderStatus.step] returns -1 for it, and every caller must branch: the
  /// stepper has no node to highlight, and a negative width factor throws.
  /// Before this, `cancelled` fell to step 0 and the screen cheerfully
  /// displayed "Order Confirmed" on a cancelled order.
  bool get _isCancelled => _status == OrderStatus.cancelled;

  bool get _delivered => _status == OrderStatus.delivered;

  String get _statusLabel => OrderStatus.label(_status);

  String get _reference => _orderId.isEmpty
      ? ''
      : '#${_orderId.substring(0, _orderId.length.clamp(0, 8)).toUpperCase()}';

  /// P5-03, audit §15. The app has always rendered a "Cancelled" tab and a
  /// cancelled badge that **no customer action could ever produce**.
  ///
  /// The window is `pending` only, and that is not a UI preference — it is the
  /// only transition rules permit a customer to make (`customerCancelling()` in
  /// firestore.rules). Once a driver has claimed the order they are already
  /// riding to the merchant, and cancelling out from under them is an
  /// operational decision, not a customer one. From there the customer is
  /// routed to support.
  bool get _canCancel => _order != null && _status == OrderStatus.pending;

  bool _cancelling = false;

  static const _cancelReasons = [
    'Ordered by mistake',
    'Taking too long',
    'Changed my mind',
    'Wrong delivery address',
    'Found it cheaper elsewhere',
  ];

  // The ETA pill is gone. It was hardcoded '~40 min' / '~25 min' / '~15 min' —
  // invented numbers presented to the customer as an estimate, derived from
  // nothing. A wrong ETA is worse than no ETA, and this screen already declines
  // to fake a map for the same reason. Revisit with the maps work (P5-05).

  static const _stepNames = [
    'Order placed',
    'Driver assigned',
    'Picked up',
    'On the way',
    'Delivered',
  ];

  static const _stepIcons = [
    SeIcons.checkCircle,
    SeIcons.user,
    SeIcons.box,
    SeIcons.bike,
    SeIcons.home,
  ];

  String _stepSub(int index) {
    final merchantName = _order?['merchantName'] as String? ?? 'the merchant';
    switch (index) {
      case 0:
        // The old copy claimed "$merchantName accepted your order", which was
        // wrong even before this change — no merchant accepts anything in this
        // system. Only a driver ever accepts an order.
        return 'Sent to $merchantName';
      case 1:
        return 'A driver accepted and is heading to $merchantName';
      case 2:
        return 'Your order is with the driver';
      case 3:
        return 'Heading to you now';
      case 4:
        return 'Delivered — thanks for ordering';
      default:
        return '';
    }
  }

  String _stepState(int stepIndex) {
    if (stepIndex < _currentStep) return 'done';
    if (stepIndex == _currentStep) return 'now';
    return 'wait';
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _argsLoaded = true;
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _orderId = args['orderId'] as String? ?? '';
      }
      if (_orderId.isNotEmpty) {
        _orderSub = FirestoreService.watchOrder(_orderId).listen((order) {
          if (!mounted) return;
          setState(() => _order = order);
          if (_isEnRoute) _startMyLocation();
          final driverId = order?['driverId'] as String?;
          if (driverId != null &&
              driverId.isNotEmpty &&
              driverId != _watchedDriverId) {
            _driverSub?.cancel();
            _watchedDriverId = driverId;
            _driverSub =
                FirestoreService.watchDriver(driverId).listen((driver) {
              if (!mounted) return;
              setState(() => _driver = driver);
              _recomputeDistance();
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _orderSub?.cancel();
    _driverSub?.cancel();
    _mySub?.cancel();
    super.dispose();
  }

  /// Starts watching the customer's own location once the driver is en route.
  /// Runs at most once per screen; a denied permission is remembered so the
  /// card can fall back to a distance-less "live" state instead of nagging.
  Future<void> _startMyLocation() async {
    if (_locStarted) return;
    _locStarted = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locDenied = true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locDenied = true);
        return;
      }
      _mySub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _myPos = pos);
        _recomputeDistance();
      }, onError: (_) {
        if (mounted) setState(() => _locDenied = true);
      });
    } catch (_) {
      if (mounted) setState(() => _locDenied = true);
    }
  }

  /// Recomputes the driver→customer straight-line distance from whichever of
  /// the two live positions just changed. Straight-line, not road distance: no
  /// routing engine is involved, and the copy says "away" rather than a fake
  /// ETA so the number is never dressed up as more than it is.
  void _recomputeDistance() {
    final loc = _driverLoc;
    final my = _myPos;
    if (loc == null || my == null) return;
    final dLat = (loc['lat'] as num?)?.toDouble();
    final dLng = (loc['lng'] as num?)?.toDouble();
    if (dLat == null || dLng == null) return;
    final meters =
        Geolocator.distanceBetween(my.latitude, my.longitude, dLat, dLng);
    setState(() {
      _prevDistanceM = _distanceM;
      _distanceM = meters;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Cancelled is a terminal state with its own content — not a stepper frozen
    // at some index. Handled before anything reads _currentStep.
    if (_isCancelled) return _cancelledView();

    return SePageScaffold(
      title: _statusLabel,
      subtitle: _delivered
          ? 'Thanks for ordering with ShipEast.'
          : 'Live · updates automatically',
      trailing: _reference.isEmpty
          ? null
          : Text(_reference,
              style: SeType.tabular(SeType.label).copyWith(
                  color: SeColors.shellInk.withValues(alpha: 0.78))),
      capBottom: _routeBar(),
      bottomBar: _delivered && _order?['rated'] != true
          ? SeBottomBar(
              child: SeButton(
                label: 'Rate your experience',
                icon: SeIcons.star,
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/rate-driver',
                  arguments: {
                    'orderId': _orderId,
                    'driverId': _order?['driverId'] ?? '',
                    'merchantId': _order?['merchantId'] ?? '',
                    'merchantName': _order?['merchantName'] ?? '',
                  },
                ),
              ),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 28),
        children: [
          _driverPanel(),
          if (_isEnRoute && _driverLoc != null) ...[
            const SizedBox(height: 12),
            _liveDistancePanel(),
          ],
          const SizedBox(height: 22),
          const SeSectionTitle(title: 'Progress'),
          const SizedBox(height: 10),
          _stepper(),
          if (!_delivered) ...[
            const SizedBox(height: 14),
            SeNotice.info("We'll notify you when your order is delivered."),
          ],
          if (_canCancel) ...[
            const SizedBox(height: 18),
            Center(
              child: SeButton(
                label: _cancelling ? 'Cancelling…' : 'Cancel order',
                variant: SeButtonVariant.ghost,
                size: SeButtonSize.medium,
                expand: false,
                onPressed: _cancelling ? null : _showCancelSheet,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Terminal presentation for a cancelled order.
  ///
  /// Same shell as every other state — only the words and the content change.
  /// There is no progress to show, and [OrderStatus.step] returns -1 here, so
  /// nothing on this path touches the stepper.
  Widget _cancelledView() {
    final reason = (_order?['cancellationReason'] as String?)?.trim() ?? '';
    final cancelledBy = _order?['cancelledBy'] as String? ?? '';
    final wasCash = (_order?['paymentMethod'] as String? ?? '')
        .toLowerCase()
        .contains('cash');

    return SePageScaffold(
      title: OrderStatus.label(OrderStatus.cancelled),
      subtitle: 'This order is no longer being delivered.',
      trailing: _reference.isEmpty
          ? null
          : Text(_reference,
              style: SeType.tabular(SeType.label).copyWith(
                  color: SeColors.shellInk.withValues(alpha: 0.78))),
      bottomBar: SeBottomBar(
        child: SeButton(
          label: 'Contact support',
          icon: SeIcons.chat,
          onPressed: () => Navigator.pushNamed(context, '/help-support'),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            SeSpacing.gutter, 20, SeSpacing.gutter, 24),
        children: [
          const SeSectionTitle(title: 'What happened'),
          const SizedBox(height: 10),
          SePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason.isNotEmpty
                      ? reason
                      : cancelledBy == 'customer'
                          ? 'You cancelled this order.'
                          : 'This order was cancelled. No reason was recorded.',
                  style: SeType.body
                      .copyWith(color: SeColors.ink900, height: 1.45),
                ),
                // Matched loosely on purpose: the stored value is the display
                // string 'Cash on Delivery', not a slug. Normalising it is a
                // schema migration, not a Phase 1 change — see
                // SCHEMA.md §orders.paymentMethod.
                if (wasCash) ...[
                  const SizedBox(height: 12),
                  SeNotice.info(
                      'Nothing was charged — this order was cash on delivery.'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Confirmation sheet with a reason picker (P5-03).
  ///
  /// The reason is required, and it is not decoration: `cancellationReason` is
  /// the only field the cancelled screen has to explain itself with, and it is
  /// what tells operations whether cancellations are a pricing problem or a
  /// speed problem.
  void _showCancelSheet() {
    String? selected;

    showSeBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
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
              Text('Cancel this order?', style: SeType.h2),
              const SizedBox(height: 4),
              Text(
                'This cannot be undone. Nothing was charged — this order is '
                'cash on delivery.',
                style: SeType.bodyS
                    .copyWith(color: SeColors.ink500, height: 1.45),
              ),
              const SizedBox(height: 18),
              const SeFieldLabel('WHY ARE YOU CANCELLING?'),
              ..._cancelReasons.map((reason) {
                final isSelected = selected == reason;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setSheetState(() => selected = reason),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SeColors.dangerSoft
                            : SeColors.surface50,
                        borderRadius: SeRadius.all(SeRadius.md),
                        border: Border.all(
                          color:
                              isSelected ? SeColors.danger : SeColors.ink200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? SeIcons.checkCircle : SeIcons.radioOff,
                            size: 20,
                            color: isSelected
                                ? SeColors.danger
                                : SeColors.ink300,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(reason,
                                style: SeType.body
                                    .copyWith(color: SeColors.ink900)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              SeButton(
                label: 'Cancel order',
                variant: SeButtonVariant.destructive,
                // Disabled until a reason is chosen. An optional reason is an
                // empty reason: nobody fills in a field they can skip, and the
                // cancelled screen then has nothing to say.
                onPressed: selected == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _cancelOrder(selected!);
                      },
              ),
              const SizedBox(height: 8),
              SeButton(
                label: 'Keep my order',
                variant: SeButtonVariant.ghost,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelOrder(String reason) async {
    setState(() => _cancelling = true);
    try {
      await FirestoreService.cancelOrder(orderId: _orderId, reason: reason);
      // No success toast and no navigation: the order stream is already live,
      // so the screen switches to its terminal cancelled presentation on its
      // own. Pushing a route here would race that rebuild.
      if (mounted) setState(() => _cancelling = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      // The likeliest cause is that a driver claimed the order a moment ago,
      // which rules reject. Say the true thing rather than "try again".
      SeToast.error(
          context, 'Could not cancel — a driver may have already accepted it.');
    }
  }

  /// The one piece of motion in the app: a node that creeps along the cap as
  /// the order moves. It sits ON the brand, so it is drawn in warm white.
  Widget _routeBar() {
    // Guarded against the cancelled case: step() returns -1 there, and a
    // negative width factor throws. The cancelled view never reaches this
    // widget, and the clamp is the belt to that braces.
    final progress =
        (_currentStep / (OrderStatus.stepCount - 1)).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return SizedBox(
          height: 22,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress == 0 ? 0.02 : progress,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: SeColors.shellInk,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Positioned(
                left: (width - 22) * progress,
                child: _pulseNode(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseNode() => SizedBox(
        width: 22,
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_currentStep < OrderStatus.stepCount - 1)
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) => Transform.scale(
                  scale: 0.7 + _pulseCtrl.value * 1.3,
                  child: Opacity(
                    opacity: (1 - _pulseCtrl.value).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: SeColors.shellInk.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                  color: SeColors.shellInk, shape: BoxShape.circle),
              child: Icon(
                _currentStep >= OrderStatus.stepCount - 1
                    ? SeIcons.check
                    : SeIcons.bike,
                size: 11,
                color: SeColors.shell,
              ),
            ),
          ],
        ),
      );

  Widget _stepper() => SePanel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          children: List.generate(
            OrderStatus.stepCount,
            (i) => _stepRow(i, isLast: i == OrderStatus.stepCount - 1),
          ),
        ),
      );

  Widget _stepRow(int stepIndex, {required bool isLast}) {
    final state = _stepState(stepIndex);
    final isDone = state == 'done';
    final isNow = state == 'now';
    final isWait = state == 'wait';

    final Color plate = isDone
        ? SeColors.successSoft
        : isNow
            ? SeColors.brandAction
            : SeColors.surface50;
    final Color glyph = isDone
        ? SeColors.success
        : isNow
            ? Colors.white
            : SeColors.ink300;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: plate, shape: BoxShape.circle),
                child: Icon(_stepIcons[stepIndex], size: 16, color: glyph),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: isDone ? SeColors.success : SeColors.ink200,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: isLast ? 8 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stepNames[stepIndex],
                    style: SeType.title.copyWith(
                        fontSize: 15,
                        color: isWait ? SeColors.ink400 : SeColors.ink900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDone || isNow ? _stepSub(stepIndex) : 'Not yet',
                    style: SeType.bodyS.copyWith(color: SeColors.ink400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callDriver() async {
    final phone = (_driver?['phone'] as String?)?.trim() ?? '';
    if (phone.isEmpty) {
      if (mounted) SeToast.info(context, 'Driver contact not available yet');
      return;
    }
    // DR-25: dial the normalised number; keep the raw string as a fallback.
    final dial = SePhone.dial(phone);
    final uri = Uri(scheme: 'tel', path: dial.isEmpty ? phone : dial);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      SeToast.error(context, 'Could not start the call');
    }
  }

  Widget _driverPanel() {
    final driverId = _order?['driverId'] as String?;
    final hasDriver = driverId != null && driverId.isNotEmpty;

    if (!hasDriver) {
      return SePanel(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SeColors.surface50,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child: const Icon(SeIcons.user, size: 22, color: SeColors.ink300),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finding your driver…',
                      style: SeType.title.copyWith(fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('A driver will be assigned shortly',
                      style: SeType.bodyS.copyWith(color: SeColors.ink400)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final driverName = _driver?['name'] as String? ?? 'Your driver';
    final avgRating =
        (_driver?['averageRating'] as num?)?.toStringAsFixed(1) ?? '5.0';
    // British spelling, per SCHEMA.md §c — both writers (driver registration
    // and the admin panel) already use it; only this reader was wrong.
    //
    // The `vehicleMake` read was deleted: no such field is written by anything,
    // and combined with the American `licensePlate` it meant vehicleInfo
    // resolved to an empty string for every driver. The customer saw a name and
    // a rating with no way to identify the car pulling up outside.
    final vehicleModel = _driver?['vehicleModel'] as String? ?? '';
    final licencePlate = _driver?['licencePlate'] as String? ?? '';
    final vehicleInfo = [
      if (vehicleModel.isNotEmpty) vehicleModel.trim(),
      if (licencePlate.isNotEmpty) licencePlate,
    ].join('  ·  ');

    return SePanel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SeColors.brandSoft,
              borderRadius: SeRadius.all(SeRadius.sm),
            ),
            child: const Icon(SeIcons.user,
                size: 22, color: SeColors.brandAction),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driverName,
                    style: SeType.title.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(SeIcons.star, size: 12, color: SeColors.star),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '$avgRating${vehicleInfo.isNotEmpty ? '  ·  $vehicleInfo' : ''}',
                        style: SeType.bodyS.copyWith(color: SeColors.ink500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _callDriver,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeColors.successSoft,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child:
                  const Icon(SeIcons.phone, size: 18, color: SeColors.success),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDistance(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km away';
    return '${(m / 10).round() * 10} m away';
  }

  /// Whether the driver's last fix is recent enough to call "live". A driver
  /// who parks and stops moving stops generating fixes (20 m filter), so beyond
  /// two minutes we say "paused" rather than imply a stale dot is live.
  bool _driverLocFresh() {
    final ts = _driverLoc?['updatedAt'];
    if (ts is! Timestamp) return true; // serverTimestamp not resolved yet
    return DateTime.now().difference(ts.toDate()).inSeconds < 120;
  }

  /// Live distance from the driver to the customer — no map, no ETA. Shows a
  /// real number when the customer has shared their location, and an honest
  /// "live location active" state (with a prompt) when they have not.
  Widget _liveDistancePanel() {
    final fresh = _driverLocFresh();
    final accent = fresh ? SeColors.info : SeColors.ink400;

    String headline;
    String sub;
    if (_locDenied) {
      headline = 'Your driver is sharing live location';
      sub = 'Turn on location to see how far away they are.';
    } else if (_distanceM != null) {
      headline = _fmtDistance(_distanceM!);
      if (_distanceM! < 120) {
        sub = 'Your driver is nearby — keep an eye out.';
      } else if (_prevDistanceM != null &&
          _distanceM! < _prevDistanceM! - 15) {
        sub = 'Getting closer to you.';
      } else {
        sub = 'Straight-line distance from your location.';
      }
    } else {
      headline = 'Locating your driver…';
      sub = 'Getting a live position from your driver.';
    }

    return SePanel(
      color: SeColors.infoSoft,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SeColors.surface0,
              borderRadius: SeRadius.all(SeRadius.sm),
            ),
            child: Icon(SeIcons.bike, size: 22, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(fresh ? 'LIVE' : 'PAUSED',
                        style: SeType.eyebrow.copyWith(color: accent)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(headline,
                    style: SeType.title
                        .copyWith(fontSize: 15, color: SeColors.ink900)),
                const SizedBox(height: 1),
                Text(sub,
                    style: SeType.bodyS.copyWith(color: SeColors.ink500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
