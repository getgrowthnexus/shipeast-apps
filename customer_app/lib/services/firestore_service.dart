import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/order_status.dart';
import '../models/order_type.dart';
import '../models/overseas_inquiry.dart';
import '../models/package_pricing.dart';
import '../models/promo_code.dart';
import '../models/promo_eligibility.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ─── Merchants ───────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> merchantsByCategory(String category) =>
      _db
          .collection('merchants')
          .where('category', isEqualTo: category)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());

  static Stream<List<Map<String, dynamic>>> allMerchantsStream() =>
      _db.collection('merchants').snapshots().map((s) =>
          s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());

  static Stream<List<Map<String, dynamic>>> menuItemsStream(String merchantId) =>
      _db
          .collection('merchants')
          .doc(merchantId)
          .collection('menuItems')
          .snapshots()
          .map((s) =>
              s.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList());

  // ─── Orders ──────────────────────────────────────────────────────────────────

  static Future<String> placeOrder({
    required String merchantId,
    required String merchantName,
    required List<Map<String, dynamic>> items,
    required int subtotal,
    required int deliveryFee,
    required int serviceFee,
    required int total,
    required String paymentMethod,
    required String deliveryAddress,
    int discount = 0,
    String? promoCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // P3-02. Before this, a discounted order recorded only the final `total`
    // with no field explaining the gap, so `subtotal + fees != total` on every
    // one of them and nothing could reconcile. Asserting here means a
    // mis-computed total fails loudly at the call site instead of becoming a
    // permanently un-reconcilable order document.
    //
    // Security rules enforce the same equation on create (P2-01), so this is
    // the friendly local copy of a check that is authoritative on the server.
    final expected = subtotal + deliveryFee + serviceFee - discount;
    if (expected != total) {
      throw StateError(
        'Order does not reconcile: subtotal($subtotal) + deliveryFee($deliveryFee) '
        '+ serviceFee($serviceFee) - discount($discount) = $expected, '
        'but total is $total.',
      );
    }

    String customerName = '';
    String customerPhone = '';
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      customerName = doc.data()?['name'] as String? ?? '';
      // The driver needs a number to reach the customer when a delivery
      // address is ambiguous. Nothing wrote it before, so the driver app had
      // no one to call — the customer could call the driver but never the
      // reverse. Read from the same profile doc we already fetch for the name.
      customerPhone = doc.data()?['phone'] as String? ?? '';
    } catch (_) {}

    // Denormalise the merchant's street address onto the order. A food order
    // never carried a pickup address, so the driver's new-order and pickup
    // screens showed '—' for where to collect — they only had the shop name.
    // The address lives solely on the merchant document; copy it here into the
    // same `merchantAddr` field a package order already uses, so the one driver
    // reader works for both kinds of job.
    String merchantAddr = '';
    // Pickup coordinates, denormalised so the driver app can rank incoming
    // offers by how near the pickup is (nearest-first dispatch). Null when the
    // merchant has no coordinates, which the driver app treats as "distance
    // unknown" and falls back to arrival order — never a gate.
    double? pickupLat;
    double? pickupLng;
    try {
      final m = await _db.collection('merchants').doc(merchantId).get();
      merchantAddr = m.data()?['address'] as String? ?? '';
      pickupLat = (m.data()?['lat'] as num?)?.toDouble();
      pickupLng = (m.data()?['lng'] as num?)?.toDouble();
    } catch (_) {}

    final ref = await _db.collection('orders').add({
      'customerId': user.uid,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'merchantId': merchantId,
      'merchantName': merchantName,
      'merchantAddr': merchantAddr,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'items': items
          .map((i) => {
                'name': i['name'],
                'price': i['price'],
                'quantity': i['quantity'],
              })
          .toList(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'serviceFee': serviceFee,
      'discount': discount,
      'promoCode': promoCode,
      'total': total,
      'paymentMethod': paymentMethod,
      'status': OrderStatus.pending,
      // P5-01. Every order now declares what kind it is. Without it a package
      // job is indistinguishable from a food delivery in the driver's queue
      // and in analytics, and the admin's type filter has nothing to filter on.
      'type': OrderType.food,
      'deliveryAddress': deliveryAddress,
      'createdAt': FieldValue.serverTimestamp(),
      'driverId': null,
      'rated': false,
    });
    return ref.id;
  }

  // ─── Packages (P5-01) ────────────────────────────────────────────────────────

  /// Reads the admin-editable pricing document.
  ///
  /// Returns `null` when it is missing or unreadable, which the caller must
  /// treat as "packages are not priced" rather than as free delivery. The
  /// document is world-readable (P2-01) because the customer app has to show
  /// the fee before sign-in.
  static Future<PackagePricing?> packagePricing() async {
    try {
      final snap = await _db.collection('settings').doc('pricing').get();
      return PackagePricing.fromSettings(snap.data());
    } catch (_) {
      // A read failure is not a price of zero.
      return null;
    }
  }

  /// Places a package delivery as a real order.
  ///
  /// A package job has no merchant and no goods — only work — so `subtotal` is
  /// 0, `deliveryFee` carries the weight-band rate and `serviceFee` carries the
  /// packing surcharge. `merchantId` is null and the pickup address travels in
  /// `merchantAddr`, which is the field the driver app already reads to reach a
  /// collection point.
  ///
  /// It then runs the ordinary `pending → delivered` lifecycle, so drivers and
  /// the admin handle it with the machinery that already exists rather than a
  /// parallel one that would need its own rules, its own triggers and its own
  /// bugs.
  static Future<String> placePackageOrder({
    required String itemCategory,
    required String pickupAddress,
    required String deliveryAddress,
    required double weightKg,
    required bool packingRequired,
    required String instructions,
    required PackageQuote quote,
    required String paymentMethod,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Same guard as placeOrder: rules recompute this server-side, and a write
    // that fails it disappears with the form still showing success — which is
    // precisely the defect P5-01 exists to remove.
    final expected = quote.subtotal + quote.deliveryFee + quote.serviceFee;
    if (expected != quote.total) {
      throw StateError(
        'Package order does not reconcile: deliveryFee(${quote.deliveryFee}) '
        '+ serviceFee(${quote.serviceFee}) = $expected, '
        'but total is ${quote.total}.',
      );
    }

    String customerName = '';
    String customerPhone = '';
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      customerName = doc.data()?['name'] as String? ?? '';
      customerPhone = doc.data()?['phone'] as String? ?? '';
    } catch (_) {}

    final ref = await _db.collection('orders').add({
      'customerId': user.uid,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'type': OrderType.package,
      // There is no merchant. Writing a placeholder id would put a package job
      // into that merchant's order count and its analytics.
      'merchantId': null,
      'merchantName': 'Package pickup',
      'merchantAddr': pickupAddress,
      'items': const <Map<String, dynamic>>[],
      'subtotal': quote.subtotal,
      'deliveryFee': quote.deliveryFee,
      'serviceFee': quote.serviceFee,
      'discount': 0,
      'promoCode': null,
      'total': quote.total,
      'paymentMethod': paymentMethod,
      'status': OrderStatus.pending,
      'deliveryAddress': deliveryAddress,
      'package': {
        'itemCategory': itemCategory,
        'pickupAddress': pickupAddress,
        'weightKg': weightKg,
        'weightBand': quote.bandLabel,
        'packingRequired': packingRequired,
        'instructions': instructions,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'driverId': null,
      'rated': false,
    });
    return ref.id;
  }

  // ─── Cancellation (P5-03) ────────────────────────────────────────────────────

  /// Cancels a pending order on the customer's behalf.
  ///
  /// The customer app has always rendered a "Cancelled" tab and a cancelled
  /// badge that no customer action could ever produce (audit §15). This is that
  /// action.
  ///
  /// The four fields written here are exactly the set rules permit a customer
  /// to touch, and only from `pending` — see `customerCancelling()` in
  /// firestore.rules. Anything else in this map makes the whole write fail, so
  /// do not add a convenience field without changing the rule with it.
  ///
  /// Refunds: orders are cash-on-delivery only today, so cancelling costs
  /// nothing and there is nothing to return. When card payments land, a refund
  /// must be issued from here — see SCHEMA.md §orders.cancellation.
  static Future<void> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'status': OrderStatus.cancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'customer',
      'cancellationReason': reason,
    });
  }

  // ─── Overseas enquiries ──────────────────────────────────────────────────────

  /// Files a request for an overseas shipment quote.
  ///
  /// Overseas ordering was a WebView pointed at two placeholder form URLs. When
  /// both failed — which is what a placeholder URL does — the customer got
  /// "Connection Error" and their request was lost. Then it was an email-only
  /// waitlist, which recorded that somebody was interested but not what they
  /// wanted to send. This records the request itself, in a shape an operator
  /// can price and reply to.
  ///
  /// Returns the new document id so the screen can quote it back.
  static Future<String> submitOverseasInquiry(OverseasInquiryDraft draft) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Validated here as well as in the form. The form is the only caller
    // today; this is what stops the *next* caller filing an enquiry nobody
    // can act on, and it is cheaper than discovering it in the panel.
    final errors = draft.errors();
    if (errors.isNotEmpty) {
      throw ArgumentError('Overseas enquiry is incomplete: ${errors.keys.join(', ')}');
    }

    final ref = await _db.collection('overseasInquiries').add({
      ...draft.toFirestore(
        // Rules pin this to the caller. Without it the collection would be a
        // write target attributable to anyone, for anyone holding the (public,
        // necessarily public) API key.
        customerId: user.uid,
        customerName: user.displayName ?? draft.recipientName,
      ),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// The caller's own enquiries, newest first.
  ///
  /// Sorted client-side for the same reason [orderHistoryStream] is: an
  /// `orderBy` alongside the `customerId` equality needs a composite index, and
  /// a missing index fails the query outright rather than degrading.
  static Stream<List<OverseasInquiry>> myOverseasInquiriesStream(String uid) =>
      _db
          .collection('overseasInquiries')
          .where('customerId', isEqualTo: uid)
          .snapshots()
          .map((s) {
            final list = s.docs
                .map((d) => OverseasInquiry.fromMap(d.id, d.data()))
                .toList();
            list.sort((a, b) {
              final at = a.createdAt ?? DateTime(0);
              final bt = b.createdAt ?? DateTime(0);
              return bt.compareTo(at);
            });
            return list;
          });

  static Stream<List<Map<String, dynamic>>> orderHistoryStream(String uid) =>
      _db
          .collection('orders')
          .where('customerId', isEqualTo: uid)
          .snapshots()
          .map((s) {
            final docs = s.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList();
            docs.sort((a, b) {
              final at = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
              final bt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
              return bt.compareTo(at);
            });
            return docs;
          });

  static Stream<Map<String, dynamic>?> watchOrder(String orderId) =>
      _db
          .collection('orders')
          .doc(orderId)
          .snapshots()
          .map((s) =>
              s.exists ? <String, dynamic>{'id': s.id, ...s.data()!} : null);

  static Stream<Map<String, dynamic>?> watchDriver(String driverId) =>
      _db.collection('drivers').doc(driverId).snapshots().map(
          (s) => s.exists ? <String, dynamic>{'id': s.id, ...s.data()!} : null);

  // ─── Addresses ───────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> addressStream(String uid) =>
      _db
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .snapshots()
          .map((s) {
            final docs = s.docs
                .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                .toList();
            docs.sort((a, b) {
              final at = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
              final bt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
              return at.compareTo(bt);
            });
            return docs;
          });

  static Future<List<Map<String, dynamic>>> getAddressesOnce(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('addresses').get();
    return _sortedAddresses(snap.docs);
  }

  static List<Map<String, dynamic>> _sortedAddresses(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final list =
        docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
    list.sort((a, b) {
      final at = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      final bt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
      return at.compareTo(bt);
    });
    return list;
  }

  static Future<void> addAddress(String uid, String label, String text) =>
      _db.collection('users').doc(uid).collection('addresses').add({
        'label': label,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> updateAddress(
          String uid, String addressId, String label, String text) =>
      _db
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .doc(addressId)
          .update({'label': label, 'text': text});

  static Future<void> deleteAddress(String uid, String addressId) =>
      _db
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .doc(addressId)
          .delete();

  // ─── User Profile ────────────────────────────────────────────────────────────

  static Stream<Map<String, dynamic>?> watchUserProfile(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((s) =>
          s.exists ? <String, dynamic>{'id': s.id, ...s.data()!} : null);

  // ─── Rating ──────────────────────────────────────────────────────────────────

  /// Previews a promo code without consuming a use (P3-03).
  ///
  /// Advisory only — the discount actually applied to the order comes from
  /// [redeemPromo]. This exists so the customer sees the saving immediately
  /// instead of waiting on a function cold start, and it enforces the full rule
  /// set (expiry, usage cap, minimum) rather than the two checks it used to.
  ///
  /// The PR-5 context ([merchantId], [merchantCategory], [deliveryArea],
  /// [orderKind], [deliveryFee]) is optional and additive: a caller that
  /// passes none of it still gets a correct preview for any code with no
  /// `eligibility` rules — every code created before PR-5. When it *is*
  /// passed, an ineligible code previews as rejected with the reason the
  /// customer would actually hit at redemption, not a generic "invalid code".
  static Future<PromoResult> previewPromoCode(
    String code,
    int subtotal, {
    String? merchantId,
    String? merchantCategory,
    String? deliveryArea,
    OrderKind orderKind = OrderKind.food,
    int deliveryFee = 0,
  }) async {
    try {
      final doc =
          await _db.collection('promoCodes').doc(code.trim().toUpperCase()).get();
      final data = doc.exists ? doc.data() : null;
      if (data != null) {
        final elig = PromoEligibility.fromMap(
          data['eligibility'] as Map<String, dynamic>?,
        );
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final check = checkEligibility(
          elig,
          EligibilityContext(
            customerId: uid,
            // Best-effort preview: an exact prior-order count needs a query
            // this preview intentionally skips (see redeemPromo's own
            // priorOrderCount, which IS authoritative). `0` under-restricts a
            // "new customer" code here in the rare case the preview is wrong,
            // which only means the customer finds out at redemption instead
            // of at code entry — never the reverse.
            priorOrderCount: 0,
            merchantId: merchantId,
            merchantCategory: merchantCategory,
            deliveryArea: deliveryArea,
            orderKind: orderKind,
          ),
        );
        if (!check.eligible) {
          return PromoResult.rejected(
            PromoRejection.ineligible,
            check.displayMessage ?? 'That promo code does not apply here.',
          );
        }
        return PromoCodes.evaluate(
          data,
          subtotal,
          DateTime.now(),
          discountBaseAmount(elig, subtotal, deliveryFee),
        );
      }
      return PromoCodes.evaluate(null, subtotal, DateTime.now());
    } catch (_) {
      // A read failure is not the same as a bad code, and must not be reported
      // as one.
      rethrow;
    }
  }

  /// Consumes one use of [code] and returns the authoritative discount.
  ///
  /// Called at order placement, not at code entry — a customer who types a code
  /// and abandons checkout must not burn a use. Throws when the code is
  /// rejected; the message is safe to show.
  ///
  /// The PR-5 context fields mirror [previewPromoCode]'s — all optional, all
  /// re-checked server-side against freshly read state regardless of what is
  /// sent here (redeemPromo.ts). Sending none of it is safe for a code with
  /// no `eligibility` rules; it is not a way to bypass one that has them.
  static Future<int> redeemPromo(
    String code,
    int subtotal, {
    String? merchantId,
    String? merchantCategory,
    String? deliveryAddress,
    OrderKind orderKind = OrderKind.food,
    int deliveryFee = 0,
  }) async {
    final callable = FirebaseFunctions.instance.httpsCallable('redeemPromo');
    final result = await callable.call<Map<String, dynamic>>({
      'code': code.trim().toUpperCase(),
      'subtotal': subtotal,
      if (merchantId != null) 'merchantId': merchantId,
      if (merchantCategory != null) 'merchantCategory': merchantCategory,
      if (deliveryAddress != null) 'deliveryAddress': deliveryAddress,
      'orderKind': _orderKindWire(orderKind),
      'deliveryFee': deliveryFee,
    });
    return (result.data['discount'] as num?)?.toInt() ?? 0;
  }

  static String _orderKindWire(OrderKind k) => switch (k) {
        OrderKind.food => 'food',
        OrderKind.package => 'package',
        OrderKind.shopDeliver => 'shop_deliver',
      };

  /// Submits a rating for a delivered order.
  ///
  /// [merchantRating] is nullable on purpose: an unrated merchant must send
  /// `null`, never a default. The caller used to substitute 5 stars when the
  /// customer skipped that question, which was harmless while nothing counted
  /// merchant ratings and would now silently inflate every merchant's average.
  ///
  /// The driver is read from the order server-side rather than passed in — the
  /// caller does not get to decide who receives the rating.
  static Future<void> submitRating({
    required String orderId,
    required int driverRating,
    int? merchantRating,
    required String comment,
    required List<String> tags,
  }) async {
    if (orderId.isEmpty) return;

    /* P3-05. This used to be a client-side transaction that rolled the rating
       up into the driver document — and dropped `merchantRating` on the floor,
       which is why every merchant showed a permanent 5.0.

       It now goes through a callable, because the aggregate fields are
       server-only under the P2-01 rules: a driver who can write their own
       `averageRating` can award themselves five stars. The same function also
       populates `ratingCounts`, the per-star histogram the admin panel has
       been rendering an empty state for. */
    final callable = FirebaseFunctions.instance.httpsCallable('submitRating');
    await callable.call<Map<String, dynamic>>({
      'orderId': orderId,
      'driverRating': driverRating,
      'merchantRating': merchantRating,
      'comment': comment,
      'tags': tags,
    });
  }

  // ─── Avatar ──────────────────────────────────────────────────────────────────

  static Future<String> uploadAvatar(String uid, File file) async {
    final ref = FirebaseStorage.instance.ref('users/$uid/avatar.jpg');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    await _db.collection('users').doc(uid).set(
      {'avatarUrl': url},
      SetOptions(merge: true),
    );
    return url;
  }

  // ─── User Stats ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getUserStats(String uid) async {
    int orderCount = 0;
    double avgRating = 0;
    int savedCount = 0;

    try {
      final ordersSnap = await _db
          .collection('orders')
          .where('customerId', isEqualTo: uid)
          .get();
      orderCount = ordersSnap.docs.length;

      final ratedOrders = ordersSnap.docs
          .where((d) => d.data()['driverRating'] != null)
          .toList();
      if (ratedOrders.isNotEmpty) {
        final total = ratedOrders.fold<int>(
            0, (acc, d) => acc + ((d.data()['driverRating'] as num?)?.toInt() ?? 0));
        avgRating = total / ratedOrders.length;
      }
    } catch (_) {}

    try {
      final addrSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .get();
      savedCount = addrSnap.docs.length;
    } catch (_) {}

    return {
      'orderCount': orderCount,
      'avgRating': avgRating,
      'savedCount': savedCount,
    };
  }

  // ─── Notifications ────────────────────────────────────────────────────────────

  /// The notifications collection grows without bound, so every read here is
  /// capped to the most recent [_notifLimit] — the same shape the admin panel
  /// uses (orderBy createdAt desc, limit). Reading the whole collection on every
  /// snapshot was O(all notifications) and got slower for every user forever.
  static const int _notifLimit = 50;

  static Stream<List<Map<String, dynamic>>> notificationsStream({String? uid}) =>
      _db
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(_notifLimit)
          .snapshots()
          .map((s) {
        final docs = s.docs
            .where((d) {
              final t = d.data()['target'] as String? ?? 'all';
              return t == 'all' || t == 'customers' || (uid != null && t == uid);
            })
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        docs.sort((a, b) {
          final at = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          final bt = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
          return bt.compareTo(at);
        });
        return docs;
      });

  static Future<void> markNotificationsRead(String uid) =>
      _db.collection('users').doc(uid).set(
        {'notificationsReadAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  static Stream<int> unreadNotificationsCountStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().asyncMap((snap) async {
      final readAt = (snap.data()?['notificationsReadAt'] as Timestamp?)?.toDate();
      // Bounded to the most recent [_notifLimit]: the badge only needs "how many
      // recent ones are unread", not a full-collection scan on every profile
      // change. A badge that would read past 50 unread is capped at 50 anyway.
      final notifSnap = await _db
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(_notifLimit)
          .get();
      final unread = notifSnap.docs.where((d) {
        final target = d.data()['target'] as String? ?? 'all';
        if (target != 'all' && target != 'customers' && target != uid) return false;
        if (readAt == null) return true;
        final ts = (d.data()['createdAt'] as Timestamp?)?.toDate();
        if (ts == null) return false;
        return ts.isAfter(readAt);
      }).length;
      return unread;
    });
  }
}
