import 'package:geolocator/geolocator.dart';

/// One reading of the phone's own position, for pinning a delivery address
/// (live tracking, Sep 2026). Returns null — never throws — when location is
/// off, permission is refused, or the platform cannot say; callers then keep
/// the typed address without a pin.
abstract final class MyLocation {
  static Future<({double lat, double lng})?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
