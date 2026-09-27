import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/screens/login_screen.dart';
import 'package:shipeast_customer/screens/register_screen.dart';
import 'package:shipeast_customer/screens/welcome_screen.dart';
import 'package:shipeast_customer/theme/app_theme.dart';
import 'package:shipeast_customer/widgets/se_button.dart';
import 'package:shipeast_customer/widgets/se_text_field.dart';

/// The signed-out path is the only part of the app laid out against the
/// viewport rather than poured into a scroll view: a brand cap, a hero and a
/// sheet that divide a fixed height between them. That makes it the one place
/// a small phone — or a keyboard eating half the screen — can push the thing
/// you came for off the bottom of the display.
///
/// These pump the real screens at the extremes and assert on GEOMETRY, which
/// is what survives here: this container cannot rasterise a frame, so
/// paint-time overflow banners never fire and cannot be relied on.
const _tiny = Size(320, 568); // smallest phone still in the wild
const _small = Size(360, 640);
const _large = Size(412, 892);

Future<Size> pumpScreen(
  WidgetTester tester,
  Widget screen,
  Size size, {
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
  addTearDown(tester.view.reset);

  // '/auth' makes Navigator seed the stack as ['/', '/auth'], so the screen
  // under test can pop — which is what its back control checks for.
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.theme,
    debugShowCheckedModeBanner: false,
    initialRoute: '/auth',
    routes: {
      '/': (_) => const SizedBox.shrink(),
      '/auth': (_) => screen,
    },
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  return size;
}

void expectOnScreen(WidgetTester tester, Finder finder, Size screen, String what) {
  final r = tester.getRect(finder);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$what is above the screen');
  expect(r.bottom, lessThanOrEqualTo(screen.height),
      reason: '$what falls off the bottom at ${screen.width}x${screen.height}');
  expect(r.left, greaterThanOrEqualTo(0), reason: '$what is off the left edge');
  expect(r.right, lessThanOrEqualTo(screen.width),
      reason: '$what is off the right edge');
}

void main() {
  group('welcome', () {
    // Nothing on this screen scrolls, so both the action and the small print
    // have to fit on the shortest phone we support.
    for (final size in [_tiny, _small, _large]) {
      testWidgets('CTA and terms sit on screen at ${size.width}x${size.height}',
          (t) async {
        await pumpScreen(t, const WelcomeScreen(), size);
        expectOnScreen(t, find.byType(SeButton), size, 'the primary button');
        expectOnScreen(t, find.textContaining('By continuing'), size,
            'the terms line');
      });
    }
  });

  group('sign in', () {
    for (final size in [_tiny, _small, _large]) {
      testWidgets('first field is reachable at ${size.width}x${size.height}',
          (t) async {
        await pumpScreen(t, const LoginScreen(), size);
        expectOnScreen(t, find.byType(SeTextField).first, size, 'the email field');
      });

      testWidgets('cap collapses for the keyboard at ${size.width}', (t) async {
        await pumpScreen(t, const LoginScreen(), size, keyboard: 300);
        // The subtitle is what the cap drops to make room; if it is still
        // there the hero never collapsed and the fields lose their space.
        expect(find.text('Sign in to pick up where you left off.'), findsNothing);
        expectOnScreen(t, find.byType(SeTextField).first, size, 'the email field');
      });
    }
  });

  group('sign up', () {
    for (final size in [_tiny, _small, _large]) {
      testWidgets('first field is reachable at ${size.width}x${size.height}',
          (t) async {
        await pumpScreen(t, const RegisterScreen(), size);
        expectOnScreen(t, find.byType(SeTextField).first, size, 'the name field');
      });

      testWidgets('cap collapses for the keyboard at ${size.width}', (t) async {
        await pumpScreen(t, const RegisterScreen(), size, keyboard: 300);
        expect(find.text('It takes about a minute — then you can order.'),
            findsNothing);
        expectOnScreen(t, find.byType(SeTextField).first, size, 'the name field');
      });
    }
  });
}
