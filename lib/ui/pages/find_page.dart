import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../flows.dart';
import '../widgets/center_ui.dart';
import '../widgets/empty_state.dart';
import '../widgets/fluid.dart';
import '../widgets/pills.dart';
import '../widgets/vehicle_ui.dart';

enum _Filter {
  all('Tous', null),
  active('En cours', VehicleStatus.enCours),
  done('Récupérés', VehicleStatus.recupere),
  overdue('Non récupérés', VehicleStatus.nonRecupere);

  const _Filter(this.label, this.status);

  final String label;
  final VehicleStatus? status;
}

/// Onglet « Retrouver un auto » : liste des véhicules par jour (semaine en onglets),
/// filtres de statut, recherche, et bouton de scan.
class FindPage extends StatefulWidget {
  const FindPage({super.key});

  @override
  State<FindPage> createState() => _FindPageState();
}

class _FindPageState extends State<FindPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late AppController _c;

  DateTime _weekStart = Fmt.startOfWeek(DateTime.now());
  int _day = DateTime.now().weekday - 1;
  _Filter _filter = _Filter.all;

  Future<List<Vehicle>> _future = Future.value(const <Vehicle>[]);
  int _seenRevision = -1;
  String? _seenCenter;

  bool _searching = false;
  final TextEditingController _query = TextEditingController();
  Future<List<Vehicle>> _searchFuture = Future.value(const <Vehicle>[]);

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this, initialIndex: _day);
    _tabs.addListener(_onTab);
    // Rafraîchit les statuts (« non récupéré ») au fil du temps.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = AppScope.of(context);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.index != _day) setState(() => _day = _tabs.index);
  }

  void _sync({bool force = false}) {
    final id = _c.current?.id;
    if (!force && _seenRevision == _c.revision && _seenCenter == id) return;
    _seenRevision = _c.revision;
    _seenCenter = id;
    _future = id == null ? Future.value(const <Vehicle>[]) : _c.vehiclesOfWeek(_weekStart);
    if (_searching) _runSearch();
  }

  void _runSearch() {
    _searchFuture = _c.search(_query.text);
  }

  void _shiftWeek(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _weekStart = Fmt.addDays(_weekStart, 7 * delta);
      _sync(force: true);
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _weekStart = Fmt.startOfWeek(now);
      _sync(force: true);
    });
    _tabs.animateTo(now.weekday - 1);
  }

  void _openSearch() {
    setState(() {
      _searching = true;
      _query.clear();
      _searchFuture = Future.value(const <Vehicle>[]);
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query.clear();
    });
  }

  Future<void> _openFindSheet() async {
    HapticFeedback.lightImpact();
    final action = await showFindMethodSheet(
      context,
      title: 'Retrouver un auto',
      actions: FindAction.values,
    );
    if (action == null || !mounted) return;
    await runFindAction(context, action);
  }

  int _count(List<Vehicle> list, VehicleStatus? status, DateTime now) =>
      status == null ? list.length : list.where((v) => v.statusAt(now) == status).length;

  List<Vehicle> _applyFilter(List<Vehicle> list, DateTime now) {
    final status = _filter.status;
    if (status == null) return list;
    return list.where((v) => v.statusAt(now) == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_c.current == null) return const Scaffold(body: SizedBox.shrink());
    final now = DateTime.now();

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        floatingActionButton: _searching
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: _openFindSheet,
                backgroundColor: p.gold,
                foregroundColor: p.onGold,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: const Icon(AppIcons.scan, size: 28),
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                child: _searching ? _searchBar(p) : _header(),
              ),
              Expanded(child: _searching ? _searchResults() : _week(p, now)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      key: const ValueKey('header'),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
      child: Row(
        children: [
          const Expanded(child: CenterTitle()),
          IconButton(
            iconSize: 26,
            tooltip: 'Rechercher',
            onPressed: _openSearch,
            icon: const Icon(AppIcons.search),
          ),
          IconButton(
            iconSize: 26,
            tooltip: 'Réglages',
            onPressed: () => showSettingsSheet(context),
            icon: const Icon(AppIcons.more),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(AppPalette p) {
    return Padding(
      key: const ValueKey('search'),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 6),
      child: Row(
        children: [
          IconButton(iconSize: 26, onPressed: _closeSearch, icon: const Icon(AppIcons.back)),
          Expanded(
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(26),
              ),
              child: TextField(
                controller: _query,
                autofocus: true,
                cursorColor: p.gold,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 18, color: p.text),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'Plaque, nom, téléphone, code',
                  hintStyle: TextStyle(fontSize: 17, color: p.textSoft),
                ),
                onChanged: (_) => setState(_runSearch),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchResults() {
    return FutureBuilder<List<Vehicle>>(
      future: _searchFuture,
      builder: (context, snap) {
        if (_query.text.trim().isEmpty) {
          return const EmptyState(
            icon: AppIcons.search,
            title: 'Rechercher un véhicule',
            message: 'Tapez une plaque, un nom, un numéro de téléphone ou un code de ticket.',
          );
        }
        final list = snap.data ?? const <Vehicle>[];
        if (list.isEmpty && snap.connectionState != ConnectionState.waiting) {
          return const EmptyState(
            icon: AppIcons.emptyBox,
            title: 'Aucun résultat',
            message: 'Essayez une partie de la plaque ou du nom.',
          );
        }
        final now = DateTime.now();
        return ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: list.length,
          itemBuilder: (context, i) => VehicleTile(
            vehicle: list[i],
            now: now,
            showDate: true,
            onTap: () => context.push('/vehicle/${list[i].id}'),
          ),
        );
      },
    );
  }

  Widget _week(AppPalette p, DateTime now) {
    final today = Fmt.startOfDay(now);
    final isCurrentWeek = _weekStart == Fmt.startOfWeek(now);

    return Column(
      children: [
        _WeekBar(
          start: _weekStart,
          isCurrent: isCurrentWeek,
          onPrev: () => _shiftWeek(-1),
          onNext: isCurrentWeek ? null : () => _shiftWeek(1),
          onToday: _goToday,
        ),
        Expanded(
          child: FutureBuilder<List<Vehicle>>(
            future: _future,
            builder: (context, snap) {
              final all = snap.data ?? const <Vehicle>[];
              final byDay = List.generate(7, (_) => <Vehicle>[]);
              for (final v in all) {
                final i =
                    (Fmt.startOfDay(v.depositedAt).difference(_weekStart).inHours / 24).round();
                if (i >= 0 && i < 7) byDay[i].add(v);
              }

              final tabs = <Widget>[
                for (var i = 0; i < 7; i++)
                  _DayTab(
                    date: Fmt.addDays(_weekStart, i),
                    today: today,
                    hasItems: byDay[i].isNotEmpty,
                  ),
              ];

              return Column(
                children: [
                  TabBar(
                    controller: _tabs,
                    tabs: tabs,
                    padding: EdgeInsets.zero,
                    labelPadding: EdgeInsets.zero,
                    indicatorColor: p.gold,
                    indicatorWeight: 3.5,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: p.divider,
                    labelColor: p.text,
                    unselectedLabelColor: p.textSoft,
                    overlayColor: WidgetStatePropertyAll(p.goldTint.withOpacity(0.5)),
                  ),
                  _filterRow(byDay[_day], now),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        for (var i = 0; i < 7; i++)
                          _DayList(
                            vehicles: _applyFilter(byDay[i], now),
                            total: byDay[i].length,
                            now: now,
                            isToday: Fmt.sameDay(Fmt.addDays(_weekStart, i), today),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterRow(List<Vehicle> day, DateTime now) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        children: [
          for (final f in _Filter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoicePill(
                label: f.label,
                count: _count(day, f.status, now),
                selected: _filter == f,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = f);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.start,
    required this.isCurrent,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime start;
  final bool isCurrent;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          IconButton(
            iconSize: 24,
            tooltip: 'Semaine précédente',
            onPressed: onPrev,
            icon: const Icon(AppIcons.chevronLeft),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToday,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  isCurrent ? 'Cette semaine · ${Fmt.weekRange(start)}' : Fmt.weekRange(start),
                  textAlign: TextAlign.center,
                  style: context.tt.titleSmall?.copyWith(color: isCurrent ? p.goldText : p.text),
                ),
              ),
            ),
          ),
          IconButton(
            iconSize: 24,
            tooltip: 'Semaine suivante',
            onPressed: onNext,
            icon: const Icon(AppIcons.chevronRight),
          ),
        ],
      ),
    );
  }
}

class _DayTab extends StatelessWidget {
  const _DayTab({required this.date, required this.today, required this.hasItems});

  final DateTime date;
  final DateTime today;
  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tab(
      height: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            Fmt.dayShort(date, today: today),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
          const SizedBox(height: 2),
          Text('${date.day}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasItems ? p.gold : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.vehicles,
    required this.total,
    required this.now,
    required this.isToday,
  });

  final List<Vehicle> vehicles;
  final int total;
  final DateTime now;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    if (vehicles.isEmpty) {
      if (total == 0) {
        return EmptyState(
          icon: AppIcons.emptyBox,
          title: 'Aucun véhicule ce jour',
          message: 'Les autos enregistrées apparaîtront ici.',
          actionLabel: isToday ? 'Enregistrer un auto' : null,
          onAction: isToday ? () => context.go('/register') : null,
        );
      }
      return const EmptyState(
        icon: AppIcons.search,
        title: 'Aucun véhicule dans ce filtre',
        message: 'Choisissez « Tous » pour tout voir.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 110),
      itemCount: vehicles.length,
      itemBuilder: (context, i) {
        final v = vehicles[i];
        return Appear(
          index: i,
          child: VehicleTile(
            vehicle: v,
            now: now,
            onTap: () => context.push('/vehicle/${v.id}'),
          ),
        );
      },
    );
  }
}
