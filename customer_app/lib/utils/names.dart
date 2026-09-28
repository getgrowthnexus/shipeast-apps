/// Person names in Title Case — "chris brown" → "Chris Brown" (client
/// checklist, Sep 2026: "This should be for the whole app").
///
/// Applied when a name is saved (register, Google sign-in, profile edit, the
/// copy onto an order) and when one is shown, so names stored before this
/// change read correctly too.
library;

class SeName {
  SeName._();

  /// Capitalises each word, including the parts of `Mary-Jane` and `O'Brien`.
  /// A word typed in mixed case (`McDonald`, `DeShawn`) is left exactly as
  /// typed — the person meant it. Runs of spaces collapse to one.
  static String title(String? raw) {
    if (raw == null) return '';
    final words = raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.map(_word).join(' ');
  }

  static String _word(String w) {
    final mixed = w != w.toLowerCase() && w != w.toUpperCase();
    if (mixed) return w;
    final lower = w.toLowerCase();
    final buf = StringBuffer();
    var start = true;
    for (final ch in lower.split('')) {
      buf.write(start ? ch.toUpperCase() : ch);
      start = ch == '-' || ch == "'" || ch == '’';
    }
    return buf.toString();
  }
}
