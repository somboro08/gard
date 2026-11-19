import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/error_reporter.dart';
import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/sync_store.dart';
import '../../net/api_config.dart';
import '../../net/api_exception.dart';
import '../../state/app_controller.dart';
import '../../sync/sync_service.dart';
import '../widgets/bars.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/fields.dart';
import '../widgets/info_row.dart';

/// Compte (facultatif) et synchronisation : connexion / inscription, état de la synchro,
/// modifications refusées, adresse du serveur, diagnostic.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();

  bool _register = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  List<OutboxOp> _failed = const [];

  @override
  void initState() {
    super.initState();
    final c = AppScope.read(context);
    _server.text = c.apiConfig?.url ?? '';
    c.sync?.addListener(_onSync);
    _loadFailed();
  }

  @override
  void dispose() {
    AppScope.read(context).sync?.removeListener(_onSync);
    _phone.dispose();
    _name.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    _loadFailed();
    setState(() {});
  }

  Future<void> _loadFailed() async {
    final store = AppScope.read(context).syncStore;
    if (store == null) return;
    final list = await store.failedOps();
    if (mounted) setState(() => _failed = list);
  }

  String _message(Object e) => e is ApiException ? e.message : 'Une erreur est survenue. Réessayez.';

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }
    FocusScope.of(context).unfocus();
    final c = AppScope.read(context);
    final session = c.session;
    if (session == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final hadCenters = c.centers.isNotEmpty;
    try {
      if (_register) {
        await session.register(
          phone: _phone.text.trim(),
          name: _name.text.trim(),
          password: _password.text,
        );
      } else {
        await session.login(phone: _phone.text.trim(), password: _password.text);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _password.clear();
      // Arrivé depuis l'accueil sans centre : on attend les centres du compte.
      if (!hadCenters) {
        await c.sync?.syncNow();
        if (!mounted) return;
        if (c.centers.isNotEmpty) {
          context.go('/find');
          return;
        }
      }
      showToast(context, 'Connecté.');
    } catch (e, st) {
      if (e is! ApiException) ErrorReporter.report(e, st, where: 'connexion');
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final c = AppScope.read(context);
    final pending = c.sync?.status.pending ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Se déconnecter ?',
      message: pending > 0
          ? '$pending modification${pending > 1 ? 's' : ''} n\'${pending > 1 ? 'ont' : 'a'} pas encore été envoyée${pending > 1 ? 's' : ''} '
              'et seront PERDUES. Connectez-vous à Internet et synchronisez d\'abord.'
          : 'Les données de cet appareil seront effacées. Elles restent sur le serveur : '
              'vous les retrouverez en vous reconnectant.',
      confirmLabel: 'Se déconnecter',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await c.session?.logout();
      if (mounted) context.go('/onboarding');
    } catch (e, st) {
      ErrorReporter.report(e, st, where: 'déconnexion');
      if (mounted) showToast(context, 'Déconnexion impossible. Réessayez.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveServer() async {
    final c = AppScope.read(context);
    final url = ApiConfig.normalize(_server.text);
    c.apiConfig?.url = url;
    await c.saveSetting('api_url', url);
    _server.text = url;
    await c.sync?.refresh();
    if (mounted) showToast(context, url.isEmpty ? 'Mode local (aucun serveur).' : 'Serveur enregistré.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = AppScope.of(context);
    final signedIn = c.session?.signedIn ?? false;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Compte et synchronisation'),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            if (signedIn) ..._signedIn(context, c) else ..._signedOut(context, c),
            const SizedBox(height: 28),
            _serverSection(context),
            const SizedBox(height: 20),
            _diagnostic(context),
          ],
        ),
      ),
    );
  }

  // ───────────── Déconnecté ─────────────

  List<Widget> _signedOut(BuildContext context, AppController c) {
    final p = context.pal;
    final configured = (c.apiConfig?.url ?? '').isNotEmpty;
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.shield, color: p.goldText, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Le compte est facultatif. Sans compte, tout reste sur cet appareil. '
                'Avec un compte, vos données sont sauvegardées, partagées entre vos téléphones et '
                'vos agents, et l\'appli continue de fonctionner sans Internet.',
                style: context.tt.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: p.goldTint,
          selectedForegroundColor: p.text,
          foregroundColor: p.textSoft,
          side: BorderSide(color: p.divider, width: 1.5),
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('Connexion')),
          ButtonSegment(value: true, label: Text('Inscription')),
        ],
        selected: {_register},
        onSelectionChanged: (s) => setState(() {
          _register = s.first;
          _error = null;
        }),
      ),
      const SizedBox(height: 18),
      Form(
        key: _form,
        child: Column(
          children: [
            AppField(
              controller: _phone,
              label: 'Numéro de téléphone',
              hint: '01 97 00 00 00',
              icon: AppIcons.phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 8
                  ? 'Numéro invalide.'
                  : null,
            ),
            if (_register) ...[
              const SizedBox(height: 14),
              AppField(
                controller: _name,
                label: 'Votre nom',
                icon: AppIcons.user,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().length < 2 ? 'Nom trop court.' : null,
              ),
            ],
            const SizedBox(height: 14),
            AppField(
              controller: _password,
              label: 'Mot de passe',
              icon: AppIcons.lock,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              validator: (v) {
                final s = v ?? '';
                if (s.isEmpty) return 'Saisissez votre mot de passe.';
                if (_register && s.length < 8) return '8 caractères minimum.';
                return null;
              },
              suffix: IconButton(
                icon: Icon(_showPassword ? AppIcons.eyeOff : AppIcons.eye),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(AppIcons.warning, color: p.danger, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_error!, style: context.tt.bodyMedium?.copyWith(color: p.danger)),
            ),
          ],
        ),
      ],
      if (!configured) ...[
        const SizedBox(height: 14),
        Text(
          'Aucun serveur configuré : renseignez son adresse ci-dessous pour activer la connexion.',
          style: context.tt.bodySmall?.copyWith(color: p.warn, height: 1.35),
        ),
      ],
      const SizedBox(height: 20),
      PrimaryButton(
        label: _register ? 'Créer mon compte' : 'Se connecter',
        icon: AppIcons.check,
        loading: _busy,
        onPressed: configured ? _submit : null,
      ),
    ];
  }

  // ───────────── Connecté ─────────────

  List<Widget> _signedIn(BuildContext context, AppController c) {
    final p = context.pal;
    final user = c.session!.user!;
    final sync = c.sync;
    final st = sync?.status ?? const SyncStatus();

    final (label, color) = switch (st.phase) {
      SyncPhase.syncing => ('Synchronisation en cours', p.goldText),
      SyncPhase.offline => ('Hors-ligne', p.warn),
      SyncPhase.error => (st.sessionExpired ? 'Session expirée' : 'Erreur', p.danger),
      SyncPhase.idle => (st.pending > 0 ? 'À envoyer' : 'À jour', st.pending > 0 ? p.warn : p.success),
      SyncPhase.off => ('Désactivée', p.textSoft),
    };

    return [
      InfoCard(children: [
        InfoRow(icon: AppIcons.user, label: 'Compte', value: user.name),
        InfoRow(icon: AppIcons.phone, label: 'Téléphone', value: user.phone),
      ]),
      const SizedBox(height: 16),
      InfoCard(children: [
        InfoRow(icon: AppIcons.sync, label: 'Synchronisation', value: label, valueColor: color),
        InfoRow(
          icon: AppIcons.clock,
          label: 'Dernière synchro',
          value: st.lastSyncAt == null ? 'Pas encore' : Fmt.dateTime(st.lastSyncAt!),
        ),
        InfoRow(
          icon: AppIcons.cloudOff,
          label: 'En attente d\'envoi',
          value: '${st.pending}',
          valueColor: st.pending > 0 ? p.warn : null,
        ),
      ]),
      if (st.phase == SyncPhase.syncing) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: st.progress,
            minHeight: 8,
            color: p.gold,
            backgroundColor: p.field,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          st.total > 1 ? '${st.step} · ${st.done}/${st.total}' : st.step,
          style: context.tt.bodySmall,
        ),
      ],
      if (st.error != null && st.phase == SyncPhase.error) ...[
        const SizedBox(height: 12),
        Text(st.error!, style: context.tt.bodyMedium?.copyWith(color: p.danger)),
      ],
      const SizedBox(height: 18),
      if (st.sessionExpired)
        ..._reconnect(context, c, user.phone)
      else
        PrimaryButton(
          label: 'Synchroniser maintenant',
          icon: AppIcons.sync,
          loading: st.phase == SyncPhase.syncing,
          onPressed: sync == null ? null : () => sync.syncNow(),
        ),
      if (_failed.isNotEmpty) ...[
        const SizedBox(height: 26),
        Text('Modifications refusées par le serveur', style: context.tt.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Ces actions n\'ont pas pu être appliquées (droits insuffisants, données en conflit…). '
          'Les données du serveur ont été rétablies sur cet appareil.',
          style: context.tt.bodySmall?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 8),
        for (final op in _failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.warning, color: p.warn, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(op.label, style: context.tt.titleSmall),
                      Text(op.lastError ?? 'Refusé', style: context.tt.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'Réessayer',
                icon: AppIcons.sync,
                onPressed: () async {
                  await c.syncStore?.retryFailedOps();
                  await c.sync?.refresh();
                  c.sync?.requestSync(immediate: true);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GhostButton(
                label: 'Ignorer',
                icon: AppIcons.close,
                onPressed: () async {
                  await c.syncStore?.discardFailedOps();
                  await c.sync?.refresh();
                  await _loadFailed();
                },
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 26),
      GhostButton(
        label: 'Se déconnecter',
        icon: AppIcons.logout,
        danger: true,
        onPressed: _busy ? null : _logout,
      ),
    ];
  }

  List<Widget> _reconnect(BuildContext context, AppController c, String phone) {
    final p = context.pal;
    if (_phone.text.isEmpty) _phone.text = phone;
    return [
      Text(
        'Votre session a expiré. Vos données restent sur l\'appareil et vos modifications '
        'seront envoyées dès la reconnexion.',
        style: context.tt.bodyMedium?.copyWith(color: p.warn, height: 1.4),
      ),
      const SizedBox(height: 14),
      Form(
        key: _form,
        child: AppField(
          controller: _password,
          label: 'Mot de passe',
          icon: AppIcons.lock,
          obscureText: !_showPassword,
          onSubmitted: (_) => _submit(),
          validator: (v) => (v ?? '').isEmpty ? 'Saisissez votre mot de passe.' : null,
          suffix: IconButton(
            icon: Icon(_showPassword ? AppIcons.eyeOff : AppIcons.eye),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: context.tt.bodyMedium?.copyWith(color: p.danger)),
      ],
      const SizedBox(height: 14),
      PrimaryButton(label: 'Se reconnecter', icon: AppIcons.lock, loading: _busy, onPressed: _submit),
    ];
  }

  // ───────────── Serveur et diagnostic ─────────────

  Widget _serverSection(BuildContext context) {
    final p = context.pal;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: p.textSoft,
        collapsedIconColor: p.textSoft,
        title: Text('Serveur (avancé)', style: context.tt.titleMedium),
        children: [
          AppField(
            controller: _server,
            label: 'Adresse de l\'API',
            hint: 'https://api.exemple.com',
            icon: AppIcons.building,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _saveServer(),
          ),
          const SizedBox(height: 10),
          GhostButton(label: 'Enregistrer', icon: AppIcons.check, onPressed: _saveServer),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _diagnostic(BuildContext context) {
    final p = context.pal;
    final lines = ErrorReporter.recent;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: p.textSoft,
        collapsedIconColor: p.textSoft,
        title: Text('Diagnostic', style: context.tt.titleMedium),
        subtitle: Text(
          lines.isEmpty ? 'Aucune erreur enregistrée' : '${lines.length} événement(s)',
          style: context.tt.bodySmall,
        ),
        children: [
          if (lines.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Tout va bien.', style: context.tt.bodyMedium),
            )
          else ...[
            for (final l in lines.reversed.take(15))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l, style: context.tt.bodySmall?.copyWith(fontFamily: 'monospace')),
              ),
            const SizedBox(height: 6),
            GhostButton(
              label: 'Copier',
              icon: AppIcons.copy,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                if (mounted) showToast(this.context, 'Diagnostic copié.');
              },
            ),
          ],
        ],
      ),
    );
  }
}
