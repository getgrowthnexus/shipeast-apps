import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dev/dev_emulators.dart';
import 'theme/app_theme.dart';
import 'theme/se_colors.dart';
import 'theme/se_icons.dart';
import 'theme/se_motion.dart';
import 'theme/se_spacing.dart';
import 'theme/se_typography.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/earnings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/history_screen.dart';
import 'screens/pending_approval_screen.dart';
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

Future<Widget> _resolveHome() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const LoginScreen();
  try {
    final doc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .get();
    if (doc.exists && doc.data()?['status'] == 'approved') {
      return const DriverShell();
    }
  } catch (_) {}
  return const PendingApprovalScreen();
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
  // Skipped on web: FCM there needs a service worker and a VAPID key that
  // this project has never registered, so requestPermission/getToken would
  // throw and take the whole launch down. The local preview is for looking at
  // screens; push is not one of the things it can honestly show.
  if (!kIsWeb) await _initFCM();
  final home = await _resolveHome();
  runApp(ShipEastDriverApp(home: home));
}

class ShipEastDriverApp extends StatelessWidget {
  final Widget home;
  const ShipEastDriverApp({super.key, required this.home});

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
      home: home,
      routes: {
        '/login': (_) => const LoginScreen(),
        '/dashboard': (_) => const DriverShell(),
      },
    );
  }
}

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _selectedIndex = 0;
  final ValueNotifier<String> _driverNameNotifier =
      ValueNotifier<String>('Driver');

  @override
  void initState() {
    super.initState();
    _loadDriverName();
  }

  Future<void> _loadDriverName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        _driverNameNotifier.value =
            doc.data()?['name'] as String? ?? 'Driver';
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _driverNameNotifier.dispose();
    super.dispose();
  }

  static const List<Map<String, dynamic>> _navItems = [
    {'label': 'Home', 'icon': SeIcons.home, 'active': SeIcons.homeFill},
    {'label': 'History', 'icon': SeIcons.history, 'active': SeIcons.history},
    {
      'label': 'Earnings',
      'icon': SeIcons.wallet,
      'active': SeIcons.walletFill
    },
    {'label': 'Profile', 'icon': SeIcons.user, 'active': SeIcons.userFill},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(
            onTabSwitch: (i) => setState(() => _selectedIndex = i),
            driverNameNotifier: _driverNameNotifier,
          ),
          const HistoryScreen(),
          const EarningsScreen(),
          ProfileScreen(driverNameNotifier: _driverNameNotifier),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(top: BorderSide(color: SeColors.ink200, width: 1)),
          boxShadow: SeElevation.e2,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final active = _selectedIndex == i;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedIndex = i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The icon lifts a couple of pixels and swaps to its
                        // filled variant on selection.
                        AnimatedSlide(
                          offset: Offset(0, active ? -0.06 : 0),
                          duration: SeMotion.fast,
                          curve: SeMotion.emphasized,
                          child: Icon(
                            (active
                                ? _navItems[i]['active']
                                : _navItems[i]['icon']) as IconData,
                            size: 24,
                            color: active ? SeColors.red500 : SeColors.ink400,
                          ),
                        ),
                        const SizedBox(height: SeSpacing.x1),
                        Text(
                          _navItems[i]['label'] as String,
                          style: SeType.eyebrow.copyWith(
                            color: active ? SeColors.red500 : SeColors.ink400,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
