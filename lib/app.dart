import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'router.dart';
import 'state/app_controller.dart';

class GardeApp extends StatefulWidget {
  const GardeApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<GardeApp> createState() => _GardeAppState();
}

class _GardeAppState extends State<GardeApp> {
  late final GoRouter _router = buildRouter(widget.controller);
  final ThemeData _light = buildTheme(Brightness.light);
  final ThemeData _dark = buildTheme(Brightness.dark);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => MaterialApp.router(
          title: 'Garde',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: widget.controller.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          routerConfig: _router,
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => _SystemUi(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// Barres système transparentes, icônes claires/sombres selon le thème.
class _SystemUi extends StatelessWidget {
  const _SystemUi({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final p = context.pal;
    final icons = dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: p.bg,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }
}
