import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'dev/dev_emulators.dart' show useEmulators, localProjectId;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // There is no deployed web build of this app and no web app registered
      // in the Firebase project. Web exists solely for the local preview
      // harness (tools/dev-up.sh), which runs everything against emulators.
      //
      // Refusing without the flag is the point: it means a web build can
      // never be pointed at production by accident, because there is no
      // production web config here to point it at.
      if (!useEmulators) {
        throw UnsupportedError(
          'Web builds are for the local emulator preview only. '
          'Run with --dart-define=USE_EMULATORS=true, or see tools/dev-up.sh.',
        );
      }
      return localPreview;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('Firebase is not configured for iOS yet.');
      default:
        throw UnsupportedError(
            'Unsupported platform: $defaultTargetPlatform');
    }
  }

  /// Placeholders, on purpose. Every service is emulated, so none of these
  /// values is ever sent anywhere real — and `demo-` makes the SDKs refuse to
  /// reach live Google endpoints even if one were.
  static const FirebaseOptions localPreview = FirebaseOptions(
    apiKey: 'local-emulator-unused',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: localProjectId,
    storageBucket: '$localProjectId.appspot.com',
    authDomain: 'localhost',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDcETjuHcvmy7TKL7vHW6sYlUk9sxa-6CA',
    appId: '1:783428944628:android:5961a34e4f30c25a5bd4a1',
    messagingSenderId: '783428944628',
    projectId: 'shipeast-1a1f6',
    storageBucket: 'shipeast-1a1f6.firebasestorage.app',
  );
}
