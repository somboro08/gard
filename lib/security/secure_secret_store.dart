import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pickup_crypto.dart';

/// Coffre du téléphone (Keystore / Keychain) pour les clés secrètes des tickets sécurisés.
/// Volontairement séparé des données de l'app : se déconnecter d'un compte n'efface pas
/// les clés du client (elles lui appartiennent, pas au compte).
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: 'garde.$key');
    } catch (_) {
      return null; // Keystore illisible : comme si aucune clé n'existait
    }
  }

  @override
  Future<void> write(String key, String value) => _s.write(key: 'garde.$key', value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _s.delete(key: 'garde.$key');
    } catch (_) {}
  }
}
