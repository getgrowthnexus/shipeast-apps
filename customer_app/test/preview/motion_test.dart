import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/screens/welcome_screen.dart';
import 'package:shipeast_customer/theme/app_theme.dart';

final dir = '${Directory.current.path}/build/shots';

void main() {
  testWidgets('rider idles', (t) async {
    final key = GlobalKey();
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(824, 1704);
    t.view.padding = const FakeViewPadding(top: 76, bottom: 48);
    addTearDown(t.view.reset);

    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
          theme: AppTheme.theme,
          debugShowCheckedModeBanner: false,
          home: const WelcomeScreen()),
    ));
    await t.runAsync(() async {
      await precacheImage(
          const AssetImage('assets/brand/rider.png'), key.currentContext!);
    });

    Future<void> shot(String name) async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await b.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await t.pump();
    await shot('motion-a'); // t = 0, bike down
    await t.pump(const Duration(milliseconds: 1250));
    await shot('motion-b'); // t = 1, bike up
    await t.pumpWidget(const SizedBox.shrink());
  });
}
