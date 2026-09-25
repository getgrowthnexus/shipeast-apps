/// Currency formatting — JMD, thousands-separated, no decimals (P3-06).
///
/// This replaces four hand-rolled `_formatPrice` copies (cart, checkout,
/// payment, merchant menu). Every one of them was subtly wrong in the same
/// way: they inserted a single separator at the thousands boundary, so
/// 1,234,567 rendered as "1234,567".
///
/// The logic here is ported verbatim from the driver app's `Money`
/// (`driver_app/lib/driver_constants.dart`), which already had it right, so
/// the same amount now renders identically in both apps.
///
/// Pair with `SeType.tabular(...)` at the call site so figures stay aligned.
library;

class Money {
  Money._();

  /// The single place the currency glyph is defined for this app. Changing it
  /// here changes every price, fee, total and earnings figure on every screen.
  /// Must match `Money.symbol` in `driver_app/lib/driver_constants.dart` and
  /// `money()` in `admin_panel/app.js` — the three apps show the same order.
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

  /// Delivery fee for display: free deliveries say so rather than showing
  /// "J$0", which reads like a missing value.
  static String deliveryFee(int fee) => fee == 0 ? 'Free' : format(fee);
}
