import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../flows.dart';
import '../widgets/scan_overlay.dart';

/// Scan d'un QR. Par défaut : le ticket (retourne le contenu brut du QR ou le code saisi à la main).
/// Avec [accept], sert aussi aux échanges de la remise sécurisée (défi / réponse du téléphone du client).
class ScanQrPage extends StatefulWidget {
  const ScanQrPage({
    super.key,
    this.accept,
    this.hint = 'Placez le QR du ticket dans le cadre',
    this.unknownHint = 'Ce QR n\'est pas un ticket Garde.',
    this.allowManual = true,
  });

  /// Filtre sur le contenu brut ; null = QR de ticket Garde.
  final bool Function(String raw)? accept;
  final String hint;
  final String unknownHint;
  final bool allowManual;

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  late final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _done = false;
  bool _torch = false;
  bool _unknown = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final accepted = widget.accept != null ? widget.accept!(raw) : Tickets.parse(raw) != null;
      if (accepted) {
        _done = true;
        HapticFeedback.mediumImpact();
        context.pop(raw);
        return;
      }
      if (!_unknown) setState(() => _unknown = true);
    }
  }

  Future<void> _typeCode() async {
    final raw = await showCodeSheet(context);
    if (raw != null && mounted && !_done) {
      _done = true;
      context.pop(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          ScanOverlay(aspect: 1, color: p.gold, widthFactor: 0.72, centerY: 0.40),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 28,
                    color: Colors.white,
                    onPressed: () => context.pop(),
                    icon: const Icon(AppIcons.back),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 28,
                    color: _torch ? p.gold : Colors.white,
                    onPressed: () async {
                      await _scanner.toggleTorch();
                      if (mounted) setState(() => _torch = !_torch);
                    },
                    icon: Icon(_torch ? AppIcons.flashOn : AppIcons.flashOff),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _unknown ? widget.unknownHint : widget.hint,
                        key: ValueKey(_unknown),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _unknown ? const Color(0xFFFF8A80) : Colors.white,
                        ),
                      ),
                    ),
                    if (widget.allowManual) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _typeCode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54, width: 1.5),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(AppIcons.keyboard, size: 22),
                          label: const Text('Saisir le code à la place'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
