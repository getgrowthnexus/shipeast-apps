/// Live GPS tracking — shared vocabulary and maths. Source of truth:
/// SCHEMA.md §orders.driverStage and §driverLocations.
///
/// This file is duplicated in customer_app and driver_app and verified
/// byte-identical by CI (tools/check-status-parity.mjs), exactly like
/// order_status.dart. Edit both, or neither. The admin panel mirrors the
/// labels and the maths in `admin_panel/tracking.js`.
///
/// Client request (Sep 2026): everyone — customer, driver, admin — sees where
/// the driver is and what they are doing: on the way to the restaurant,
/// waiting at the restaurant, picked up, on the way to you, nearby, arrived.
///
/// The ORDER status says who holds the order (Driver Assigned, Picked Up, Out
/// for Delivery). `driverStage` is a finer, GPS-driven detail inside those:
/// it never gates a transition, so a phone with poor GPS can only make a label
/// less precise, never block a delivery.
library;

import 'dart:math' as math;

import 'order_status.dart';

abstract final class DriverStage {
  /// Claimed; driving to the pickup (restaurant / package sender).
  static const toPickup = 'to_pickup';

  /// Within [Tracking.arriveRadiusM] of the pickup, or the driver tapped
  /// "I've arrived". Waiting for the order.
  static const atPickup = 'at_pickup';

  /// Out for delivery; driving to the customer.
  static const toDropoff = 'to_dropoff';

  /// At the drop-off (GPS or "I've arrived"). Waiting for the customer.
  static const atDropoff = 'at_dropoff';

  static const all = [toPickup, atPickup, toDropoff, atDropoff];
}

abstract final class Tracking {
  /// Close enough to count as "arrived" (GPS is typically good to 10–30 m;
  /// a shop front or a gate can be 50+ m from its map pin).
  static const double arriveRadiusM = 150;

  /// Close enough to tell the customer "your driver is nearby".
  static const double nearbyRadiusM = 1000;

  /// A position older than this is not "live" any more.
  static const Duration freshFor = Duration(minutes: 3);

  /// Straight-line distance in metres (haversine).
  static double distanceM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180;

  /// Rough minutes to cover [metres] by road: roads wind (×1.35 over the
  /// straight line) and town traffic averages ~25 km/h. An honest estimate,
  /// always shown with "about" — there is no routing service behind it.
  static int etaMinutes(double metres) {
    final km = metres * 1.35 / 1000;
    return math.max(1, (km / 25 * 60).round());
  }

  /// "450 m" / "3.2 km".
  static String distanceLabel(double metres) => metres < 1000
      ? '${(metres / 10).round() * 10} m'
      : '${(metres / 1000).toStringAsFixed(1)} km';

  /// The live line everyone reads, from the order status, the driver stage,
  /// and (optionally) how far the driver is from the drop-off.
  ///
  /// [isPackage] says "pickup" instead of "restaurant" — a package job is
  /// collected from an address, not a shop.
  static String liveLabel(
    String status,
    String? stage, {
    bool isPackage = false,
    double? metresToDropoff,
  }) {
    final place = isPackage ? 'the pickup' : 'the restaurant';
    switch (status) {
      case OrderStatus.confirmed:
        return stage == DriverStage.atPickup
            ? 'Driver waiting at $place'
            : 'Driver on the way to $place';
      case OrderStatus.pickedUp:
        return 'Order picked up';
      case OrderStatus.inTransit:
        if (stage == DriverStage.atDropoff) return 'Driver has arrived';
        if (metresToDropoff != null && metresToDropoff <= nearbyRadiusM) {
          return 'Driver is nearby';
        }
        return 'On the way to you';
      default:
        return '';
    }
  }

  /// Whether a driver at ([lat], [lng]) has reached ([toLat], [toLng]).
  static bool hasArrived(double lat, double lng, double? toLat, double? toLng) =>
      toLat != null &&
      toLng != null &&
      distanceM(lat, lng, toLat, toLng) <= arriveRadiusM;
}
