import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/plates.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// État global : centres, centre courant, thème. Toute modification de données
/// incrémente [revision] pour que les écrans rechargent leurs listes.
class AppController extends ChangeNotifier {
  AppController(this._repo);

  final ParkingRepository _repo;

  List<ParkingCenter> _centers = const [];
  String? _currentId;
  ThemeMode _themeMode = ThemeMode.system;
  int _revision = 0;

  List<ParkingCenter> get centers => _centers;
  ThemeMode get themeMode => _themeMode;
  int get revision => _revision;

  ParkingCenter? get current {
    for (final c in _centers) {
      if (c.id == _currentId) return c;
    }
    return _centers.isEmpty ? null : _centers.first;
  }

  ParkingCenter? centerById(String id) {
    for (final c in _centers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> init() async {
    await _repo.init();
    _centers = await _repo.centers();
    _currentId = await _repo.getSetting('current_center');
    final theme = await _repo.getSetting('theme_mode');
    _themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void _bump() {
    _revision++;
    notifyListeners();
  }

  // ───────────── Réglages ─────────────

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _repo.setSetting('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    notifyListeners();
  }

  // ───────────── Centres ─────────────

  Future<ParkingCenter> saveCenter({
    String? id,
    required String name,
    required String location,
    required int guardHours,
  }) async {
    final c = await _repo.saveCenter(
      id: id,
      name: name.trim(),
      location: location.trim(),
      guardHours: guardHours,
    );
    _centers = await _repo.centers();
    if (id == null) {
      _currentId = c.id;
      await _repo.setSetting('current_center', c.id);
    }
    _bump();
    return c;
  }

  Future<void> removeCenter(String id) async {
    await _repo.deleteCenter(id);
    _centers = await _repo.centers();
    if (_currentId == id) {
      _currentId = _centers.isEmpty ? null : _centers.first.id;
      if (_currentId != null) await _repo.setSetting('current_center', _currentId!);
    }
    _bump();
  }

  Future<void> selectCenter(String id) async {
    if (_currentId == id) return;
    _currentId = id;
    await _repo.setSetting('current_center', id);
    _bump();
  }

  // ───────────── Véhicules ─────────────

  Future<Vehicle> registerVehicle({
    required String plate,
    required VehicleType type,
    required String ownerName,
    required String ownerPhone,
    required String note,
  }) async {
    final center = current;
    if (center == null) throw StateError('Aucun centre sélectionné.');
    final v = await _repo.addVehicle(
      centerId: center.id,
      plate: plate,
      type: type,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      note: note,
      guardHours: center.guardHours,
    );
    _bump();
    return v;
  }

  Future<void> updateVehicle(Vehicle v) async {
    await _repo.updateVehicle(v);
    _bump();
  }

  Future<void> collect(Vehicle v, PickupCheck check, {required bool ticketVerified}) async {
    await _repo.markCollected(
      v.id,
      at: DateTime.now(),
      check: check,
      ticketVerified: ticketVerified,
    );
    _bump();
  }

  Future<void> deleteVehicle(String id) async {
    await _repo.deleteVehicle(id);
    _bump();
  }

  Future<Vehicle?> vehicleById(String id) => _repo.vehicleById(id);

  Future<Vehicle?> vehicleByCode(String code) => _repo.vehicleByCode(code);

  /// Tous les véhicules déposés pendant la semaine commençant à [weekStart] (lundi).
  Future<List<Vehicle>> vehiclesOfWeek(DateTime weekStart) {
    final center = current;
    if (center == null) return Future.value(const <Vehicle>[]);
    return _repo.vehiclesBetween(center.id, weekStart, Fmt.addDays(weekStart, 7));
  }

  Future<List<Vehicle>> search(String query) {
    final center = current;
    if (center == null) return Future.value(const <Vehicle>[]);
    return _repo.search(center.id, query);
  }

  /// Plaque déjà en garde (comparaison stricte) — pour avertir d'un doublon.
  Future<List<Vehicle>> activeByPlateExact(String plate) {
    final center = current;
    if (center == null) return Future.value(const <Vehicle>[]);
    return _repo.activeByPlateKey(center.id, Plates.key(plate));
  }

  /// Retrouve les véhicules en garde dont la plaque ressemble à [plate] (tolère l'OCR).
  Future<List<Vehicle>> findActiveByPlate(String plate) async {
    final center = current;
    if (center == null) return const <Vehicle>[];
    final all = await _repo.activeVehicles(center.id);
    final hits = <(Vehicle, PlateMatch)>[];
    for (final v in all) {
      if (!v.hasPlate) continue;
      final m = Plates.compare(v.plate, plate);
      if (m != PlateMatch.different) hits.add((v, m));
    }
    hits.sort((a, b) => a.$2.index.compareTo(b.$2.index));
    return hits.map((e) => e.$1).toList();
  }
}

/// Accès à l'[AppController] depuis n'importe quel widget.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  /// Lecture + abonnement (le widget se reconstruit quand l'état change).
  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope introuvable dans l\'arbre.');
    return scope!.notifier!;
  }

  /// Lecture seule, sans abonnement (pour les callbacks).
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope introuvable dans l\'arbre.');
    return scope!.notifier!;
  }
}
