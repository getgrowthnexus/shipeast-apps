import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../driver_constants.dart';
import '../models/order_status.dart';

class DriverFirestoreService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> setDriverOnline(String uid, bool isOnline) =>
      _db.collection('drivers').doc(uid).set(
        {
          'isOnline': isOnline,
          // `onlineSince` marks when the current online session began, so the
          // dashboard can show "Online since 2:45 PM" (client request). Set on
          // toggle-on; cleared on toggle-off so a stale value never shows.
          'onlineSince':
              isOnline ? FieldValue.serverTimestamp() : FieldValue.delete(),
        },
        SetOptions(merge: true),
      );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> driverStream(
          String uid) =>
      _db.collection('drivers').doc(uid).snapshots();

  static Future<Map<String, dynamic>?> getDriverData(String uid) async {
    final doc = await _db.collection('drivers').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  static Stream<List<Map<String, dynamic>>> pendingOrdersStream() =>
      _db
          .collection('orders')
          .where('status', isEqualTo: OrderStatus.pending)
          .where('driverId', isNull: true)
          .snapshots()
          .map((s) => s.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList());

  /// Stream of the driver's current active order.
  ///
  /// Covers every state in which a driver holds the order. This previously
  /// listed only confirmed and picked_up, so the moment an order moved to
  /// in_transit it dropped out of this query and the driver's dashboard
  /// blanked mid-delivery — with the goods already in their vehicle and no
  /// recovery path in the UI.
  static Stream<List<Map<String, dynamic>>> activeOrderStream(String uid) =>
      _db
          .collection('orders')
          .where('driverId', isEqualTo: uid)
          .where('status', whereIn: OrderStatus.driverHeld)
          .snapshots()
          .map((s) => s.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList());

  /// Thrown when another driver won the race for an order.
  static const String orderTakenCode = 'order-already-taken';

  /// Claims an order for [driverUid].
  ///
  /// Runs in a transaction that aborts if the order already has a driver or has
  /// moved off `pending` — two drivers tapping Accept at the same instant would
  /// otherwise both succeed with a blind `update()`, and the second write would
  /// silently steal the first driver's order.
  ///
  /// Throws [StateError] with [orderTakenCode] when the claim is lost.
  static Future<void> acceptOrder(String orderId, String driverUid) async {
    String driverName = '';
    String driverPhone = '';
    try {
      final doc = await _db.collection('drivers').doc(driverUid).get();
      if (doc.exists) {
        driverName = doc.data()?['name'] as String? ?? '';
        driverPhone = doc.data()?['phone'] as String? ?? '';
      }
    } catch (_) {}

    await _db.runTransaction((tx) async {
      final ref = _db.collection('orders').doc(orderId);
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError(orderTakenCode);

      final data = snap.data() ?? const <String, dynamic>{};
      final existingDriver = data['driverId'];
      final status = data['status'] as String? ?? OrderStatus.pending;
      final claimed = existingDriver != null &&
          (existingDriver as String).isNotEmpty &&
          existingDriver != driverUid;
      if (claimed || status != OrderStatus.pending) {
        throw StateError(orderTakenCode);
      }

      tx.update(ref, {
        'driverId': driverUid,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'status': OrderStatus.confirmed,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> confirmPickup(String orderId) =>
      _db.collection('orders').doc(orderId).update({
        'status': OrderStatus.pickedUp,
        'pickedUpAt': FieldValue.serverTimestamp(),
      });

  /// Marks the driver as en route to the customer.
  ///
  /// This state has never existed in the data. It is what makes the customer's
  /// "On the Way" tracker step reachable — before this, the customer jumped
  /// from "Picked Up" straight to "Delivered" with no signal that the driver
  /// had actually set off.
  static Future<void> startTransit(String orderId) =>
      _db.collection('orders').doc(orderId).update({
        'status': OrderStatus.inTransit,
        'inTransitAt': FieldValue.serverTimestamp(),
      });

  static Future<String> uploadDeliveryPhoto(String orderId, File file) async {
    final ref =
        FirebaseStorage.instance.ref('orders/$orderId/delivery_photo.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Thrown by [confirmDelivery] when the order is not in a state this driver
  /// can complete. The screen maps each code to a message.
  static const String orderMissingCode = 'order-missing';
  static const String notYourOrderCode = 'not-your-order';
  static const String notInTransitCode = 'not-in-transit';

  /// Marks the order delivered and records the commission, transactionally,
  /// returning the amount credited.
  ///
  /// P3-04 originally moved this into the `confirmDelivery` Cloud Function so a
  /// modified client could not pay itself an arbitrary amount: the function
  /// recomputed the commission from the order's *stored* total. That function
  /// needs the Blaze plan and is not deployed on this project, which left every
  /// delivery failing. The same guarantee now lives in the Firestore rules
  /// (`driverDelivering`), which cap `driverCommission` at the order's own
  /// `total` times the rate — the total being immutable. So this writes
  /// directly, but keeps the two properties that mattered:
  ///
  ///   1. the commission is derived from the total read *inside the
  ///      transaction*, never from a cached or caller-supplied figure, and
  ///   2. the rules reject the write if that figure is inflated.
  ///
  /// Idempotent: a retry against an already-delivered order pays nothing extra
  /// and returns what was credited, mirroring the old function's behaviour.
  static Future<int> confirmDelivery(
    String orderId, {
    String? photoUrl,
    String? note,
  }) async {
    final ref = _db.collection('orders').doc(orderId);
    final uid = currentUid;
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError(orderMissingCode);

      final data = snap.data() ?? const <String, dynamic>{};
      if (data['driverId'] != uid) throw StateError(notYourOrderCode);

      final status = data['status'] as String? ?? '';
      if (status == OrderStatus.delivered) {
        // Already done — do not pay twice; report what was credited.
        return (data['driverCommission'] as num?)?.toInt() ??
            DriverPay.commissionOn((data['total'] as num?) ?? 0).round();
      }
      if (status != OrderStatus.inTransit) throw StateError(notInTransitCode);

      final total = (data['total'] as num?)?.toInt() ?? 0;
      final commission = DriverPay.commissionOn(total).round();

      tx.update(ref, {
        'status': OrderStatus.delivered,
        'deliveredAt': FieldValue.serverTimestamp(),
        'driverCommission': commission,
        'commissionRate': DriverPay.commissionRate,
        // Clear the live position: once delivered the driver app can no longer
        // write this order, so a stale coordinate would otherwise linger.
        'driverLoc': FieldValue.delete(),
        if (photoUrl != null && photoUrl.isNotEmpty) 'deliveryPhotoUrl': photoUrl,
        if (note != null && note.isNotEmpty) 'deliveryNote': note,
      });
      return commission;
    });
  }

  static Future<String> uploadProfilePhoto(String uid, File file) async {
    final ref = FirebaseStorage.instance.ref('drivers/$uid/avatar.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Uploads one credential photo for the admin document-review flow (DV-5).
  /// [key] is `licence`, `vehicle`, … and becomes the field name under
  /// `drivers/{uid}.documents`.
  static Future<String> uploadDriverDocument(
      String uid, String key, File file) async {
    final ref = FirebaseStorage.instance.ref('drivers/$uid/documents/$key.jpg');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  static Stream<List<Map<String, dynamic>>> driverOrderHistoryStream(
          String uid) =>
      _db
          .collection('orders')
          .where('driverId', isEqualTo: uid)
          .snapshots()
          .map((s) {
        final docs = s.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        docs.sort((a, b) {
          final at = (a['createdAt'] as Timestamp?)?.toDate() ??
              (a['deliveredAt'] as Timestamp?)?.toDate() ??
              DateTime(0);
          final bt = (b['createdAt'] as Timestamp?)?.toDate() ??
              (b['deliveredAt'] as Timestamp?)?.toDate() ??
              DateTime(0);
          return bt.compareTo(at);
        });
        return docs;
      });

  static Future<void> saveFcmToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.collection('drivers').doc(uid).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }

  static String get currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';
}
