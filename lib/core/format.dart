const _months = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];
const _days = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];

/// Formats français sans dépendance externe (pas besoin d'intl).
abstract final class Fmt {
  static String two(int n) => n.toString().padLeft(2, '0');

  static String time(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

  static String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String dateTime(DateTime d) => '${dayMonth(d)} · ${time(d)}';

  static String full(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year} à ${time(d)}';

  /// LUN, MAR, … (AUJ. pour aujourd'hui)
  static String dayShort(DateTime d, {DateTime? today}) {
    if (today != null && sameDay(d, today)) return 'AUJ.';
    return _days[d.weekday - 1];
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Lundi de la semaine de [d] à 00:00.
  static DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  /// « 16 – 22 nov. » ou « 28 oct. – 3 nov. »
  static String weekRange(DateTime start) {
    final end = addDays(start, 6);
    if (start.month == end.month) {
      return '${start.day} – ${end.day} ${_months[end.month - 1]}';
    }
    return '${dayMonth(start)} – ${dayMonth(end)}';
  }

  /// 45 min · 3 h 20 · 2 j 4 h
  static String duration(Duration d) {
    final m = d.inMinutes;
    if (m < 1) return "moins d'1 min";
    if (m < 60) return '$m min';
    final h = d.inHours;
    if (h < 48) {
      final rm = m % 60;
      return rm == 0 ? '$h h' : '$h h ${two(rm)}';
    }
    final days = d.inDays;
    final rh = h % 24;
    return rh == 0 ? '$days j' : '$days j $rh h';
  }

  /// Durée de garde : 6 h, 24 h, 3 jours…
  static String hours(int h) {
    if (h >= 48 && h % 24 == 0) return '${h ~/ 24} jours';
    return '$h h';
  }

  /// 1500 → « 1 500 FCFA » (espace insécable pour ne pas couper le montant).
  static String money(int amount) {
    final digits = amount.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u00A0');
      buf.write(digits[i]);
    }
    return '${amount < 0 ? '-' : ''}$buf\u00A0FCFA';
  }

  /// 482913 → 482 913
  static String code(String c) =>
      c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;
}
