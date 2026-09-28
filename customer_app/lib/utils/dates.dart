/// Date and time formatting — one format app-wide (client checklist, Sep 2026:
/// "Date format through the app should be July 31, 2026").
///
/// No `intl` dependency: English month names and a 12-hour clock are all the
/// app shows, and every caller goes through here so the format cannot drift.
library;

class SeDate {
  SeDate._();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  /// `July 31, 2026`
  static String long(DateTime dt) {
    final d = dt.toLocal();
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// `6:42 PM`
  static String clock(DateTime dt) {
    final d = dt.toLocal();
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final mm = d.minute.toString().padLeft(2, '0');
    return '$h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// `July 31, 2026 · 6:42 PM`
  static String longWithTime(DateTime dt) => '${long(dt)} · ${clock(dt)}';
}
