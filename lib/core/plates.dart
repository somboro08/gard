import 'dart:math' as math;

enum PlateMatch { exact, close, different }

/// Normalisation et comparaison des plaques d'immatriculation.
abstract final class Plates {
  static final RegExp _sep = RegExp(r'[^A-Z0-9]+');
  static final RegExp _notAlnum = RegExp(r'[^A-Z0-9]');

  /// Confusions classiques de l'OCR (O/0, I/1, B/8, S/5…). Appliquées des deux côtés.
  static const Map<String, String> _fold = {
    'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1',
    'Z': '2', 'S': '5', 'G': '6', 'B': '8',
  };

  /// « ab-1234  rb » → « AB 1234 RB »
  static String display(String raw) => raw.toUpperCase().replaceAll(_sep, ' ').trim();

  /// Clé de comparaison : majuscules, sans espaces ni ponctuation.
  static String key(String raw) => raw.toUpperCase().replaceAll(_notAlnum, '');

  static String fold(String key) => key.split('').map((c) => _fold[c] ?? c).join();

  /// exact  : mêmes caractères.
  /// close  : écart uniquement dû à des confusions OCR, ou 1 seul caractère d'écart.
  /// different : sinon.
  static PlateMatch compare(String stored, String scanned) {
    final a = key(stored);
    final b = key(scanned);
    if (a.isEmpty || b.isEmpty) return PlateMatch.different;
    if (a == b) return PlateMatch.exact;
    final fa = fold(a);
    final fb = fold(b);
    if (fa == fb) return PlateMatch.close;
    return _levenshtein(fa, fb) <= 1 ? PlateMatch.close : PlateMatch.different;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    var prev = List<int>.generate(t.length + 1, (i) => i);
    for (var i = 1; i <= s.length; i++) {
      final cur = List<int>.filled(t.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= t.length; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[t.length];
  }
}

/// Extraction de candidats « plaque » depuis le texte brut de l'OCR.
abstract final class PlateOcr {
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _letter = RegExp(r'[A-Z]');

  static List<String> candidates(List<String> lines) {
    final cleaned = lines.map(Plates.display).where((l) => l.isNotEmpty).toList();
    final pool = <String>[...cleaned];
    // Les plaques de motos sont souvent sur 2 lignes : on teste aussi les paires.
    for (var i = 0; i + 1 < cleaned.length; i++) {
      pool.add('${cleaned[i]} ${cleaned[i + 1]}');
    }

    final seen = <String>{};
    final scored = <(String, int)>[];
    for (final c in pool) {
      final k = Plates.key(c);
      if (k.length < 4 || k.length > 10 || !_digit.hasMatch(k)) continue;
      if (!seen.add(k)) continue;
      scored.add((c, _score(k)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(5).map((e) => e.$1).toList();
  }

  static int _score(String k) {
    var s = 0;
    if (_letter.hasMatch(k)) s += 3;
    if (k.length >= 6 && k.length <= 9) s += 3;
    if (_digit.allMatches(k).length >= 3) s += 2;
    return s;
  }
}

/// Contenu du QR code du ticket.
abstract final class Tickets {
  static String encode(String code) => 'GARDE:$code';

  /// Accepte « GARDE:482913 », « 482913 » ou « 482 913 ». Retourne le code à 6 chiffres.
  static String? parse(String raw) {
    final s = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final m = RegExp(r'^(?:GARDE:)?(\d{6})$').firstMatch(s);
    return m?.group(1);
  }
}

abstract final class Phones {
  /// Numéro au format wa.me (indicatif Bénin 229 ajouté si absent).
  static String waNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.isEmpty) return '';
    if (d.startsWith('229') && d.length >= 11) return d;
    if (d.length <= 10) return '229$d';
    return d;
  }
}
