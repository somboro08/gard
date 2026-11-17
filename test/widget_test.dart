// Tests de la logique pure (plaques, tickets, statuts, formats).
// Le nom du fichier est volontairement « widget_test.dart » : `flutter create`
// ne le recrée donc pas (son modèle par défaut référencerait un widget inexistant).
import 'package:flutter_test/flutter_test.dart';
import 'package:garde/core/format.dart';
import 'package:garde/core/plates.dart';
import 'package:garde/data/models.dart';

Vehicle _vehicle({
  required DateTime deposited,
  required DateTime due,
  DateTime? collected,
  String plate = 'AB 1234 RB',
}) {
  return Vehicle(
    id: 'v1',
    centerId: 'c1',
    code: '482913',
    plate: plate,
    type: VehicleType.moto,
    ownerName: 'Georges',
    ownerPhone: '',
    note: '',
    depositedAt: deposited,
    dueAt: due,
    collectedAt: collected,
  );
}

void main() {
  group('Plates', () {
    test('display normalise la saisie', () {
      expect(Plates.display(' ab-1234  rb '), 'AB 1234 RB');
      expect(Plates.display(''), '');
    });

    test('key ignore espaces et ponctuation', () {
      expect(Plates.key('ab 1234 rb'), 'AB1234RB');
      expect(Plates.key('AB-1234-RB'), 'AB1234RB');
    });

    test('compare : exact', () {
      expect(Plates.compare('AB 1234 RB', 'ab1234rb'), PlateMatch.exact);
    });

    test('compare : confusion OCR O/0, B/8 → proche', () {
      expect(Plates.compare('AB 1234 RB', 'AB 1234 R8'), PlateMatch.close);
      expect(Plates.compare('AB 1234 RB', 'AB 1Z34 RB'), PlateMatch.close);
    });

    test('compare : un seul caractère d\'écart → proche', () {
      expect(Plates.compare('AB 1234 RB', 'AB 1235 RB'), PlateMatch.close);
    });

    test('compare : plaques différentes', () {
      expect(Plates.compare('AB 1234 RB', 'ZX 9999 QQ'), PlateMatch.different);
      expect(Plates.compare('AB 1234 RB', ''), PlateMatch.different);
    });
  });

  group('PlateOcr', () {
    test('ignore le texte sans chiffre et retrouve la plaque', () {
      final c = PlateOcr.candidates(['BENIN', 'AB 1234 RB']);
      expect(c.first, 'AB 1234 RB');
    });

    test('aucun candidat si rien d\'exploitable', () {
      expect(PlateOcr.candidates(['BENIN', 'MOTO']), isEmpty);
    });
  });

  group('Tickets', () {
    test('parse accepte QR, code brut et code espacé', () {
      expect(Tickets.parse('GARDE:482913'), '482913');
      expect(Tickets.parse('482913'), '482913');
      expect(Tickets.parse('482 913'), '482913');
    });

    test('parse refuse le reste', () {
      expect(Tickets.parse('hello'), isNull);
      expect(Tickets.parse('GARDE:12'), isNull);
      expect(Tickets.parse('1234567'), isNull);
    });

    test('encode / parse aller-retour', () {
      expect(Tickets.parse(Tickets.encode('123456')), '123456');
    });
  });

  group('Phones', () {
    test('waNumber ajoute l\'indicatif 229', () {
      expect(Phones.waNumber('01 97 12 34 56'), '2290197123456');
      expect(Phones.waNumber('97123456'), '22997123456');
      expect(Phones.waNumber(''), '');
    });
  });

  group('Vehicle.statusAt', () {
    final dep = DateTime(2026, 11, 16, 8);
    final due = DateTime(2026, 11, 17, 8);

    test('en cours avant l\'échéance', () {
      final v = _vehicle(deposited: dep, due: due);
      expect(v.statusAt(DateTime(2026, 11, 16, 12)), VehicleStatus.enCours);
    });

    test('non récupéré après l\'échéance', () {
      final v = _vehicle(deposited: dep, due: due);
      expect(v.statusAt(DateTime(2026, 11, 17, 9)), VehicleStatus.nonRecupere);
    });

    test('récupéré dès que collectedAt est renseigné', () {
      final v = _vehicle(deposited: dep, due: due, collected: DateTime(2026, 11, 18));
      expect(v.statusAt(DateTime(2026, 11, 20)), VehicleStatus.recupere);
    });

    test('hasPlate', () {
      expect(_vehicle(deposited: dep, due: due).hasPlate, isTrue);
      expect(_vehicle(deposited: dep, due: due, plate: '').hasPlate, isFalse);
    });

    test('toMap / fromMap aller-retour', () {
      final v = _vehicle(deposited: dep, due: due);
      final back = Vehicle.fromMap(v.toMap());
      expect(back.code, v.code);
      expect(back.plate, v.plate);
      expect(back.depositedAt, v.depositedAt);
      expect(back.collectedAt, isNull);
    });
  });

  group('Tarifs et paiements', () {
    final dep = DateTime(2026, 11, 16, 8);
    final due = DateTime(2026, 11, 17, 8);

    test('Tariff.forType et isFree', () {
      const t = Tariff(moto: 100, velo: 50, voiture: 500);
      expect(t.forType(VehicleType.moto), 100);
      expect(t.forType(VehicleType.autre), 0);
      expect(t.isFree, isFalse);
      expect(const Tariff().isFree, isTrue);
    });

    test('balance / isPaid', () {
      final v = Vehicle(
        id: 'v',
        centerId: 'c',
        code: '123456',
        plate: 'AB 1234 RB',
        type: VehicleType.moto,
        ownerName: 'Georges',
        ownerPhone: '',
        note: '',
        depositedAt: dep,
        dueAt: due,
        price: 100,
        paidAmount: 40,
      );
      expect(v.balance, 60);
      expect(v.isPaid, isFalse);
      expect(Vehicle.fromMap(v.toMap()).paidAmount, 40);
      expect(_vehicle(deposited: dep, due: due).isPaid, isTrue); // prix 0 = gratuit
    });

    test('ParkingCenter aller-retour avec tarifs', () {
      final c = ParkingCenter(
        id: 'c',
        name: 'Parking école',
        location: 'Cotonou',
        guardHours: 24,
        createdAt: dep,
        tariff: const Tariff(moto: 100, velo: 50),
      );
      final back = ParkingCenter.fromMap(c.toMap());
      expect(back.tariff.moto, 100);
      expect(back.tariff.velo, 50);
      expect(back.tariff.voiture, 0);
    });
  });

  group('Fmt', () {
    test('money groupe les milliers', () {
      expect(Fmt.money(0), '0\u00A0FCFA');
      expect(Fmt.money(100), '100\u00A0FCFA');
      expect(Fmt.money(1500), '1\u00A0500\u00A0FCFA');
      expect(Fmt.money(1250000), '1\u00A0250\u00A0000\u00A0FCFA');
    });

    test('startOfWeek renvoie le lundi', () {
      // 18 nov. 2026 = mercredi
      expect(Fmt.startOfWeek(DateTime(2026, 11, 18, 15, 30)), DateTime(2026, 11, 16));
      // un lundi reste le même jour
      expect(Fmt.startOfWeek(DateTime(2026, 11, 16)), DateTime(2026, 11, 16));
    });

    test('weekRange', () {
      expect(Fmt.weekRange(DateTime(2026, 11, 16)), '16 – 22 nov.');
      expect(Fmt.weekRange(DateTime(2026, 10, 26)), '26 oct. – 1 nov.');
    });

    test('duration', () {
      expect(Fmt.duration(const Duration(minutes: 45)), '45 min');
      expect(Fmt.duration(const Duration(hours: 3, minutes: 20)), '3 h 20');
      expect(Fmt.duration(const Duration(hours: 50)), '2 j 2 h');
    });

    test('code et hours', () {
      expect(Fmt.code('482913'), '482 913');
      expect(Fmt.hours(24), '24 h');
      expect(Fmt.hours(72), '3 jours');
    });
  });
}
