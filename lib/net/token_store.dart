import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  Map<String, String> toJson() => {'a': accessToken, 'r': refreshToken};

  static Tokens? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = j['a'];
    final r = j['r'];
    if (a is String && r is String && a.isNotEmpty && r.isNotEmpty) {
      return Tokens(accessToken: a, refreshToken: r);
    }
    return null;
  }
}

/// Où sont gardés les jetons de connexion.
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens tokens);
  Future<void> clear();
}

/// Keystore (Android) / Keychain (iOS) : jamais dans la base SQLite ni en clair.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _s;
  static const _key = 'garde.tokens';

  @override
  Future<Tokens?> read() async {
    try {
      final raw = await _s.read(key: _key);
      return raw == null ? null : Tokens.fromJson(jsonDecode(raw));
    } catch (_) {
      // Keystore illisible (sauvegarde restaurée sur un autre téléphone…) : on repart déconnecté.
      return null;
    }
  }

  @override
  Future<void> write(Tokens tokens) => _s.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _key);
    } catch (_) {}
  }
}

/// Pour les tests.
class MemoryTokenStore implements TokenStore {
  Tokens? _t;

  @override
  Future<Tokens?> read() async => _t;

  @override
  Future<void> write(Tokens tokens) async => _t = tokens;

  @override
  Future<void> clear() async => _t = null;
}
