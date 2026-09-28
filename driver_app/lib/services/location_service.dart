import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/order_status.dart';
import '../models/tracking.dart';

/// Live GPS for the driver (client request, Sep 2026: "real-time GPS tracking
/// for admin, driver and customer, all connected").
///
/// One position stream, running whenever the driver is online. Each fix goes
/// to up to two places:
///
///  * `driverLocations/{uid}` — the admin's Live Map. Every fix while on a
///    delivery; while idle, at most every [_idleEvery] or [_idleMetres], so an
///    online driver waiting for work costs a handful of writes a minute, not
///    one a second.
///  * `orders/{id}.driverLoc` — only while holding an order. The customer's
///    live map reads this. The order document is readable by just that
///    customer, the driver and admin, which is why the position goes there
///    rather than onto the (widely readable) driver document.
///
/// It also moves the order's `driverStage` by distance: within
/// [Tracking.arriveRadiusM] of the pickup → "waiting at the restaurant"; of
/// the drop-off → "driver has arrived". The driver's "I've arrived" buttons do
/// the same by hand when GPS is poor.
///
/// On Android the stream runs as a foreground service with a visible notice,
/// so it keeps going while the driver has Google Maps open for directions —
/// without one, Android pauses location for a backgrounded app within seconds.
class DriverLocationService {
  DriverLocationService._();
  static final DriverLocationService instance = DriverLocationService._();

  static const _idleEvery = Duration(seconds: 45);
  static const _idleMetres = 100.0;

  final _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _sub;
  bool _starting = false;

  String? _uid;
  bool _online = false;

  /// The order being delivered, as last seen by the dashboard (id, status,
  /// driverStage, pickup/delivery coordinates). Null when idle.
  Map<String, dynamic>? _order;
  String? _stageWritten; // last stage this service wrote, to avoid repeats

  DateTime? _lastPresenceAt;
  Position? _lastPresencePos;

  bool get isTracking => _sub != null;

  /// Called from the driver-document listener. Online → the stream runs and
  /// the admin map shows this driver; offline → it stops and the admin map
  /// drops them (unless an order is still in hand).
  Future<void> setOnline(String uid, bool online) async {
    _uid = uid;
    _online = online;
    if (online) {
      await _ensureStream();
    } else if (_order == null) {
      await _shutdown(markOffline: true);
    }
  }

  /// Called on every active-order snapshot. Idempotent: the same order just
  /// refreshes the status / stage / coordinates used for arrival checks.
  Future<void> setOrder(Map<String, dynamic>? order) async {
    final previous = _order?['id'] as String?;
    _order = order == null ? null : Map<String, dynamic>.from(order);
    final current = _order?['id'] as String?;
    if (current != previous) _stageWritten = null;

    if (previous != null && previous != current) {
      // Finished or reassigned: clear the old order's live coordinate so its
      // customer is not left looking at a stale pin.
      await _clearOrderLoc(previous);
    }
    if (_order != null) {
      await _ensureStream();
    } else if (!_online) {
      await _shutdown(markOffline: true);
    }
  }

  /// Everything off — sign-out, revocation, the dashboard going away.
  Future<void> stop() async {
    final held = _order?['id'] as String?;
    _order = null;
    if (held != null) await _clearOrderLoc(held);
    await _shutdown(markOffline: true);
  }

