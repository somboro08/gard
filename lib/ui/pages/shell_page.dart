import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../widgets/sync_banner.dart';

/// Coquille de l'app : 2 onglets (Retrouver / Enregistrer) avec transition fluide.
class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.shell, required this.children});

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: _BranchStack(index: shell.currentIndex, children: children)),
          // État de la synchro (hors-ligne, envoi en cours, erreur) juste au-dessus de la navigation.
          const SyncBanner(),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) {
                HapticFeedback.selectionClick();
                shell.goBranch(i, initialLocation: i == shell.currentIndex);
              },
              destinations: const [
                NavigationDestination(icon: Icon(AppIcons.navFind), label: 'Retrouver'),
                NavigationDestination(icon: Icon(AppIcons.navRegister), label: 'Enregistrer'),
              ],
            ),
    );
  }
}

class _BranchStack extends StatelessWidget {
  const _BranchStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          _Branch(active: i == index, side: i < index ? -1 : 1, child: children[i]),
      ],
    );
  }
}

class _Branch extends StatelessWidget {
  const _Branch({required this.active, required this.side, required this.child});

  final bool active;
  final int side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: !active,
      child: IgnorePointer(
        ignoring: !active,
        // Pas de TickerMode ici : il gèlerait le fondu de l'onglet quitté
        // (opacité bloquée à 1) et il resterait affiché par-dessus l'autre.
        child: AnimatedSlide(
          offset: active ? Offset.zero : Offset(0.06 * side, 0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}
