import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/error_reporter.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../security/pickup_crypto.dart';
import '../../state/app_controller.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import 'exchange_page.dart' show showResponseSheet;

/// Espace client : ce téléphone devient la « clé » du véhicule déposé.
/// Au dépôt, l'agent enrôle ce téléphone ; à la sortie, seul lui peut prouver que son
/// propriétaire est présent — sans Internet, même si le ticket est perdu.
class ClientPage extends StatefulWidget {
  const ClientPage({super.key});

  @override
  State<ClientPage> createState() => _ClientPageState();
}

class _ClientPageState extends State<ClientPage> {
  List<ClientTicket> _tickets = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final v = AppScope.read(context).vault;
    final list = v == null ? const <ClientTicket>[] : await v.tickets();
    if (mounted) setState(() => _tickets = list);
  }

  Future<void> _scan() async {
    final vault = AppScope.read(context).vault;
    if (vault == null) {
      showToast(context, 'Fonction indisponible sur cet appareil.', error: true);
      return;
    }
    final raw = await context.push<String>('/scan/request');
    if (raw == null || !mounted) return;
    final req = PickupRequest.parse(raw);
    if (req == null) {
      showToast(context, 'QR non reconnu.', error: true);
      return;
    }

    final details = 'Centre : ${req.center.isEmpty ? '—' : req.center}\n'
        'Plaque : ${req.plate.isEmpty ? 'sans plaque' : req.plate}\n'
        'Code du ticket : ${Fmt.code(req.code)}';
    final ok = await confirmDialog(
      context,
      title: req.isEnroll ? 'Sécuriser ce véhicule ?' : 'Prouver que ce véhicule est à vous ?',
      message: req.isEnroll
          ? '$details\n\nCe téléphone deviendra la clé de ce véhicule : lui seul pourra le faire sortir.'
          : '$details\n\nNe validez que si vous êtes devant l\'agent pour récupérer CE véhicule.',
      confirmLabel: req.isEnroll ? 'Sécuriser' : 'Je suis le propriétaire',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final qr = req.isEnroll ? await vault.enroll(req) : await vault.respond(req);
      if (!mounted) return;
      if (qr == null) {
        showToast(context, 'Ce téléphone n\'a pas la clé de ce véhicule.', error: true);
        return;
      }
      await _load();
      if (!mounted) return;
      await showResponseSheet(
        context,
        title: req.isEnroll ? 'Réponse d\'enrôlement' : 'Preuve de remise',
        qr: qr,
      );
    } catch (e, st) {
      ErrorReporter.report(e, st, where: 'espace client');
      if (mounted) showToast(context, 'Opération impossible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget(ClientTicket t) async {
    final ok = await confirmDialog(
      context,
      title: 'Oublier ce véhicule ?',
      message: 'Ce téléphone ne pourra plus prouver que ce véhicule est à vous. '
          'À faire seulement après la récupération du véhicule.',
      confirmLabel: 'Oublier',
      danger: true,
    );
    if (!ok || !mounted) return;
    await AppScope.read(context).vault?.forget(t.vehicleId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Espace client'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.shield, color: p.goldText),
                    const SizedBox(width: 10),
                    Text('Votre téléphone, clé de votre véhicule', style: context.tt.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Au dépôt, demandez à l\'agent de « sécuriser avec le téléphone du client », puis scannez son QR ici. '
                  'À la sortie, scannez le QR de l\'agent : seul ce téléphone peut prouver que vous êtes le propriétaire, '
                  'sans Internet et même si vous perdez le ticket.',
                  style: context.tt.bodyMedium?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Scanner un QR du centre',
                  icon: AppIcons.scan,
                  loading: _busy,
                  onPressed: _busy ? null : _scan,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Mes véhicules sécurisés', style: context.tt.titleMedium),
          ),
          const SizedBox(height: 8),
          if (_tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Aucun véhicule sécurisé sur ce téléphone.', style: context.tt.bodySmall),
            )
          else
            for (final t in _tickets) _TicketTile(ticket: t, onForget: () => _forget(t)),
          const SizedBox(height: 18),
          Text(
            'Gardez ce téléphone avec vous : sa clé n\'existe nulle part ailleurs. '
            'Sans lui, l\'agent peut encore vérifier à la main (ticket, plaque, pièce d\'identité).',
            style: context.tt.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.onForget});

  final ClientTicket ticket;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: p.successTint, shape: BoxShape.circle),
            child: Icon(AppIcons.shield, color: p.success, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.plate.isEmpty ? 'Sans plaque' : ticket.plate,
                  style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${ticket.center.isEmpty ? 'Centre' : ticket.center} · ${Fmt.code(ticket.code)} · ${Fmt.full(ticket.enrolledAt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Oublier',
            icon: Icon(AppIcons.trash, color: p.danger),
            onPressed: onForget,
          ),
        ],
      ),
    );
  }
}
