import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/screens/coming_soon_screen.dart';
import 'package:shipeast_customer/screens/help_support_screen.dart';
import 'package:shipeast_customer/screens/login_screen.dart';
import 'package:shipeast_customer/screens/order_confirmed_screen.dart';
import 'package:shipeast_customer/screens/order_status_screen.dart';
import 'package:shipeast_customer/screens/payment_screen.dart';
import 'package:shipeast_customer/screens/privacy_security_screen.dart';
import 'package:shipeast_customer/screens/rate_driver_screen.dart';
import 'package:shipeast_customer/screens/register_screen.dart';
import 'package:shipeast_customer/screens/splash_screen.dart';
import 'package:shipeast_customer/screens/welcome_screen.dart';

import 'harness.dart';
import 'previews.dart';

/// Order args, shaped exactly as checkout hands them on.
const _order = {
  'merchantId': 'm1',
  'merchantName': 'Island Grill Morant Bay',
  'items': [
    {'name': 'Curry Goat with Rice & Peas', 'quantity': 2, 'price': 1450},
    {'name': 'Festival (2 pcs)', 'quantity': 1, 'price': 300},
    {'name': 'Ting', 'quantity': 3, 'price': 250},
  ],
  'subtotal': 3850,
  'deliveryFee': 350,
  'serviceFee': 385,
  'discount': 0,
  'total': 4585,
  'deliveryAddress': '14 Yallahs Main Road, St. Thomas',
  'paymentMethod': 'Cash on Delivery',
  'orderId': 'se4821bf90c1',
};

void main() {
  // Screens that touch no Firebase before their first frame: photographed for
  // real, not mirrored.
  testWidgets('welcome', (t) async => shoot(t, const WelcomeScreen(), 'welcome'));
  testWidgets('payment',
      (t) async => shoot(t, const PaymentScreen(), 'payment', args: _order));
  testWidgets(
      'confirmed',
      (t) async => shoot(t, const OrderConfirmedScreen(), 'confirmed',
          args: _order));
  testWidgets(
      'track', (t) async => shoot(t, const OrderStatusScreen(), 'track'));
  testWidgets('rate', (t) async => shoot(t, const RateDriverScreen(), 'rate'));
  testWidgets('help', (t) async => shoot(t, const HelpSupportScreen(), 'help'));
  testWidgets('privacy',
      (t) async => shoot(t, const PrivacySecurityScreen(), 'privacy'));
  testWidgets('coming-soon',
      (t) async => shoot(t, const ComingSoonScreen(title: 'Wallet'), 'coming-soon'));

  // Screens that reach for Firebase in initState: mirrored (see previews.dart).
  testWidgets('home', (t) async => shoot(t, homePreview(), 'home'));
  testWidgets('home-small',
      (t) async => shoot(t, homePreview(), 'home-small', size: small));
  testWidgets('search', (t) async => shoot(t, searchPreview(), 'search'));
  testWidgets('alerts', (t) async => shoot(t, alertsPreview(), 'alerts'));
  testWidgets('orders', (t) async => shoot(t, ordersPreview(), 'orders'));
  testWidgets('profile', (t) async => shoot(t, profilePreview(), 'profile'));
  testWidgets('menu', (t) async => shoot(t, menuPreview(), 'menu'));
  testWidgets('cart', (t) async => shoot(t, cartPreview(), 'cart'));
  testWidgets('checkout', (t) async => shoot(t, checkoutPreview(), 'checkout'));
  testWidgets('overseas', (t) async => shoot(t, overseasPreview(), 'overseas'));
  testWidgets('overseas-small',
      (t) async => shoot(t, overseasPreview(), 'overseas-small', size: small));

  // The five routes the instrument used to miss. Splash, login and register
  // only reach Firebase from a BUTTON, and splash's 2200ms hold outlives the
  // 1300ms of pumps below, so all three photograph for real.
  testWidgets('splash', (t) async => shoot(t, const SplashScreen(), 'splash'));
  testWidgets('login', (t) async => shoot(t, const LoginScreen(), 'login'));
  testWidgets(
      'register', (t) async => shoot(t, const RegisterScreen(), 'register'));
  testWidgets('all-merchants',
      (t) async => shoot(t, allMerchantsPreview(), 'all-merchants'));
  testWidgets('saved-addresses',
      (t) async => shoot(t, savedAddressesPreview(), 'saved-addresses'));

  // States. A screen is not designed until its empty, loading and error faces
  // are designed too.
  testWidgets('all-merchants-loading',
      (t) async => shoot(t, allMerchantsLoadingPreview(), 'all-merchants-loading'));
  testWidgets('all-merchants-empty',
      (t) async => shoot(t, allMerchantsEmptyPreview(), 'all-merchants-empty'));
  testWidgets('saved-addresses-empty',
      (t) async => shoot(t, savedAddressesEmptyPreview(), 'saved-addresses-empty'));
  testWidgets(
      'cart-empty', (t) async => shoot(t, cartEmptyPreview(), 'cart-empty'));
  testWidgets('address-sheet',
      (t) async => shoot(t, addressSheetPreview(), 'address-sheet'));
  testWidgets(
      'toasts', (t) async => shoot(t, toastGalleryPreview(), 'toasts'));
}
