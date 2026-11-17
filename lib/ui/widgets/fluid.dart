import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _enter = Duration(milliseconds: 340);
const _exit = Duration(milliseconds: 280);

/// Transition « WhatsApp » : la nouvelle page glisse depuis la droite
/// (avec fondu) pendant que la précédente recule légèrement.
CustomTransitionPage<T> slidePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: _enter,
    reverseTransitionDuration: _exit,
    transitionsBuilder: (context, animation, secondary, child) {
      final inCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final outCurve = CurvedAnimation(
        parent: secondary,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.18, 0)).animate(outCurve),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(inCurve),
          child: FadeTransition(opacity: inCurve, child: child),
        ),
      );
    },
  );
}

/// Transition « feuille » : la page monte depuis le bas (scan, ticket).
CustomTransitionPage<T> risePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Simple fondu (écran d'accueil du premier lancement).
CustomTransitionPage<T> fadePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Apparition douce (fondu + léger glissement) pour les premiers éléments d'une liste.
class Appear extends StatelessWidget {
  const Appear({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (index > 8) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: child,
    );
  }
}
