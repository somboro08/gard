import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/query_cache.dart';
import '../widgets/bars.dart';
import '../widgets/empty_state.dart';
import '../widgets/query_builder.dart';
import '../widgets/vehicle_ui.dart';
import '../widgets/week_widgets.dart';

class _RevenueData {
  const _RevenueData(this.payments, this.pending);

  final List<Payment> payments;
  final int pending;
}

/// Revenus du centre courant : encaissements par jour, total de la semaine,
/// montant restant à encaisser.
class RevenuePage extends StatefulWidget {
  const RevenuePage({super.key});

  @override
  State<RevenuePage> createState() => _RevenuePageState();
}

class _RevenuePageState extends State<RevenuePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late AppController _c;

  DateTime _weekStart = Fmt.startOfWeek(DateTime.now());
  int _day = DateTime.now().weekday - 1;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this, initialIndex: _day);
    _tabs.addListener(() {
      if (_tabs.index != _day) setState(() => _day = _tabs.index);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c = AppScope.of(context);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_RevenueData> _load() async {
    final payments = await _c.paymentsOfWeek(_weekStart);
    final pending = await _c.pendingAmount();
    return _RevenueData(payments, pending);
  }

  void _shiftWeek(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _weekStart = Fmt.addDays(_weekStart, 7 * delta);
    });
  }

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _weekStart = Fmt.startOfWeek(now);
    });
    _tabs.animateTo(now.weekday - 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final now = DateTime.now();
    final today = Fmt.startOfDay(now);
    final isCurrentWeek = _weekStart == Fmt.startOfWeek(now);

    return Scaffold(
      backgroundColor: p.bg,
      appBar: simpleBar(context, 'Revenus'),
      body: Column(
        children: [
          WeekBar(
            start: _weekStart,
            isCurrent: isCurrentWeek,
            onPrev: () => _shiftWeek(-1),
            onNext: isCurrentWeek ? null : () => _shiftWeek(1),
            onToday: _goToday,
          ),
          Expanded(
            child: QueryBuilder<_RevenueData>(
              queryKey: 'revenue:${_c.current?.id}:${_weekStart.millisecondsSinceEpoch}',
              // Les revenus dépendent des paiements ET des véhicules (reste à encaisser).
              tags: {
                Tags.payments(_c.current?.id ?? ''),
                Tags.vehicles(_c.current?.id ?? ''),
              },
              fetch: _load,
              builder: (context, q) {
                if (q.isFailure) {
                  return QueryError(onRetry: () => _c.cache.invalidateAll());
                }
                final data = q.data ?? const _RevenueData([], 0);

                final byDay = List.generate(7, (_) => <Payment>[]);
                for (final pay in data.payments) {
                  final i =
                      (Fmt.startOfDay(pay.paidAt).difference(_weekStart).inHours / 24).round();
                  if (i >= 0 && i < 7) byDay[i].add(pay);
                }
                final totals = [
                  for (final list in byDay) list.fold<int>(0, (sum, x) => sum + x.amount),
                ];
                final weekTotal = totals.fold<int>(0, (a, b) => a + b);
                final dayDate = Fmt.addDays(_weekStart, _day);

                return Column(
                  children: [
                    DayTabBar(
                      controller: _tabs,
                      weekStart: _weekStart,
                      today: today,
                      marked: [for (final t in totals) t > 0],
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: [
                          _SummaryCard(
                            date: dayDate,
                            isToday: Fmt.sameDay(dayDate, today),
                            total: totals[_day],
                            count: byDay[_day].length,
                            weekTotal: weekTotal,
                            pending: data.pending,
                          ),
                          const SizedBox(height: 14),
                          _WeekChart(
                            weekStart: _weekStart,
                            totals: totals,
                            selected: _day,
                            onSelect: (i) => _tabs.animateTo(i),
                          ),
                          const SizedBox(height: 22),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Encaissements du ${Fmt.dayMonth(dayDate)}',
                              style: context.tt.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (byDay[_day].isEmpty)
                            const SizedBox(
                              height: 220,
                              child: EmptyState(
                                icon: AppIcons.wallet,
                                title: 'Aucun encaissement ce jour',
                                message: 'Les paiements enregistrés apparaîtront ici.',
                              ),
                            )
                          else
                            for (final pay in byDay[_day]) _PaymentTile(payment: pay),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.date,
    required this.isToday,
    required this.total,
    required this.count,
    required this.weekTotal,
    required this.pending,
  });

  final DateTime date;
  final bool isToday;
  final int total;
  final int count;
  final int weekTotal;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isToday ? 'Revenus d\'aujourd\'hui' : 'Revenus du ${Fmt.dayMonth(date)}',
            style: context.tt.bodySmall,
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            key: ValueKey(total),
            tween: Tween(begin: 0, end: total.toDouble()),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              Fmt.money(v.round()),
              style: context.tt.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: total > 0 ? p.goldText : p.textSoft,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count == 0 ? 'Aucun paiement' : '$count paiement${count > 1 ? 's' : ''} en espèces',
            style: context.tt.bodySmall,
          ),
          const SizedBox(height: 16),
          Divider(color: p.divider),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Mini(label: 'Total semaine', value: Fmt.money(weekTotal))),
              Expanded(
                child: _Mini(
                  label: 'À encaisser',
                  value: Fmt.money(pending),
                  color: pending > 0 ? p.warn : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.tt.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.tt.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Histogramme simple des 7 jours (toucher une barre sélectionne le jour).
class _WeekChart extends StatelessWidget {
  const _WeekChart({
    required this.weekStart,
    required this.totals,
    required this.selected,
    required this.onSelect,
  });

  final DateTime weekStart;
  final List<int> totals;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final maxTotal = totals.fold<int>(0, math.max);
    const maxBar = 86.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        height: maxBar + 34,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        height: maxTotal == 0 ? 6 : 6 + (maxBar - 6) * totals[i] / maxTotal,
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        decoration: BoxDecoration(
                          color: i == selected
                              ? p.gold
                              : (totals[i] > 0 ? p.goldTint : p.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Fmt.dayShort(Fmt.addDays(weekStart, i)),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                          color: i == selected ? p.text : p.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pay = payment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.successTint, shape: BoxShape.circle),
            child: Icon(pay.type.icon, color: p.success, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pay.plate.isEmpty ? 'Sans plaque' : pay.plate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${pay.ownerName} · ${Fmt.time(pay.paidAt)} · ${pay.method.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tt.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+ ${Fmt.money(pay.amount)}',
            style: context.tt.titleSmall?.copyWith(color: p.success, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
