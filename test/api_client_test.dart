import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garde/net/api_client.dart';
import 'package:garde/net/api_exception.dart';
import 'package:garde/net/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<ApiClient> client(MockClientHandler handler, {Tokens? tokens}) async {
  final store = MemoryTokenStore();
  if (tokens != null) await store.write(tokens);
  return ApiClient(
    baseUrl: () => 'https://api.test',
    tokens: store,
    client: MockClient(handler),
  );
}

const _t = Tokens(accessToken: 'acc1', refreshToken: 'ref1');

void main() {
  group('ApiClient', () {
    test('envoie le jeton et décode le JSON', () async {
      final c = await client((req) async {
        expect(req.headers['authorization'], 'Bearer acc1');
        expect(req.url.toString(), 'https://api.test/centers');
        return json(200, {'centers': []});
      }, tokens: _t);
      final r = await c.get('/centers');
      expect((r as Map)['centers'], isEmpty);
    });

    test('adresse de serveur vide → hors-ligne, sans requête', () async {
      final c = ApiClient(
        baseUrl: () => '  ',
        tokens: MemoryTokenStore(),
        client: MockClient((_) async => fail('aucune requête attendue')),
      );
      expect(
        () => c.post('/auth/login', auth: false),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.offline)),
      );
    });

    test('renouvelle le jeton sur 401 puis rejoue la requête une fois', () async {
      var calls = 0;
      final c = await client((req) async {
        if (req.url.path == '/auth/refresh') {
          expect(jsonDecode(req.body)['refreshToken'], 'ref1');
          return json(200, {'accessToken': 'acc2', 'refreshToken': 'ref2', 'expiresIn': 900});
        }
        calls++;
        if (req.headers['authorization'] == 'Bearer acc1') {
          return json(401, {'error': 'unauthorized', 'message': 'Session expirée ou invalide.'});
        }
        expect(req.headers['authorization'], 'Bearer acc2');
        return json(200, {'ok': true});
      }, tokens: _t);
      final r = await c.get('/centers');
      expect((r as Map)['ok'], true);
      expect(calls, 2);
      expect((await c.tokens.read())!.refreshToken, 'ref2'); // jeton roté enregistré
    });

    test('plusieurs 401 simultanés = un seul renouvellement', () async {
      var refreshes = 0;
      final c = await client((req) async {
        if (req.url.path == '/auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return json(200, {'accessToken': 'acc2', 'refreshToken': 'ref2', 'expiresIn': 900});
        }
        return req.headers['authorization'] == 'Bearer acc1'
            ? json(401, {'error': 'unauthorized', 'message': 'x'})
            : json(200, {'ok': true});
      }, tokens: _t);
      await Future.wait([c.get('/a'), c.get('/b'), c.get('/c')]);
      expect(refreshes, 1);
    });

    test('renouvellement refusé : session expirée signalée, jetons effacés', () async {
      var expired = 0;
      final c = await client((req) async {
        if (req.url.path == '/auth/refresh') {
          return json(401, {'error': 'unauthorized', 'message': 'Session invalide.'});
        }
        return json(401, {'error': 'unauthorized', 'message': 'Session expirée ou invalide.'});
      }, tokens: _t);
      c.onSessionExpired = () => expired++;
      await expectLater(
        c.get('/centers'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.unauthorized)),
      );
      expect(expired, 1);
      expect(await c.tokens.read(), isNull);
    });

    test('réseau coupé pendant le renouvellement : la session est conservée', () async {
      var expired = 0;
      final c = await client((req) async {
        if (req.url.path == '/auth/refresh') throw const SocketException('down');
        return json(401, {'error': 'unauthorized', 'message': 'x'});
      }, tokens: _t);
      c.onSessionExpired = () => expired++;
      await expectLater(c.get('/centers'), throwsA(isA<ApiException>()));
      expect(expired, 0);
      expect(await c.tokens.read(), isNotNull);
    });

    test('classe les erreurs', () async {
      Future<ApiException> fail(int status, [Object? body]) async {
        final c = await client((_) async => json(status, body ?? {'error': 'e', 'message': 'm'}), tokens: _t);
        try {
          await c.get('/x');
        } on ApiException catch (e) {
          return e;
        }
        throw StateError('aucune exception');
      }

      expect((await fail(400)).kind, ApiErrorKind.validation);
      expect((await fail(403)).kind, ApiErrorKind.forbidden);
      expect((await fail(404)).kind, ApiErrorKind.notFound);
      final conflict = await fail(409, {'error': 'already_collected', 'message': 'Déjà remis.'});
      expect(conflict.kind, ApiErrorKind.conflict);
      expect(conflict.code, 'already_collected');
      expect(conflict.message, 'Déjà remis.');
      expect(conflict.isRetryable, isFalse);
      final rate = await fail(429);
      expect(rate.kind, ApiErrorKind.rateLimited);
      expect(rate.isRetryable, isTrue);
      final srv = await fail(503, 'pas du json');
      expect(srv.kind, ApiErrorKind.server);
      expect(srv.isRetryable, isTrue);
    });

    test('panne réseau → offline ; lenteur → timeout (réessayables)', () async {
      final c1 = await client((_) async => throw const SocketException('x'), tokens: _t);
      await expectLater(
        c1.get('/x'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.offline)),
      );
      final slow = ApiClient(
        baseUrl: () => 'https://api.test',
        tokens: MemoryTokenStore()..write(_t),
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return json(200, {});
        }),
      );
      try {
        await slow.get('/x');
        fail('timeout attendu');
      } on ApiException catch (e) {
        expect(e.kind, ApiErrorKind.timeout);
        expect(e.isNetwork, isTrue);
      }
    });

    test('ping', () async {
      final ok = await client((req) async {
        expect(req.url.path, '/health');
        expect(req.headers.containsKey('authorization'), isFalse);
        return json(200, {'ok': true});
      });
      expect(await ok.ping(), isTrue);
      final down = await client((_) async => throw const SocketException('x'));
      expect(await down.ping(), isFalse);
    });
  });
}
