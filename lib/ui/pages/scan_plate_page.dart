import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/fields.dart';
import '../widgets/pills.dart';
import '../widgets/scan_overlay.dart';

/// Photo de la plaque → OCR (ML Kit, sur l'appareil, hors-ligne) → plaque corrigeable.
/// Retourne la plaque normalisée (ex. « AB 1234 RB »).
class ScanPlatePage extends StatefulWidget {
  const ScanPlatePage({super.key});

  @override
  State<ScanPlatePage> createState() => _ScanPlatePageState();
}

class _ScanPlatePageState extends State<ScanPlatePage> with WidgetsBindingObserver {
  CameraController? _cam;
  String? _error;
  bool _busy = false;
  bool _torch = false;

  /// Non null = panneau de résultat visible (liste éventuellement vide).
  List<String>? _found;

  final TextEditingController _text = TextEditingController();
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    _recognizer.close();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final old = _cam;
      if (old != null) {
        setState(() => _cam = null);
        old.dispose();
      }
    } else if (state == AppLifecycleState.resumed && _cam == null && _found == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _cam = ctrl;
        _error = null;
        _torch = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code.contains('Denied')
            ? 'Autorisez l\'accès à la caméra dans les réglages du téléphone.'
            : 'Caméra indisponible. Vous pouvez saisir la plaque à la main.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Caméra indisponible. Vous pouvez saisir la plaque à la main.');
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    final next = !_torch;
    try {
      await cam.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _busy || !cam.value.isInitialized) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final shot = await cam.takePicture();
      final result = await _recognizer.processImage(InputImage.fromFilePath(shot.path));
      final lines = <String>[
        for (final b in result.blocks)
          for (final l in b.lines) l.text,
      ];
      final candidates = PlateOcr.candidates(lines);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      if (!mounted) return;
      await cam.pausePreview();
      setState(() {
        _found = candidates;
        _text.text = candidates.isEmpty ? '' : candidates.first;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, 'Lecture impossible. Réessayez ou saisissez la plaque.', error: true);
    }
  }

  void _manual() {
    setState(() {
      _found = const <String>[];
      _text.clear();
    });
  }

  Future<void> _retake() async {
    try {
      await _cam?.resumePreview();
    } catch (_) {}
    if (mounted) setState(() => _found = null);
  }

  void _use() {
    final plate = Plates.display(_text.text);
    if (Plates.key(plate).length < 3) {
      showToast(context, 'Plaque trop courte.', error: true);
      return;
    }
    context.pop(plate);
  }

  Widget _preview(BuildContext context) {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    final size = MediaQuery.sizeOf(context);
    var scale = size.aspectRatio * cam.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(scale: scale, child: Center(child: CameraPreview(cam))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final showPanel = _found != null;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _preview(context),
          if (_error == null) ScanOverlay(aspect: 3.0, color: p.gold, widthFactor: 0.88, centerY: 0.36),

          // Barre du haut
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
                  if (_cam != null && !showPanel)
                    IconButton(
                      iconSize: 28,
                      color: _torch ? p.gold : Colors.white,
                      onPressed: _toggleTorch,
                      icon: Icon(_torch ? AppIcons.flashOn : AppIcons.flashOff),
                    ),
                ],
              ),
            ),
          ),

          // Message d'erreur caméra
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.white, height: 1.4),
                ),
              ),
            ),

          // Consigne + obturateur
          if (!showPanel)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Cadrez la plaque, puis appuyez',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SizedBox(
                            width: 104,
                            child: TextButton.icon(
                              onPressed: _manual,
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                              icon: const Icon(AppIcons.keyboard, size: 22),
                              label: const Text('Saisir', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          _Shutter(busy: _busy, enabled: _cam != null, onTap: _capture),
                          const SizedBox(width: 104),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Panneau de résultat
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showPanel
                  ? AnimatedPadding(
                      key: const ValueKey('panel'),
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                      child: _ResultPanel(
                        candidates: _found!,
                        controller: _text,
                        onPick: (c) => setState(() => _text.text = c),
                        onUse: _use,
                        onRetake: _retake,
                        canRetake: _cam != null,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.busy, required this.enabled, required this.onTap});

  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedScale(
        scale: busy ? 0.92 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? p.gold : Colors.white24,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.candidates,
    required this.controller,
    required this.onPick,
    required this.onUse,
    required this.onRetake,
    required this.canRetake,
  });

  final List<String> candidates;
  final TextEditingController controller;
  final ValueChanged<String> onPick;
  final VoidCallback onUse;
  final VoidCallback onRetake;
  final bool canRetake;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: p.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: p.divider, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            candidates.isEmpty ? 'Saisissez la plaque' : 'Plaque détectée',
            style: context.tt.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            candidates.isEmpty
                ? 'Aucune plaque lue automatiquement.'
                : 'Vérifiez et corrigez si besoin.',
            style: context.tt.bodySmall,
          ),
          if (candidates.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in candidates)
                  ChoicePill(
                    label: c,
                    selected: Plates.key(controller.text) == Plates.key(c),
                    onTap: () => onPick(c),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          AppField(
            controller: controller,
            label: 'Plaque',
            hint: 'AB 1234 RB',
            big: true,
            autofocus: candidates.isEmpty,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [upperCaseFormatter],
            onSubmitted: (_) => onUse(),
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Utiliser cette plaque', icon: AppIcons.check, onPressed: onUse),
          if (canRetake) ...[
            const SizedBox(height: 10),
            GhostButton(label: 'Reprendre la photo', icon: AppIcons.camera, onPressed: onRetake),
          ],
        ],
      ),
    );
  }
}
