import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Remise sécurisée : le client prouve qu'il détient la clé privée enrôlée au dépôt
/// en signant un défi choisi par l'agent. Tout fonctionne hors-ligne (QR dans les deux sens),
/// et le serveur revérifie la même preuve à la synchronisation (server/src/pickup.ts).
///
/// Messages signés (identiques côté serveur) :
///   enrôlement : "GARDE-ENROLL-1|<vehicleId>|<nonce>"
///   remise     : "GARDE-PICKUP-1|<vehicleId>|<nonce>"
abstract final class PickupCrypto {
  static final Ed25519 _ed = Ed25519();
  static final Random _rng = Random.secure();

  static String enrollMessage(String vehicleId, String nonce) => 'GARDE-ENROLL-1|$vehicleId|$nonce';
  static String pickupMessage(String vehicleId, String nonce) => 'GARDE-PICKUP-1|$vehicleId|$nonce';

  /// Octets aléatoires (cryptographiquement sûrs).
  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// Défi à usage unique : 16 octets, base64url sans « = ».
  static String newNonce() => b64(randomBytes(16));

  static String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// Décode du base64url (avec ou sans « = »). Retourne null si invalide.
  static Uint8List? unb64(String s) {
    try {
      return Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));
    } on FormatException {
      return null;
    }
  }

  /// Nouvelle clé : graine secrète de 32 octets (à garder dans le coffre sécurisé du téléphone).
  static Future<ClientKey> newKey() => keyFromSeed(randomBytes(32));

  static Future<ClientKey> keyFromSeed(List<int> seed) async {
    final pair = await _ed.newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return ClientKey(seed: b64(seed), publicKey: b64(pub.bytes));
  }

  static Future<String> sign(String seed, String message) async {
    final bytes = unb64(seed);
    if (bytes == null || bytes.length != 32) throw ArgumentError('Clé secrète invalide.');
    final pair = await _ed.newKeyPairFromSeed(bytes);
    final sig = await _ed.sign(utf8.encode(message), keyPair: pair);
    return b64(sig.bytes);
  }

  /// Vrai seulement si [signature] est une signature Ed25519 valide de [message] par [publicKey].
  static Future<bool> verify(String publicKey, String message, String signature) async {
    final key = unb64(publicKey);
    final sig = unb64(signature);
    if (key == null || sig == null || key.length != 32 || sig.length != 64) return false;
    try {
      return await _ed.verify(
        utf8.encode(message),
        signature: Signature(sig, publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return false;
    }
  }
}

class ClientKey {
  const ClientKey({required this.seed, required this.publicKey});

  /// Secret (jamais envoyé nulle part).
  final String seed;
  final String publicKey;
}

/// Messages échangés par QR : « GP1: » + JSON compact en base64url.
///
/// Types : `e` demande d'enrôlement (agent → client) · `E` clé enrôlée (client → agent) ·
/// `c` défi de remise (agent → client) · `P` preuve de remise (client → agent).
abstract final class PickupCodec {
  static const prefix = 'GP1:';

  static String encode(Map<String, Object?> m) =>
      '$prefix${PickupCrypto.b64(utf8.encode(jsonEncode(m)))}';

  static Map<String, Object?>? decode(String raw) {
    final s = raw.trim();
    if (!s.startsWith(prefix)) return null;
    final bytes = PickupCrypto.unb64(s.substring(prefix.length));
    if (bytes == null) return null;
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    return null;
  }
}

/// Ce que le téléphone du client affiche avant de signer (pour qu'il sache ce qu'il approuve).
class PickupRequest {
  const PickupRequest({
    required this.isEnroll,
    required this.vehicleId,
    required this.nonce,
    required this.center,
    required this.plate,
    required this.code,
  });

  final bool isEnroll;
  final String vehicleId;
  final String nonce;
  final String center;
  final String plate;
  final String code;

  static PickupRequest? parse(String raw) {
    final j = PickupCodec.decode(raw);
    if (j == null) return null;
    final t = j['t'];
    final v = j['v'];
    final x = j['x'];
    if ((t != 'e' && t != 'c') || v is! String || x is! String) return null;
    if (v.length != 36 || (PickupCrypto.unb64(x)?.length ?? 0) < 16) return null;
    return PickupRequest(
      isEnroll: t == 'e',
      vehicleId: v,
      nonce: x,
      center: (j['n'] as String?) ?? '',
      plate: (j['p'] as String?) ?? '',
      code: (j['c'] as String?) ?? '',
    );
  }
}

/// Résultat d'une vérification côté agent.
class PickupProofResult {
  const PickupProofResult.ok({this.key, this.nonce, this.sig}) : error = null;
  const PickupProofResult.fail(this.error)
      : key = null,
        nonce = null,
        sig = null;

  /// Clé publique du client (enrôlement).
  final String? key;
  final String? nonce;
  final String? sig;
  final String? error;
  bool get isOk => error == null;
}

/// Côté agent : un échange à usage unique (nonce frais, durée limitée).
class AgentExchange {
  AgentExchange.enroll({
    required this.vehicleId,
    required this.code,
    required this.center,
    required this.plate,
    String? nonce,
    DateTime? now,
  })  : isEnroll = true,
        ownerKey = null,
        nonce = nonce ?? PickupCrypto.newNonce(),
        _startedAt = now ?? DateTime.now();

  AgentExchange.challenge({
    required this.vehicleId,
    required this.code,
    required this.center,
    required this.plate,
    required String this.ownerKey,
    String? nonce,
    DateTime? now,
  })  : isEnroll = false,
        nonce = nonce ?? PickupCrypto.newNonce(),
        _startedAt = now ?? DateTime.now();

  /// Un défi périmé est refusé : la preuve doit être produite « ici et maintenant ».
  static const validity = Duration(minutes: 3);

  final bool isEnroll;
  final String vehicleId;
  final String code;
  final String center;
  final String plate;
  final String nonce;

  /// Clé publique enrôlée (remise seulement).
  final String? ownerKey;
  final DateTime _startedAt;

  /// QR à montrer au client.
  String get requestQr => PickupCodec.encode({
        't': isEnroll ? 'e' : 'c',
        'v': vehicleId,
        'c': code,
        'n': center,
        'p': plate,
        'x': nonce,
      });

  bool expired([DateTime? now]) => (now ?? DateTime.now()).difference(_startedAt) > validity;

  /// Vérifie le QR renvoyé par le client.
  Future<PickupProofResult> verify(String raw, {DateTime? now}) async {
    if (expired(now)) {
      return const PickupProofResult.fail('Le défi a expiré. Recommencez pour afficher un nouveau QR.');
    }
    final j = PickupCodec.decode(raw);
    if (j == null) return const PickupProofResult.fail('Ce QR n\'est pas une réponse Garde.');
    if (j['v'] != vehicleId) {
      return const PickupProofResult.fail('Cette réponse concerne un autre véhicule.');
    }
    final sig = j['s'];
    if (sig is! String) return const PickupProofResult.fail('Réponse incomplète.');

    if (isEnroll) {
      final key = j['k'];
      if (j['t'] != 'E' || key is! String) {
        return const PickupProofResult.fail('Ce QR n\'est pas une réponse d\'enrôlement.');
      }
      final ok = await PickupCrypto.verify(key, PickupCrypto.enrollMessage(vehicleId, nonce), sig);
      if (!ok) return const PickupProofResult.fail('La signature du client est invalide.');
      return PickupProofResult.ok(key: key, nonce: nonce, sig: sig);
    }

    if (j['t'] != 'P') return const PickupProofResult.fail('Ce QR n\'est pas une preuve de remise.');
    final ok = await PickupCrypto.verify(ownerKey!, PickupCrypto.pickupMessage(vehicleId, nonce), sig);
    if (!ok) {
      return const PickupProofResult.fail(
        'Preuve invalide : ce téléphone ne détient pas la clé de ce véhicule.',
      );
    }
    return PickupProofResult.ok(nonce: nonce, sig: sig);
  }
}

/// Un véhicule sécurisé, tel que mémorisé sur le téléphone du client.
class ClientTicket {
  const ClientTicket({
    required this.vehicleId,
    required this.center,
    required this.plate,
    required this.code,
    required this.enrolledAt,
  });

  final String vehicleId;
  final String center;
  final String plate;
  final String code;
  final DateTime enrolledAt;

  Map<String, Object?> toJson() => {
        'v': vehicleId,
        'n': center,
        'p': plate,
        'c': code,
        'at': enrolledAt.millisecondsSinceEpoch,
      };

  static ClientTicket? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['v'];
    final at = j['at'];
    if (v is! String || at is! int) return null;
    return ClientTicket(
      vehicleId: v,
      center: (j['n'] as String?) ?? '',
      plate: (j['p'] as String?) ?? '',
      code: (j['c'] as String?) ?? '',
      enrolledAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// Stockage de secrets (Keystore / Keychain en production, mémoire dans les tests).
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Côté client : une clé secrète par véhicule (aucun lien entre deux centres ou deux dépôts).
class ClientVault {
  ClientVault(this._store);

  final SecretStore _store;
  static const _index = 'pickup_index';

  String _seedKey(String vehicleId) => 'pickup_seed_$vehicleId';

  Future<List<ClientTicket>> tickets() async {
    final raw = await _store.read(_index);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (ClientTicket.fromJson(e) != null) ClientTicket.fromJson(e)!,
      ]..sort((a, b) => b.enrolledAt.compareTo(a.enrolledAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveIndex(List<ClientTicket> all) =>
      _store.write(_index, jsonEncode([for (final t in all) t.toJson()]));

  /// Enrôle ce téléphone pour un véhicule : crée (ou retrouve) la clé et renvoie le QR de réponse.
  Future<String> enroll(PickupRequest r, {DateTime? now}) async {
    var seed = await _store.read(_seedKey(r.vehicleId));
    final String pub;
    if (seed == null) {
      final k = await PickupCrypto.newKey();
      seed = k.seed;
      pub = k.publicKey;
      await _store.write(_seedKey(r.vehicleId), seed);
    } else {
      pub = (await PickupCrypto.keyFromSeed(PickupCrypto.unb64(seed)!)).publicKey;
    }
    final all = [for (final t in await tickets()) if (t.vehicleId != r.vehicleId) t];
    all.add(ClientTicket(
      vehicleId: r.vehicleId,
      center: r.center,
      plate: r.plate,
      code: r.code,
      enrolledAt: now ?? DateTime.now(),
    ));
    await _saveIndex(all);
    final sig = await PickupCrypto.sign(seed, PickupCrypto.enrollMessage(r.vehicleId, r.nonce));
    return PickupCodec.encode({'t': 'E', 'v': r.vehicleId, 'k': pub, 's': sig});
  }

  /// Répond à un défi de remise. Retourne null si ce téléphone n'a pas la clé de ce véhicule.
  Future<String?> respond(PickupRequest r) async {
    final seed = await _store.read(_seedKey(r.vehicleId));
    if (seed == null) return null;
    final sig = await PickupCrypto.sign(seed, PickupCrypto.pickupMessage(r.vehicleId, r.nonce));
    return PickupCodec.encode({'t': 'P', 'v': r.vehicleId, 's': sig});
  }

  Future<bool> has(String vehicleId) async => (await _store.read(_seedKey(vehicleId))) != null;

  /// Oublie un véhicule (après la remise, ou pour nettoyer).
  Future<void> forget(String vehicleId) async {
    await _store.delete(_seedKey(vehicleId));
    await _saveIndex([for (final t in await tickets()) if (t.vehicleId != vehicleId) t]);
  }
}
