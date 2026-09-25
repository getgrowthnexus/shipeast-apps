import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Streams the driver's real GPS onto the active order document while they are
/// on a delivery, so that order's customer can show a live distance.
///
/// There is no map here and none is implied — only coordinates and a freshness
/// stamp written to `orders/{orderId}.driverLoc`. The customer app pairs this
/// with its own device location to state, honestly, how far the driver is from
/// where the customer is standing.
///
/// Why the ORDER doc and not `drivers/{uid}.location`: the driver document is
/// readable by any signed-in user (the tracking screen needs the driver's name
/// and rating), so a coordinate there is visible to everyone. The order document
/// is readable only by that order's customer, driver, and an admin, so writing
/// the location here means only the customer being delivered to can see it. The
/// write is permitted by the existing `driverAdvancing()` rule — `driverLoc` is
/// not a protected field and the write leaves `status` unchanged.
class DriverLocationService {
  DriverLocationService._();
  static final DriverLocationService instance = DriverLocationService._();

  final _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _sub;
  String? _orderId;
  bool _starting = false;

  bool get isTracking => _sub != null;

  /// Begins writing the driver's position onto [orderId]. Idempotent: calling it
  /// again for the order already being tracked is a no-op, so the dashboard can
  /// call it on every active-order snapshot without restarting the stream.
  Future<void> start(String orderId) async {
    if (_orderId == orderId && (_sub != null || _starting)) return;
    await stop(); // switching orders or recovering from a denied permission
    _orderId = orderId;
    _starting = true;
    try {
      if (!await _ensurePermission()) {
        _orderId = null;
        return;
      }
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 20, // metres of movement before a new fix
        ),
      ).listen(
        (pos) => _write(orderId, pos),
        onError: (_) {},
      );
    } finally {
      _starting = false;
    }
  }

  /// Stops tracking and clears the stored coordinate, so the customer app does
  /// not keep showing a position left over from a finished delivery. This clear
  /// only succeeds while the order is not yet `delivered`; on completion the
  /// `confirmDelivery` function clears `driverLoc` server-side instead.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final orderId = _orderId;
    _orderId = null;
    if (orderId != null) {
      try {
        await _db.collection('orders').doc(orderId).update(
          {'driverLoc': FieldValue.delete()},
        );
      } catch (_) {}
    }
  }

  Future<void> _write(String orderId, Position pos) async {
    try {
      await _db.collection('orders').doc(orderId).update({
        'driverLoc': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    } catch (_) {
      // A dropped fix is not worth interrupting the delivery for; the next one
      // is ~20 m away.
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
