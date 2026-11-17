import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/plates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

extension VehicleTypeUi on VehicleType {
  IconData get icon => switch (this) {
        VehicleType.moto => Icons.two_wheeler_rounded,
        VehicleType.velo => Icons.pedal_bike_rounded,
        VehicleType.voiture => AppIcons.car,
        VehicleType.autre => Icons.more_horiz_rounded,
      };
}

class StatusStyle {
  const StatusStyle(this.label, this.icon, this.fg, this.bg);

  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
}

StatusStyle statusStyleOf(AppPalette p, VehicleStatus s) => switch (s) {
      VehicleStatus.enCours => StatusStyle('En cours', AppIcons.clock, p.goldText, p.goldTint),
      VehicleStatus.recupere => StatusStyle('Récupéré', AppIcons.check, p.success, p.successTint),
      VehicleStatus.nonRecupere =>
        StatusStyle('Non récupéré', AppIcons.warning, p.danger, p.dangerTint),
    };

/// Ligne de détail selon le statut.
String statusDetail(Vehicle v, DateTime now) {
  switch (v.statusAt(now)) {
    case VehicleStatus.enCours:
      final due = Fmt.sameDay(v.dueAt, v.depositedAt) ? Fmt.time(v.dueAt) : Fmt.dateTime(v.dueAt);
      return 'À récupérer avant $due';
    case VehicleStatus.recupere:
      return 'Récupéré le ${Fmt.dayMonth(v.collectedAt!)} à ${Fmt.time(v.collectedAt!)}';
    case VehicleStatus.nonRecupere:
      return 'Délai dépassé de ${Fmt.duration(v.overdue(now))}';
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final s = statusStyleOf(context.pal, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 15, color: s.fg),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: s.fg),
          ),
        ],
      ),
    );
  }
}

class VehicleAvatar extends StatelessWidget {
  const VehicleAvatar({super.key, required this.type, required this.status, this.size = 54});

  final VehicleType type;
  final VehicleStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = statusStyleOf(context.pal, status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: s.bg, shape: BoxShape.circle),
      child: Icon(type.icon, color: s.fg, size: size * 0.5),
    );
  }
}

/// Ligne de liste façon « discussion WhatsApp ».
class VehicleTile extends StatelessWidget {
  const VehicleTile({
    super.key,
    required this.vehicle,
    required this.now,
    required this.onTap,
    this.showDate = false,
  });

  final Vehicle vehicle;
  final DateTime now;
  final VoidCallback onTap;

  /// Affiche la date complète du dépôt (résultats de recherche multi-jours).
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final status = vehicle.statusAt(now);
    final style = statusStyleOf(p, status);
    final v = vehicle;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            VehicleAvatar(type: v.type, status: status),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          v.hasPlate ? v.plate : 'Sans plaque',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: v.hasPlate ? p.text : p.textSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        showDate ? Fmt.dateTime(v.depositedAt) : Fmt.time(v.depositedAt),
                        style: context.tt.bodySmall?.copyWith(
                          color: status == VehicleStatus.nonRecupere ? p.danger : p.textSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          v.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(status: status),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    statusDetail(v, now),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tt.bodySmall?.copyWith(
                      color: status == VehicleStatus.enCours ? p.textSoft : style.fg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compare la plaque enregistrée et la plaque scannée, caractère par caractère.
class PlateCompare extends StatelessWidget {
  const PlateCompare({super.key, required this.stored, required this.scanned});

  final String stored;
  final String scanned;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = Plates.key(stored);
    final b = Plates.key(scanned);
    final sameLength = a.length == b.length;

    Widget row(String label, String mine, String other) {
      return Row(
        children: [
          SizedBox(width: 104, child: Text(label, style: context.tt.bodySmall)),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < mine.length; i++)
                    TextSpan(
                      text: mine[i],
                      style: TextStyle(
                        color: sameLength && mine[i] != other[i] ? p.danger : p.text,
                        decoration: sameLength && mine[i] != other[i]
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        decorationColor: p.danger,
                      ),
                    ),
                ],
              ),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Enregistrée', a, b),
          const SizedBox(height: 10),
          row('Scannée', b, a),
          if (!sameLength) ...[
            const SizedBox(height: 10),
            Text(
              'Les deux plaques n\'ont pas la même longueur.',
              style: context.tt.bodySmall?.copyWith(color: p.warn),
            ),
          ],
        ],
      ),
    );
  }
}
