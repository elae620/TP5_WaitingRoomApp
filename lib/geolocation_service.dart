import 'package:geolocator/geolocator.dart';

class GeolocationService {
  Future<Position?> getCurrentPosition() async {
    try {
      // 1. Vérifier si le service GPS est activé.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return null;
      }

      // 2. Vérifier la permission de localisation.
      LocationPermission permission = await Geolocator.checkPermission();

      // 3. Demander la permission si elle est refusée.
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // 4. Vérifier si la permission est toujours refusée.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // 5. Récupérer la position actuelle.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;
    }
  }
}
