/// Local preview harness — points the Firebase SDKs at the emulator suite.
///
/// ## Why this is safe to ship in the source tree
///
/// [useEmulators] is a `bool.fromEnvironment` constant, so it is resolved at
/// compile time, not run time. A release APK is built without
/// `--dart-define=USE_EMULATORS=true`, which makes the constant `false` and
/// lets the tree-shaker delete [connectToEmulators] and every call in it
/// outright. There is no flag to flip at run time, no config file to get
/// wrong, and no code path from a shipped build to a developer's machine.
///
/// The second guard is the project id: the local build uses `demo-shipeast`.
/// `demo-` is reserved in the Firebase tooling — the SDKs refuse to fall back
/// to real Google endpoints for such a project. So if the emulator is not
/// running, the app fails to connect rather than quietly finding production.
///
/// Started by `tools/dev-up.sh`. See that script for the ports.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Set by `--dart-define=USE_EMULATORS=true`. False in every real build.
const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');

/// Where the suite is listening. `localhost` is correct for a Flutter web
/// build viewed through a forwarded port; an Android emulator would need
/// `10.0.2.2`, hence the override rather than a hardcoded constant.
const String emulatorHost =
    String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

/// Mirrors the `emulators` block in the repo-root firebase.json.
const int authPort = 9099;
const int firestorePort = 8080;
const int storagePort = 9199;
const int functionsPort = 5001;

/// The Firebase project the local build talks to. Deliberately not the real
/// one — see the library doc.
const String localProjectId = 'demo-shipeast';

bool _connected = false;

/// Redirects every SDK at the emulator suite. Must be called after
/// `Firebase.initializeApp` and before the first read or write:
/// `useFirestoreEmulator` throws once the instance has been used.
Future<void> connectToEmulators() async {
  if (!useEmulators || _connected) return;
  _connected = true;

  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, firestorePort);
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, authPort);
  await FirebaseStorage.instance.useStorageEmulator(emulatorHost, storagePort);
  FirebaseFunctions.instance.useFunctionsEmulator(emulatorHost, functionsPort);

  debugPrint('[dev] Firebase emulators: $emulatorHost ($localProjectId)');
}
