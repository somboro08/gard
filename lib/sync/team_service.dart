import '../net/api_client.dart';
import 'mappers.dart';

/// Un membre d'un centre (propriétaire ou agent).
class Member {
  const Member({required this.id, required this.name, required this.phone, required this.role});

  final String id;
  final String name;
  final String phone;

  /// « owner » ou « agent ».
  final String role;

  bool get isOwner => role == 'owner';

  static Member? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final role = json['role'];
    if (id is! String || role is! String) return null;
    return Member(
      id: id,
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      role: role,
    );
  }
}

/// Gestion de l'équipe d'un centre via l'API (nécessite le réseau).
class TeamService {
  TeamService(this._api);

  final ApiClient _api;

  Future<List<Member>> list(String centerId) async {
    final j = asMap(await _api.get('/centers/$centerId/members'));
    return [
      for (final m in asMapList(j['members']))
        if (Member.fromJson(m) != null) Member.fromJson(m)!,
    ];
  }

  /// Ajoute (ou change le rôle de) un agent déjà inscrit, par son numéro.
  Future<Member> add(String centerId, {required String phone, String role = 'agent'}) async {
    final j = asMap(await _api.post('/centers/$centerId/members', body: {'phone': phone, 'role': role}));
    final m = Member.fromJson(j['member']);
    if (m == null) throw StateError('Réponse inattendue du serveur.');
    return m;
  }

  Future<void> remove(String centerId, String userId) async {
    await _api.delete('/centers/$centerId/members/$userId');
  }
}
