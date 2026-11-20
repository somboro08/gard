import 'dart:async';

import 'core/error_reporter.dart';
import 'data/sqlite_repository.dart';
import 'data/sqlite_sync_store.dart';
import 'net/api_client.dart';
import 'net/api_config.dart';
import 'net/token_store.dart';
import 'state/app_controller.dart';
import 'sync/connectivity.dart';
import 'sync/session.dart';
import 'sync/sync_service.dart';
import 'sync/team_service.dart';

/// Assemble l'application : base locale, cache, compte, réseau, synchronisation.
///
/// L'appli démarre TOUJOURS depuis la base locale. Si la couche réseau échoue à s'initialiser
/// (plugin indisponible…), elle reste utilisable en mode local au lieu de planter.
Future<AppController> createAppController() async {
  final repo = SqliteParkingRepository();
  final controller = AppController(repo);
  await controller.init(); // ouvre SQLite (migrations comprises)

  try {
    final store = SqliteSyncStore(repo);
    final config = ApiConfig(await repo.getSetting('api_url'));
    final tokens = SecureTokenStore();
    final api = ApiClient(baseUrl: () => config.url, tokens: tokens);
    final net = ConnectivityService(probe: PluginNetworkProbe(), ping: api.ping);
    final sync = SyncService(
      store: store,
      api: api,
      connectivity: net,
      onChanged: (change) => unawaited(controller.onSyncChange(change)),
    );
    final session = SessionController(
      api: api,
      tokens: tokens,
      settings: repo,
      store: store,
      onLocalDataReset: controller.onLocalDataReset,
    )..sync = sync;

    controller
      ..sync = sync
      ..syncStore = store
      ..session = session
      ..team = TeamService(api)
      ..apiConfig = config;

    await session.init();
    await controller.loadRoles();
    await net.start();
    await sync.start();
  } catch (e, st) {
    ErrorReporter.report(e, st, where: 'démarrage synchro');
  }
  return controller;
}
