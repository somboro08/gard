import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_reporter.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../net/api_exception.dart';
import '../../state/app_controller.dart';
import '../../sync/team_service.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback.dart';
import '../widgets/fields.dart';

/// Équipe d'un centre : le propriétaire ajoute ou retire des agents (par numéro de téléphone),
/// chacun peut quitter le centre. Nécessite le réseau (les droits sont gérés par le serveur).
class TeamPage extends StatefulWidget {
  const TeamPage({super.key, required this.centerId});

  final String centerId;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();

  List<Member>? _members;
  String? _error;
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _message(Object e) =>
      e is ApiException ? e.message : 'Une erreur est survenue. Réessayez.';

  Future<void> _load() async {
    final team = AppScope.read(context).team;
    if (team == null) {
      setState(() {
        _loading = false;
        _error = 'La synchronisation n\'est pas disponible sur cet appareil.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await team.list(widget.centerId);
      if (!mounted) return;
      setState(() {
        _members = list;
        _loading = false;
      });
    } catch (e, st) {
      if (e is! ApiException) ErrorReporter.report(e, st, where: 'équipe · liste');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _add() async {
    if (!(_form.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }
    final c = AppScope.read(context);
    setState(() => _adding = true);
    try {
      final m = await c.team!.add(widget.centerId, phone: _phone.text.trim());
      if (!mounted) return;
      _phone.clear();
      FocusScope.of(context).unfocus();
      showToast(context, '${m.name.isEmpty ? m.phone : m.name} ajouté(e) comme agent.');
      await _load();
    } catch (e, st) {
      if (e is! ApiException) ErrorReporter.report(e, st, where: 'équipe · ajout');
      if (mounted) showToast(context, _message(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(Member m, {required bool self}) async {
    final ok = await confirmDialog(
      context,
      title: self ? 'Quitter ce centre ?' : 'Retirer cet agent ?',
      message: self
          ? 'Vous ne verrez plus ce centre ni ses véhicules sur cet appareil après la prochaine synchronisation.'
          : '${m.name.isEmpty ? m.phone : m.name} n\'aura plus accès à ce centre.',
      confirmLabel: self ? 'Quitter' : 'Retirer',
      danger: true,
    );
    if (!ok || !mounted) return;
    final c = AppScope.read(context);
    try {
      await c.team!.remove(widget.centerId, m.id);
      if (!mounted) return;
      if (self) {
        // Le centre disparaît de cet appareil au prochain cycle de synchro.
        c.sync?.requestSync(immediate: true);
        Navigator.of(context).pop();
      } else {
        showToast(context, 'Agent retiré.');
        await _load();
      }
    } catch (e, st) {
      if (e is! ApiException) ErrorReporter.report(e, st, where: 'équipe · retrait');
      if (mounted) showToast(context, _message(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = AppScope.of(context);
    final isOwner = c.roleOf(widget.centerId) == 'owner';
    final me = c.session?.user?.id;

    Widget body;
    if (_loading && _members == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_members == null) {
      body = EmptyState(
        icon: AppIcons.warning,
        title: 'Équipe indisponible',
        message: _error ?? 'Impossible de charger l\'équipe.',
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    } else {
      final members = _members!;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: context.tt.bodySmall?.copyWith(color: p.danger)),
              ),
            if (isOwner) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ajouter un agent', style: context.tt.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'L\'agent doit d\'abord créer son compte dans l\'app (Compte et synchronisation), '
                        'puis vous saisissez son numéro.',
                        style: context.tt.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      AppField(
                        controller: _phone,
                        label: 'Numéro de l\'agent',
                        hint: '01 97 00 00 00',
                        icon: AppIcons.phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(),
                        validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 8
                            ? 'Numéro invalide.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Ajouter',
                        icon: AppIcons.add,
                        loading: _adding,
                        onPressed: _adding ? null : _add,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Membres (${members.length})', style: context.tt.titleMedium),
            ),
            const SizedBox(height: 8),
            for (final m in members)
              _MemberTile(
                member: m,
                isMe: m.id == me,
                // Le propriétaire retire les autres ; chacun peut se retirer lui-même.
                onRemove: (isOwner && m.id != me) || (m.id == me && !m.isOwner)
                    ? () => _remove(m, self: m.id == me)
                    : null,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Équipe du centre'),
      body: body,
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.isMe, this.onRemove});

  final Member member;
  final bool isMe;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final title = member.name.isEmpty ? '+${member.phone}' : member.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: member.isOwner ? p.goldTint : p.field,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.user, color: member.isOwner ? p.goldText : p.textSoft, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$title (vous)' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${member.isOwner ? 'Propriétaire' : 'Agent'} · +${member.phone}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall,
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: isMe ? 'Quitter' : 'Retirer',
              icon: Icon(isMe ? AppIcons.logout : AppIcons.trash, color: p.danger),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