  Future<void> _ensureStream() async {
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      if (!await _ensurePermission()) return;
      _sub = Geolocator.getPositionStream(locationSettings: _settings())
          .listen(_onFix, onError: (_) {});
    } finally {
      _starting = false;
    }
  }

  LocationSettings _settings() {
    if (kIsWeb) {
      return const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20);
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20, // metres of movement before a new fix
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'ShipEast is sharing your location',
            notificationText:
                'Only while you are online or delivering. Go offline to stop.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 20);
    }
  }

  Future<void> _onFix(Position pos) async {
    final order = _order;
    final orderId = order?['id'] as String?;

    if (orderId != null) {
      await _writeOrderLoc(orderId, pos);
      await _checkArrival(orderId, order!, pos);
    }

    // Presence for the admin map: every fix mid-delivery; throttled when idle.
    final now = DateTime.now();
    final last = _lastPresencePos;
    final due = orderId != null ||
        _lastPresenceAt == null ||
        now.difference(_lastPresenceAt!) >= _idleEvery ||
        (last != null &&
            Tracking.distanceM(last.latitude, last.longitude, pos.latitude,
                    pos.longitude) >=
                _idleMetres);
    if (due) {
      _lastPresenceAt = now;
      _lastPresencePos = pos;
      await _writePresence(pos, orderId);
    }
  }

  /// Moves `driverStage` when the driver reaches the pickup or the drop-off.
  /// Only forward, only once per order and stage.
  Future<void> _checkArrival(
      String orderId, Map<String, dynamic> order, Position pos) async {
    final status = order['status'] as String? ?? '';
    final stage = order['driverStage'] as String?;
    double? n(String k) => (order[k] as num?)?.toDouble();

    String? next;
    String? stampField;
    if (status == OrderStatus.confirmed &&
        stage != DriverStage.atPickup &&
        Tracking.hasArrived(
            pos.latitude, pos.longitude, n('pickupLat'), n('pickupLng'))) {
      next = DriverStage.atPickup;
      stampField = 'arrivedPickupAt';
    } else if (status == OrderStatus.inTransit &&
        stage != DriverStage.atDropoff &&
        Tracking.hasArrived(
            pos.latitude, pos.longitude, n('deliveryLat'), n('deliveryLng'))) {
      next = DriverStage.atDropoff;
      stampField = 'arrivedDropoffAt';
    }
    if (next == null || _stageWritten == next) return;
    _stageWritten = next;
    order['driverStage'] = next;
    try {
      await _db.collection('orders').doc(orderId).update({
        'driverStage': next,
        stampField!: FieldValue.serverTimestamp(),
      });
    } catch (_) {
      _stageWritten = null; // try again on the next fix
    }
  }

  Future<void> _writeOrderLoc(String orderId, Position pos) async {
    try {
      await _db.collection('orders').doc(orderId).update({
        'driverLoc': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'heading': pos.heading,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (_) {
      // A dropped fix is not worth interrupting the delivery for; the next one
      // is ~20 m away.
    }
  }

  Future<void> _writePresence(Position pos, String? orderId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('driverLocations').doc(uid).set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'heading': pos.heading,
        'speed': pos.speed,
        'online': true,
        'orderId': orderId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _clearOrderLoc(String orderId) async {
    // Only succeeds while the order is still held; after delivery the
    // delivering write clears driverLoc itself.
    try {
      await _db
          .collection('orders')
          .doc(orderId)
          .update({'driverLoc': FieldValue.delete()});
    } catch (_) {}
  }

  Future<void> _shutdown({required bool markOffline}) async {
    await _sub?.cancel();
    _sub = null;
    _lastPresenceAt = null;
    _lastPresencePos = null;
    final uid = _uid;
    if (markOffline && uid != null) {
      try {
        await _db
            .collection('driverLocations')
            .doc(uid)
            .update({'online': false, 'orderId': null});
      } catch (_) {
        // No document yet (never had a fix) — nothing to mark.
      }
    }
  }

  /// A one-shot current fix used to rank pending orders by how near their
  /// pickup is, so the driver is offered the closest job first rather than
  /// whichever happened to arrive first.
  ///
  /// Returns null when a fix is unavailable — permission denied, location
  /// services off, or a web preview where the browser refuses geolocation — in
  /// which case dispatch falls back to arrival order. Ranking is a convenience,
  /// never a gate: an order is still offered when position is unknown.
  Future<Position?> currentPosition() async {
    try {
      if (!await _ensurePermission()) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }
}
