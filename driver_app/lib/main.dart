import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dev/dev_emulators.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/dashboard_host.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/driver_firestore_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _initFirebase() async {
  for (int attempt = 1; attempt <= 5; attempt++) {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      return;
    } catch (e) {
      if (attempt == 5) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
    }
  }
}

/// Registers for push, and asks for the OS permission that goes with it.
///
/// Deliberately NOT awaited before `runApp`. The permission sheet used to be
/// raised over the blank window the OS hands a launching app, because this ran
/// ahead of the first frame; now it lands on the splash screen, which at least
/// says whose app is asking.
Future<void> _initFCM() async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Foreground messages are handled by the active screen
  });
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    await DriverFirestoreService.saveFcmToken(uid);
  }
  FirebaseMessaging.instance.onTokenRefresh.listen((token) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) {
      FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUid)
          .set({'fcmToken': token}, SetOptions(merge: true));
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  // No-op unless compiled with --dart-define=USE_EMULATORS=true. Must run
  // before the first Firestore read — useFirestoreEmulator throws once the
  // instance has been used.
  await connectToEmulators();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // The first frame goes up HERE, before anything that touches the network.
  // This used to sit behind a push-permission prompt and a Firestore read of
  // the driver's approval status, both awaited, so a cold start on a weak
  // signal showed an empty OS window for as long as the round trip took.
  // SplashScreen owns that wait now and looks like the product while it runs.
  runApp(const ShipEastDriverApp());

  // Skipped on web: FCM there needs a service worker and a VAPID key that
  // this project has never registered, so requestPermission/getToken would
  // throw and take the whole launch down. The local preview is for looking at
  // screens; push is not one of the things it can honestly show.
  if (!kIsWeb) unawaited(_initFCM());
}

class ShipEastDriverApp extends StatelessWidget {
  const ShipEastDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShipEast Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      // The SEDS driver UI is designed light-first — every screen hardcodes the
      // warm light surfaces (surface50 background) while shared widgets like
      // SeCard and the input fields pull their fill from the ACTIVE theme's
      // colorScheme.surface / inputDecorationTheme. A device in dark mode was
      // therefore rendering dark cards (#201E1A) and dark input fields
      // (#2A2823) behind light scaffolds — the "black everywhere" the user saw.
      //
      // themeMode.light alone should prevent this, but to make a dark surface
      // STRUCTURALLY IMPOSSIBLE (OEM quirks, a future regression, a stray
      // Theme() override) we hand BOTH theme slots the light ThemeData. There
      // is no dark design in this app, so there is nothing to lose.
      darkTheme: AppTheme.theme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
      routes: {
        '/welcome': (_) => const WelcomeScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/dashboard': (_) => const DriverShell(),
      },
    );
  }
}
