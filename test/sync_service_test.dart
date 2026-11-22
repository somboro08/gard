import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garde/data/models.dart';
import 'package:garde/data/sync_store.dart';
import 'package:garde/net/api_client.dart';
import 'package:garde/net/token_store.dart';
import 'package:garde/sync/connectivity.dart';
import 'package:garde/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Base locale factice : juste assez pour observer ce que la synchro lui demande.
class FakeStore implements SyncStore {
  FakeStore(this.ops);

  final List<OutboxOp> ops;
  final Map<String, String> state = {};
  final List<String> log = [];
  final Set<String> failedSeqs = {};
  final Map<int, String> errors = {};
  List<ParkingCenter> centers = [];
  Map<String, ApplyResult> applyResults = {};
  final List<(String, List<Vehicle>, List<Payment>, List<String>)> applied = [];

  @override
  bool syncEnabled = true;

  @override
  Future<void> setSyncEnabled(bool enabled) async => syncEnabled = enabled;

  @override
  Future<List<OutboxOp>> pendingOps({int limit = 200}) async =>
      ops.where((o) => !failedSeqs.contains(o.seq.toString())).take(limit).toList();

  @override
  Future<int> pendingCount() async => ops.where((o) => !failedSeqs.contains('${o.seq}')).length;

  @override
  Future<List<OutboxOp>> failedOps() async =>
      ops.where((o) => failedSeqs.contains('${o.seq}')).toList();

  @override
  Future<void> completeOp(int seq) async {
    log.add('done:$seq');
    ops.removeWhere((o) => o.seq == seq);
  }

  @override
  Future<void> recordOpError(int seq, String message, {required bool permanent}) async {
    errors[seq] = message;
    if (permanent) failedSeqs.add('$seq');
    log.add('${permanent ? 'failed' : 'retry'}:$seq');
  }

  @override
  Future<void> retryFailedOps() async => failedSeqs.clear();

  @override
  Future<void> discardFailedOps() async {
    ops.removeWhere((o) => failedSeqs.contains('${o.seq}'));
    failedSeqs.clear();
  }

  @override
  Future<String?> syncValue(String key) async => state[key];

  @override
  Future<void> setSyncValue(String key, String? value) async {
    if (value == null) {
      state.remove(key);
    } else {
      state[key] = value;
    }
  }

  @override
  Future<Set<String>> applyRemoteCenters(List<ParkingCenter> remote, Map<String, String> roles) async {
    centers = remote;
    for (final e in roles.entries) {
      state['role:${e.key}'] = e.value;
    }
    return {};
  }

  @override
  Future<ApplyResult> applyRemoteChanges(
    String centerId, {
    required List<Vehicle> vehicles,
    required List<Payment> payments,
    required List<String> deletedVehicleIds,
  }) async {
    applied.add((centerId, vehicles, payments, deletedVehicleIds));
    return applyResults[centerId] ??
        ApplyResult(changedVehicleIds: {for (final v in vehicles) v.id});
  }

  @override
  Future<void> markCenterKnown(String centerId) async => state['known:$centerId'] = '1';

  final List<String> droppedPayments = [];
  final Map<String, String> codes = {};

  @override
  Future<void> updateLocalVehicleCode(String vehicleId, String code) async =>
      codes[vehicleId] = code;

  @override
  Future<void> dropLocalPayment(String paymentId) async => droppedPayments.add(paymentId);

  final List<String> clearedKeys = [];

  @override
  Future<void> clearLocalOwnerKey(String vehicleId) async => clearedKeys.add(vehicleId);

  @override
  Future<void> wipeAll() async {}
}

class FakeProbe implements NetworkProbe {
  @override
  Future<bool> hasNetwork() async => true;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}

OutboxOp op(int seq, String kind, String entity, {String? center, Map<String, dynamic>? payload}) =>
    OutboxOp(
      seq: seq,
      kind: kind,
      entityId: entity,
      centerId: center,
      payload: payload ?? const {},
      attempts: 0,
      lastError: null,
      failed: false,
      createdAt: DateTime(2026, 11, 18),
    );

