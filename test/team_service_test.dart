import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garde/net/api_client.dart';
import 'package:garde/net/api_exception.dart';
import 'package:garde/net/token_store.dart';
import 'package:garde/sync/team_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(int status, Object? body) => http.Response(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<TeamService> _team(MockClientHandler handler) async {
  final store = MemoryTokenStore();
  await store.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
  return TeamService(
    ApiClient(baseUrl: () => 'https://api.test', tokens: store, client: MockClient(handler)),
  );
}

void main() {
  const cid = '11111111-1111-4111-8111-111111111111';

  test('liste les membres et ignore les entrées invalides', () async {
    final t = await _team((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, '/centers/$cid/members');
      return _json(200, {
        'members': [
          {'id': 'u1', 'name': 'Awa', 'phone': '22901970000', 'role': 'owner'},
          {'id': 'u2', 'name': 'Koffi', 'phone': '22901970001', 'role': 'agent'},
          {'name': 'sans id'},
        ],
      });
    });
    final list = await t.list(cid);
    expect(list.map((m) => m.name), ['Awa', 'Koffi']);
    expect(list.first.isOwner, isTrue);
    expect(list.last.isOwner, isFalse);
  });

  test('ajoute un agent par numéro', () async {
    final t = await _team((req) async {
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'phone': '01 97 00 00 02', 'role': 'agent'});
      return _json(201, {
        'member': {'id': 'u3', 'name': 'Moussa', 'phone': '22901970002', 'role': 'agent'},
      });
    });
    final m = await t.add(cid, phone: '01 97 00 00 02');
    expect(m.name, 'Moussa');
    expect(m.role, 'agent');
  });

  test('numéro sans compte → notFound avec le message du serveur', () async {
    final t = await _team((req) async => _json(404, {
          'error': 'not_found',
          'message': "Aucun compte avec ce numéro : l'agent doit d'abord s'inscrire.",
        }));
    expect(
      () => t.add(cid, phone: '0100000000'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiErrorKind.notFound)
          .having((e) => e.message, 'message', contains('s\'inscrire'))),
    );
  });

  test('retire un membre (204) et refuse pour un non-propriétaire (403)', () async {
    var forbidden = false;
    final t = await _team((req) async {
      expect(req.method, 'DELETE');
      expect(req.url.path, '/centers/$cid/members/u2');
      return forbidden ? _json(403, {'error': 'forbidden', 'message': 'Réservé au propriétaire du centre.'}) : _json(204, null);
    });
    await t.remove(cid, 'u2');
    forbidden = true;
    expect(
      () => t.remove(cid, 'u2'),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden)),
    );
  });
}
