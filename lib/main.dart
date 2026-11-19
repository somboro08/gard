import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/error_reporter.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Aucune erreur ne doit faire planter l'appli en silence : on les garde pour le diagnostic.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReporter.report(details.exception, details.stack, where: 'flutter');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorReporter.report(error, stack, where: 'async');
    return true;
  };
  ErrorWidget.builder = (details) => const _BrokenWidget();

  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final controller = await createAppController();
  runApp(GardeApp(controller: controller));
}

/// Remplace le carré gris/rouge par défaut quand un widget plante à la construction.
class _BrokenWidget extends StatelessWidget {
  const _BrokenWidget();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Un problème d\'affichage est survenu.\nRevenez en arrière et réessayez.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Color(0xFF8A8A8A)),
          ),
        ),
      ),
    );
  }
}
