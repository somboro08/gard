import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'sqlite_repository.dart';
import 'sync_store.dart';

/// Implémentation SQLite de [SyncStore] : partage la base de [SqliteParkingRepository].
class SqliteSyncStore implements SyncStore {
  SqliteSyncStore(this._repo);

  final SqliteParkingRepository _repo;

  Database get _d => _repo.database;

  @override
  bool get syncEnabled => _repo.syncEnabled;

  @override
  Future<void> setSyncEnabled(bool enabled) async {
    await _repo.setSetting('sync_enabled', enabled ? '1' : '0');
    _repo.syncEnabled = enabled;
    if (enabled) await _enqueueAllLocal();
  }

  /// Met en file toutes les données locales (centres, véhicules, remises, paiements).
  /// Idempotent côté serveur : les identifiants sont ceux de l'appareil.
  Future<void> _enqueueAllLocal() async {
    await _d.transaction((txn) async {
      await txn.delete('outbox', where: "status = 'pending'");
      for (final r in await txn.query('centers', orderBy: 'created_at ASC')) {
        final c = ParkingCenter.fromMap(r);
        await enqueueOp(
          txn,
          kind: 'center.create',
          entityId: c.id,
          centerId: c.id,
          payload: centerPayload(c),
        );
      }
      for (final r in await txn.query('vehicles', orderBy: 'deposited_at ASC')) {
        final v = Vehicle.fromMap(r);
        await enqueueOp(
          txn,
          kind: 'vehicle.create',
          entityId: v.id,
          centerId: v.centerId,
          payload: vehicleCreatePayload(v),
        );
        final ownerProof = PickupProof.parse(r['owner_key_proof'] as String?);
        final key = v.ownerKey;
        if (key != null && ownerProof != null) {
          await enqueueOp(
            txn,
            kind: 'vehicle.ownerkey',
            entityId: v.id,
            centerId: v.centerId,
            payload: ownerKeyPayload(key: key, nonce: ownerProof.nonce, sig: ownerProof.sig),
          );
        }
        for (final pr in await txn.query('payments', where: 'vehicle_id = ?', whereArgs: [v.id], orderBy: 'paid_at ASC')) {
          final pay = Payment.fromMap(pr);
          await enqueueOp(
            txn,
            kind: 'payment.add',
            entityId: v.id,
            centerId: v.centerId,
            payload: paymentPayload(pay),
          );
        }
        final at = v.collectedAt;
        if (at != null) {
          await enqueueOp(
            txn,
            kind: 'vehicle.collect',
            entityId: v.id,
            centerId: v.centerId,
            payload: collectPayload(
              at: at,
              check: v.pickupCheck ?? PickupCheck.skipped,
              ticketVerified: v.ticketVerified,
              method: v.pickupMethod ?? PickupMethod.manual,
              proof: PickupProof.parse(r['pickup_proof'] as String?),
            ),
          );
        }
      }
    });
  }

  // ───────────────────────── Outbox ─────────────────────────

  @override
  Future<List<OutboxOp>> pendingOps({int limit = 200}) async {
    final rows = await _d.query(
      'outbox',
      where: "status = 'pending'",
      orderBy: 'seq ASC',
      limit: limit,
    );
    return rows.map(OutboxOp.fromMap).toList();
  }

  @override
  Future<int> pendingCount() async {
    final r = await _d.rawQuery("SELECT COUNT(*) AS n FROM outbox WHERE status = 'pending'");
    return (r.first['n'] as int?) ?? 0;
  }

  @override
  Future<List<OutboxOp>> failedOps() async {
    final rows = await _d.query('outbox', where: "status = 'failed'", orderBy: 'seq ASC');
    return rows.map(OutboxOp.fromMap).toList();
  }

  @override
  Future<void> completeOp(int seq) => _d.delete('outbox', where: 'seq = ?', whereArgs: [seq]);

