import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/fields.dart';
import '../widgets/pills.dart';
import '../widgets/vehicle_ui.dart';

const List<int> _presets = [6, 12, 24, 48];

/// Création / modification d'un centre de garde (nom, lieu, durée de garde).
/// En mode [onboarding] : premier lancement, aucun centre n'existe encore.
class CenterFormPage extends StatefulWidget {
  const CenterFormPage({super.key, this.editing, this.onboarding = false});

  final ParkingCenter? editing;
  final bool onboarding;

  @override
  State<CenterFormPage> createState() => _CenterFormPageState();
}

class _CenterFormPageState extends State<CenterFormPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _location = TextEditingController();
  final TextEditingController _custom = TextEditingController();
  final Map<VehicleType, TextEditingController> _prices = {
    for (final t in VehicleType.values) t: TextEditingController(),
  };

  int _hours = 24;
  bool _useCustom = false;
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _location.text = e.location;
      _hours = e.guardHours;
      _useCustom = !_presets.contains(e.guardHours);
      if (_useCustom) _custom.text = '${e.guardHours}';
      for (final t in VehicleType.values) {
        final price = e.tariff.forType(t);
        if (price > 0) _prices[t]!.text = '$price';
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _custom.dispose();
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _effectiveHours => _useCustom ? (int.tryParse(_custom.text.trim()) ?? 0) : _hours;

  int _priceOf(VehicleType t) => int.tryParse(_prices[t]!.text.trim()) ?? 0;

  Tariff get _tariff => Tariff(
        moto: _priceOf(VehicleType.moto),
        velo: _priceOf(VehicleType.velo),
        voiture: _priceOf(VehicleType.voiture),
        autre: _priceOf(VehicleType.autre),
      );

  String? _validateCustom(String? v) {
    if (!_useCustom) return null;
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1 || n > 720) return 'Entre 1 et 720 heures';
    return null;
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    final c = AppScope.read(context);
    setState(() => _saving = true);
    try {
      await c.saveCenter(
        id: widget.editing?.id,
        name: _name.text,
        location: _location.text,
        guardHours: _effectiveHours,
        tariff: _tariff,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (widget.onboarding) {
        context.go('/find');
      } else {
        showToast(context, _isEdit ? 'Centre mis à jour.' : 'Centre créé.');
        goBack(context);
      }
    } catch (_) {
      if (mounted) showToast(context, 'Enregistrement impossible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final center = widget.editing;
    if (center == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Supprimer ce centre ?',
      message:
          '« ${center.name} » et tous ses véhicules enregistrés seront supprimés de cet appareil. Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    final c = AppScope.read(context);
    await c.removeCenter(center.id);
    if (!mounted) return;
    // S'il ne reste aucun centre, le routeur redirige vers l'écran d'accueil.
    if (c.centers.isNotEmpty) goBack(context);
  }

  Widget _priceField(VehicleType t) {
    return AppField(
      controller: _prices[t]!,
      label: t.label,
      hint: '0',
      icon: t.icon,
      maxLength: 6,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final onboarding = widget.onboarding;

    return Scaffold(
      backgroundColor: p.bg,
      appBar: onboarding
          ? null
          : simpleBar(context, _isEdit ? 'Modifier le centre' : 'Nouveau centre'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  children: [
                    if (onboarding) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(color: p.goldTint, shape: BoxShape.circle),
                          child: Icon(AppIcons.shield, size: 46, color: p.goldText),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Bienvenue sur Garde',
                        textAlign: TextAlign.center,
                        style: context.tt.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créez votre premier centre de garde pour commencer à enregistrer des véhicules.',
                        textAlign: TextAlign.center,
                        style: context.tt.bodyMedium?.copyWith(color: p.textSoft, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => context.push('/account'),
                          icon: Icon(AppIcons.account, color: p.goldText),
                          label: Text(
                            'J\'ai déjà un compte · Se connecter',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: p.goldText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    AppField(
                      controller: _name,
                      label: 'Nom du centre',
                      hint: 'Parking de l\'école, Marché…',
                      icon: AppIcons.building,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v ?? '').trim().length < 2 ? 'Donnez un nom au centre' : null,
                    ),
                    const SizedBox(height: 14),
                    AppField(
                      controller: _location,
                      label: 'Lieu (facultatif)',
                      hint: 'Quartier, ville',
                      icon: AppIcons.location,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 26, 4, 6),
                      child: Text(
                        'Durée de garde',
                        style: context.tt.labelMedium?.copyWith(color: p.goldText, fontSize: 15),
                      ),
                    ),
                    Text(
                      'Passé ce délai, un véhicule non récupéré passe en « Non récupéré ».',
                      style: context.tt.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final h in _presets)
                          ChoicePill(
                            label: Fmt.hours(h),
                            selected: !_useCustom && _hours == h,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _useCustom = false;
                                _hours = h;
                              });
                            },
                          ),
                        ChoicePill(
                          label: 'Autre',
                          selected: _useCustom,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _useCustom = true);
                          },
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _useCustom
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: AppField(
                                controller: _custom,
                                label: 'Durée en heures',
                                hint: 'ex. 12 ou 72',
                                icon: AppIcons.clock,
                                keyboardType: TextInputType.number,
                                maxLength: 3,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                validator: _validateCustom,
                                onChanged: (_) => setState(() {}),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 28, 4, 6),
                      child: Text(
                        'Tarifs (FCFA)',
                        style: context.tt.labelMedium?.copyWith(color: p.goldText, fontSize: 15),
                      ),
                    ),
                    Text(
                      'Prix d\'une garde de ${Fmt.hours(_effectiveHours > 0 ? _effectiveHours : 24)}, '
                      'selon le type de véhicule. Laissez vide pour « gratuit ».',
                      style: context.tt.bodySmall?.copyWith(height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < VehicleType.values.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(child: _priceField(VehicleType.values[i])),
                            const SizedBox(width: 12),
                            Expanded(child: _priceField(VehicleType.values[i + 1])),
                          ],
                        ),
                      ),
                    if (_isEdit) ...[
                      const SizedBox(height: 2),
                      Text(
                        'La nouvelle durée et les nouveaux tarifs s\'appliquent aux prochains dépôts. '
                        'Les véhicules déjà enregistrés gardent leur échéance et leur prix.',
                        style: context.tt.bodySmall?.copyWith(height: 1.35),
                      ),
                      const SizedBox(height: 28),
                      GhostButton(
                        label: 'Supprimer ce centre',
                        icon: AppIcons.trash,
                        danger: true,
                        onPressed: _delete,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: PrimaryButton(
                label: _isEdit ? 'Enregistrer' : 'Créer le centre',
                icon: AppIcons.check,
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
