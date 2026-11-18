import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

/// Client REST de l'API Garde : JSON, jeton d'accès, renouvellement automatique
/// de la session (une seule requête de renouvellement à la fois), erreurs typées.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

  /// Adresse de l'API (lue à chaque requête : modifiable sans redémarrer).
  final String Function() baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  final Duration timeout;

  /// Appelé quand le renouvellement de session échoue définitivement (à reconnecter).
  void Function()? onSessionExpired;

  Future<bool>? _refreshing;

  bool get isConfigured => baseUrl().trim().isNotEmpty;

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      send('GET', path, query: query);

  Future<Object?> post(String path, {Object? body, bool auth = true}) =>
      send('POST', path, body: body ?? const {}, auth: auth);

  Future<Object?> patch(String path, {Object? body}) => send('PATCH', path, body: body ?? const {});

  Future<Object?> delete(String path) => send('DELETE', path);

  Future<Object?> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
  }) async {
    try {
      return await _once(method, path, query: query, body: body, auth: auth);
    } on ApiException catch (e) {
      // Jeton d'accès expiré : on renouvelle puis on rejoue UNE fois.
      if (e.kind == ApiErrorKind.unauthorized && auth && await _refresh()) {
        return _once(method, path, query: query, body: body, auth: auth);
      }
      rethrow;
    }
  }

  Future<Object?> _once(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    required bool auth,
  }) async {
    final base = baseUrl().trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const ApiException(ApiErrorKind.offline, "Serveur non configuré.");
    }
    final Uri uri;
    try {
      uri = Uri.parse('$base$path').replace(queryParameters: query);
    } catch (_) {
      throw const ApiException(ApiErrorKind.offline, "Adresse du serveur invalide.");
    }

    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) headers['content-type'] = 'application/json';
    if (auth) {
      final t = await tokens.read();
      if (t == null) throw const ApiException(ApiErrorKind.unauthorized, 'Connexion requise.', status: 401);
      headers['authorization'] = 'Bearer ${t.accessToken}';
    }

    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout, 'Le serveur met trop de temps à répondre.');
    } on SocketException {
      throw const ApiException(ApiErrorKind.offline, 'Pas de connexion au serveur.');
    } on HandshakeException {
      throw const ApiException(ApiErrorKind.offline, 'Connexion sécurisée impossible.');
    } on http.ClientException {
      throw const ApiException(ApiErrorKind.offline, 'Pas de connexion au serveur.');
    }

    return _decode(res);
  }

  Object? _decode(http.Response res) {
    Object? json;
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        json = null;
      }
    }
    final s = res.statusCode;
    if (s >= 200 && s < 300) return json;

    final code = json is Map ? json['error'] as String? : null;
    final msg = (json is Map ? json['message'] as String? : null);
    final kind = switch (s) {
      400 || 422 => ApiErrorKind.validation,
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      408 => ApiErrorKind.timeout,
      409 => ApiErrorKind.conflict,
      429 => ApiErrorKind.rateLimited,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.unknown,
    };
    throw ApiException(
      kind,
      msg ?? _defaultMessage(kind),
      status: s,
      code: code,
    );
  }

  static String _defaultMessage(ApiErrorKind k) => switch (k) {
        ApiErrorKind.unauthorized => 'Session expirée. Reconnectez-vous.',
        ApiErrorKind.forbidden => 'Action non autorisée.',
        ApiErrorKind.notFound => 'Élément introuvable.',
        ApiErrorKind.rateLimited => 'Trop de tentatives. Réessayez dans un instant.',
        ApiErrorKind.server => 'Le serveur rencontre un problème. Réessayez plus tard.',
        _ => 'Requête refusée.',
      };

  /// Renouvelle les jetons. Une seule requête à la fois ; les autres attendent son résultat.
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final j = await _once(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': t.refreshToken},
        auth: false,
      );
      if (j is Map && j['accessToken'] is String && j['refreshToken'] is String) {
        await tokens.write(
          Tokens(accessToken: j['accessToken'] as String, refreshToken: j['refreshToken'] as String),
        );
        return true;
      }
      return false;
    } on ApiException catch (e) {
      // Réseau coupé pendant le renouvellement : la session reste valide, on réessaiera.
      if (e.isRetryable) return false;
      // Refus définitif (jeton révoqué ou expiré) : il faudra se reconnecter.
      await tokens.clear();
      onSessionExpired?.call();
      return false;
    }
  }

  void close() => _http.close();
}
