import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/sqlite_repository.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Pour passer à PostgreSQL plus tard : remplacer SqliteParkingRepository
  // par une implémentation API de ParkingRepository. Rien d'autre ne change.
  final controller = AppController(SqliteParkingRepository());
  await controller.init();

  runApp(GardeApp(controller: controller));
}
