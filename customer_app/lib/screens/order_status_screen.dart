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
import '../widgets/se_card.dart';
import '../widgets/se_button.dart';
import '../widgets/se_bottom_sheet.dart';
import '../widgets/se_toast.dart';

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

  String get _statusLabel => OrderStatus.label(_status);

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
    'Order Placed',
    'Driver Assigned',
    'Picked Up',
    'On the Way',
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
    final merchantName = _order?['merchantName'] as String? ?? 'Merchant';
    switch (index) {
      case 0:
        // The old copy claimed "$merchantName accepted your order", which was
        // wrong even before this change — no merchant accepts anything in this
        // system. Only a driver ever accepts an order.
        return 'Your order was sent to $merchantName';
      case 1:
        return 'A driver accepted and is heading to $merchantName';
      case 2:
        return 'Driver collected your order';
      case 3:
        return 'Driver is heading to you now';
      case 4:
        return 'Order delivered successfully!';
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
    // Cancelled is a terminal state with its own presentation — not a stepper
    // frozen at some index. Handled before anything reads _currentStep.
    if (_isCancelled) return _buildCancelledScaffold();

    final delivered = _currentStep == OrderStatus.stepCount - 1;
    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          _buildHero(delivered),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStepper(),
                  const SizedBox(height: 16),
                  _buildDriverCard(),
                  const SizedBox(height: 12),
                  if (_isEnRoute && _driverLoc != null) ...[
                    _buildLiveDistanceCard(),
                    const SizedBox(height: 12),
                  ],
                  if (delivered && _order?['rated'] != true)
                    SeButton(
                      label: 'Rate Your Experience',
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
                  if (!delivered) _buildTrackingNote(),
                  if (_canCancel) ...[
                    const SizedBox(height: 12),
                    SeButton(
                      label: _cancelling ? 'Cancelling…' : 'Cancel Order',
                      icon: SeIcons.close,
                      variant: SeButtonVariant.destructive,
                      onPressed: _cancelling ? null : _showCancelSheet,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Honest live-tracking status hero (SEDS) — deliberately NOT a fake street
  // map. Shows the real order status, a route progress bar, and a pulsing
  // "current" node. A real map lands with the maps integration (see audit).
  Widget _buildHero(bool delivered) {
    return Container(
      decoration: BoxDecoration(
        gradient:
            delivered ? _successGradient : SeColors.emberGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, SeSpacing.gutter, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(SeIcons.arrowLeft,
                          size: 20, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _orderId.isNotEmpty
                          ? 'Order #${_orderId.substring(0, _orderId.length.clamp(0, 8)).toUpperCase()}'
                          : 'Your Order',
                      style: SeType.label.copyWith(
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                  // The ETA pill stood here. Removed — see _stepNames.
                ],
              ),
              const SizedBox(height: 16),
              Text(_statusLabel, style: SeType.h1.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text(
                delivered
                    ? 'Thanks for ordering with ShipEast.'
                    : 'Live status · updates automatically',
                style: SeType.bodyS.copyWith(
                    color: Colors.white.withValues(alpha: 0.85)),
              ),
              const SizedBox(height: 16),
              _routeBar(delivered),
            ],
          ),
        ),
      ),
    );
  }

  static const LinearGradient _successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF16A34A), Color(0xFF0B7A38)],
  );

  /// Neutral slate, deliberately not the brand ember and not alarm red. A
  /// cancelled order is a dead end, not an error the customer caused.
  static const LinearGradient _cancelledGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF475467), Color(0xFF1D2939)],
  );

  /// Terminal presentation for a cancelled order.
  ///
  /// Deliberately does not fall through to the stepper: there is no progress to
  /// show, and [OrderStatus.step] returns -1 here. Shows the reason when one was
  /// recorded, and routes to support rather than leaving the customer with a
  /// dead screen and no next action.
  Widget _buildCancelledScaffold() {
    final reason = (_order?['cancellationReason'] as String?)?.trim() ?? '';
    final cancelledBy = _order?['cancelledBy'] as String? ?? '';

    return Scaffold(
      backgroundColor: SeColors.surface50,
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: _cancelledGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 8, SeSpacing.gutter, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(SeIcons.arrowLeft,
                                size: 20, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _orderId.isNotEmpty
                                ? 'Order #${_orderId.substring(0, _orderId.length.clamp(0, 8)).toUpperCase()}'
                                : 'Your Order',
                            style: SeType.label.copyWith(
                                color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(OrderStatus.label(OrderStatus.cancelled),
                        style: SeType.h1.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      'This order is no longer being delivered.',
                      style: SeType.bodyS.copyWith(
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SeSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SeCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(SeIcons.warningCircle,
                                size: 20, color: SeColors.danger),
                            const SizedBox(width: 8),
                            Text('What happened',
                                style: SeType.label
                                    .copyWith(color: SeColors.ink500)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          reason.isNotEmpty
                              ? reason
                              : cancelledBy == 'customer'
                                  ? 'You cancelled this order.'
                                  : 'This order was cancelled. No reason was '
                                      'recorded.',
                          style: SeType.bodyS,
                        ),
                        // Matched loosely on purpose: the stored value is the
                        // display string 'Cash on Delivery', not a slug.
                        // Normalising it is a schema migration, not a Phase 1
                        // change — see SCHEMA.md §orders.paymentMethod.
                        if ((_order?['paymentMethod'] as String? ?? '')
                            .toLowerCase()
                            .contains('cash')) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Nothing was charged — this order was cash on '
                            'delivery.',
                            style: SeType.bodyS
                                .copyWith(color: SeColors.ink300),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SeButton(
                    label: 'Contact Support',
                    icon: SeIcons.chat,
                    onPressed: () =>
                        Navigator.pushNamed(context, '/help-support'),
                  ),
                ],
              ),
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
              const SizedBox(height: 12),
              Text('Cancel this order?', style: SeType.h2),
              const SizedBox(height: 4),
              Text(
                'This cannot be undone. Nothing was charged — this order is '
                'cash on delivery.',
                style: SeType.bodyS.copyWith(color: SeColors.ink500),
              ),
              const SizedBox(height: 18),
              Text('Why are you cancelling?',
                  style: SeType.label.copyWith(color: SeColors.ink700)),
              const SizedBox(height: 8),
              ..._cancelReasons.map((reason) {
                final isSelected = selected == reason;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setSheetState(() => selected = reason),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? SeColors.dangerTint
                            : SeColors.surface50,
                        borderRadius: SeRadius.inputRadius,
                        border: Border.all(
                          color: isSelected
                              ? SeColors.danger
                              : SeColors.ink200,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? SeIcons.checkCircle
                                : SeIcons.radioOff,
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
                label: 'Cancel Order',
                icon: SeIcons.close,
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
                label: 'Keep My Order',
                icon: SeIcons.arrowLeft,
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

  Widget _routeBar(bool delivered) {
    // Guarded against the cancelled case: step() returns -1 there, and a
    // negative width factor throws. The cancelled view never reaches this
    // widget, and the clamp is the belt to that braces.
    final progress =
        (_currentStep / (OrderStatus.stepCount - 1)).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress == 0 ? 0.02 : progress,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              // Moving node
              Positioned(
                left: (width - 20) * progress,
                child: _pulseNode(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pulseNode() {
    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_currentStep < 3)
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) => Transform.scale(
                scale: 0.7 + _pulseCtrl.value * 1.3,
                child: Opacity(
                  opacity: (1 - _pulseCtrl.value).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: SeElevation.e1,
            ),
            child: Icon(
              _currentStep >= 3 ? SeIcons.check : SeIcons.bike,
              size: 8,
              color: SeColors.red500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    return SeCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: List.generate(
          OrderStatus.stepCount,
          (i) => _stepRow(i, isLast: i == OrderStatus.stepCount - 1),
        ),
      ),
    );
  }

  Widget _stepRow(int stepIndex, {required bool isLast}) {
    final state = _stepState(stepIndex);
    final isDone = state == 'done';
    final isNow = state == 'now';
    final isWait = state == 'wait';

    final Color dotBg = isDone
        ? SeColors.successTint
        : isNow
            ? SeColors.red500
            : SeColors.surface50;
    final Color iconColor = isDone
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: dotBg,
                  shape: BoxShape.circle,
                  boxShadow:
                      isNow ? SeElevation.glow : SeElevation.e0,
                ),
                child: Icon(_stepIcons[stepIndex], size: 18, color: iconColor),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isDone ? SeColors.success : SeColors.ink200,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: isLast ? 8 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stepNames[stepIndex],
                    style: SeType.title.copyWith(
                        color: isWait ? SeColors.ink400 : SeColors.ink900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDone || isNow ? _stepSub(stepIndex) : 'Waiting...',
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

  Future<void> _callDriver(String name) async {
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

  Widget _buildDriverCard() {
    final driverId = _order?['driverId'] as String?;
    final hasDriver = driverId != null && driverId.isNotEmpty;

    if (!hasDriver) {
      return SeCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
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
                  Text('Finding your driver...', style: SeType.title),
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

    final driverName = _driver?['name'] as String? ?? 'Your Driver';
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

    return SeCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: SeColors.emberGradient,
              borderRadius: SeRadius.all(SeRadius.sm),
            ),
            child: const Icon(SeIcons.user, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(driverName, style: SeType.title),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(SeIcons.star, size: 12, color: SeColors.gold500),
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
          GestureDetector(
            onTap: () => _callDriver(driverName),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SeColors.successTint,
                borderRadius: SeRadius.all(SeRadius.sm),
              ),
              child: const Icon(SeIcons.phone, size: 18, color: SeColors.success),
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
  Widget _buildLiveDistanceCard() {
    final fresh = _driverLocFresh();
    final accent = fresh ? SeColors.ocean500 : SeColors.ink400;

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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeColors.oceanTint,
        borderRadius: SeRadius.all(SeRadius.md),
      ),
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
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(fresh ? 'LIVE' : 'PAUSED',
                        style: SeType.label.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(headline,
                    style: SeType.title.copyWith(color: SeColors.ink900)),
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

  Widget _buildTrackingNote() => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SeColors.oceanTint,
          borderRadius: SeRadius.all(SeRadius.md),
        ),
        child: Row(
          children: [
            const Icon(SeIcons.info, size: 18, color: SeColors.ocean500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "We'll notify you when your order is delivered.",
                style: SeType.bodyS.copyWith(color: SeColors.ocean500),
              ),
            ),
          ],
        ),
      );
}
