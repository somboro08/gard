import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sync_store.dart';
import '../net/api_client.dart';
import '../net/api_exception.dart';
import 'connectivity.dart';
import 'mappers.dart';

enum SyncPhase {
  /// Pas de compte connecté (mode local) ou serveur non configuré.
  off,
  idle,
  offline,
  syncing,
  error,
}

/// État affiché à l'utilisateur (bannière, écran Compte).
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.off,
    this.done = 0,
    this.total = 0,
    this.step = '',
    this.pending = 0,
    this.failed = 0,
    this.lastSyncAt,
    this.error,
    this.sessionExpired = false,
  });

  final SyncPhase phase;

  /// Avancement : étapes terminées / étapes prévues.
  final int done;
  final int total;
  final String step;

  /// Modifications locales pas encore envoyées / refusées par le serveur.
  final int pending;
  final int failed;
  final DateTime? lastSyncAt;
  final String? error;
  final bool sessionExpired;

  double? get progress => total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();

  SyncStatus copyWith({
    SyncPhase? phase,
    int? done,
    int? total,
    String? step,
    int? pending,
    int? failed,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
    bool? sessionExpired,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        step: step ?? this.step,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: clearError ? null : (error ?? this.error),
        sessionExpired: sessionExpired ?? this.sessionExpired,
      );
}

/// Ce qui a changé localement pendant une synchronisation (pour rafraîchir l'écran / le cache).
class SyncChange {
  bool centers = false;
  final Set<String> centerIds = {};
  final Set<String> vehicleIds = {};

  bool get isEmpty => !centers && centerIds.isEmpty && vehicleIds.isEmpty;
}

