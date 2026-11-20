import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/plates.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/sync_store.dart';
import '../net/api_config.dart';
import '../sync/session.dart';
import '../sync/sync_service.dart';
import '../sync/team_service.dart';
import 'query_cache.dart';

/// État global : centres, centre courant, thème. Toute modification de données
/// incrémente [revision] pour que les écrans rechargent leurs listes.
class AppController extends ChangeNotifier {
  AppController(this._repo, {QueryCache? cache}) : cache = cache ?? QueryCache();

  final ParkingRepository _repo;

  /// Cache des listes affichées (invalidé à chaque modification locale ou synchro).
  final QueryCache cache;

  /// Branchés par main.dart (absents en mode « tout local » / dans les tests).
  SyncService? sync;
  SyncStore? syncStore;
  SessionController? session;
  TeamService? team;
  ApiConfig? apiConfig;

  /// Rôle de l'utilisateur dans chaque centre synchronisé (« owner » / « agent »).
  Map<String, String> _roles = const {};

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

  /// Un agent (non propriétaire) ne peut pas supprimer de véhicule ni modifier un centre synchronisé.
  /// En mode local ou sans information de rôle : tout est permis.
  bool canManage(String centerId) {
    final r = _roles[centerId];
    return r == null || r == 'owner';
  }

  /// Rôle dans ce centre (« owner » / « agent »), null si le centre n'est pas synchronisé.
  String? roleOf(String centerId) => _roles[centerId];

  Future<void> _loadRoles() async {
    final store = syncStore;
    if (store == null) return;
    final map = <String, String>{};
    for (final c in _centers) {
      final r = await store.syncValue('role:${c.id}');
      if (r != null) map[c.id] = r;
    }
    _roles = map;
  }

  Future<String?> getSetting(String key) => _repo.getSetting(key);

  Future<void> saveSetting(String key, String value) => _repo.setSetting(key, value);

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

  /// Après l'initialisation de la synchro : rôles par centre.
  Future<void> loadRoles() async {
    await _loadRoles();
    notifyListeners();
  }

  /// Invalide les listes touchées par une modification, puis demande une synchro.
  void _touch(String? centerId, {Iterable<String> vehicleIds = const []}) {
    final tags = <String>{
      if (centerId != null) ...[Tags.vehicles(centerId), Tags.payments(centerId)],
      for (final id in vehicleIds) Tags.vehicle(id),
    };
    cache.invalidate(tags);
    sync?.requestSync();
  }

  /// La synchro a modifié la base locale : on recharge les centres et on invalide ce qui a changé.
  Future<void> onSyncChange(SyncChange change) async {
    if (change.centers || change.centerIds.isNotEmpty) {
      _centers = await _repo.centers();
      if (_currentId != null && !_centers.any((c) => c.id == _currentId)) {
        _currentId = _centers.isEmpty ? null : _centers.first.id;
      }
      await _loadRoles();
    }
    final tags = <String>{
      for (final c in {...change.centerIds, ..._centers.map((c) => c.id)}) ...[
        Tags.vehicles(c),
        Tags.payments(c),
      ],
      for (final v in change.vehicleIds) Tags.vehicle(v),
    };
    cache.invalidate(tags);
    _bump();
  }

  /// Données locales effacées (déconnexion, changement de compte) : on repart de zéro.
  Future<void> onLocalDataReset() async {
    cache.clear();
    _centers = await _repo.centers();
    _currentId = null;
    _roles = const {};
    _bump();
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
    Tariff tariff = const Tariff(),
  }) async {
    final c = await _repo.saveCenter(
      id: id,
      name: name.trim(),
      location: location.trim(),
      guardHours: guardHours,
      tariff: tariff,
    );
    _centers = await _repo.centers();
    if (id == null) {
      _currentId = c.id;
      await _repo.setSetting('current_center', c.id);
    }
    _touch(c.id);
    _bump();
    return c;
  }

  Future<void> removeCenter(String id) async {
    await _repo.deleteCenter(id);
    _touch(id);
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
      price: center.tariff.forType(type),
    );
    _touch(center.id, vehicleIds: [v.id]);
    _bump();
    return v;
  }

  Future<void> updateVehicle(Vehicle v) async {
    var next = v;
    final center = centerById(v.centerId);
    // Tant que rien n'a été encaissé, le prix suit le type de véhicule corrigé.
    if (center != null && v.paidAmount == 0 && !v.isCollected) {
      next = v.copyWith(price: center.tariff.forType(v.type));
    }
    await _repo.updateVehicle(next);
    _touch(v.centerId, vehicleIds: [v.id]);
    _bump();
  }

  /// Encaisse [amount] (par défaut : tout le reste à payer) en espèces.
  Future<void> recordPayment(Vehicle v, {int? amount}) async {
    final due = amount ?? v.balance;
    if (due <= 0) return;
    await _repo.addPayment(
      vehicleId: v.id,
      centerId: v.centerId,
      amount: due,
      method: PaymentMethod.cash,
    );
    _touch(v.centerId, vehicleIds: [v.id]);
    _bump();
  }

  /// Paiements encaissés pendant la semaine commençant à [weekStart] (lundi).
  Future<List<Payment>> paymentsOfWeek(DateTime weekStart) {
    final center = current;
    if (center == null) return Future.value(const <Payment>[]);
    return _repo.paymentsBetween(center.id, weekStart, Fmt.addDays(weekStart, 7));
  }

  /// Montant restant à encaisser sur les véhicules encore en garde.
  Future<int> pendingAmount() {
    final center = current;
    if (center == null) return Future.value(0);
    return _repo.pendingAmount(center.id);
  }

  Future<void> collect(Vehicle v, PickupCheck check, {required bool ticketVerified}) async {
    await _repo.markCollected(
      v.id,
      at: DateTime.now(),
      check: check,
      ticketVerified: ticketVerified,
    );
    _touch(v.centerId, vehicleIds: [v.id]);
    _bump();
  }

  Future<void> deleteVehicle(String id) async {
    final centerId = (await _repo.vehicleById(id))?.centerId;
    await _repo.deleteVehicle(id);
    _touch(centerId, vehicleIds: [id]);
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
