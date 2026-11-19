import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Source de l'état du réseau (remplaçable dans les tests).
abstract class NetworkProbe {
  Future<bool> hasNetwork();
  Stream<bool> get changes;
}

class PluginNetworkProbe implements NetworkProbe {
  PluginNetworkProbe([Connectivity? c]) : _c = c ?? Connectivity();

  final Connectivity _c;

  static bool _any(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);

  @override
  Future<bool> hasNetwork() async {
    try {
      return _any(await _c.checkConnectivity());
    } catch (_) {
      return true; // dans le doute on tente : l'API dira si c'est injoignable
    }
  }

  @override
  Stream<bool> get changes => _c.onConnectivityChanged.map(_any);
}

/// « En ligne » = un réseau est présent ET le serveur répond.
/// Avoir du Wi-Fi ne prouve pas que l'API est joignable (forfait épuisé, panne) :
/// quand une requête échoue, on sonde le serveur à intervalles croissants jusqu'au retour.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({
    required NetworkProbe probe,
    required Future<bool> Function() ping,
    this.maxProbeDelay = const Duration(seconds: 60),
  })  : _probe = probe,
        _ping = ping;

  final NetworkProbe _probe;
  final Future<bool> Function() _ping;
  final Duration maxProbeDelay;

  bool _network = true;
  bool _reachable = true;
  StreamSubscription<bool>? _sub;
  Timer? _probeTimer;
  int _probes = 0;
  bool _disposed = false;

  bool get online => _network && _reachable;
  bool get hasNetwork => _network;

  Future<void> start() async {
    _network = await _probe.hasNetwork();
    _sub = _probe.changes.listen((has) {
      if (has == _network) return;
      _network = has;
      if (has) {
        // Réseau revenu : on vérifie tout de suite que le serveur répond.
        _reachable = false;
        _probeNow();
      } else {
        _probeTimer?.cancel();
      }
      _notify();
    });
  }

  /// Une requête vient d'échouer faute de réseau : on passe hors-ligne et on guette le retour.
  void reportUnreachable() {
    if (!_reachable && _probeTimer != null) return;
    _reachable = false;
    _scheduleProbe();
    _notify();
  }

  /// Une requête a abouti : le serveur répond.
  void reportReachable() {
    if (_reachable) return;
    _reachable = true;
    _probes = 0;
    _probeTimer?.cancel();
    _probeTimer = null;
    _notify();
  }

  void _scheduleProbe() {
    _probeTimer?.cancel();
    if (!_network) return; // sans réseau, on attend l'événement du système
    final shift = _probes > 5 ? 5 : _probes;
    final secs = math.min(3 * (1 << shift), maxProbeDelay.inSeconds);
    _probeTimer = Timer(Duration(seconds: secs), _probeNow);
  }

  Future<void> _probeNow() async {
    _probeTimer?.cancel();
    _probeTimer = null;
    bool ok;
    try {
      ok = await _ping();
    } catch (_) {
      ok = false;
    }
    if (_disposed) return;
    if (ok) {
      reportReachable();
    } else {
      _probes++;
      _scheduleProbe();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _probeTimer?.cancel();
    super.dispose();
  }
}
