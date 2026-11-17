import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../flows.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback.dart';
import '../widgets/info_row.dart';
import '../widgets/vehicle_ui.dart';

/// Fiche d'un véhicule + vérification à la sortie (ticket, plaque) + remise.
class VehiclePage extends StatefulWidget {
  const VehiclePage({super.key, required this.id, this.ticketVerified = false});

  final String id;

  /// true quand on arrive après un scan de QR / saisie de code valide.
  final bool ticketVerified;

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends State<VehiclePage> {
  Vehicle? _v;
  bool _loading = true;
  late bool _ticketOk;
  String? _scannedPlate;
  PlateMatch? _match;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticketOk = widget.ticketVerified;
    _load();
  }

  Future<void> _load() async {
    final v = await AppScope.read(context).vehicleById(widget.id);
    if (!mounted) return;
    setState(() {
      _v = v;
      _loading = false;
    });
  }

  // ───────────── Vérifications ─────────────

  Future<void> _verifyTicket() async {
    final v = _v;
    if (v == null) return;
    final action = await showFindMethodSheet(
      context,
      title: 'Valider le ticket',
      actions: const [FindAction.qr, FindAction.code],
    );
    if (action == null || !mounted) return;
    final raw = action == FindAction.qr
        ? await context.push<String>('/scan/qr')
        : await showCodeSheet(context);
    if (raw == null || !mounted) return;
    final code = Tickets.parse(raw);
    if (code != null && code == v.code) {
      HapticFeedback.mediumImpact();
      setState(() => _ticketOk = true);
      showToast(context, 'Ticket validé.');
    } else {
      HapticFeedback.heavyImpact();
      showToast(context, 'Ce ticket ne correspond pas à ce véhicule.', error: true);
    }
  }

