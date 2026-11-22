import '../data/models.dart';

/// JSON de l'API → modèles locaux.

Map<String, dynamic> asMap(Object? o) {
  if (o is Map) return o.cast<String, dynamic>();
  throw const FormatException('Réponse inattendue du serveur.');
}

List<Map<String, dynamic>> asMapList(Object? o) {
  if (o == null) return const [];
  if (o is List) return [for (final e in o) asMap(e)];
  throw const FormatException('Réponse inattendue du serveur.');
}

DateTime _dt(Object? v) => DateTime.parse(v as String).toLocal();

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

ParkingCenter centerFromJson(Map<String, dynamic> j) {
  final t = (j['tariff'] is Map) ? asMap(j['tariff']) : const <String, dynamic>{};
  return ParkingCenter(
    id: j['id'] as String,
    name: j['name'] as String,
    location: (j['location'] as String?) ?? '',
    guardHours: _int(j['guardHours']),
    createdAt: _dt(j['createdAt']),
    tariff: Tariff(
      moto: _int(t['moto']),
      velo: _int(t['velo']),
      voiture: _int(t['voiture']),
      autre: _int(t['autre']),
    ),
  );
}

Vehicle vehicleFromJson(Map<String, dynamic> j) => Vehicle(
      id: j['id'] as String,
      centerId: j['centerId'] as String,
      code: j['code'] as String,
      plate: (j['plate'] as String?) ?? '',
      type: VehicleType.parse(j['type'] as String?),
      ownerName: j['ownerName'] as String,
      ownerPhone: (j['ownerPhone'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      depositedAt: _dt(j['depositedAt']),
      dueAt: _dt(j['dueAt']),
      collectedAt: j['collectedAt'] == null ? null : _dt(j['collectedAt']),
      pickupCheck: PickupCheck.parse(j['pickupCheck'] as String?),
      ticketVerified: j['ticketVerified'] == true,
      price: _int(j['price']),
      paidAmount: _int(j['paidAmount']),
      ownerKey: j['ownerKey'] as String?,
      pickupMethod: PickupMethod.parse(j['pickupMethod'] as String?),
    );

Payment paymentFromJson(Map<String, dynamic> j) => Payment(
      id: j['id'] as String,
      vehicleId: j['vehicleId'] as String,
      centerId: j['centerId'] as String,
      amount: _int(j['amount']),
      method: PaymentMethod.parse(j['method'] as String?),
      paidAt: _dt(j['paidAt']),
    );

class AuthUser {
  const AuthUser({required this.id, required this.phone, required this.name});

  final String id;
  final String phone;
  final String name;

  Map<String, String> toJson() => {'id': id, 'phone': phone, 'name': name};

  static AuthUser? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['id'];
    final phone = o['phone'];
    final name = o['name'];
    if (id is String && phone is String && name is String) {
      return AuthUser(id: id, phone: phone, name: name);
    }
    return null;
  }
}
