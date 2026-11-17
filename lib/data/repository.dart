import 'models.dart';

/// Contrat d'accès aux données.
///
/// Aujourd'hui : [SqliteParkingRepository] (local, hors-ligne).
/// Demain : une implémentation `ApiParkingRepository` (REST → PostgreSQL)
/// qui respecte exactement cette interface. Aucun écran n'a à changer.
abstract class ParkingRepository {
  Future<void> init();

  // Centres
  Future<List<ParkingCenter>> centers();
  Future<ParkingCenter> saveCenter({
    String? id,
    required String name,
    required String location,
    required int guardHours,
  });
  Future<void> deleteCenter(String id);

  // Véhicules
  Future<Vehicle> addVehicle({
    required String centerId,
    required String plate,
    required VehicleType type,
    required String ownerName,
    required String ownerPhone,
    required String note,
    required int guardHours,
    DateTime? now,
  });
  Future<void> updateVehicle(Vehicle v);
  Future<void> markCollected(
    String id, {
    required DateTime at,
    required PickupCheck check,
    required bool ticketVerified,
  });
  Future<void> deleteVehicle(String id);

  Future<Vehicle?> vehicleById(String id);

  /// Cherche un ticket : privilégie le véhicule encore en garde avec ce code.
  Future<Vehicle?> vehicleByCode(String code);

  /// Véhicules déposés dans [from, to[ (heure locale).
  Future<List<Vehicle>> vehiclesBetween(String centerId, DateTime from, DateTime to);

  Future<List<Vehicle>> activeVehicles(String centerId);
  Future<List<Vehicle>> activeByPlateKey(String centerId, String key);
  Future<List<Vehicle>> search(String centerId, String query, {int limit = 80});

  // Réglages (thème, centre courant…)
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
}
