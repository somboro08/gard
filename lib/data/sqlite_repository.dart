import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/plates.dart';
import 'models.dart';
import 'repository.dart';

const List<String> _schema = [
  '''
  CREATE TABLE centers(
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    location TEXT NOT NULL DEFAULT '',
    guard_hours INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE vehicles(
    id TEXT PRIMARY KEY,
    center_id TEXT NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    plate TEXT NOT NULL DEFAULT '',
    plate_key TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL,
    owner_name TEXT NOT NULL,
    owner_phone TEXT NOT NULL DEFAULT '',
    note TEXT NOT NULL DEFAULT '',
    deposited_at INTEGER NOT NULL,
    due_at INTEGER NOT NULL,
    collected_at INTEGER,
    pickup_check TEXT,
    ticket_verified INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX idx_vehicles_center_day ON vehicles(center_id, deposited_at)',
  'CREATE INDEX idx_vehicles_code ON vehicles(code)',
  'CREATE INDEX idx_vehicles_plate ON vehicles(plate_key)',
  '''
  CREATE TABLE settings(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
];

class SqliteParkingRepository implements ParkingRepository {
  Database? _db;
  final Random _rng = Random.secure();

  Database get _d {
    final d = _db;
    if (d == null) throw StateError('Repository non initialisé : appelez init().');
    return d;
  }

  @override
  Future<void> init() async {
    if (_db != null) return;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'garde.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
    );
  }

  /// UUID v4 (compatible avec une future base PostgreSQL).
  String _newId() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int from, int to) =>
        b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
  }

  // ───────────────────────── Centres ─────────────────────────

  @override
  Future<List<ParkingCenter>> centers() async {
    final rows = await _d.query('centers', orderBy: 'created_at ASC');
    return rows.map(ParkingCenter.fromMap).toList();
  }

  @override
  Future<ParkingCenter> saveCenter({
    String? id,
    required String name,
    required String location,
    required int guardHours,
  }) async {
    if (id == null) {
      final c = ParkingCenter(
        id: _newId(),
        name: name,
        location: location,
        guardHours: guardHours,
        createdAt: DateTime.now(),
      );
      await _d.insert('centers', c.toMap());
      return c;
    }
    await _d.update(
      'centers',
      {'name': name, 'location': location, 'guard_hours': guardHours},
      where: 'id = ?',
      whereArgs: [id],
    );
    final rows = await _d.query('centers', where: 'id = ?', whereArgs: [id], limit: 1);
    return ParkingCenter.fromMap(rows.first);
  }

  @override
  Future<void> deleteCenter(String id) async {
    await _d.transaction((txn) async {
      await txn.delete('vehicles', where: 'center_id = ?', whereArgs: [id]);
      await txn.delete('centers', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ───────────────────────── Véhicules ─────────────────────────

  Future<String> _uniqueCode() async {
    for (var i = 0; i < 40; i++) {
      final code = (100000 + _rng.nextInt(900000)).toString();
      final rows = await _d.query(
        'vehicles',
        columns: ['id'],
        where: 'code = ? AND collected_at IS NULL',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isEmpty) return code;
    }
    throw StateError('Impossible de générer un code unique.');
  }

  @override
  Future<Vehicle> addVehicle({
    required String centerId,
    required String plate,
    required VehicleType type,
    required String ownerName,
    required String ownerPhone,
    required String note,
    required int guardHours,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final v = Vehicle(
      id: _newId(),
      centerId: centerId,
      code: await _uniqueCode(),
      plate: Plates.display(plate),
      type: type,
      ownerName: ownerName.trim(),
      ownerPhone: ownerPhone.trim(),
      note: note.trim(),
      depositedAt: at,
      dueAt: at.add(Duration(hours: guardHours)),
    );
    await _d.insert('vehicles', v.toMap());
    return v;
  }

  @override
  Future<void> updateVehicle(Vehicle v) async {
    await _d.update(
      'vehicles',
      {
        'plate': Plates.display(v.plate),
        'plate_key': Plates.key(v.plate),
        'type': v.type.name,
        'owner_name': v.ownerName.trim(),
        'owner_phone': v.ownerPhone.trim(),
        'note': v.note.trim(),
      },
      where: 'id = ?',
      whereArgs: [v.id],
    );
  }

  @override
  Future<void> markCollected(
    String id, {
    required DateTime at,
    required PickupCheck check,
    required bool ticketVerified,
  }) async {
    await _d.update(
      'vehicles',
      {
        'collected_at': at.millisecondsSinceEpoch,
        'pickup_check': check.name,
        'ticket_verified': ticketVerified ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteVehicle(String id) async {
    await _d.delete('vehicles', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<Vehicle?> vehicleById(String id) async {
    final rows = await _d.query('vehicles', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Vehicle.fromMap(rows.first);
  }

  @override
  Future<Vehicle?> vehicleByCode(String code) async {
    final rows = await _d.query(
      'vehicles',
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'CASE WHEN collected_at IS NULL THEN 0 ELSE 1 END, deposited_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Vehicle.fromMap(rows.first);
  }

  @override
  Future<List<Vehicle>> vehiclesBetween(String centerId, DateTime from, DateTime to) async {
    final rows = await _d.query(
      'vehicles',
      where: 'center_id = ? AND deposited_at >= ? AND deposited_at < ?',
      whereArgs: [centerId, from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
      orderBy: 'deposited_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  @override
  Future<List<Vehicle>> activeVehicles(String centerId) async {
    final rows = await _d.query(
      'vehicles',
      where: 'center_id = ? AND collected_at IS NULL',
      whereArgs: [centerId],
      orderBy: 'deposited_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  @override
  Future<List<Vehicle>> activeByPlateKey(String centerId, String key) async {
    if (key.isEmpty) return const [];
    final rows = await _d.query(
      'vehicles',
      where: 'center_id = ? AND plate_key = ? AND collected_at IS NULL',
      whereArgs: [centerId, key],
      orderBy: 'deposited_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  @override
  Future<List<Vehicle>> search(String centerId, String query, {int limit = 80}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${q.toLowerCase()}%';
    final digits = q.replaceAll(RegExp(r'\s'), '');
    final key = Plates.key(q);

    final clauses = <String>['LOWER(owner_name) LIKE ?', 'owner_phone LIKE ?', 'code LIKE ?'];
    final args = <Object>[like, like, '%$digits%'];
    if (key.isNotEmpty) {
      clauses.add('plate_key LIKE ?');
      args.add('%$key%');
    }

    final rows = await _d.query(
      'vehicles',
      where: 'center_id = ? AND (${clauses.join(' OR ')})',
      whereArgs: [centerId, ...args],
      orderBy: 'deposited_at DESC',
      limit: limit,
    );
    return rows.map(Vehicle.fromMap).toList();
  }

  // ───────────────────────── Réglages ─────────────────────────

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _d.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _d.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
