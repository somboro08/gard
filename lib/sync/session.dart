import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../data/sync_store.dart';
import '../net/api_client.dart';
import '../net/api_exception.dart';
import '../net/token_store.dart';
import 'mappers.dart';
import 'sync_service.dart';

/// Compte connecté (facultatif : sans compte, l'appli fonctionne 100 % en local).
class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient api,
    required TokenStore tokens,
    required ParkingRepository settings,
    required SyncStore store,
    required this.onLocalDataReset,
  })  : _api = api,
        _tokens = tokens,
        _settings = settings,
        _store = store;

  final ApiClient _api;
  final TokenStore _tokens;
  final ParkingRepository _settings;
  final SyncStore _store;

  /// Appelé quand les données locales ont été effacées (déconnexion, autre compte).
  final Future<void> Function() onLocalDataReset;

  /// Branché après construction (SyncService dépend aussi de l'API).
  late SyncService sync;

  AuthUser? _user;
  bool _expired = false;

  AuthUser? get user => _user;
  bool get signedIn => _user != null;

  /// Le serveur a révoqué la session : les données locales restent, mais il faut se reconnecter.
  bool get expired => _expired;

  Future<void> init() async {
    final raw = await _settings.getSetting('session_user');
    if (raw != null && raw.isNotEmpty) {
      try {
        _user = AuthUser.fromJson(jsonDecode(raw));
      } catch (_) {
        _user = null;
      }
    }
    if (_user != null && await _tokens.read() == null) _expired = true;
    _api.onSessionExpired = _handleExpired;
    notifyListeners();
  }

  void _handleExpired() {
    _expired = true;
    sync.markSessionExpired();
    notifyListeners();
  }

  Future<void> login({required String phone, required String password}) =>
      _authenticate('/auth/login', {'phone': phone, 'password': password});

  Future<void> register({
    required String phone,
    required String name,
    required String password,
  }) =>
      _authenticate('/auth/register', {'phone': phone, 'name': name, 'password': password});

  /// Lève [ApiException] (message déjà lisible) en cas d'échec.
  Future<void> _authenticate(String path, Map<String, Object?> body) async {
    if (!_api.isConfigured) {
      throw const ApiException(ApiErrorKind.offline, "L'adresse du serveur n'est pas configurée.");
    }
    final j = asMap(await _api.post(path, body: body, auth: false));
    final user = AuthUser.fromJson(j['user']);
    final access = j['accessToken'];
    final refresh = j['refreshToken'];
    if (user == null || access is! String || refresh is! String) {
      throw const ApiException(ApiErrorKind.unknown, 'Réponse inattendue du serveur.');
    }
    await _tokens.write(Tokens(accessToken: access, refreshToken: refresh));

    // Un autre compte se connecte sur cet appareil : on n'expose jamais les données du précédent.
    final previous = await _settings.getSetting('session_user_id');
    if (previous != null && previous.isNotEmpty && previous != user.id) {
      await _store.wipeAll();
      await onLocalDataReset();
    }
    await _settings.setSetting('session_user_id', user.id);
    await _settings.setSetting('session_user', jsonEncode(user.toJson()));
    _user = user;
    _expired = false;
    sync.markSessionValid();
    // Première connexion de cet appareil : on met en file les données déjà saisies hors-ligne.
    // (Reconnexion du même compte : l'outbox existante est conservée telle quelle.)
    if (!_store.syncEnabled) await _store.setSyncEnabled(true);
    notifyListeners();
    await sync.refresh();
    sync.requestSync(immediate: true);
  }

  /// Déconnexion : efface les données de l'appareil (elles restent sur le serveur).
  Future<void> logout() async {
    try {
      final t = await _tokens.read();
      if (t != null) {
        await _api.post('/auth/logout', body: {'refreshToken': t.refreshToken}, auth: false);
      }
    } catch (_) {
      // Hors-ligne : la session serveur expirera d'elle-même.
    }
    sync.stop();
    await _tokens.clear();
    await _store.wipeAll();
    await _settings.setSetting('session_user', '');
    await _settings.setSetting('session_user_id', '');
    _user = null;
    _expired = false;
    notifyListeners();
    await onLocalDataReset();
  }
}