  Future<void> _scanPlate() async {
    final v = _v;
    if (v == null) return;
    final plate = await context.push<String>('/scan/plate');
    if (plate == null || !mounted) return;
    final m = Plates.compare(v.plate, plate);
    if (m == PlateMatch.exact) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _scannedPlate = plate;
      _match = m;
    });
  }

  // ───────────── Remise ─────────────

  Future<void> _confirm() async {
    final v = _v;
    if (v == null || _busy) return;

    // Paiement : à encaisser avant de remettre le véhicule.
    if (v.balance > 0) {
      final paid = await confirmDialog(
        context,
        title: 'Paiement à encaisser',
        message: '${Fmt.money(v.balance)} à encaisser en espèces avant la remise du véhicule.',
        confirmLabel: 'Encaissé',
      );
      if (!paid || !mounted) return;
      await AppScope.read(context).recordPayment(v);
      if (!mounted) return;
    }

    final issues = <String>[];
    if (!_ticketOk) issues.add('Le ticket du client n\'a pas été validé.');
    if (v.hasPlate) {
      switch (_match) {
        case null:
          issues.add('La plaque n\'a pas été scannée.');
        case PlateMatch.close:
          issues.add('La plaque scannée est proche mais pas identique.');
        case PlateMatch.different:
          issues.add('La plaque scannée est DIFFÉRENTE de celle enregistrée.');
        case PlateMatch.exact:
          break;
      }
    }

    if (issues.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'Vérification incomplète',
        message:
            '${issues.map((e) => '• $e').join('\n')}\n\nConfirmer quand même la remise du véhicule ?',
        confirmLabel: 'Remettre quand même',
        danger: true,
      );
      if (!ok || !mounted) return;
    }

    final check = !v.hasPlate
        ? PickupCheck.skipped
        : switch (_match) {
            PlateMatch.exact => PickupCheck.exact,
            PlateMatch.close => PickupCheck.close,
            PlateMatch.different => PickupCheck.different,
            null => PickupCheck.skipped,
          };

    setState(() => _busy = true);
    try {
      await AppScope.read(context).collect(v, check, ticketVerified: _ticketOk);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      showToast(context, 'Véhicule remis au propriétaire.');
    } catch (_) {
      if (mounted) showToast(context, 'Opération impossible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cashIn(Vehicle v) async {
    final ok = await confirmDialog(
      context,
      title: 'Encaisser en espèces',
      message: '${Fmt.money(v.balance)} reçus du client ?',
      confirmLabel: 'Encaissé',
    );
    if (!ok || !mounted) return;
    await AppScope.read(context).recordPayment(v);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    await _load();
    if (mounted) showToast(context, 'Paiement enregistré.');
  }

  Future<void> _edit(Vehicle v) async {
    await context.push('/vehicle/${v.id}/edit', extra: v);
    if (mounted) {
      setState(() {
        _scannedPlate = null;
        _match = null;
      });
      await _load();
    }
  }

  Future<void> _delete(Vehicle v) async {
    final ok = await confirmDialog(
      context,
      title: 'Supprimer ce véhicule ?',
      message: 'L\'enregistrement et ses paiements seront supprimés de cet appareil (les revenus du jour changeront). Utilisez ceci uniquement pour corriger une erreur de saisie.',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    await AppScope.read(context).deleteVehicle(v.id);
    if (mounted) goBack(context);
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {
      if (mounted) showToast(context, 'Impossible de lancer l\'appel.', error: true);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, 'Code copié.');
  }

  // ───────────── UI ─────────────

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = _v;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(
        context,
        'Détails',
        actions: v == null ? null : [_menu(context, v)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : v == null
              ? const EmptyState(icon: AppIcons.warning, title: 'Véhicule introuvable')
              : _body(context, v),
    );
  }

  Widget _menu(BuildContext context, Vehicle v) {
    final p = context.pal;
    return PopupMenuButton<String>(
      icon: const Icon(AppIcons.more),
      iconSize: 26,
      color: p.sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (value) {
        if (value == 'edit') _edit(v);
        if (value == 'delete') _delete(v);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          height: 52,
          child: Text('Modifier', style: context.tt.bodyLarge),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 52,
          child: Text('Supprimer', style: context.tt.bodyLarge?.copyWith(color: p.danger)),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, Vehicle v) {
    final p = context.pal;
    final now = DateTime.now();
    final status = v.statusAt(now);
    final center = AppScope.of(context).centerById(v.centerId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        // En-tête
        Column(
          children: [
            VehicleAvatar(type: v.type, status: status, size: 78),
            const SizedBox(height: 14),
            Text(
              v.hasPlate ? v.plate : 'Sans plaque',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: v.hasPlate ? p.text : p.textSoft,
              ),
            ),
            const SizedBox(height: 4),
            Text(v.ownerName, style: context.tt.titleMedium),
            const SizedBox(height: 10),
            StatusPill(status: status),
          ],
        ),
        const SizedBox(height: 20),

        // Alertes
        if (v.isCollected && widget.ticketVerified) ...[
          Banner2(
            icon: AppIcons.warning,
            fg: p.danger,
            bg: p.dangerTint,
            text:
                'Ce ticket a déjà été utilisé : véhicule remis le ${Fmt.full(v.collectedAt!)}. Ne remettez rien sans vérification.',
          ),
          const SizedBox(height: 14),
        ] else if (status == VehicleStatus.nonRecupere) ...[
          Banner2(
            icon: AppIcons.clock,
            fg: p.danger,
            bg: p.dangerTint,
            text: 'Délai de garde dépassé de ${Fmt.duration(v.overdue(now))}. Le véhicule est toujours sur place.',
          ),
          const SizedBox(height: 14),
        ],

        // Informations
        InfoCard(
          children: [
            if (v.ownerPhone.isNotEmpty)
              InfoRow(
                icon: AppIcons.phone,
                label: 'Téléphone',
                value: v.ownerPhone,
                trailing: IconButton(
                  tooltip: 'Appeler',
                  icon: Icon(AppIcons.phone, color: p.goldText),
                  onPressed: () => _call(v.ownerPhone),
                ),
              ),
            InfoRow(icon: v.type.icon, label: 'Type', value: v.type.label),
            if (v.note.isNotEmpty) InfoRow(icon: AppIcons.note, label: 'Remarque', value: v.note),
            InfoRow(icon: AppIcons.calendar, label: 'Déposé le', value: Fmt.full(v.depositedAt)),
            InfoRow(
              icon: AppIcons.clock,
              label: 'Fin de garde',
              value: Fmt.full(v.dueAt),
              valueColor: status == VehicleStatus.nonRecupere ? p.danger : null,
            ),
            InfoRow(
              icon: AppIcons.wallet,
              label: 'Paiement',
              value: v.price == 0
                  ? 'Gratuit'
                  : v.isPaid
                      ? 'Payé · ${Fmt.money(v.price)}'
                      : '${Fmt.money(v.balance)} à payer',
              valueColor: v.price == 0 ? null : (v.isPaid ? p.success : p.warn),
              trailing: (!v.isCollected && v.balance > 0)
                  ? TextButton(
                      onPressed: () => _cashIn(v),
                      style: TextButton.styleFrom(
                        foregroundColor: p.goldText,
                        textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Encaisser'),
                    )
                  : null,
            ),
            InfoRow(
              icon: AppIcons.ticket,
              label: 'Code du ticket',
              value: Fmt.code(v.code),
              trailing: IconButton(
                tooltip: 'Copier',
                icon: Icon(AppIcons.copy, color: p.textSoft),
                onPressed: () => _copyCode(v.code),
              ),
            ),
            if (center != null)
              InfoRow(icon: AppIcons.building, label: 'Centre', value: center.name),
          ],
        ),
        const SizedBox(height: 18),

        if (v.isCollected) ..._collectedSection(context, v) else ..._verificationSection(context, v),
      ],
    );
  }

  List<Widget> _collectedSection(BuildContext context, Vehicle v) {
    final p = context.pal;
    final check = v.pickupCheck;
    final ok = check == PickupCheck.exact;
    return [
      InfoCard(
        children: [
          InfoRow(
            icon: AppIcons.check,
            label: 'Récupéré le',
            value: Fmt.full(v.collectedAt!),
            valueColor: p.success,
          ),
          InfoRow(
            icon: AppIcons.ticket,
            label: 'Ticket',
            value: v.ticketVerified ? 'Validé' : 'Non validé',
            valueColor: v.ticketVerified ? null : p.warn,
          ),
          InfoRow(
            icon: AppIcons.shield,
            label: 'Plaque',
            value: check?.label ?? 'Non vérifiée',
            valueColor: ok ? p.success : p.warn,
          ),
        ],
      ),
    ];
  }

  List<Widget> _verificationSection(BuildContext context, Vehicle v) {
    final p = context.pal;

    final _StepState plateState = switch (_match) {
      null => _StepState.pending,
      PlateMatch.exact => _StepState.ok,
      PlateMatch.close => _StepState.warn,
      PlateMatch.different => _StepState.bad,
    };
    final plateSubtitle = switch (_match) {
      null => 'À scanner avec la caméra',
      PlateMatch.exact => 'Plaque conforme',
      PlateMatch.close => 'Plaque proche — vérifiez chaque caractère',
      PlateMatch.different => 'Plaque différente — ne pas remettre',
    };

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Vérification à la sortie', style: context.tt.titleMedium),
            ),
            _Step(
              icon: AppIcons.ticket,
              title: 'Ticket',
              subtitle: _ticketOk ? 'Code ${Fmt.code(v.code)} validé' : 'À scanner ou à saisir',
              state: _ticketOk ? _StepState.ok : _StepState.pending,
              actionLabel: _ticketOk ? null : 'Valider',
              onAction: _verifyTicket,
            ),
            if (v.hasPlate)
              _Step(
                icon: AppIcons.camera,
                title: 'Plaque',
                subtitle: plateSubtitle,
                state: plateState,
                actionLabel: _match == null ? 'Scanner' : 'Rescanner',
                onAction: _scanPlate,
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 8, 10),
                child: Text(
                  'Aucune plaque enregistrée : la vérification se fait avec le ticket.',
                  style: context.tt.bodySmall?.copyWith(height: 1.35),
                ),
              ),
            if (_scannedPlate != null && v.hasPlate)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                child: PlateCompare(stored: v.plate, scanned: _scannedPlate!),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      PrimaryButton(
        label: 'Confirmer la remise',
        icon: AppIcons.check,
        loading: _busy,
        onPressed: _confirm,
      ),
      const SizedBox(height: 10),
      Text(
        'Validez le ticket et la plaque avant de remettre le véhicule.',
        textAlign: TextAlign.center,
        style: context.tt.bodySmall,
      ),
    ];
  }
}

enum _StepState { pending, ok, warn, bad }

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final _StepState state;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (fg, bg, shown) = switch (state) {
      _StepState.pending => (p.textSoft, p.field, icon),
      _StepState.ok => (p.success, p.successTint, AppIcons.check),
      _StepState.warn => (p.warn, p.warnTint, AppIcons.warning),
      _StepState.bad => (p.danger, p.dangerTint, AppIcons.warning),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(shown, color: fg, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.titleSmall),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.tt.bodySmall?.copyWith(
                    color: state == _StepState.pending ? p.textSoft : fg,
                    fontWeight: state == _StepState.pending ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: p.goldText,
                minimumSize: const Size(72, 44),
                textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
