# Pending for iOS

**Status: PENDING — to be done later.**

iOS location configuration for the live delivery-tracking feature has **not** been
done yet. Android is complete; iOS is deferred.

## What's already done (Android)
- `customer_app/android/app/src/main/AndroidManifest.xml` — added
  `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`.
- `driver_app/android/app/src/main/AndroidManifest.xml` — added
  `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`.
- Web preview needs no extra config (localhost/https is a secure context).

## What's still pending (iOS)
Both apps use `geolocator` for live tracking:
- **customer_app** — reads the device's own location to show how far the driver is.
- **driver_app** — streams real GPS to Firestore during an active delivery.

For real iOS device/simulator builds, each app's `ios/Runner/Info.plist` needs a
usage-description string (iOS refuses to prompt for location without one and will
crash on the location request):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>ShipEast uses your location to show live delivery tracking.</string>
```

Notes:
- Foreground use only, so `NSLocationWhenInUseUsageDescription` is sufficient —
  `NSLocationAlwaysAndWhenInUseUsageDescription` is **not** needed (we do not
  track in the background).
- Tailor the customer vs. driver copy if desired (e.g. driver: "…to share your
  live location with the customer during a delivery").
- No API key is involved — there are no map tiles, only coordinates.

## When we do this later
1. Add the key above to `customer_app/ios/Runner/Info.plist`.
2. Add the key (driver-worded) to `driver_app/ios/Runner/Info.plist`.
3. Run `pod install` in each `ios/` dir if needed and test on a device/simulator.
