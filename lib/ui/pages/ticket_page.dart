import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback.dart';
import '../widgets/info_row.dart';

/// Ticket remis au client après l'enregistrement : QR + code à 6 chiffres.
class TicketPage extends StatefulWidget {
  const TicketPage({super.key, required this.id});

  final String id;

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  late final Future<Vehicle?> _future;

  static const _ink = Color(0xFF111111);
  static const _inkSoft = Color(0xFF667781);

  @override
  void initState() {
    super.initState();
    _future = AppScope.read(context).vehicleById(widget.id);
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showToast(context, 'Code copié.');
  }

  Future<void> _whatsapp(Vehicle v, String centerName) async {
    final text = 'Ticket de garde — $centerName\n'
        'Code : ${Fmt.code(v.code)}\n'
        '${v.hasPlate ? 'Plaque : ${v.plate}\n' : ''}'
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
    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Ticket de garde', leadingIcon: AppIcons.close),
      body: FutureBuilder<Vehicle?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final v = snap.data;
          if (v == null) {
            return const EmptyState(icon: AppIcons.warning, title: 'Ticket introuvable');
          }
          final centerName = AppScope.read(context).centerById(v.centerId)?.name ?? 'Garde';
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
                  ],
                ),
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
                PrimaryButton(
                  label: 'Terminé',
                  icon: AppIcons.check,
                  onPressed: () => goBack(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
