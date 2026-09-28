# iOS status

Both apps are Flutter and target Android **and iOS**, but so far only Android
has been built and shipped. As of 2026-09-28 the iOS side is not ready.

## Missing for either app to run on an iPhone

1. **Firebase iOS registration.** Neither app has an iOS app registered in
   Firebase project `shipeast-1a1f6`: there is no
   `ios/Runner/GoogleService-Info.plist` and no `ios` entry in
   `lib/firebase_options.dart`. Register both bundle IDs in the Firebase
   console (or `flutterfire configure`) before anything else.
2. **Permission strings in `ios/Runner/Info.plist`.** iOS terminates an app
   that requests a permission without a usage description.
   - Location (`geolocator`, foreground only):
     `NSLocationWhenInUseUsageDescription` in both apps. The customer app
     reads its own position to show driver distance; the driver app streams
     GPS to Firestore during an active delivery. `NSLocationAlways…` is not
     needed — nothing tracks in the background.
   - Camera (`image_picker`): `NSCameraUsageDescription` in the driver app
     (delivery proof, profile, licence and vehicle photos). The customer app
     only picks from the gallery today.
   - Photo library: `NSPhotoLibraryUsageDescription` — present in the customer
     app, missing in the driver app.
3. **Push notifications** (`firebase_messaging`): an APNs key uploaded to
   Firebase, and the Push Notifications + Background Modes (remote
   notifications) capabilities in Xcode.
4. **Signing and distribution:** an Apple Developer account, bundle IDs,
   provisioning, and a macOS build machine — a GitHub Actions `macos` runner
   can replace a local Mac. There is no iOS workflow yet; the existing
   workflows build Android APKs only.

## History

The original note (`Pending-for-IOS.md`, location strings only) lived at the
repo root on the old `main` and was dropped when the 2026 redesign was merged;
see tag `archive/main-2026-09-20`.
