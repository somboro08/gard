import 'dart:async';

import 'package:flutter/foundation.dart';

/// Résultat d'une requête : chargement, données, erreur — et surtout les trois à la fois.
/// Pendant un rafraîchissement ou après une erreur, les DERNIÈRES DONNÉES restent disponibles
/// (l'écran ne clignote pas et ne se vide pas).
@immutable
class Loadable<T> {
  const Loadable({this.data, this.error, this.isLoading = false});

  final T? data;
  final Object? error;
  final bool isLoading;

  bool get hasData => data != null;

  /// Données affichées, mise à jour en cours.
  bool get isRefreshing => isLoading && hasData;

  /// Premier chargement, rien à afficher encore.
  bool get isInitialLoading => isLoading && !hasData;

  bool get hasError => error != null;

  /// Échec sans rien à afficher : écran d'erreur avec « Réessayer ».
  bool get isFailure => hasError && !hasData && !isLoading;
}

/// Une requête en cache : dernière valeur, fraîcheur, dédoublonnage des appels en cours.
class QueryEntry<T> extends ChangeNotifier {
  /// Vrai tant qu'un widget observe cette entrée (jamais évincée dans ce cas).
  bool get isWatched => hasListeners;

  QueryEntry(this.key, this._cache, this._fetch, this.tags);

  final String key;
  final QueryCache _cache;
  Future<T> Function() _fetch;
  Set<String> tags;

  Loadable<T> state = Loadable<T>(isLoading: true);
  DateTime? _fetchedAt;
  bool _stale = true;
  Future<void>? _inflight;
  bool _refetch = false;
  bool _disposed = false;

  /// Remplace la fonction de chargement (le widget peut avoir de nouveaux paramètres).
  void update(Future<T> Function() fetch, Set<String> newTags) {
    _fetch = fetch;
    tags = newTags;
  }

  bool get _isOld {
    final at = _fetchedAt;
    return at == null || _cache._now().difference(at) > _cache.staleAfter;
  }

  /// Charge si rien n'est en cache, si une invalidation a eu lieu, ou si c'est trop vieux.
  void ensureFresh() {
    if (_inflight != null) return;
    if (_stale || _isOld) unawaited(fetch());
  }

  /// Invalidation : on garde l'ancienne valeur affichée, on recharge si l'écran est ouvert.
  void markStale() {
    _stale = true;
    if (hasListeners) unawaited(fetch());
  }

  /// Recharge. Plusieurs appels simultanés = un seul chargement (+ un de plus si invalidé entre-temps).
  Future<void> fetch() {
    final running = _inflight;
    if (running != null) {
      _refetch = true;
      return running;
    }
    return _inflight = _run();
  }

  Future<void> _run() async {
    _stale = false;
    _set(Loadable(data: state.data, isLoading: true));
    try {
      final v = await _fetch();
      _fetchedAt = _cache._now();
      _set(Loadable(data: v));
    } catch (e) {
      _stale = true; // la prochaine ouverture réessaiera
      _set(Loadable(data: state.data, error: e));
    } finally {
      _inflight = null;
    }
    if (_refetch && !_disposed) {
      _refetch = false;
      unawaited(fetch());
    }
  }

  void _set(Loadable<T> s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Cache de requêtes avec invalidation par étiquettes.
///
/// - `entry(clé, fetch, tags)` : la même clé renvoie toujours la même entrée.
/// - `invalidate({'vehicles:c1'})` : toutes les entrées portant cette étiquette sont marquées
///   périmées et rechargées en arrière-plan si un écran les affiche.
/// - Une entrée plus vieille que [staleAfter] est rechargée à l'ouverture de l'écran.
class QueryCache {
  QueryCache({
    this.staleAfter = const Duration(seconds: 30),
    this.maxEntries = 48,
    DateTime Function()? clock,
  }) : _clock = clock;

  final Duration staleAfter;
  final int maxEntries;
  final DateTime Function()? _clock;

  final Map<String, QueryEntry<dynamic>> _entries = {};
  final Map<String, Set<VoidCallback>> _tagListeners = {};

  DateTime _now() => (_clock ?? DateTime.now)();

  int get length => _entries.length;

  QueryEntry<T> entry<T>(String key, Future<T> Function() fetch, {Set<String> tags = const {}}) {
    final existing = _entries.remove(key); // retiré puis réinséré : l'ordre sert de LRU
    if (existing is QueryEntry<T>) {
      existing.update(fetch, tags);
      _entries[key] = existing;
      return existing;
    }
    existing?.dispose();
    final e = QueryEntry<T>(key, this, fetch, tags);
    _entries[key] = e;
    _evict();
    return e;
  }

  void _evict() {
    if (_entries.length <= maxEntries) return;
    final victims = <String>[];
    for (final e in _entries.entries) {
      if (_entries.length - victims.length <= maxEntries) break;
      if (!e.value.isWatched) victims.add(e.key); // jamais une entrée affichée
    }
    for (final k in victims) {
      _entries.remove(k)?.dispose();
    }
  }

  /// Marque périmées toutes les entrées portant l'une de ces étiquettes.
  void invalidate(Iterable<String> tags) {
    final set = tags.toSet();
    if (set.isEmpty) return;
    for (final e in _entries.values.toList()) {
      if (e.tags.any(set.contains)) e.markStale();
    }
    for (final t in set) {
      final ls = _tagListeners[t];
      if (ls == null) continue;
      for (final cb in ls.toList()) {
        cb();
      }
    }
  }

  void invalidateAll() {
    for (final e in _entries.values.toList()) {
      e.markStale();
    }
  }

  /// Vide tout (déconnexion : aucune donnée d'un autre compte ne doit rester en mémoire).
  void clear() {
    for (final e in _entries.values) {
      e.dispose();
    }
    _entries.clear();
  }

  /// Écoute une étiquette (pour les écrans qui chargent eux-mêmes, ex. la fiche véhicule).
  /// Retourne la fonction qui arrête l'écoute.
  VoidCallback listenTag(String tag, VoidCallback onInvalidated) {
    _tagListeners.putIfAbsent(tag, () => {}).add(onInvalidated);
    return () {
      final s = _tagListeners[tag];
      if (s == null) return;
      s.remove(onInvalidated);
      if (s.isEmpty) _tagListeners.remove(tag);
    };
  }
}

/// Étiquettes d'invalidation (centralisées pour éviter les fautes de frappe).
abstract final class Tags {
  static String vehicles(String centerId) => 'vehicles:$centerId';
  static String payments(String centerId) => 'payments:$centerId';
  static String vehicle(String vehicleId) => 'vehicle:$vehicleId';
}
