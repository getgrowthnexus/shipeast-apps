import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/se_toast.dart';

/// Opens turn-by-turn directions in the phone's maps app (Google Maps on
/// Android, and on iOS when installed — otherwise the browser).
///
/// Uses the pin when the order has one; falls back to the typed address,
/// which Google Maps geocodes itself. Live tracking keeps running while the
/// maps app is in front (DriverLocationService's foreground service).
Future<void> openDirections(
  BuildContext context, {
  double? lat,
  double? lng,
  String address = '',
}) async {
  final destination = (lat != null && lng != null)
      ? '$lat,$lng'
      : address.trim();
  if (destination.isEmpty) {
    SeToast.info(context, 'No address or map pin on this order');
    return;
  }
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    'travelmode': 'driving',
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    SeToast.error(context, 'Could not open maps');
  }
}
