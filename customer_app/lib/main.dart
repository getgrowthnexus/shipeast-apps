import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dev/dev_emulators.dart';
import 'package:provider/provider.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'providers/cart_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/merchant_menu_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/order_confirmed_screen.dart';
import 'screens/order_status_screen.dart';
import 'screens/order_history_screen.dart';
import 'screens/overseas_order_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rate_driver_screen.dart';
import 'screens/saved_addresses_screen.dart';
import 'screens/search_screen.dart';
import 'screens/help_support_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/privacy_security_screen.dart';
import 'theme/app_theme.dart';
import 'theme/se_colors.dart';
import 'theme/se_icons.dart';
import 'theme/se_spacing.dart';
import 'theme/se_typography.dart';

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

/// Owned by main so NotificationService can open the order a push refers to
/// from outside the widget tree (P4-03).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  // No-op unless compiled with --dart-define=USE_EMULATORS=true. Must run
  // before the first Firestore read — useFirestoreEmulator throws once the
  // instance has been used.
  await connectToEmulators();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Registers handlers only. The permission prompt is deliberately NOT here —
  // see NotificationService for why spending it on a cold launch is a
  // permanent, unrecoverable loss on iOS.
  //
  // Skipped on web: FCM there needs a service worker and a VAPID key that
  // this project has never registered, so initialise() would throw and take
  // the whole launch down. The local preview is for looking at screens; push
  // is not one of the things it can honestly show.
  if (!kIsWeb) {
    NotificationService.navigatorKey = appNavigatorKey;
    await NotificationService.initialise();
  }
  runApp(const ShipEastApp());
}

class ShipEastApp extends StatelessWidget {
  const ShipEastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'ShipEast',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/welcome': (_) => const WelcomeScreen(),
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const MainShell(),
          '/merchant': (_) => const MerchantMenuScreen(),
          '/cart': (_) => const CartScreen(),
          '/checkout': (_) => const CheckoutScreen(),
          '/payment': (_) => const PaymentScreen(),
          '/order-confirmed': (_) => const OrderConfirmedScreen(),
          '/order-status': (_) => const OrderStatusScreen(),
          '/order-history': (_) => const OrderHistoryScreen(),
          '/overseas-order': (_) => const OverseasOrderScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/rate-driver': (_) => const RateDriverScreen(),
          '/saved-addresses': (_) => const SavedAddressesScreen(),
          '/search': (_) => const SearchScreen(),
          '/help-support': (_) => const HelpSupportScreen(),
          '/notifications': (_) => const NotificationsScreen(),
          '/privacy-security': (_) => const PrivacySecurityScreen(),
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  int _unreadNotifications = 0;
  StreamSubscription<int>? _unreadSub;

  static const List<Map<String, dynamic>> _navItems = [
    {'label': 'Home', 'icon': SeIcons.home, 'active': SeIcons.homeFill},
    {'label': 'Search', 'icon': SeIcons.search, 'active': SeIcons.searchFill},
    {'label': 'Orders', 'icon': SeIcons.orders, 'active': SeIcons.ordersFill},
    {'label': 'Alerts', 'icon': SeIcons.bell, 'active': SeIcons.bellFill},
    {'label': 'Profile', 'icon': SeIcons.user, 'active': SeIcons.userFill},
  ];

  @override
  void initState() {
    super.initState();
    _subscribeUnread();
  }

  void _subscribeUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _unreadSub = FirestoreService.unreadNotificationsCountStream(uid).listen((count) {
      if (mounted) setState(() => _unreadNotifications = count);
    });
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  Widget? _buildCartFab(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (ctx, cart, _) {
        if (cart.cartCount == 0) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => Navigator.pushNamed(ctx, '/cart'),
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              gradient: SeColors.emberGradient,
              shape: BoxShape.circle,
              boxShadow: SeElevation.glow,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Icon(SeIcons.cartFill, color: Colors.white, size: 24),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: SeColors.red500, width: 1.5),
                    ),
                    child: Text(
                      cart.cartCount > 9 ? '9+' : '${cart.cartCount}',
                      textAlign: TextAlign.center,
                      style: SeType.tabular(SeType.inter(9, FontWeight.w800,
                          color: SeColors.red500)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          HomeScreen(),
          SearchScreen(),
          OrderHistoryScreen(),
          NotificationsScreen(),
          ProfileScreen(),
        ],
      ),
      floatingActionButton: _buildCartFab(context),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: SeColors.surface0,
          border: Border(top: BorderSide(color: SeColors.ink200)),
          boxShadow: SeElevation.e2,
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: List.generate(_navItems.length, (i) {
                final active = _selectedIndex == i;
                final isAlerts = _navItems[i]['label'] == 'Alerts';
                final showBadge =
                    isAlerts && _unreadNotifications > 0 && !active;
                final color =
                    active ? SeColors.red500 : SeColors.ink400;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: active
                                    ? SeColors.red50
                                    : Colors.transparent,
                                borderRadius: SeRadius.pill,
                              ),
                              child: Icon(
                                (active
                                    ? _navItems[i]['active']
                                    : _navItems[i]['icon']) as IconData,
                                size: 23,
                                color: color,
                              ),
                            ),
                            if (showBadge)
                              Positioned(
                                top: -2,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: SeColors.red500,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: SeColors.surface0, width: 1.5),
                                  ),
                                  constraints: const BoxConstraints(
                                      minWidth: 16, minHeight: 16),
                                  child: Text(
                                    _unreadNotifications > 9
                                        ? '9+'
                                        : '$_unreadNotifications',
                                    style: SeType.tabular(SeType.inter(
                                        8, FontWeight.w800,
                                        color: Colors.white)),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _navItems[i]['label'] as String,
                          style: SeType.inter(10, FontWeight.w600,
                              color: color),
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
