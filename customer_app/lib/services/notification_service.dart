import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';
import '../widgets/se_toast.dart';

/// Push notifications for the customer app (P4-03).
///
/// `firebase_messaging` was declared in pubspec.yaml and **not one line of the
/// app used it**, so a customer could not receive a push under any
/// circumstance. This mirrors the driver app's working setup, with two
/// deliberate differences, both about the permission prompt.
///
/// **1. Permission is requested contextually, never at launch.** iOS grants
/// exactly one system prompt per install. Spending it during a cold start —
/// before the customer has done anything or has any reason to want push —
/// converts a large share of users into a *permanent* denial that no code
/// change can undo. [maybeRequestAfterOrder] asks once, right after the first
/// order is placed, when "get told when your driver is on the way" is an offer
/// rather than an interruption.
///
/// **2. The token follows the session, not the process.** It is written on
/// sign-in and deleted on sign-out. A shared or resold phone would otherwise
/// keep delivering one customer's order updates — their merchant, their
/// status, their driver — to whoever signs in next.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a separate isolate with no Firebase initialised. Nothing else
  // belongs here: display is the system's job, and any work done here happens
  // while the app is backgrounded and unwatched.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Asked-once flag. Keyed per uid: a second customer on the same device gets
  /// their own prompt rather than inheriting the first one's silence.
  static String _askedKey(String uid) => 'notif_permission_asked_$uid';

  /// Navigator used to open the order a notification refers to. Set by main().
  static GlobalKey<NavigatorState>? navigatorKey;

  static bool _wired = false;

  /// Registers the handlers. Safe at startup — it requests nothing.
  static Future<void> initialise() async {
    if (_wired) return;
    _wired = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // A refreshed token is useless unless it is stored. Tokens rotate on app
    // reinstall, restore-from-backup, and periodically on their own; a client
    // that only saves at sign-in goes quietly unreachable after any of them.
    _fcm.onTokenRefresh.listen((token) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _writeToken(uid, token);
    });

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_openTarget);

    // A push that launched the app from terminated is delivered here and
    // nowhere else — without this, tapping the notification opens the home
    // screen and the customer has to go find the order themselves.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _openTarget(initial);
  }

  /// Call after a successful sign-in or registration.
  ///
  /// Only stores a token if permission already exists. It never prompts:
  /// on iOS, `getToken()` before authorisation returns null anyway, and
  /// prompting here would be the cold-launch mistake in a different costume.
  static Future<void> onSignedIn(String uid) async {
    try {
      final settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await _fcm.getToken();
      if (token != null) await _writeToken(uid, token);
    } catch (_) {
      // Push is an enhancement. Failing to register for it must never block
      // someone from signing in and ordering food.
    }
  }

  /// Call **before** `FirebaseAuth.signOut()`, while the uid is still valid.
  ///
  /// Deleting the FCM token as well as the stored field matters: leaving the
  /// device registered means the server can still reach it through a token it
  /// has not yet learned is stale.
  static Future<void> onSignedOut(String uid) async {
    try {
      await _db.collection('users').doc(uid).set(
        {'fcmToken': FieldValue.delete()},
        SetOptions(merge: true),
      );
    } catch (_) {}
    try {
      await _fcm.deleteToken();
    } catch (_) {}
  }

  /// The contextual prompt — the one chance, spent at the right moment.
  ///
  /// Called once per customer, immediately after their first order. Returns
  /// true if push is authorised afterwards.
  static Future<bool> maybeRequestAfterOrder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final current = await _fcm.getNotificationSettings();
      if (current.authorizationStatus == AuthorizationStatus.authorized ||
          current.authorizationStatus == AuthorizationStatus.provisional) {
        await onSignedIn(uid);
        return true;
      }
      // `denied` is terminal on iOS: re-prompting does nothing but is also
      // never shown, so treat it as answered rather than retrying forever.
      if (current.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey(uid)) == true) return false;
      await prefs.setBool(_askedKey(uid), true);

      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) await onSignedIn(uid);
      return granted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeToken(String uid, String token) async {
    try {
      await _db.collection('users').doc(uid).set(
        {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Android and iOS both suppress the system banner while the app is
  /// foregrounded, so without this the message simply vanishes.
  static void _showForeground(RemoteMessage message) {
    final context = navigatorKey?.currentContext;
    if (context == null) return;
    final body = message.notification?.body ??
        message.data['body'] as String? ??
        message.notification?.title;
    if (body == null || body.isEmpty) return;
    SeToast.info(context, body);
  }

  /// Deep-link where the message points.
  ///
  /// Order status pushes carry an `orderId` (functions/src/notifications.ts).
  /// Broadcasts may carry a `destType` / `destValue` pair (checklist NT-4):
  ///   order  → the order-status screen for that id
  ///   search → the search screen, pre-filled
  ///   screen → a named route, from a short allow-list
  ///   url    → an external browser
  /// Anything unrecognised is ignored — a stale or malformed link must never
  /// throw or land the customer somewhere confusing.
  static void _openTarget(RemoteMessage message) {
    final nav = navigatorKey?.currentState;
    if (nav == null) return;
    final data = message.data;

    final orderId = data['orderId'] as String?;
    if (orderId != null && orderId.isNotEmpty) {
      nav.pushNamed('/order-status',
          arguments: <String, dynamic>{'orderId': orderId});
      return;
    }

    final destType = data['destType'] as String?;
    final destValue = (data['destValue'] as String?)?.trim() ?? '';
    if (destType == null || destValue.isEmpty) return;

    switch (destType) {
      case 'search':
        nav.pushNamed('/search', arguments: <String, dynamic>{'query': destValue});
        break;
      case 'screen':
        const allowed = {
          '/home', '/order-history', '/overseas-order', '/search',
          '/profile', '/notifications', '/saved-addresses',
        };
        if (allowed.contains(destValue)) nav.pushNamed(destValue);
        break;
      case 'url':
        final uri = Uri.tryParse(destValue);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }
}
