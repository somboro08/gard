import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error_reporter.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../security/pickup_crypto.dart';
import '../../state/app_controller.dart';
import '../../state/query_cache.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback.dart';
import '../widgets/info_row.dart';

/// Ticket remis au client après l'enregistrement : QR + code à 6 chiffres,
/// montant à payer et encaissement en espèces.
class TicketPage extends StatefulWidget {
  const TicketPage({super.key, required this.id});

  final String id;

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  Vehicle? _vehicle;
  bool _loading = true;

  static const _ink = Color(0xFF111111);
  static const _inkSoft = Color(0xFF667781);

  VoidCallback? _stopListening;

  @override
  void initState() {
    super.initState();
    _load();
    _stopListening =
        AppScope.read(context).cache.listenTag(Tags.vehicle(widget.id), _load);
  }

  @override
  void dispose() {
    _stopListening?.call();
    super.dispose();
  }

  Future<void> _load() async {
    final v = await AppScope.read(context).vehicleById(widget.id);
    if (!mounted) return;
    setState(() {
      _vehicle = v;
      _loading = false;
    });
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, 'Code copié.');
  }

  Future<void> _cashIn(Vehicle v) async {
    final ok = await confirmDialog(
      context,
      title: 'Encaisser en espèces',
      message: '${Fmt.money(v.balance)} reçus du client ?',
      confirmLabel: 'Encaissé',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).recordPayment(v);
    } catch (e, st) {
      ErrorReporter.report(e, st, where: 'encaissement');
      if (mounted) showToast(context, 'Encaissement impossible. Réessayez.', error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    await _load();
    if (mounted) showToast(context, 'Paiement enregistré.');
  }

  /// Enrôle le téléphone du client : il pourra seul prouver qu'il est le propriétaire à la sortie.
  Future<void> _secure(Vehicle v, String centerName) async {
    final ex = AgentExchange.enroll(
      vehicleId: v.id,
      code: v.code,
      center: centerName,
      plate: v.plate,
    );
    final res = await context.push<PickupProofResult>('/exchange', extra: ex);
    if (res == null || !res.isOk || !mounted) return;
    try {
      await AppScope.read(context).enrollOwnerKey(v, key: res.key!, nonce: res.nonce!, sig: res.sig!);
    } catch (e, st) {
      ErrorReporter.report(e, st, where: 'enrôlement de la clé');
      if (mounted) showToast(context, 'Enregistrement impossible. Réessayez.', error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    await _load();
    if (mounted) showToast(context, 'Véhicule sécurisé avec le téléphone du client.');
  }

  Future<void> _whatsapp(Vehicle v, String centerName) async {
    final text = 'Ticket de garde — $centerName\n'
        'Code : ${Fmt.code(v.code)}\n'
        '${v.hasPlate ? 'Plaque : ${v.plate}\n' : ''}'
        '${v.price > 0 ? 'Montant : ${Fmt.money(v.price)} (${v.isPaid ? 'payé' : 'à payer'})\n' : ''}'
        'Déposé le ${Fmt.full(v.depositedAt)}\n'
        'À récupérer avant le ${Fmt.full(v.dueAt)}.\n\n'
        'Présentez ce code (ou le QR) pour récupérer votre véhicule.';
    final number = Phones.waNumber(v.ownerPhone);
    final uri = Uri.parse(
      number.isEmpty
          ? 'https://wa.me/?text=${Uri.encodeComponent(text)}'
          : 'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showToast(context, 'WhatsApp est introuvable sur cet appareil.', error: true);
      }
    } catch (_) {
      if (mounted) showToast(context, 'WhatsApp est introuvable sur cet appareil.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = _vehicle;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Ticket de garde', leadingIcon: AppIcons.close),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : v == null
              ? const EmptyState(icon: AppIcons.warning, title: 'Ticket introuvable')
              : _content(context, v),
    );
  }

  Widget _content(BuildContext context, Vehicle v) {
    final p = context.pal;
    final centerName = AppScope.read(context).centerById(v.centerId)?.name ?? 'Garde';
    final due = v.balance;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: p.gold, width: 3),
              ),
              child: Column(
                children: [
                  Text(
                    centerName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ticket de garde',
                    style: TextStyle(fontSize: 14.5, color: _inkSoft),
                  ),
                  const SizedBox(height: 14),
                  QrImageView(
                    data: Tickets.encode(v.code),
                    size: 230,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Fmt.code(v.code),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          InfoCard(
            children: [
              InfoRow(
                icon: AppIcons.car,
                label: 'Plaque',
                value: v.hasPlate ? v.plate : 'Sans plaque',
              ),
              InfoRow(icon: AppIcons.user, label: 'Propriétaire', value: v.ownerName),
              InfoRow(
                icon: AppIcons.calendar,
                label: 'Déposé le',
                value: Fmt.full(v.depositedAt),
              ),
              InfoRow(
                icon: AppIcons.clock,
                label: 'À récupérer avant',
                value: Fmt.full(v.dueAt),
              ),
              InfoRow(
                icon: AppIcons.wallet,
                label: 'Montant',
                value: v.price == 0
                    ? 'Gratuit'
                    : v.isPaid
                        ? 'Payé · ${Fmt.money(v.price)}'
                        : '${Fmt.money(due)} à payer',
                valueColor: v.price == 0 ? null : (v.isPaid ? p.success : p.warn),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (v.isSecured)
            Banner2(
              icon: AppIcons.shield,
              fg: p.success,
              bg: p.successTint,
              text: 'Sécurisé : à la sortie, le client devra prouver son identité avec son téléphone.',
            )
          else if (!v.isCollected) ...[
            GhostButton(
              label: 'Sécuriser avec le téléphone du client',
              icon: AppIcons.shield,
              onPressed: () => _secure(v, centerName),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Demandez au client de garder ce ticket (capture d\'écran ou WhatsApp). '
            'Il devra le présenter pour récupérer son véhicule.',
            style: context.tt.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Copier',
                  icon: AppIcons.copy,
                  onPressed: () => _copy(v.code),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'WhatsApp',
                  icon: AppIcons.send,
                  onPressed: () => _whatsapp(v, centerName),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (due > 0) ...[
            PrimaryButton(
              label: 'Encaisser ${Fmt.money(due)}',
              icon: AppIcons.wallet,
              onPressed: () => _cashIn(v),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Terminé · payer à la sortie',
              icon: AppIcons.check,
              onPressed: () => goBack(context),
            ),
          ] else
            PrimaryButton(
              label: 'Terminé',
              icon: AppIcons.check,
              onPressed: () => goBack(context),
            ),
        ],
      ),
    );
  }
}
