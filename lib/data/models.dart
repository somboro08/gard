import '../core/plates.dart';

enum VehicleType {
  moto,
  velo,
  voiture,
  autre;

  String get label => switch (this) {
        VehicleType.moto => 'Moto',
        VehicleType.velo => 'Vélo',
        VehicleType.voiture => 'Voiture',
        VehicleType.autre => 'Autre',
      };

  /// La plaque est obligatoire pour les motos et voitures (pas pour vélos/autres).
  bool get plateRequired => this == VehicleType.moto || this == VehicleType.voiture;

  static VehicleType parse(String? s) =>
      VehicleType.values.firstWhere((t) => t.name == s, orElse: () => VehicleType.autre);
}

enum VehicleStatus { enCours, recupere, nonRecupere }

/// Résultat de la vérification de plaque au moment de la remise.
enum PickupCheck {
  exact,
  close,
  different,
  skipped;

  String get label => switch (this) {
        PickupCheck.exact => 'Plaque conforme',
        PickupCheck.close => 'Plaque proche (validée manuellement)',
        PickupCheck.different => 'Plaque différente (forcée)',
        PickupCheck.skipped => 'Plaque non vérifiée',
      };

  static PickupCheck? parse(String? s) {
    for (final c in PickupCheck.values) {
      if (c.name == s) return c;
    }
    return null;
  }
}

class ParkingCenter {
  const ParkingCenter({
    required this.id,
    required this.name,
    required this.location,
    required this.guardHours,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String location;

  /// Durée de garde normale (en heures). 24 par défaut, modifiable par centre.
  final int guardHours;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': location,
        'guard_hours': guardHours,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ParkingCenter.fromMap(Map<String, Object?> m) => ParkingCenter(
        id: m['id'] as String,
        name: m['name'] as String,
        location: (m['location'] as String?) ?? '',
        guardHours: m['guard_hours'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.centerId,
    required this.code,
    required this.plate,
    required this.type,
    required this.ownerName,
    required this.ownerPhone,
    required this.note,
    required this.depositedAt,
    required this.dueAt,
    this.collectedAt,
    this.pickupCheck,
    this.ticketVerified = false,
  });

  final String id;
  final String centerId;

  /// Code numérique à 6 chiffres (aussi encodé dans le QR du ticket).
  final String code;

  /// Plaque telle qu'affichée (ex. « AB 1234 RB »). Vide si absente.
  final String plate;
  final VehicleType type;
  final String ownerName;
  final String ownerPhone;
  final String note;
  final DateTime depositedAt;

  /// Fin du délai de garde (déposé + durée du centre au moment du dépôt).
  final DateTime dueAt;
  final DateTime? collectedAt;
  final PickupCheck? pickupCheck;
  final bool ticketVerified;

  String get plateKey => Plates.key(plate);
  bool get hasPlate => plateKey.isNotEmpty;
  bool get isCollected => collectedAt != null;

  VehicleStatus statusAt(DateTime now) {
    if (collectedAt != null) return VehicleStatus.recupere;
    return now.isAfter(dueAt) ? VehicleStatus.nonRecupere : VehicleStatus.enCours;
  }

  Duration overdue(DateTime now) => now.difference(dueAt);

  Vehicle copyWith({
    String? plate,
    VehicleType? type,
    String? ownerName,
    String? ownerPhone,
    String? note,
  }) =>
      Vehicle(
        id: id,
        centerId: centerId,
        code: code,
        plate: plate ?? this.plate,
        type: type ?? this.type,
        ownerName: ownerName ?? this.ownerName,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        note: note ?? this.note,
        depositedAt: depositedAt,
        dueAt: dueAt,
        collectedAt: collectedAt,
        pickupCheck: pickupCheck,
        ticketVerified: ticketVerified,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'center_id': centerId,
        'code': code,
        'plate': plate,
        'plate_key': plateKey,
        'type': type.name,
        'owner_name': ownerName,
        'owner_phone': ownerPhone,
        'note': note,
        'deposited_at': depositedAt.millisecondsSinceEpoch,
        'due_at': dueAt.millisecondsSinceEpoch,
        'collected_at': collectedAt?.millisecondsSinceEpoch,
        'pickup_check': pickupCheck?.name,
        'ticket_verified': ticketVerified ? 1 : 0,
      };

  factory Vehicle.fromMap(Map<String, Object?> m) {
    final collected = m['collected_at'] as int?;
    return Vehicle(
      id: m['id'] as String,
      centerId: m['center_id'] as String,
      code: m['code'] as String,
      plate: (m['plate'] as String?) ?? '',
      type: VehicleType.parse(m['type'] as String?),
      ownerName: m['owner_name'] as String,
      ownerPhone: (m['owner_phone'] as String?) ?? '',
      note: (m['note'] as String?) ?? '',
      depositedAt: DateTime.fromMillisecondsSinceEpoch(m['deposited_at'] as int),
      dueAt: DateTime.fromMillisecondsSinceEpoch(m['due_at'] as int),
      collectedAt: collected == null ? null : DateTime.fromMillisecondsSinceEpoch(collected),
      pickupCheck: PickupCheck.parse(m['pickup_check'] as String?),
      ticketVerified: ((m['ticket_verified'] as int?) ?? 0) == 1,
    );
  }
}
