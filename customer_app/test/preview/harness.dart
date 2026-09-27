import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipeast_customer/theme/app_theme.dart';

/// A development instrument, not a test.
///
/// `flutter test` is the only renderer available in this container, so this is
/// how a design gets LOOKED at rather than reasoned about. It rasterises a
/// widget to a PNG in the scratchpad.
///
/// Two things have to be set up by hand or the picture lies:
///
///  1. **The icon font.** `uses-material-design: true` puts MaterialIcons in the
///     app bundle, but not into the test binary's font set — every glyph comes
///     out as a tofu box. It is loaded here straight from the SDK cache.
///  2. **Images.** Asset decoding is genuinely async. Under `pump`'s fake clock
///     the codec never runs, so an `Image.asset` silently renders as empty
///     space. They have to be precached inside `runAsync` first.
///
/// Figtree needs no work here: it is a bundled asset now, so `google_fonts`
/// resolves it from the bundle instead of failing an HTTP fetch.
///
/// Nothing here is allowed to hardcode a machine: the PNGs land in the
/// package's own git-ignored `build/`, and the icon font is found through
/// `FLUTTER_ROOT`, which `flutter test` exports. A dev instrument that only
/// runs on the machine it was written on is not worth keeping.
final shotDir = '${Directory.current.path}/build/shots';

final _sdkFonts =
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';

/// Device sizes worth checking. `small` is the floor we support.
const phone = Size(412, 892);
const small = Size(320, 568);

/// The pixel ratio every shot is taken at. Named, because `physicalSize` and
/// `padding` both have to agree with it.
const double _dpr = 2.0;

bool _fontsReady = false;

Future<void> _loadIconFont() async {
  if (_fontsReady) return;
  _fontsReady = true;
  final loader = FontLoader('MaterialIcons')
    ..addFont(
      File('$_sdkFonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)),
    );
  await loader.load();
}

/// Rasterise [screen] to `$shotDir/$name.png`.
///
/// [assets] are precached before the frame is captured — pass every image the
/// widget will reach for, or it will photograph as a blank hole.
Future<void> shoot(
  WidgetTester tester,
  Widget screen,
  String name, {
  Size size = phone,
  List<String> assets = const ['assets/brand/rider.png', 'assets/logo.png'],
  Object? args,
}) async {
  final key = GlobalKey();

  tester.view.devicePixelRatio = _dpr;
  tester.view.physicalSize = size * _dpr;
  // `ViewPadding` is in PHYSICAL pixels, so these have to be scaled by the
  // device pixel ratio the way `physicalSize` is. Passing the logical values
  // straight through gave every shot a 19dp status bar instead of 38 — which
  // is not a size any phone has, and it quietly moved every cap up by 19dp.
  tester.view.padding = FakeViewPadding(
    top: 38 * _dpr,
    bottom: 24 * _dpr,
  );
  addTearDown(tester.view.reset);

  await tester.runAsync(_loadIconFont);

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        // '/shot' on top of '/', so a back button renders. The route itself is
        // generated rather than pulled from the `routes` map, because that is
        // the only form that can carry route ARGUMENTS — which is how half
        // these screens receive the order they are describing.
        initialRoute: '/shot',
        routes: {'/': (_) => const SizedBox.shrink()},
        onGenerateRoute: (settings) => settings.name == '/shot'
            ? MaterialPageRoute<void>(
                settings: RouteSettings(name: '/shot', arguments: args),
                builder: (_) => screen,
              )
            : null,
      ),
    ),
  );

  // Decode every asset for real, then let the image stream deliver.
  await tester.runAsync(() async {
    final ctx = key.currentContext!;
    for (final a in assets) {
      try {
        await precacheImage(AssetImage(a), ctx);
      } catch (_) {
        // An asset a particular screen does not use is not an error here.
      }
    }
  });

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 400));

  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: _dpr);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File('$shotDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  // Unmount, so any AnimationController the screen started is disposed. A live
  // ticker at the end of a test is an error, and half these screens animate.
  await tester.pumpWidget(const SizedBox.shrink());
}
