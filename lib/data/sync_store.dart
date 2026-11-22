import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Une opération locale à rejouer sur le serveur (file d'attente « outbox »).
/// Écrite dans la MÊME transaction SQLite que la modification : aucune perte possible.
class OutboxOp {
  const OutboxOp({
    required this.seq,
    required this.kind,
    required this.entityId,
    required this.centerId,
    required this.payload,
    required this.attempts,
    required this.lastError,
    required this.failed,
    required this.createdAt,
  });

  final int seq;

  /// center.create | center.update | center.delete | vehicle.create | vehicle.update |
  /// vehicle.collect | vehicle.ownerkey | vehicle.delete | payment.add
  final String kind;

  /// Centre ou véhicule concerné (pour un paiement : le véhicule).
  final String entityId;
  final String? centerId;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;

  /// Refusée définitivement par le serveur (visible dans l'écran Compte).
  final bool failed;
  final DateTime createdAt;

  factory OutboxOp.fromMap(Map<String, Object?> m) => OutboxOp(
        seq: m['seq'] as int,
        kind: m['kind'] as String,
        entityId: m['entity_id'] as String,
        centerId: m['center_id'] as String?,
        payload: (jsonDecode(m['payload'] as String) as Map).cast<String, dynamic>(),
        attempts: (m['attempts'] as int?) ?? 0,
        lastError: m['last_error'] as String?,
        failed: m['status'] == 'failed',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  /// Libellé lisible pour l'écran Compte.
  String get label => switch (kind) {
        'center.create' => 'Création du centre',
        'center.update' => 'Modification du centre',
        'center.delete' => 'Suppression du centre',
        'vehicle.create' => 'Enregistrement d\'un véhicule',
        'vehicle.update' => 'Modification d\'un véhicule',
        'vehicle.collect' => 'Remise d\'un véhicule',
        'vehicle.ownerkey' => 'Clé de sécurité du client',
        'vehicle.delete' => 'Suppression d\'un véhicule',
        'payment.add' => 'Encaissement',
        _ => kind,
      };
}

/// Résultat de l'application des changements reçus d'un centre.
class ApplyResult {
  const ApplyResult({this.changedVehicleIds = const {}, this.skipped = false});

  final Set<String> changedVehicleIds;

  /// Des éléments ont été ignorés car modifiés localement en attente d'envoi :
  /// on ne fait pas avancer le curseur, ils seront relus au prochain tour.
  final bool skipped;
}

/// Accès de la synchro à la base locale (implémenté par la base SQLite).
abstract class SyncStore {
  bool get syncEnabled;

  /// Active/désactive l'écriture dans l'outbox. À l'activation, toutes les données
  /// locales existantes sont mises en file (le serveur ignore les doublons).
  Future<void> setSyncEnabled(bool enabled);

  Future<List<OutboxOp>> pendingOps({int limit = 200});
  Future<int> pendingCount();
  Future<List<OutboxOp>> failedOps();
  Future<void> completeOp(int seq);
  Future<void> recordOpError(int seq, String message, {required bool permanent});
  Future<void> retryFailedOps();
  Future<void> discardFailedOps();

  Future<String?> syncValue(String key);
  Future<void> setSyncValue(String key, String? value);

  /// Remplace les centres locaux par ceux du serveur (sauf ceux modifiés localement).
  /// Retourne les identifiants de centres supprimés localement (retirés côté serveur).
  Future<Set<String>> applyRemoteCenters(List<ParkingCenter> remote, Map<String, String> roles);

  Future<ApplyResult> applyRemoteChanges(
    String centerId, {
    required List<Vehicle> vehicles,
    required List<Payment> payments,
    required List<String> deletedVehicleIds,
  });

  Future<void> markCenterKnown(String centerId);
  Future<void> updateLocalVehicleCode(String vehicleId, String code);

  /// Annule localement un encaissement refusé par le serveur.
  Future<void> dropLocalPayment(String paymentId);

  /// Retire la clé du client d'un véhicule (refusée par le serveur).
  Future<void> clearLocalOwnerKey(String vehicleId);

  /// Déconnexion : efface toutes les données de cet appareil (outbox comprise).
  Future<void> wipeAll();
}

// ───────────────────────── Charges utiles envoyées au serveur ─────────────────────────

String isoUtc(DateTime d) => d.toUtc().toIso8601String();

Map<String, Object?> centerPayload(ParkingCenter c) => {
      'id': c.id,
      'name': c.name,
      'location': c.location,
      'guardHours': c.guardHours,
      'tariff': {
        'moto': c.tariff.moto,
        'velo': c.tariff.velo,
        'voiture': c.tariff.voiture,
        'autre': c.tariff.autre,
      },
    };

Map<String, Object?> vehicleCreatePayload(Vehicle v) => {
      'id': v.id,
      'code': v.code,
      'plate': v.plate,
      'type': v.type.name,
      'ownerName': v.ownerName,
      'ownerPhone': v.ownerPhone,
      'note': v.note,
      'price': v.price,
      'depositedAt': isoUtc(v.depositedAt),
      'dueAt': isoUtc(v.dueAt),
    };

Map<String, Object?> vehicleUpdatePayload(Vehicle v) => {
      'plate': v.plate,
      'type': v.type.name,
      'ownerName': v.ownerName,
      'ownerPhone': v.ownerPhone,
      'note': v.note,
      'price': v.price,
    };

Map<String, Object?> ownerKeyPayload({required String key, required String nonce, required String sig}) =>
    {'ownerKey': key, 'nonce': nonce, 'sig': sig};

Map<String, Object?> collectPayload({
  required DateTime at,
  required PickupCheck check,
  required bool ticketVerified,
  PickupMethod method = PickupMethod.manual,
  PickupProof? proof,
}) =>
    {
      'collectedAt': isoUtc(at),
      'pickupCheck': check.name,
      'ticketVerified': ticketVerified,
      'pickupMethod': method.name,
      if (proof != null) 'proof': {'nonce': proof.nonce, 'sig': proof.sig},
    };

Map<String, Object?> paymentPayload(Payment p) => {
      'id': p.id,
      'amount': p.amount,
      'method': p.method.name,
      'paidAt': isoUtc(p.paidAt),
    };

/// Ajoute une opération à l'outbox, dans la transaction [ex] de l'appelant.
Future<void> enqueueOp(
  DatabaseExecutor ex, {
  required String kind,
  required String entityId,
  required String? centerId,
  required Map<String, Object?> payload,
}) {
  return ex.insert('outbox', {
    'kind': kind,
    'entity_id': entityId,
    'center_id': centerId,
    'payload': jsonEncode(payload),
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'status': 'pending',
  });
}
