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

/// Moyen de paiement. Seul `cash` est proposé dans l'app pour l'instant ;
/// `wallet` est réservé au futur portefeuille.
enum PaymentMethod {
  cash,
  wallet;

  String get label => switch (this) {
        PaymentMethod.cash => 'Espèces',
        PaymentMethod.wallet => 'Portefeuille',
      };

  static PaymentMethod parse(String? s) =>
      PaymentMethod.values.firstWhere((m) => m.name == s, orElse: () => PaymentMethod.cash);
}

/// Prix d'une garde (une durée de garde du centre) selon le type de véhicule, en FCFA.
/// 0 = gratuit.
class Tariff {
  const Tariff({this.moto = 0, this.velo = 0, this.voiture = 0, this.autre = 0});

  final int moto;
  final int velo;
  final int voiture;
  final int autre;

  int forType(VehicleType t) => switch (t) {
        VehicleType.moto => moto,
        VehicleType.velo => velo,
        VehicleType.voiture => voiture,
        VehicleType.autre => autre,
      };

  bool get isFree => moto == 0 && velo == 0 && voiture == 0 && autre == 0;
}

class ParkingCenter {
  const ParkingCenter({
    required this.id,
    required this.name,
    required this.location,
    required this.guardHours,
    required this.createdAt,
    this.tariff = const Tariff(),
  });

  final String id;
  final String name;
  final String location;

  /// Durée de garde normale (en heures). 24 par défaut, modifiable par centre.
  final int guardHours;
  final DateTime createdAt;

  /// Prix d'une garde par type de véhicule.
  final Tariff tariff;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'location': location,
        'guard_hours': guardHours,
        'created_at': createdAt.millisecondsSinceEpoch,
        'price_moto': tariff.moto,
        'price_velo': tariff.velo,
        'price_voiture': tariff.voiture,
        'price_autre': tariff.autre,
      };

  factory ParkingCenter.fromMap(Map<String, Object?> m) => ParkingCenter(
        id: m['id'] as String,
        name: m['name'] as String,
        location: (m['location'] as String?) ?? '',
        guardHours: m['guard_hours'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        tariff: Tariff(
          moto: (m['price_moto'] as int?) ?? 0,
          velo: (m['price_velo'] as int?) ?? 0,
          voiture: (m['price_voiture'] as int?) ?? 0,
          autre: (m['price_autre'] as int?) ?? 0,
        ),
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
    this.price = 0,
    this.paidAmount = 0,
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

  /// Montant dû pour cette garde (FCFA), figé au dépôt d'après le tarif du centre.
  final int price;

  /// Total déjà encaissé (FCFA).
  final int paidAmount;

  String get plateKey => Plates.key(plate);
  bool get hasPlate => plateKey.isNotEmpty;
  bool get isCollected => collectedAt != null;

  /// Reste à payer (jamais négatif).
  int get balance => price > paidAmount ? price - paidAmount : 0;
  bool get isPaid => balance == 0;

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
    int? price,
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
        price: price ?? this.price,
        paidAmount: paidAmount,
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
        'price': price,
        'paid_amount': paidAmount,
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
      price: (m['price'] as int?) ?? 0,
      paidAmount: (m['paid_amount'] as int?) ?? 0,
    );
  }
}

/// Un encaissement. Les champs `plate`, `ownerName` et `type` ne sont renseignés
/// que pour les paiements lus avec leur véhicule (écran Revenus).
class Payment {
  const Payment({
    required this.id,
    required this.vehicleId,
    required this.centerId,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.plate = '',
    this.ownerName = '',
    this.type = VehicleType.autre,
  });

  final String id;
  final String vehicleId;
  final String centerId;
  final int amount;
  final PaymentMethod method;
  final DateTime paidAt;
  final String plate;
  final String ownerName;
  final VehicleType type;

  Map<String, Object?> toMap() => {
        'id': id,
        'vehicle_id': vehicleId,
        'center_id': centerId,
        'amount': amount,
        'method': method.name,
        'paid_at': paidAt.millisecondsSinceEpoch,
      };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as String,
        vehicleId: m['vehicle_id'] as String,
        centerId: m['center_id'] as String,
        amount: m['amount'] as int,
        method: PaymentMethod.parse(m['method'] as String?),
        paidAt: DateTime.fromMillisecondsSinceEpoch(m['paid_at'] as int),
        plate: (m['plate'] as String?) ?? '',
        ownerName: (m['owner_name'] as String?) ?? '',
        type: VehicleType.parse(m['vtype'] as String?),
      );
}
