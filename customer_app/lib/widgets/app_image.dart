import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// One image widget for merchant and menu photos.
///
/// Photos are stored directly inside the Firestore document as a base64
/// `data:` URL (no Cloud Storage, so no paid Blaze plan). Older merchants — and
/// anything seeded with a pasted link — still carry a normal `http(s)` URL.
/// This widget renders both transparently so every call site is identical:
///   - `data:`   → decoded once and drawn with [Image.memory]
///   - `http(s)` → [CachedNetworkImage] (network cache, as before)
///   - empty / undecodable → [errorWidget]
class AppImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  /// Shown while a *network* image loads. Embedded images decode instantly, so
  /// they never show it.
  final Widget? placeholder;

  /// Shown for an empty, broken, or undecodable image.
  final Widget? errorWidget;

  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = errorWidget ?? const SizedBox.shrink();
    if (url.isEmpty) return fallback;

    if (url.startsWith('data:')) {
      final bytes = _decode(url);
      if (bytes == null) return fallback;
      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (c, e, s) => fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: placeholder == null ? null : (c, u) => placeholder!,
      errorWidget: (c, u, e) => fallback,
    );
  }

  // Decoded bytes are memoised by their data URL so the SAME Uint8List instance
  // is reused across rebuilds. A fresh decode every build would produce a new
  // MemoryImage each time, miss Flutter's image cache, and re-decode on every
  // scroll frame. Bounded so a long browse session cannot grow it without end.
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};

  static Uint8List? _decode(String dataUrl) {
    final cached = _cache[dataUrl];
    if (cached != null) return cached;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      if (_cache.length > 64) _cache.clear();
      _cache[dataUrl] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
