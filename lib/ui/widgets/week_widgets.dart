import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';

/// Navigation de semaine : « ‹  Cette semaine · 16 – 22 nov.  › ».
class WeekBar extends StatelessWidget {
  const WeekBar({
    super.key,
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

/// Barre d'onglets LUN … DIM d'une semaine. [marked] indique les jours avec du contenu.
class DayTabBar extends StatelessWidget {
  const DayTabBar({
    super.key,
    required this.controller,
    required this.weekStart,
    required this.today,
    required this.marked,
  });

  final TabController controller;
  final DateTime weekStart;
  final DateTime today;
  final List<bool> marked;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TabBar(
      controller: controller,
      tabs: [
        for (var i = 0; i < 7; i++)
          DayTab(date: Fmt.addDays(weekStart, i), today: today, hasItems: marked[i]),
      ],
      padding: EdgeInsets.zero,
      labelPadding: EdgeInsets.zero,
      indicatorColor: p.gold,
      indicatorWeight: 3.5,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: p.divider,
      labelColor: p.text,
      unselectedLabelColor: p.textSoft,
      overlayColor: WidgetStatePropertyAll(p.goldTint.withOpacity(0.5)),
    );
  }
}

class DayTab extends StatelessWidget {
  const DayTab({super.key, required this.date, required this.today, required this.hasItems});

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
