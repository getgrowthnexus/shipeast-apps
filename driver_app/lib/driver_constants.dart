/// Shared driver-app constants and formatters.
///
/// Audit §7.12 flagged the 10% commission rate hardcoded in five separate
/// places, and §7.13 flagged `_formatPrice`/`_formatEarnings` copy-pasted into
/// five screens. Both now live here so a rate change is a one-line edit and
/// every money value on screen formats identically.
library;

class DriverPay {
  DriverPay._();

  /// Share of an order total the driver keeps.
  static const double commissionRate = 0.10;

  /// Driver's cut of [orderTotal].
  static double commissionOn(num orderTotal) =>
      orderTotal.toDouble() * commissionRate;

  /// What the driver was actually paid for [order].
  ///
  /// Prefers `driverCommission`, written by the server at delivery (P3-04),
  /// and falls back to the local estimate only for orders delivered before
  /// that field existed. Use this anywhere a *completed* delivery is shown;
  /// [commissionOn] is for estimating a job not yet taken.
  static double creditedOn(Map<String, dynamic> order) {
    final credited = (order['driverCommission'] as num?)?.toDouble();
    return credited ?? commissionOn((order['total'] as num?) ?? 0);
  }

  /// Commission expressed for UI copy, e.g. "10%".
  static String get commissionLabel =>
      '${(commissionRate * 100).toStringAsFixed(0)}%';
}

/// Currency formatting — JMD, thousands-separated, no decimals.
///
/// Pair with `SeType.tabular(...)` at the call site so figures stay aligned.
class Money {
  Money._();

  /// The single place the currency glyph is defined for this app. Must match
  /// `Money.symbol` in `customer_app/lib/utils/money.dart` and `money()` in
  /// `admin_panel/app.js` — the three apps show the same order.
  static const String symbol = 'J\$';

  /// `12345.6` → `J$12,346`
  static String format(num? value) => '$symbol${plain(value)}';

  /// `12345.6` → `12,346` (no symbol, for when the unit is shown separately).
  static String plain(num? value) {
    final rounded = (value ?? 0).round();
    final digits = rounded.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}$buf';
  }
}

/// Phone-number formatting — one Jamaican format everywhere (client request:
/// `1-876-111-1111` throughout all apps). Kept next to `Money` for the same
/// reason: one definition, identical output on every screen and in all three
/// apps. Mirror any change in `customer_app/lib/utils/phone.dart` and the
/// admin panel's `phone()` helper.
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
  /// The dialer, not the human, reads this, so it stays punctuation-free.
  static String dial(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 7) d = '876$d';
    if (d.length == 10) d = '1$d';
    return d.isEmpty ? raw.trim() : '+$d';
  }
}
