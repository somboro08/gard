import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';

/// Retour fiable : pop si possible, sinon retour à l'accueil.
void goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/find');
  }
}

/// Barre d'app simple et épurée (fond uni, sans élévation).
PreferredSizeWidget simpleBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  IconData leadingIcon = AppIcons.back,
}) {
  final p = context.pal;
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: p.bg,
    foregroundColor: p.text,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 64,
    centerTitle: false,
    titleSpacing: 0,
    leading: IconButton(
      iconSize: 26,
      icon: Icon(leadingIcon),
      onPressed: () => goBack(context),
    ),
    title: Text(title, style: context.tt.titleLarge),
    actions: actions,
  );
}
