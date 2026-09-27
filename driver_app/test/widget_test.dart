import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_driver/main.dart';

/// The launch path, end to end.
///
/// This file used to hold `expect(true, isTrue)` under a comment blaming
/// SharedPreferences, which the app does not use. It was untestable for a real
/// reason, though: `main()` resolved the driver's approval status before
/// `runApp`, so there was no widget tree to pump without a live Firebase.
///
/// There is one now. The splash owns that lookup and guards it, precisely so a
/// launch cannot hang on a Firebase that is not there — which is the same
/// property that makes it pumpable here. If someone removes that guard, this
/// test is what tells them what else they broke.
void main() {
  testWidgets('a cold start shows the splash, then lands on welcome',
      (tester) async {
    await tester.pumpWidget(const ShipEastDriverApp());

    // Frame one is the brand, not an empty window. The wordmark is one
    // `Text.rich` in two tones, so it matches as the whole string.
    expect(find.text('ShipEast'), findsOneWidget);
    expect(find.text('DRIVER'), findsOneWidget);
    expect(find.text('COURIERS & DELIVERY · JAMAICA'), findsOneWidget);

    // With no signed-in driver — and no Firebase to ask — the hold expires and
    // the app opens on the one screen that needs nothing from the network.
    await tester.pump(const Duration(seconds: 3));
    // Frames, not `pumpAndSettle`. The courier mark on the welcome screen idles
    // forever by design, so there is no settled state to wait for — settling is
    // how this test hangs rather than how it passes.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Apply to drive'), findsOneWidget);
    expect(find.textContaining('Already driving with us?'), findsOneWidget);

    // Unmount, or that idle ticker is still running when the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
