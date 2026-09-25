/// Phone-number formatting — one Jamaican format everywhere (client request:
/// `1-876-111-1111` throughout all apps).
///
/// Ported verbatim from `driver_app/lib/driver_constants.dart` (`SePhone`), the
/// same way `Money` is, so a number renders identically in both apps and in the
/// admin panel's `phone()` helper. Edit all three, or none.
library;

class SePhone {
  SePhone._();

  /// Display form: `1-876-000-0000`. Returns the trimmed input unchanged when
  /// it is not a recognisable 7- or 10-digit local number, so a number typed
  /// in some other shape is never mangled.
  static String format(String? raw) {
    if (raw == null) return '';
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11 && d.startsWith('1')) d = d.substring(1);
    if (d.length == 10) {
      return '1-${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
    }
    if (d.length == 7) {
      return '1-876-${d.substring(0, 3)}-${d.substring(3)}';
    }
    return raw.trim();
  }

  /// `tel:` form — E.164 digits with the country code, e.g. `+18760000000`.
  static String dial(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 7) d = '876$d';
    if (d.length == 10) d = '1$d';
    return d.isEmpty ? raw.trim() : '+$d';
  }
}