http.Response json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const centerJson = {
  'id': 'c1',
  'name': 'Parking',
  'location': '',
  'guardHours': 24,
  'tariff': {'moto': 100, 'velo': 0, 'voiture': 0, 'autre': 0},
  'role': 'owner',
  'createdAt': '2026-11-18T08:00:00.000Z',
};

const vehicleJson = {
  'id': 'v1',
  'centerId': 'c1',
  'code': '123456',
  'plate': 'AB 1 CD',
  'type': 'moto',
  'ownerName': 'Georges',
  'ownerPhone': '',
  'note': '',
  'depositedAt': '2026-11-18T08:00:00.000Z',
  'dueAt': '2026-11-19T08:00:00.000Z',
  'collectedAt': null,
  'pickupCheck': null,
  'ticketVerified': false,
  'price': 100,
  'paidAmount': 0,
};

class Harness {
  Harness(this.store, this.handler) {
    api = ApiClient(
      baseUrl: () => 'https://api.test',
      tokens: MemoryTokenStore()..write(const Tokens(accessToken: 'a', refreshToken: 'r')),
      client: MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        return handler(req);
      }),
    );
    net = ConnectivityService(probe: FakeProbe(), ping: api.ping);
    sync = SyncService(
      store: store,
      api: api,
      connectivity: net,
      onChanged: changes.add,
      pollEvery: const Duration(hours: 1),
    );
  }

  final FakeStore store;
  final Future<http.Response> Function(http.Request) handler;
  final List<String> requests = [];
  final List<SyncChange> changes = [];
  late final ApiClient api;
  late final ConnectivityService net;
  late final SyncService sync;

  void dispose() {
    sync.dispose();
    net.dispose();
  }
}

Future<http.Response> okServer(http.Request req) async {
  final path = req.url.path;
  if (req.method == 'GET' && path == '/centers') return json(200, {'centers': [centerJson]});
  if (req.method == 'GET' && path == '/centers/c1/changes') {
    return json(200, {
      'serverTime': '2026-11-18T09:00:00.000Z',
      'vehicles': [vehicleJson],
      'payments': [],
      'deletedVehicleIds': [],
    });
  }
  if (req.method == 'POST' && path == '/centers/c1/vehicles') {
    return json(201, {'vehicle': vehicleJson});
  }
  return json(200, {});
}

