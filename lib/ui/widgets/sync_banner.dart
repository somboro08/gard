import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../../sync/sync_service.dart';

/// Bandeau d'état de la synchronisation, au-dessus de la barre de navigation :
/// hors-ligne, envoi en cours (barre de progression), erreur, « À jour ».
/// Invisible quand tout va bien (ou sans compte connecté).
class SyncBanner extends StatefulWidget {
  const SyncBanner({super.key});

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  SyncService? _sync;
  SyncPhase _lastPhase = SyncPhase.off;
  bool _showDone = false;
  Timer? _doneTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.read(context).sync;
    if (!identical(s, _sync)) {
      _sync?.removeListener(_onStatus);
      _sync = s;
      s?.addListener(_onStatus);
    }
  }

  void _onStatus() {
    final st = _sync?.status;
    if (st == null || !mounted) return;
    // Fin d'une synchro qui avait du travail à faire : « À jour ✓ » quelques secondes.
    if (_lastPhase == SyncPhase.syncing && st.phase == SyncPhase.idle && st.total > 1) {
      _showDone = true;
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showDone = false);
      });
    }
    if (st.phase != SyncPhase.idle) _showDone = false;
    _lastPhase = st.phase;
    setState(() {});
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    _sync?.removeListener(_onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = _sync?.status ?? const SyncStatus();
    final content = _content(context, st);
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: content ?? const SizedBox(key: ValueKey('none'), width: double.infinity),
      ),
    );
  }

  Widget? _content(BuildContext context, SyncStatus st) {
    final p = context.pal;
    final open = () => context.push('/account');

    String plural(int n, String one, String many) => '$n ${n > 1 ? many : one}';

    switch (st.phase) {
      case SyncPhase.off:
        return null;
      case SyncPhase.syncing:
        final label = st.step.isEmpty ? 'Synchronisation…' : st.step;
        return _Bar(
          key: const ValueKey('syncing'),
          color: p.goldTint,
          foreground: p.text,
          onTap: open,
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: p.goldText),
          ),
          text: st.total > 1 ? '$label · ${st.done}/${st.total}' : label,
          progress: st.progress,
          progressColor: p.gold,
        );
      case SyncPhase.offline:
        return _Bar(
          key: const ValueKey('offline'),
          color: p.warnTint,
          foreground: p.warn,
          onTap: open,
          leading: const Icon(AppIcons.cloudOff, size: 22),
          text: st.pending > 0
              ? 'Hors-ligne · ${plural(st.pending, 'modification en attente', 'modifications en attente')}'
              : 'Hors-ligne · tout est enregistré sur cet appareil',
        );
      case SyncPhase.error:
        return _Bar(
          key: ValueKey('error-${st.sessionExpired}'),
          color: p.dangerTint,
          foreground: p.danger,
          onTap: open,
          leading: const Icon(AppIcons.warning, size: 22),
          text: st.sessionExpired
              ? 'Session expirée · reconnectez-vous'
              : (st.error ?? 'Erreur de synchronisation'),
          action: st.sessionExpired ? 'Se connecter' : 'Réessayer',
          onAction: st.sessionExpired ? open : () => _sync?.syncNow(),
        );
      case SyncPhase.idle:
        if (st.failed > 0) {
          return _Bar(
            key: const ValueKey('failed'),
            color: p.warnTint,
            foreground: p.warn,
            onTap: open,
            leading: const Icon(AppIcons.warning, size: 22),
            text: '${plural(st.failed, 'modification refusée', 'modifications refusées')} par le serveur',
            action: 'Voir',
            onAction: open,
          );
        }
        if (_showDone) {
          return _Bar(
            key: const ValueKey('done'),
            color: p.successTint,
            foreground: p.success,
            onTap: open,
            leading: const Icon(AppIcons.cloudDone, size: 22),
            text: 'Tout est synchronisé',
          );
        }
        if (st.pending > 0) {
          return _Bar(
            key: const ValueKey('pending'),
            color: p.field,
            foreground: p.textSoft,
            onTap: open,
            leading: const Icon(AppIcons.sync, size: 22),
            text: '${plural(st.pending, 'modification', 'modifications')} à envoyer',
          );
        }
        return null;
    }
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.color,
    required this.foreground,
    required this.leading,
    required this.text,
    required this.onTap,
    this.progress,
    this.progressColor,
    this.action,
    this.onAction,
  });

  final Color color;
  final Color foreground;
  final Widget leading;
  final String text;
  final VoidCallback onTap;
  final double? progress;
  final Color? progressColor;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  IconTheme(data: IconThemeData(color: foreground), child: leading),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: foreground),
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
            ),
            if (progress != null || progressColor != null)
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: progressColor,
                backgroundColor: Colors.transparent,
              ),
          ],
        ),
      ),
    );
  }
}
