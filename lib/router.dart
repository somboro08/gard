import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/icons.dart';
import 'data/models.dart';
import 'state/app_controller.dart';
import 'ui/pages/account_page.dart';
import 'ui/pages/team_page.dart';
import 'ui/pages/center_form_page.dart';
import 'ui/pages/find_page.dart';
import 'ui/pages/register_page.dart';
import 'ui/pages/revenue_page.dart';
import 'ui/pages/scan_plate_page.dart';
import 'ui/pages/scan_qr_page.dart';
import 'ui/pages/shell_page.dart';
import 'ui/pages/ticket_page.dart';
import 'ui/pages/vehicle_page.dart';
import 'ui/widgets/bars.dart';
import 'ui/widgets/empty_state.dart';
import 'ui/widgets/fluid.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Routes :
///  /onboarding            premier lancement (créer le 1er centre)
///  /find   | /register    les 2 onglets du bas
///  /revenue               revenus par jour / semaine
///  /account               compte et synchronisation
///  /center/new            nouveau centre            (glisse depuis la droite)
///  /center/:id/edit       modifier un centre
///  /vehicle/:id           fiche + vérification     (?t=1 : ticket déjà validé)
///  /vehicle/:id/edit      modifier un véhicule
///  /ticket/:id            ticket QR du client      (monte depuis le bas)
///  /scan/qr | /scan/plate scanners plein écran     (montent depuis le bas)
GoRouter buildRouter(AppController controller) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/find',
    refreshListenable: controller,
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (controller.centers.isEmpty) {
        // Sans centre : accueil, ou écran Compte (se connecter pour retrouver ses centres).
        return (location == '/onboarding' || location == '/account') ? null : '/onboarding';
      }
      if (location == '/onboarding') return '/find';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => fadePage(state, const CenterFormPage(onboarding: true)),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) =>
            ShellPage(shell: shell, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/find',
                pageBuilder: (context, state) => const NoTransitionPage(child: FindPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/register',
                pageBuilder: (context, state) => const NoTransitionPage(child: RegisterPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/account',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => slidePage(state, const AccountPage()),
      ),
      GoRoute(
        path: '/center/:id/team',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            slidePage(state, TeamPage(centerId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/revenue',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => slidePage(state, const RevenuePage()),
      ),
      GoRoute(
        path: '/center/new',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => slidePage(state, const CenterFormPage()),
      ),
      GoRoute(
        path: '/center/:id/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final center = AppScope.read(context).centerById(state.pathParameters['id']!);
          return slidePage(
            state,
            center == null ? const _NotFoundPage() : CenterFormPage(editing: center),
          );
        },
      ),
      GoRoute(
        path: '/vehicle/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => slidePage(
          state,
          VehiclePage(
            id: state.pathParameters['id']!,
            ticketVerified: state.uri.queryParameters['t'] == '1',
          ),
        ),
        routes: [
          GoRoute(
            path: 'edit',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (context, state) {
              final vehicle = state.extra;
              return slidePage(
                state,
                vehicle is Vehicle ? RegisterPage(editing: vehicle) : const _NotFoundPage(),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/ticket/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            risePage(state, TicketPage(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/scan/qr',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => risePage(state, const ScanQrPage()),
      ),
      GoRoute(
        path: '/scan/plate',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => risePage(state, const ScanPlatePage()),
      ),
    ],
  );
}

class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: simpleBar(context, 'Introuvable'),
      body: const EmptyState(icon: AppIcons.warning, title: 'Page introuvable'),
    );
  }
}
