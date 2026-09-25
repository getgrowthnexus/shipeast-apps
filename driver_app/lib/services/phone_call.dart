import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../driver_constants.dart';
import '../widgets/se_toast.dart';

/// Places a phone call to [phone] through the device dialer.
///
/// This is the driver-side counterpart to the customer app's "call driver"
/// button: when a delivery address is ambiguous the driver needs to reach the
/// customer, and until now nothing on the driver side could. The number is
/// denormalised onto the order as `customerPhone` by the customer app at
/// checkout.
///
/// Shows an honest message rather than failing silently when there is no
/// number (an order placed before `customerPhone` was written) or the platform
/// cannot open a dialer (e.g. the web preview).
Future<void> callPhone(
  BuildContext context,
  String phone, {
  String label = 'Contact',
}) async {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) {
    SeToast.info(context, '$label number not available for this order');
    return;
  }
  // Dial the normalised E.164 form; fall back to the raw string if it did not
  // parse (an unusual number should still be callable).
  final dial = SePhone.dial(trimmed);
  final uri = Uri(scheme: 'tel', path: dial.isEmpty ? trimmed : dial);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    SeToast.error(context, 'Could not start the call');
  }
}