/// Synchronisation « hors-ligne d'abord » : l'appli travaille toujours sur SQLite ;
/// ce service envoie l'outbox puis reçoit les changements du serveur quand c'est possible.
///
/// Déclencheurs : démarrage, connexion, retour du réseau, retour au premier plan,
/// après chaque modification locale (anti-rebond), toutes les 45 s, bouton « Synchroniser ».
class SyncService extends ChangeNotifier {
  SyncService({
    required SyncStore store,
    required ApiClient api,
    required ConnectivityService connectivity,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 800),
    this.pollEvery = const Duration(seconds: 45),
    DateTime Function()? clock,
  })  : _store = store,
        _api = api,
        _net = connectivity,
        _clock = clock ?? DateTime.now;

  final SyncStore _store;
  final ApiClient _api;
  final ConnectivityService _net;
  final DateTime Function() _clock;
  final void Function(SyncChange change) onChanged;
  final Duration debounce;
  final Duration pollEvery;

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  bool _started = false;
  bool _disposed = false;
  bool _running = false;
  bool _again = false;
  bool _sessionExpired = false;
  int _failures = 0;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Timer? _pollTimer;
  bool _wasOnline = true;

  bool get _enabled => _store.syncEnabled && _api.isConfigured;

  // ───────────── Cycle de vie ─────────────

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _wasOnline = _net.online;
    _net.addListener(_onNetwork);
    _pollTimer = Timer.periodic(pollEvery, (_) {
      if (_enabled && !_running && _net.online && !_sessionExpired) requestSync();
    });
    await refresh();
    if (_enabled) requestSync(immediate: true);
  }

  /// Recalcule l'état affiché (après connexion/déconnexion, changement d'adresse…).
  Future<void> refresh() async {
    if (_disposed) return;
    if (!_enabled) {
      _emit(const SyncStatus());
      return;
    }
    final counts = await _counts();
    _emit(_status.copyWith(
      phase: _sessionExpired
          ? SyncPhase.error
          : (_net.online ? (_status.phase == SyncPhase.syncing ? SyncPhase.syncing : SyncPhase.idle) : SyncPhase.offline),
      pending: counts.$1,
      failed: counts.$2,
      sessionExpired: _sessionExpired,
      error: _sessionExpired ? 'Session expirée : reconnectez-vous.' : null,
      clearError: !_sessionExpired,
    ));
  }

  /// L'API a refusé définitivement le renouvellement de session.
  void markSessionExpired() {
    _sessionExpired = true;
    _retryTimer?.cancel();
    refresh();
  }

  void markSessionValid() {
    _sessionExpired = false;
    _failures = 0;
    refresh();
  }

  /// Arrêt (déconnexion).
  void stop() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _failures = 0;
    _sessionExpired = false;
    _emit(const SyncStatus());
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    _net.removeListener(_onNetwork);
    super.dispose();
  }

  void _onNetwork() {
    final online = _net.online;
    if (online && !_wasOnline) {
      _failures = 0;
      requestSync(immediate: true);
    } else if (!online && _enabled && !_running) {
      refresh();
    }
    _wasOnline = online;
  }

  // ───────────── Déclenchement ─────────────

  /// Demande une synchro (regroupe les demandes rapprochées).
  void requestSync({bool immediate = false}) {
    if (_disposed || !_enabled) return;
    _debounceTimer?.cancel();
    if (immediate) {
      unawaited(syncNow());
    } else {
      _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
    }
    // Les compteurs « en attente » se mettent à jour tout de suite.
    unawaited(refresh());
  }

  /// Synchronise maintenant (bouton « Synchroniser »). Ne lève jamais d'exception.
  Future<void> syncNow() async {
    if (_disposed || !_enabled) return;
    if (_sessionExpired) {
      await refresh();
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    if (!_net.online) {
      await refresh();
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _cycle();
      } while (_again && _failures == 0 && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<(int, int)> _counts() async {
    final pending = await _store.pendingCount();
    final failed = (await _store.failedOps()).length;
    return (pending, failed);
  }

  void _emit(SyncStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  void _progress({int? done, int? total, String? step}) {
    _emit(_status.copyWith(
      phase: SyncPhase.syncing,
      done: done,
      total: total,
      step: step,
      clearError: true,
    ));
  }

  // ───────────── Un cycle : envoyer puis recevoir ─────────────

  Future<void> _cycle() async {
    final change = SyncChange();
    var done = 0;
    var total = 1;
    final resetCursors = <String>{};
    try {
      final ops = await _store.pendingOps(limit: 500);
      total = ops.length + 1;
      _progress(done: 0, total: total, step: ops.isEmpty ? 'Vérification…' : 'Envoi des modifications');

      // 1) Envoi, dans l'ordre. Un refus définitif n'arrête pas la suite ;
      //    un problème de réseau/serveur arrête le cycle (on réessaiera, l'ordre est préservé).
      for (final op in ops) {
        try {
          await _push(op, change);
          await _store.completeOp(op.seq);
        } on ApiException catch (e) {
          if (e.isRetryable || e.kind == ApiErrorKind.unauthorized) {
            await _store.recordOpError(op.seq, e.message, permanent: false);
            rethrow;
          }
          await _store.recordOpError(op.seq, e.message, permanent: true);
          await _compensate(op);
          final cid = op.centerId;
          if (cid != null) resetCursors.add(cid);
        }
        done++;
        _progress(done: done);
      }

      // 2) Réception : liste des centres, puis changements de chaque centre.
      _progress(step: 'Réception des données');
      final list = asMapList(await _api.get('/centers').then((j) => asMap(j)['centers']));
      final centers = [for (final j in list) centerFromJson(j)];
      final roles = <String, String>{
        for (final j in list)
          if (j['role'] is String) j['id'] as String: j['role'] as String,
      };
      total += centers.length;
      final removed = await _store.applyRemoteCenters(centers, roles);
      if (removed.isNotEmpty || centers.isNotEmpty) change.centers = true;
      change.centerIds.addAll(removed);
      done++;
      _progress(done: done, total: total);

      for (final c in centers) {
        if (resetCursors.contains(c.id)) await _store.setSyncValue('cursor:${c.id}', null);
        try {
          await _pullCenter(c.id, change);
        } on ApiException catch (e) {
          // Centre retiré à l'instant : le prochain tour le retirera. Les autres erreurs remontent.
          if (e.kind != ApiErrorKind.notFound && e.kind != ApiErrorKind.forbidden) rethrow;
        }
        done++;
        _progress(done: done);
      }

      _net.reportReachable();
      _failures = 0;
      final counts = await _counts();
      _emit(_status.copyWith(
        phase: SyncPhase.idle,
        done: total,
        total: total,
        pending: counts.$1,
        failed: counts.$2,
        lastSyncAt: _clock(),
        clearError: true,
      ));
    } on ApiException catch (e) {
      await _onApiError(e);
    } on FormatException catch (e) {
      await _onUnexpected(e);
    } catch (e, st) {
      debugPrint('Synchro : $e\n$st');
      await _onUnexpected(e);
    } finally {
      if (!change.isEmpty) onChanged(change);
    }
  }

  Future<void> _onApiError(ApiException e) async {
    final counts = await _counts();
    if (e.isNetwork) {
      _net.reportUnreachable();
      _emit(_status.copyWith(phase: SyncPhase.offline, pending: counts.$1, failed: counts.$2, clearError: true));
      return; // la sonde du réseau relancera la synchro dès le retour
    }
    if (e.kind == ApiErrorKind.unauthorized) {
      _sessionExpired = true;
      _emit(_status.copyWith(
        phase: SyncPhase.error,
        pending: counts.$1,
        failed: counts.$2,
        sessionExpired: true,
        error: 'Session expirée : reconnectez-vous.',
      ));
      return;
    }
    _failures++;
    _emit(_status.copyWith(
      phase: SyncPhase.error,
      pending: counts.$1,
      failed: counts.$2,
      error: e.message,
    ));
    _scheduleRetry();
  }

  Future<void> _onUnexpected(Object e) async {
    _failures++;
    final counts = await _counts();
    _emit(_status.copyWith(
      phase: SyncPhase.error,
      pending: counts.$1,
      failed: counts.$2,
      error: 'Erreur de synchronisation. Nouvel essai automatique.',
    ));
    _scheduleRetry();
  }

  /// Attente exponentielle : 3 s, 6 s, 12 s … 5 min.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final shift = _failures > 7 ? 7 : _failures;
    final secs = (3 * (1 << shift)).clamp(3, 300);
    _retryTimer = Timer(Duration(seconds: secs.toInt()), () {
      if (!_disposed) unawaited(syncNow());
    });
  }

  // ───────────── Envoi d'une opération ─────────────

  Future<void> _push(OutboxOp op, SyncChange change) async {
    final p = op.payload;
    switch (op.kind) {
      case 'center.create':
        await _api.post('/centers', body: p);
        await _store.markCenterKnown(op.entityId);
        change.centers = true;
      case 'center.update':
        await _api.patch('/centers/${op.entityId}', body: p);
      case 'center.delete':
        await _ignoring(ApiErrorKind.notFound, () => _api.delete('/centers/${op.entityId}'));
        await _store.setSyncValue('known:${op.entityId}', null);
      case 'vehicle.create':
        final j = asMap(await _api.post('/centers/${op.centerId}/vehicles', body: p));
        final server = asMap(j['vehicle']);
        final code = server['code'];
        // Deux appareils hors-ligne ont tiré le même code : le serveur en a attribué un autre.
        if (code is String && code != p['code']) {
          await _store.updateLocalVehicleCode(op.entityId, code);
          change.vehicleIds.add(op.entityId);
        }
      case 'vehicle.update':
        await _api.patch('/vehicles/${op.entityId}', body: p);
      case 'vehicle.collect':
        try {
          await _api.post('/vehicles/${op.entityId}/collect', body: p);
        } on ApiException catch (e) {
          if (e.code != 'already_collected') rethrow; // déjà remis ailleurs : l'état est le même
        }
      case 'vehicle.delete':
        await _ignoring(ApiErrorKind.notFound, () => _api.delete('/vehicles/${op.entityId}'));
      case 'payment.add':
        await _api.post('/vehicles/${op.entityId}/payments', body: p);
      default:
        throw ApiException(ApiErrorKind.validation, 'Opération inconnue : ${op.kind}');
    }
  }

  Future<void> _ignoring(ApiErrorKind kind, Future<Object?> Function() f) async {
    try {
      await f();
    } on ApiException catch (e) {
      if (e.kind != kind) rethrow;
    }
  }

  /// Annule localement ce que le serveur a refusé, pour ne pas garder un faux état.
  Future<void> _compensate(OutboxOp op) async {
    if (op.kind == 'payment.add') {
      final id = op.payload['id'];
      if (id is String) await _store.dropLocalPayment(id);
    }
  }

  // ───────────── Réception d'un centre ─────────────

  Future<void> _pullCenter(String centerId, SyncChange change) async {
    final cursor = await _store.syncValue('cursor:$centerId');
    Map<String, String>? query;
    if (cursor != null) {
      final t = DateTime.tryParse(cursor);
      // Marge de 5 s : absorbe les transactions longues côté serveur (le rejeu est sans danger).
      if (t != null) query = {'since': isoUtc(t.subtract(const Duration(seconds: 5)))};
    }
    final j = asMap(await _api.get('/centers/$centerId/changes', query: query));
    final r = await _store.applyRemoteChanges(
      centerId,
      vehicles: [for (final v in asMapList(j['vehicles'])) vehicleFromJson(v)],
      payments: [for (final p in asMapList(j['payments'])) paymentFromJson(p)],
      deletedVehicleIds: [for (final d in (j['deletedVehicleIds'] as List? ?? const [])) d as String],
    );
    final serverTime = j['serverTime'];
    if (!r.skipped && serverTime is String) {
      await _store.setSyncValue('cursor:$centerId', serverTime);
    }
    if (r.changedVehicleIds.isNotEmpty) {
      change.centerIds.add(centerId);
      change.vehicleIds.addAll(r.changedVehicleIds);
    }
  }
}
