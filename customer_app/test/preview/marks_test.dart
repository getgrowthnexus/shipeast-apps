import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/screens/login_screen.dart';
import 'package:shipeast_customer/screens/register_screen.dart';
import 'package:shipeast_customer/screens/welcome_screen.dart';

import 'harness.dart';

/// The user's handset: 412 x 852dp with a 38dp status bar. Shooting at any
/// other size makes the annotated screenshots unusable as a ruler.
const device = Size(412, 852);
const floor = Size(320, 568);
const mid = Size(360, 640);

void main() {
  testWidgets('m-welcome',
      (t) async => shoot(t, const WelcomeScreen(), 'm-welcome', size: device));
  testWidgets('m-login',
      (t) async => shoot(t, const LoginScreen(), 'm-login', size: device));
  testWidgets('m-signup',
      (t) async => shoot(t, const RegisterScreen(), 'm-signup', size: device));

  testWidgets('s-welcome',
      (t) async => shoot(t, const WelcomeScreen(), 's-welcome', size: floor));
  testWidgets('s-login',
      (t) async => shoot(t, const LoginScreen(), 's-login', size: floor));
  testWidgets('s-signup',
      (t) async => shoot(t, const RegisterScreen(), 's-signup', size: floor));
  testWidgets('mid-welcome',
      (t) async => shoot(t, const WelcomeScreen(), 'mid-welcome', size: mid));
  testWidgets('mid-signup',
      (t) async => shoot(t, const RegisterScreen(), 'mid-signup', size: mid));
}
