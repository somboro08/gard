import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/error_reporter.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../security/pickup_crypto.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';

/// Écran de l'agent pour la remise sécurisée : il montre un QR (enrôlement ou défi de remise),
/// le client le scanne avec son téléphone, puis l'agent scanne la réponse.
/// Retourne un [PickupProofResult] valide, ou null si l'agent abandonne.
class ExchangePage extends StatefulWidget {
  const ExchangePage({super.key, required this.exchange});

  final AgentExchange exchange;

  @override
  State<ExchangePage> createState() => _ExchangePageState();
}

class _ExchangePageState extends State<ExchangePage> {
  bool _busy = false;
  String? _error;

  Future<void> _scanResponse() async {
    final raw = await context.push<String>('/scan/response');
    if (raw == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.exchange.verify(raw);
      if (!mounted) return;
      if (result.isOk) {
        HapticFeedback.mediumImpact();
        context.pop(result);
      } else {
        HapticFeedback.heavyImpact();
        setState(() => _error = result.error);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, where: 'remise sécurisée · vérification');
      if (mounted) setState(() => _error = 'Vérification impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ex = widget.exchange;
    final title = ex.isEnroll ? 'Sécuriser avec le téléphone du client' : 'Vérifier le téléphone du client';
    final steps = ex.isEnroll
        ? 'Le client ouvre Garde sur son téléphone › Espace client › « Scanner un QR du centre », '
            'puis scanne ce QR et valide. Ensuite, scannez la réponse affichée sur son téléphone.'
        : 'Le client ouvre Garde › Espace client › « Scanner un QR du centre », scanne ce QR et valide. '
            'Ensuite, scannez la réponse affichée sur son téléphone. Aucune connexion Internet n\'est nécessaire.';

    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, title, leadingIcon: AppIcons.close),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: QrImageView(
                  data: ex.requestQr,
                  size: 260,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF111111),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${ex.center}${ex.plate.isEmpty ? '' : ' · ${ex.plate}'}',
              textAlign: TextAlign.center,
              style: context.tt.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              ex.isEnroll ? 'Enrôlement du véhicule' : 'Défi de remise · valable 3 minutes',
              textAlign: TextAlign.center,
              style: context.tt.bodySmall,
            ),
            const SizedBox(height: 18),
            Text(steps, style: context.tt.bodyMedium?.copyWith(height: 1.4)),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: context.tt.bodyMedium?.copyWith(color: p.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Scanner la réponse du client',
              icon: AppIcons.scan,
              loading: _busy,
              onPressed: _busy ? null : _scanResponse,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Annuler',
              icon: AppIcons.close,
              onPressed: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Montre le QR de réponse du téléphone du client (à scanner par l'agent).
Future<void> showResponseSheet(BuildContext context, {required String title, required String qr}) {
  return showAppSheet<void>(
    context: context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(title),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: QrImageView(
              data: qr,
              size: 260,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111111)),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF111111),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Montrez ce QR à l\'agent : il le scanne avec son téléphone.',
            textAlign: TextAlign.center,
            style: ctx.tt.bodyMedium,
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Terminé', icon: AppIcons.check, onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    ),
  );
}
