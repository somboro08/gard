import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/format.dart';
import '../core/icons.dart';
import '../core/plates.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'widgets/action_tile.dart';
import 'widgets/buttons.dart';
import 'widgets/feedback.dart';
import 'widgets/fields.dart';
import 'widgets/vehicle_ui.dart';

/// Façons de retrouver un auto.
enum FindAction { qr, code, plate }

/// Feuille « Comment retrouver ? ». Retourne l'action choisie.
Future<FindAction?> showFindMethodSheet(
  BuildContext context, {
  required String title,
  required List<FindAction> actions,
}) {
  return showAppSheet<FindAction>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetTitle(title),
        for (final a in actions)
          ActionTile(
            icon: switch (a) {
              FindAction.qr => AppIcons.scan,
              FindAction.code => AppIcons.keyboard,
              FindAction.plate => AppIcons.camera,
            },
            title: switch (a) {
              FindAction.qr => 'Scanner le QR du ticket',
              FindAction.code => 'Saisir le code du ticket',
              FindAction.plate => 'Scanner la plaque',
            },
            subtitle: switch (a) {
              FindAction.qr => 'Le client présente son ticket',
              FindAction.code => 'Code à 6 chiffres',
              FindAction.plate => 'Retrouver un auto à partir de sa plaque',
            },
            onTap: () => Navigator.pop(ctx, a),
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// Exécute le parcours choisi : ouvre la fiche du véhicule trouvé.
Future<void> runFindAction(BuildContext context, FindAction action) async {
  switch (action) {
    case FindAction.qr:
      {
        final raw = await context.push<String>('/scan/qr');
        if (raw == null || !context.mounted) return;
        await openByTicket(context, raw);
      }
    case FindAction.code:
      {
        final raw = await showCodeSheet(context);
        if (raw == null || !context.mounted) return;
        await openByTicket(context, raw);
      }
    case FindAction.plate:
      {
        final plate = await context.push<String>('/scan/plate');
        if (plate == null || !context.mounted) return;
        await openByPlate(context, plate);
      }
  }
}

/// Ticket (QR ou code) → fiche du véhicule, marquée « ticket validé ».
Future<void> openByTicket(BuildContext context, String raw) async {
  final c = AppScope.read(context);
  final code = Tickets.parse(raw);
  if (code == null) {
    showToast(context, 'Ce QR n\'est pas un ticket Garde.', error: true);
    return;
  }
  final v = await c.vehicleByCode(code);
  if (!context.mounted) return;
  if (v == null) {
    showToast(context, 'Aucun ticket ne correspond au code ${Fmt.code(code)}.', error: true);
    return;
  }
  if (v.centerId != c.current?.id) {
    await c.selectCenter(v.centerId);
    if (!context.mounted) return;
  }
  HapticFeedback.mediumImpact();
  context.push('/vehicle/${v.id}?t=1');
}

/// Plaque scannée → véhicules en garde qui lui ressemblent.
Future<void> openByPlate(BuildContext context, String plate) async {
  final c = AppScope.read(context);
  final hits = await c.findActiveByPlate(plate);
  if (!context.mounted) return;
  if (hits.isEmpty) {
    showToast(context, 'Aucun véhicule en garde avec la plaque « $plate ».', error: true);
    return;
  }
  if (hits.length == 1) {
    context.push('/vehicle/${hits.first.id}');
    return;
  }
  final picked = await showAppSheet<Vehicle>(
    context: context,
    builder: (ctx) {
      final now = DateTime.now();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetTitle('Plusieurs véhicules correspondent'),
          for (final v in hits)
            VehicleTile(vehicle: v, now: now, showDate: true, onTap: () => Navigator.pop(ctx, v)),
          const SizedBox(height: 12),
        ],
      );
    },
  );
  if (picked != null && context.mounted) {
    context.push('/vehicle/${picked.id}');
  }
}

/// Feuille de saisie du code à 6 chiffres. Retourne le code.
Future<String?> showCodeSheet(BuildContext context) {
  return showAppSheet<String>(context: context, builder: (ctx) => const _CodeSheet());
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet();

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final TextEditingController _ctrl = TextEditingController();

  bool get _ready => _ctrl.text.length == 6;

  void _submit() {
    if (_ready) Navigator.pop(context, _ctrl.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetTitle('Code du ticket', subtitle: 'Saisissez les 6 chiffres remis au client.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AppField(
            controller: _ctrl,
            label: 'Code',
            hint: '000000',
            big: true,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: PrimaryButton(
            label: 'Rechercher',
            icon: AppIcons.search,
            onPressed: _ready ? _submit : null,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