  @override
  Future<void> recordOpError(int seq, String message, {required bool permanent}) {
    return _d.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_error = ?, status = ? WHERE seq = ?',
      [message, permanent ? 'failed' : 'pending', seq],
    );
  }

  @override
  Future<void> retryFailedOps() =>
      _d.rawUpdate("UPDATE outbox SET status = 'pending', attempts = 0 WHERE status = 'failed'");

  @override
  Future<void> discardFailedOps() => _d.delete('outbox', where: "status = 'failed'");

  // ───────────────────────── État de synchro (curseurs, rôles…) ─────────────────────────

  @override
  Future<String?> syncValue(String key) async {
    final rows = await _d.query('sync_state', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSyncValue(String key, String? value) async {
    if (value == null) {
      await _d.delete('sync_state', where: 'key = ?', whereArgs: [key]);
    } else {
      await _d.insert('sync_state', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ───────────────────────── Données reçues du serveur ─────────────────────────

  Future<Set<String>> _pendingEntities(DatabaseExecutor ex) async {
    final rows = await ex.rawQuery("SELECT DISTINCT entity_id FROM outbox WHERE status = 'pending'");
    return {for (final r in rows) r['entity_id'] as String};
  }

  Future<void> _upsert(DatabaseExecutor ex, String table, Map<String, Object?> row) async {
    // Pas d'UPSERT SQL (absent des anciens Android) ni de REPLACE (il supprimerait les
    // paiements liés par la clé étrangère) : mise à jour, puis insertion si la ligne manque.
    final n = await ex.update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    if (n == 0) await ex.insert(table, row);
  }

  @override
  Future<Set<String>> applyRemoteCenters(
    List<ParkingCenter> remote,
    Map<String, String> roles,
  ) async {
    final removed = <String>{};
    await _d.transaction((txn) async {
      final pending = await txn.rawQuery(
        "SELECT DISTINCT center_id FROM outbox WHERE status = 'pending' AND center_id IS NOT NULL",
      );
      final pendingCenters = {for (final r in pending) r['center_id'] as String};
      final remoteIds = <String>{};

      for (final c in remote) {
        remoteIds.add(c.id);
        await _setState(txn, 'known:${c.id}', '1');
        final role = roles[c.id];
        if (role != null) await _setState(txn, 'role:${c.id}', role);
        if (pendingCenters.contains(c.id)) continue; // modification locale à envoyer d'abord
        await _upsert(txn, 'centers', c.toMap());
      }

      // Centres que le serveur ne renvoie plus (retirés, supprimés par un autre appareil).
      final known = await txn.query('sync_state', where: "key LIKE 'known:%'");
      for (final k in known) {
        final id = (k['key'] as String).substring('known:'.length);
        if (remoteIds.contains(id) || pendingCenters.contains(id)) continue;
        await txn.delete('payments', where: 'center_id = ?', whereArgs: [id]);
        await txn.delete('vehicles', where: 'center_id = ?', whereArgs: [id]);
        await txn.delete('centers', where: 'id = ?', whereArgs: [id]);
        await txn.delete('sync_state', where: 'key IN (?, ?, ?)',
            whereArgs: ['known:$id', 'role:$id', 'cursor:$id']);
        removed.add(id);
      }
    });
    return removed;
  }

  Future<void> _setState(DatabaseExecutor ex, String key, String value) => ex.insert(
        'sync_state',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<ApplyResult> applyRemoteChanges(
    String centerId, {
    required List<Vehicle> vehicles,
    required List<Payment> payments,
    required List<String> deletedVehicleIds,
  }) async {
    final changed = <String>{};
    var skipped = false;
    await _d.transaction((txn) async {
      final pending = await _pendingEntities(txn);

      for (final v in vehicles) {
        if (pending.contains(v.id)) {
          skipped = true;
          continue;
        }
        await _upsert(txn, 'vehicles', v.toMap());
        changed.add(v.id);
      }

      for (final pay in payments) {
        final exists = await txn.query('payments', columns: ['id'], where: 'id = ?', whereArgs: [pay.id], limit: 1);
        if (exists.isNotEmpty) continue;
        final veh = await txn.query('vehicles', columns: ['id'], where: 'id = ?', whereArgs: [pay.vehicleId], limit: 1);
        if (veh.isEmpty) {
          skipped = true; // véhicule pas encore reçu : on relira
          continue;
        }
        await txn.insert('payments', pay.toMap());
        changed.add(pay.vehicleId);
      }

      for (final id in deletedVehicleIds) {
        if (pending.contains(id)) {
          skipped = true;
          continue;
        }
        await txn.delete('payments', where: 'vehicle_id = ?', whereArgs: [id]);
        await txn.delete('vehicles', where: 'id = ?', whereArgs: [id]);
        changed.add(id);
      }
    });
    return ApplyResult(changedVehicleIds: changed, skipped: skipped);
  }

  @override
  Future<void> markCenterKnown(String centerId) => _setState(_d, 'known:$centerId', '1');

  @override
  Future<void> updateLocalVehicleCode(String vehicleId, String code) =>
      _d.update('vehicles', {'code': code}, where: 'id = ?', whereArgs: [vehicleId]);

  @override
  Future<void> clearLocalOwnerKey(String vehicleId) => _d.update(
        'vehicles',
        {'owner_key': null, 'owner_key_proof': null},
        where: 'id = ?',
        whereArgs: [vehicleId],
      );

  @override
  Future<void> dropLocalPayment(String paymentId) async {
    await _d.transaction((txn) async {
      final rows = await txn.query('payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
      if (rows.isEmpty) return;
      final pay = Payment.fromMap(rows.first);
      await txn.delete('payments', where: 'id = ?', whereArgs: [paymentId]);
      await txn.rawUpdate(
        'UPDATE vehicles SET paid_amount = MAX(0, paid_amount - ?) WHERE id = ?',
        [pay.amount, pay.vehicleId],
      );
    });
  }

  @override
  Future<void> wipeAll() async {
    await _d.transaction((txn) async {
      await txn.delete('payments');
      await txn.delete('vehicles');
      await txn.delete('centers');
      await txn.delete('outbox');
      await txn.delete('sync_state');
      await txn.delete('settings', where: "key IN ('current_center', 'sync_enabled')");
    });
    _repo.syncEnabled = false;
  }
}
