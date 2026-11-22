import 'package:flutter_test/flutter_test.dart';
import 'package:garde/security/pickup_crypto.dart';

// Vecteur produit par Node (server/test/pickup.test.ts) : Ed25519 est déterministe,
// Dart et le serveur doivent donc produire / accepter exactement les mêmes octets.
const _seedHex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _pub = 'A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg';
const _vid = '11111111-2222-4333-8444-555555555555';
const _nonce = 'AAECAwQFBgcICQoLDA0ODw';
const _enroll = '-NBvMOPCtF2zxi4IkdbwDHtWIx7VeFcuv9_kTutZnbx9o5KgzV2MiBbPokzLMJ8n46QjTOqNwe8qEZC3Pw7dDA';
const _pickup = 'NtlJaRcFP_lxp4oLCPQY2jXb4Z_Ip7BNJ6ZBLvAkKh9SMtXFDLzQzkdC6qosayv5JgHs3vtvpUzXDARAQmmbAQ';

List<int> _seed() => [
      for (var i = 0; i < _seedHex.length; i += 2) int.parse(_seedHex.substring(i, i + 2), radix: 16),
    ];

void main() {
  group('compatibilité avec le serveur (Node)', () {
    test('même clé publique et mêmes signatures que Node', () async {
      final k = await PickupCrypto.keyFromSeed(_seed());
      expect(k.publicKey, _pub);
      expect(await PickupCrypto.sign(k.seed, PickupCrypto.enrollMessage(_vid, _nonce)), _enroll);
      expect(await PickupCrypto.sign(k.seed, PickupCrypto.pickupMessage(_vid, _nonce)), _pickup);
    });

    test('vérifie les signatures de Node et refuse les messages modifiés', () async {
      expect(await PickupCrypto.verify(_pub, PickupCrypto.pickupMessage(_vid, _nonce), _pickup), isTrue);
      // Une preuve d'enrôlement ne vaut pas preuve de remise.
      expect(await PickupCrypto.verify(_pub, PickupCrypto.pickupMessage(_vid, _nonce), _enroll), isFalse);
      expect(await PickupCrypto.verify(_pub, PickupCrypto.pickupMessage('autre', _nonce), _pickup), isFalse);
      expect(await PickupCrypto.verify(_pub, 'GARDE-PICKUP-1|$_vid|AAAAAAAAAAAAAAAAAAAAAA', _pickup), isFalse);
      expect(await PickupCrypto.verify('court', 'x', _pickup), isFalse);
      expect(await PickupCrypto.verify(_pub, 'x', '%%%'), isFalse);
    });
  });

  group('échange agent ↔ client', () {
    const vid = '99999999-aaaa-4bbb-8ccc-dddddddddddd';

    test('enrôlement puis remise : la preuve du bon téléphone passe', () async {
      final vault = ClientVault(MemorySecretStore());

      final enroll = AgentExchange.enroll(vehicleId: vid, code: '123456', center: 'Parking', plate: 'AB 12');
      final req = PickupRequest.parse(enroll.requestQr)!;
      expect(req.isEnroll, isTrue);
      expect(req.center, 'Parking');
      final answer = await vault.enroll(req);
      final enrolled = await enroll.verify(answer);
      expect(enrolled.isOk, isTrue, reason: enrolled.error);
      final ownerKey = enrolled.key!;

      expect((await vault.tickets()).single.vehicleId, vid);

      final challenge = AgentExchange.challenge(
        vehicleId: vid, code: '123456', center: 'Parking', plate: 'AB 12', ownerKey: ownerKey,
      );
      final creq = PickupRequest.parse(challenge.requestQr)!;
      expect(creq.isEnroll, isFalse);
      final proof = await vault.respond(creq);
      final res = await challenge.verify(proof!);
      expect(res.isOk, isTrue, reason: res.error);
      expect(res.nonce, challenge.nonce);
      expect(await PickupCrypto.verify(ownerKey, PickupCrypto.pickupMessage(vid, challenge.nonce), res.sig!), isTrue);
    });

    test('le téléphone d\'un autre client ne peut pas répondre', () async {
      final mine = ClientVault(MemorySecretStore());
      final thief = ClientVault(MemorySecretStore());
      final enroll = AgentExchange.enroll(vehicleId: vid, code: '1', center: 'C', plate: '');
      final key = (await enroll.verify(await mine.enroll(PickupRequest.parse(enroll.requestQr)!))).key!;

      final challenge = AgentExchange.challenge(vehicleId: vid, code: '1', center: 'C', plate: '', ownerKey: key);
      final creq = PickupRequest.parse(challenge.requestQr)!;
      expect(await thief.respond(creq), isNull); // pas de clé pour ce véhicule

      // Il enrôle sa propre clé pour le même véhicule, puis signe : la clé enrôlée ne correspond pas.
      await thief.enroll(PickupRequest.parse(AgentExchange.enroll(vehicleId: vid, code: '1', center: 'C', plate: '').requestQr)!);
      final forged = await thief.respond(creq);
      final res = await challenge.verify(forged!);
      expect(res.isOk, isFalse);
    });

    test('une réponse enregistrée ne sert pas pour un nouveau défi (rejeu)', () async {
      final vault = ClientVault(MemorySecretStore());
      final enroll = AgentExchange.enroll(vehicleId: vid, code: '1', center: 'C', plate: '');
      final key = (await enroll.verify(await vault.enroll(PickupRequest.parse(enroll.requestQr)!))).key!;

      final first = AgentExchange.challenge(vehicleId: vid, code: '1', center: 'C', plate: '', ownerKey: key);
      final recorded = (await vault.respond(PickupRequest.parse(first.requestQr)!))!;
      final second = AgentExchange.challenge(vehicleId: vid, code: '1', center: 'C', plate: '', ownerKey: key);
      expect((await second.verify(recorded)).isOk, isFalse);
    });

    test('défi expiré, QR étranger, autre véhicule', () async {
      final vault = ClientVault(MemorySecretStore());
      final t0 = DateTime(2026, 1, 1, 12);
      final enroll = AgentExchange.enroll(vehicleId: vid, code: '1', center: 'C', plate: '', now: t0);
      final answer = await vault.enroll(PickupRequest.parse(enroll.requestQr)!);
      final late = await enroll.verify(answer, now: t0.add(const Duration(minutes: 4)));
      expect(late.isOk, isFalse);
      expect(late.error, contains('expiré'));

      expect((await enroll.verify('GARDE:123456')).isOk, isFalse);
      final other = AgentExchange.enroll(vehicleId: '88888888-aaaa-4bbb-8ccc-dddddddddddd', code: '2', center: 'C', plate: '');
      expect((await other.verify(answer)).error, contains('autre véhicule'));
    });

    test('PickupRequest refuse les QR invalides', () {
      expect(PickupRequest.parse('GARDE:123456'), isNull);
      expect(PickupRequest.parse('GP1:@@@'), isNull);
      expect(PickupRequest.parse(PickupCodec.encode({'t': 'e', 'v': 'court', 'x': 'AAAA'})), isNull);
    });

    test('le coffre oublie un véhicule et se relit sans erreur', () async {
      final store = MemorySecretStore();
      final vault = ClientVault(store);
      final enroll = AgentExchange.enroll(vehicleId: vid, code: '1', center: 'C', plate: 'X');
      await vault.enroll(PickupRequest.parse(enroll.requestQr)!);
      expect(await vault.has(vid), isTrue);
      // Réenrôler le même véhicule réutilise la clé (même clé publique).
      final a = PickupCodec.decode(await vault.enroll(PickupRequest.parse(enroll.requestQr)!))!['k'];
      final b = PickupCodec.decode(await vault.enroll(PickupRequest.parse(enroll.requestQr)!))!['k'];
      expect(a, b);
      expect((await vault.tickets()).length, 1);
      await vault.forget(vid);
      expect(await vault.has(vid), isFalse);
      expect(await vault.tickets(), isEmpty);
      store.data['pickup_index'] = '{pas du json';
      expect(await ClientVault(store).tickets(), isEmpty);
    });
  });
}
