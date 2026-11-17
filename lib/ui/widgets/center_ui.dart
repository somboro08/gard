import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import 'action_tile.dart';
import 'feedback.dart';

String _centerSubtitle(ParkingCenter c) {
  final guard = 'Garde ${Fmt.hours(c.guardHours)}';
  return c.location.isEmpty ? guard : '$guard · ${c.location}';
}

/// Titre d'écran façon WhatsApp : nom du centre en gros + chevron (ouvre le sélecteur).
class CenterTitle extends StatelessWidget {
  const CenterTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final center = AppScope.of(context).current;
    if (center == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showCenterSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      center.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(AppIcons.chevronDown, size: 22),
                ],
              ),
              Text(_centerSubtitle(center), style: context.tt.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rappel du centre courant (formulaire d'enregistrement).
class CenterChip extends StatelessWidget {
  const CenterChip({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final center = AppScope.of(context).current;
    if (center == null) return const SizedBox.shrink();
    return Material(
      color: p.field,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showCenterSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: p.goldTint, shape: BoxShape.circle),
                child: Icon(AppIcons.building, color: p.goldText, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      center.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.titleSmall,
                    ),
                    Text(_centerSubtitle(center), style: context.tt.bodySmall),
                  ],
                ),
              ),
              const Icon(AppIcons.chevronDown, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille : choisir / modifier / ajouter un centre de garde.
Future<void> showCenterSheet(BuildContext context) {
  final router = GoRouter.of(context);
  return showAppSheet<void>(
    context: context,
    builder: (ctx) => _CenterSheet(router: router),
  );
}

class _CenterSheet extends StatelessWidget {
  const _CenterSheet({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = AppScope.of(context);
    final currentId = c.current?.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Mes centres de garde'),
        for (final center in c.centers)
          ActionTile(
            icon: AppIcons.building,
            title: center.name,
            subtitle: _centerSubtitle(center),
            selected: center.id == currentId,
            onTap: () async {
              await c.selectCenter(center.id);
              if (context.mounted) Navigator.pop(context);
            },
            trailing: IconButton(
              tooltip: 'Modifier',
              icon: Icon(AppIcons.edit, color: p.textSoft),
              onPressed: () {
                Navigator.pop(context);
                router.push('/center/${center.id}/edit');
              },
            ),
          ),
        const SizedBox(height: 4),
        ActionTile(
          icon: AppIcons.add,
          title: 'Ajouter un centre',
          subtitle: 'Un autre parking ou lieu de garde',
          onTap: () {
            Navigator.pop(context);
            router.push('/center/new');
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Feuille de réglages : thème clair / sombre / auto.
Future<void> showSettingsSheet(BuildContext context) {
  return showAppSheet<void>(context: context, builder: (ctx) => const _SettingsSheet());
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = AppScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetTitle('Réglages'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('Apparence', style: context.tt.bodySmall),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: p.goldTint,
                  selectedForegroundColor: p.text,
                  foregroundColor: p.textSoft,
                  side: BorderSide(color: p.divider, width: 1.5),
                  minimumSize: const Size.fromHeight(52),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                ],
                selected: {c.themeMode},
                onSelectionChanged: (s) => c.setThemeMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Garde · MVP 1.0\nLes données sont stockées sur cet appareil (SQLite).',
              style: context.tt.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