void main() {
  group('SyncService', () {
    test('envoie l\'outbox dans l\'ordre puis reçoit les changements', () async {
      final store = FakeStore([
        op(1, 'center.create', 'c1', center: 'c1', payload: {'id': 'c1', 'name': 'Parking'}),
        op(2, 'vehicle.create', 'v1', center: 'c1', payload: {'id': 'v1', 'code': '123456'}),
        op(3, 'payment.add', 'v1', center: 'c1', payload: {'id': 'p1', 'amount': 100}),
      ]);
      final h = Harness(store, okServer);
      await h.sync.syncNow();

      expect(h.requests, [
        'POST /centers',
        'POST /centers/c1/vehicles',
        'POST /vehicles/v1/payments',
        'GET /centers',
        'GET /centers/c1/changes',
      ]);
      expect(store.ops, isEmpty);
      expect(store.state['known:c1'], '1');
      expect(store.state['role:c1'], 'owner');
      expect(store.state['cursor:c1'], '2026-11-18T09:00:00.000Z');
      expect(h.sync.status.phase, SyncPhase.idle);
      expect(h.sync.status.pending, 0);
      expect(h.sync.status.lastSyncAt, isNotNull);
      expect(h.changes, isNotEmpty);
      expect(h.changes.last.vehicleIds, contains('v1'));
      h.dispose();
    });

    test('sans réseau : l\'opération reste en file et on passe hors-ligne', () async {
      final store = FakeStore([op(1, 'vehicle.create', 'v1', center: 'c1')]);
      final h = Harness(store, (_) async => throw const SocketException('down'));
      await h.sync.syncNow();

      expect(h.sync.status.phase, SyncPhase.offline);
      expect(h.net.online, isFalse);
      expect(store.ops, hasLength(1)); // rien de perdu
      expect(store.failedSeqs, isEmpty); // pas un refus définitif
      expect(h.sync.status.pending, 1);
      h.dispose();
    });

    test('un refus définitif n\'arrête pas la suite et annule l\'encaissement local', () async {
      final store = FakeStore([
        op(1, 'payment.add', 'v1', center: 'c1', payload: {'id': 'p1', 'amount': 500}),
        op(2, 'vehicle.collect', 'v1', center: 'c1', payload: {'pickupCheck': 'exact'}),
      ]);
      final h = Harness(store, (req) async {
        if (req.url.path == '/vehicles/v1/payments') {
          return json(409, {'error': 'overpayment', 'message': 'Montant supérieur au solde.'});
        }
        return okServer(req);
      });
      await h.sync.syncNow();

      expect(store.failedSeqs, {'1'});
      expect(store.errors[1], 'Montant supérieur au solde.');
      expect(store.droppedPayments, ['p1']);
      expect(store.ops.map((o) => o.seq), [1]); // l'opération 2 est partie
      expect(h.sync.status.failed, 1);
      expect(h.sync.status.phase, SyncPhase.idle);
      h.dispose();
    });

    test('remise déjà faite ailleurs = succès', () async {
      final store = FakeStore([op(1, 'vehicle.collect', 'v1', center: 'c1')]);
      final h = Harness(store, (req) async {
        if (req.url.path == '/vehicles/v1/collect') {
          return json(409, {'error': 'already_collected', 'message': 'Déjà remis.'});
        }
        return okServer(req);
      });
      await h.sync.syncNow();
      expect(store.ops, isEmpty);
      expect(store.failedSeqs, isEmpty);
      h.dispose();
    });

    test('clé du client : envoyée avec sa preuve', () async {
      final store = FakeStore([
        op(1, 'vehicle.create', 'v1', center: 'c1'),
        op(2, 'vehicle.ownerkey', 'v1', center: 'c1', payload: {'ownerKey': 'k', 'nonce': 'n', 'sig': 's'}),
      ]);
      final h = Harness(store, okServer);
      await h.sync.syncNow();
      expect(h.requests, contains('POST /vehicles/v1/owner-key'));
      expect(store.ops, isEmpty);
      expect(store.clearedKeys, isEmpty);
      h.dispose();
    });

    test('clé refusée par le serveur : opération en échec et clé locale retirée', () async {
      final store = FakeStore([
        op(1, 'vehicle.ownerkey', 'v1', center: 'c1', payload: {'ownerKey': 'k', 'nonce': 'n', 'sig': 's'}),
      ]);
      final h = Harness(store, (req) async {
        if (req.url.path == '/vehicles/v1/owner-key') {
          return json(409, {'error': 'key_already_set', 'message': 'Une clé est déjà enrôlée pour ce véhicule.'});
        }
        return okServer(req);
      });
      await h.sync.syncNow();
      expect(store.failedSeqs, {'1'});
      expect(store.clearedKeys, ['v1']);
      h.dispose();
    });

    test('preuve de remise invalide (422) : refus définitif, la suite continue', () async {
      final store = FakeStore([
        op(1, 'vehicle.collect', 'v1', center: 'c1', payload: {'pickupMethod': 'key'}),
        op(2, 'payment.add', 'v2', center: 'c1', payload: {'id': 'p9', 'amount': 100}),
      ]);
      final h = Harness(store, (req) async {
        if (req.url.path == '/vehicles/v1/collect') {
          return json(422, {'error': 'invalid_proof', 'message': 'Preuve de remise invalide.'});
        }
        return okServer(req);
      });
      await h.sync.syncNow();
      expect(store.failedSeqs, {'1'});
      expect(store.ops, hasLength(1)); // l'opération en échec reste visible ; le paiement est parti
      h.dispose();
    });

    test('suppression d\'un élément déjà absent du serveur = succès', () async {
      final store = FakeStore([op(1, 'vehicle.delete', 'v9', center: 'c1')]);
      final h = Harness(store, (req) async {
        if (req.method == 'DELETE') return json(404, {'error': 'not_found', 'message': 'x'});
        return okServer(req);
      });
      await h.sync.syncNow();
      expect(store.ops, isEmpty);
      h.dispose();
    });

    test('code de ticket réattribué par le serveur → mis à jour localement', () async {
      final store = FakeStore([
        op(1, 'vehicle.create', 'v1', center: 'c1', payload: {'id': 'v1', 'code': '999999'}),
      ]);
      final h = Harness(store, okServer); // le serveur renvoie le code 123456
      await h.sync.syncNow();
      expect(store.codes['v1'], '123456');
      h.dispose();
    });

    test('erreur serveur 500 : on s\'arrête, l\'opération reste, nouvel essai planifié', () async {
      final store = FakeStore([
        op(1, 'vehicle.create', 'v1', center: 'c1'),
        op(2, 'vehicle.update', 'v1', center: 'c1'),
      ]);
      final h = Harness(store, (_) async => json(503, {'error': 'x', 'message': 'Indisponible.'}));
      await h.sync.syncNow();
      expect(store.ops, hasLength(2));
      expect(store.failedSeqs, isEmpty);
      expect(h.sync.status.phase, SyncPhase.error);
      expect(h.sync.status.error, 'Indisponible.');
      expect(h.requests, ['POST /centers/c1/vehicles']); // l'ordre est préservé : pas de saut
      h.dispose();
    });

    test('session expirée : pause de la synchro, données gardées', () async {
      final store = FakeStore([op(1, 'vehicle.create', 'v1', center: 'c1')]);
      final h = Harness(store, (req) async {
        if (req.url.path == '/auth/refresh') return json(401, {'error': 'unauthorized', 'message': 'x'});
        return json(401, {'error': 'unauthorized', 'message': 'x'});
      });
      await h.sync.syncNow();
      expect(h.sync.status.sessionExpired, isTrue);
      expect(h.sync.status.phase, SyncPhase.error);
      expect(store.ops, hasLength(1));

      // Tant que la session est expirée, plus aucune requête.
      final before = h.requests.length;
      await h.sync.syncNow();
      expect(h.requests.length, before);
      h.dispose();
    });

    test('éléments ignorés (modifs locales en attente) : le curseur n\'avance pas', () async {
      final store = FakeStore([])..applyResults['c1'] = const ApplyResult(skipped: true);
      final h = Harness(store, okServer);
      await h.sync.syncNow();
      expect(store.state.containsKey('cursor:c1'), isFalse);
      h.dispose();
    });

    test('envoie le curseur (−5 s) aux synchros suivantes', () async {
      final store = FakeStore([])..state['cursor:c1'] = '2026-11-18T09:00:00.000Z';
      String? since;
      final h = Harness(store, (req) async {
        if (req.url.path == '/centers/c1/changes') since = req.url.queryParameters['since'];
        return okServer(req);
      });
      await h.sync.syncNow();
      expect(since, '2026-11-18T08:59:55.000Z');
      h.dispose();
    });

    test('désactivée sans compte : aucune requête', () async {
      final store = FakeStore([])..syncEnabled = false;
      final h = Harness(store, okServer);
      await h.sync.syncNow();
      expect(h.requests, isEmpty);
      expect(h.sync.status.phase, SyncPhase.off);
      h.dispose();
    });

    test('la progression atteint 100 % à la fin', () async {
      final store = FakeStore([
        op(1, 'center.create', 'c1', center: 'c1'),
        op(2, 'vehicle.create', 'v1', center: 'c1'),
      ]);
      final h = Harness(store, okServer);
      final seen = <double>[];
      h.sync.addListener(() {
        final p = h.sync.status.progress;
        if (p != null) seen.add(p);
      });
      await h.sync.syncNow();
      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1] - 1e-9)); // jamais de recul
      }
      h.dispose();
    });
  });

  group('ConnectivityService', () {
    test('hors-ligne après un échec, en ligne au retour du serveur', () async {
      var up = false;
      final net = ConnectivityService(
        probe: FakeProbe(),
        ping: () async => up,
        maxProbeDelay: const Duration(seconds: 3),
      );
      expect(net.online, isTrue);
      net.reportUnreachable();
      expect(net.online, isFalse);
      up = true;
      net.reportReachable();
      expect(net.online, isTrue);
      net.dispose();
    });
  });
}
