import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/screens/register_screen.dart';
import 'package:shipeast_customer/theme/app_theme.dart';

final dir = '${Directory.current.path}/build/shots';

void main() {
  testWidgets('signup with the keyboard up', (t) async {
    final key = GlobalKey();
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(824, 1704);
    t.view.padding = const FakeViewPadding(top: 76, bottom: 48);
    t.view.viewInsets = const FakeViewPadding(bottom: 640);
    addTearDown(t.view.reset);

    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
          theme: AppTheme.theme,
          debugShowCheckedModeBanner: false,
          home: const RegisterScreen()),
    ));
    await t.pump(const Duration(milliseconds: 400));

    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await t.runAsync(() async {
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/kbd-signup.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  });
}
