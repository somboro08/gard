import 'package:flutter/foundation.dart';

/// Journal des erreurs inattendues (mémoire seulement, 40 dernières) — affiché dans
/// Compte › Diagnostic pour aider au dépannage sans outil de développement.
abstract final class ErrorReporter {
  static final List<String> _recent = [];

  static List<String> get recent => List.unmodifiable(_recent);

  static void report(Object error, StackTrace? stack, {String? where}) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)} '
        '${where == null ? '' : '[$where] '}$error';
    _recent.add(line);
    if (_recent.length > 40) _recent.removeAt(0);
    debugPrint('Erreur ${where ?? ''}: $error\n${stack ?? ''}');
  }

  static void clear() => _recent.clear();
}
