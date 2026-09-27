import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/theme/se_typography.dart';

/// Proves Figtree Black is actually resolving out of `google_fonts/`. If the
/// asset were missing, google_fonts would hand back the 800 it does have (or
/// Roboto) and the two lines would measure the same.
void main() {
  testWidgets('w900 is a different face from w800', (t) async {
    Future<Size> measure(TextStyle s) async {
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: Text('Delivery, done right.', key: key, style: s),
        ),
      ));
      return t.getSize(find.byKey(key));
    }

    final w800 = await measure(SeType.display.copyWith(fontSize: 37));
    final w900 = await measure(SeType.hero(37).copyWith(letterSpacing: -0.7));
    // ignore: avoid_print
    print('w800=$w800  w900=$w900');
    expect(w900.width, isNot(w800.width));
  });
}
