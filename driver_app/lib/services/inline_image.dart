import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Photos stored inside Firestore as `data:` URLs.
///
/// This project is on Firebase's free Spark plan, which has no Cloud Storage
/// bucket, so every `FirebaseStorage` upload fails. Merchant and menu photos
/// already moved to this approach (commit 282b117); driver photos follow it.
/// Callers downscale at pick time (`ImagePicker(maxWidth, imageQuality)`), and
/// [encode] refuses anything that would not fit comfortably under Firestore's
/// 1 MiB document limit once base64-encoded.
class InlineImage {
  InlineImage._();

  /// Raw bytes allowed per photo. base64 grows it by a third, so ~700 KB
  /// becomes ~930 KB — still under the 1 MiB cap with room for the fields
  /// stored beside it.
  static const int maxBytes = 700 * 1024;

  /// Picker settings for document photos: sharp enough to read a licence.
  static const double docMaxWidth = 1280;
  static const int docQuality = 70;

  /// Picker settings for a profile photo, which is shown small.
  static const double avatarMaxWidth = 400;
  static const int avatarQuality = 75;

  /// The photo as a `data:image/jpeg;base64,…` URL.
  static Future<String> encode(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw const InlineImageTooLarge();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  /// Bytes of a `data:` URL, or null for anything else or a broken one.
  static Uint8List? decode(String? url) {
    if (url == null || !url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  /// An image provider for either kind of URL: a stored `data:` photo, or an
  /// older `http(s)` link. Null when there is nothing to show.
  static ImageProvider? provider(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final bytes = decode(url);
      return bytes == null ? null : MemoryImage(bytes);
    }
    return NetworkImage(url);
  }
}

class InlineImageTooLarge implements Exception {
  const InlineImageTooLarge();

  @override
  String toString() =>
      'That photo is too large. Try again a little further away, or in better light.';
}
