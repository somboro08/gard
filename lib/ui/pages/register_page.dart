import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/center_ui.dart';
import '../widgets/feedback.dart';
import '../widgets/fields.dart';
import '../widgets/vehicle_ui.dart';

/// Onglet « Enregistrer un auto » (et écran de modification quand [editing] est fourni).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.editing});

  final Vehicle? editing;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _plate = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _note = TextEditingController();

  VehicleType _type = VehicleType.moto;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _plate.text = e.plate;
      _name.text = e.ownerName;
      _phone.text = e.ownerPhone;
      _note.text = e.note;
      _type = e.type;
    }
  }

  @override
  void dispose() {
    _plate.dispose();
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _scanPlate() async {
    FocusScope.of(context).unfocus();
    final plate = await context.push<String>('/scan/plate');
    if (plate != null && mounted) {
      setState(() => _plate.text = plate);
      _form.currentState?.validate();
    }
  }

  String? _validatePlate(String? value) {
    final key = Plates.key(value ?? '');
    if (key.isEmpty) {
      return _type.plateRequired ? 'Plaque requise (scannez-la ou saisissez-la)' : null;
    }
    if (key.length < 3) return 'Plaque trop courte';
    return null;
  }

  String? _validateName(String? value) {
    if ((value ?? '').trim().length < 2) return 'Nom du propriétaire requis';
    return null;
  }

  String? _validatePhone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length < 8 ? 'Numéro invalide' : null;
  }

  Future<void> _submit() async {
    final form = _form.currentState;
    if (form == null || !form.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    final c = AppScope.read(context);
    final plate = Plates.display(_plate.text);

    if (_isEdit) {
      setState(() => _saving = true);
      try {
        await c.updateVehicle(
          widget.editing!.copyWith(
            plate: plate,
            type: _type,
            ownerName: _name.text.trim(),
            ownerPhone: _phone.text.trim(),
            note: _note.text.trim(),
          ),
        );
        if (!mounted) return;
        showToast(context, 'Modifications enregistrées.');
        goBack(context);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    // Doublon : même plaque déjà en garde dans ce centre ?
    if (plate.isNotEmpty) {
      final dups = await c.activeByPlateExact(plate);
      if (!mounted) return;
      if (dups.isNotEmpty) {
        final d = dups.first;
        final go = await confirmDialog(
          context,
          title: 'Plaque déjà en garde',
          message:
              '« ${d.plate} » est déjà enregistrée (déposée le ${Fmt.full(d.depositedAt)}, propriétaire : ${d.ownerName}).\n\nEnregistrer quand même ?',
          confirmLabel: 'Enregistrer',
        );
        if (!go || !mounted) return;
      }
    }

    setState(() => _saving = true);
    try {
      final v = await c.registerVehicle(
        plate: plate,
        type: _type,
        ownerName: _name.text.trim(),
        ownerPhone: _phone.text.trim(),
        note: _note.text.trim(),
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _plate.clear();
      _name.clear();
      _phone.clear();
      _note.clear();
      _form.currentState?.reset();
      context.push('/ticket/${v.id}');
    } catch (_) {
      if (mounted) showToast(context, 'Enregistrement impossible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Reconstruit quand le centre change (durée de garde affichée).
    AppScope.of(context);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: _isEdit ? simpleBar(context, 'Modifier le véhicule') : null,
      body: SafeArea(
        bottom: _isEdit,
        child: Column(
          children: [
            if (!_isEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 4, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Enregistrer un auto', style: context.tt.headlineSmall)),
                    IconButton(
                      iconSize: 26,
                      tooltip: 'Réglages',
                      onPressed: () => showSettingsSheet(context),
                      icon: const Icon(AppIcons.more),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    if (!_isEdit) const CenterChip(),
                    const _SectionLabel('Véhicule'),
                    _TypeSelector(
                      value: _type,
                      onChanged: (t) => setState(() => _type = t),
                    ),
                    const SizedBox(height: 14),
                    AppField(
                      controller: _plate,
                      label: _type.plateRequired ? 'Plaque' : 'Plaque (facultatif)',
                      hint: 'AB 1234 RB',
                      big: true,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [upperCaseFormatter],
                      validator: _validatePlate,
                      suffix: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton.filled(
                          tooltip: 'Scanner la plaque',
                          style: IconButton.styleFrom(
                            backgroundColor: p.gold,
                            foregroundColor: p.onGold,
                          ),
                          onPressed: _scanPlate,
                          icon: const Icon(AppIcons.camera),
                        ),
                      ),
                    ),
                    const _SectionLabel('Propriétaire'),
                    AppField(
                      controller: _name,
                      label: 'Nom et prénom',
                      icon: AppIcons.user,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      validator: _validateName,
                    ),
                    const SizedBox(height: 14),
                    AppField(
                      controller: _phone,
                      label: 'Téléphone (facultatif)',
                      icon: AppIcons.phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      validator: _validatePhone,
                    ),
                    const _SectionLabel('Remarque'),
                    AppField(
                      controller: _note,
                      label: 'Couleur, marque… (facultatif)',
                      icon: AppIcons.note,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: PrimaryButton(
                label: _isEdit ? 'Enregistrer les modifications' : 'Enregistrer et créer le ticket',
                icon: _isEdit ? AppIcons.check : AppIcons.ticket,
                loading: _saving,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text,
        style: context.tt.labelMedium?.copyWith(color: context.pal.goldText, fontSize: 15),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final VehicleType value;
  final ValueChanged<VehicleType> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        for (final t in VehicleType.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: t == VehicleType.values.last ? 0 : 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(t);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 78,
                  decoration: BoxDecoration(
                    color: t == value ? p.goldTint : p.field,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: t == value ? p.gold : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(t.icon, size: 28, color: t == value ? p.goldText : p.textSoft),
                      const SizedBox(height: 4),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: t == value ? FontWeight.w700 : FontWeight.w500,
                          color: t == value ? p.text : p.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
