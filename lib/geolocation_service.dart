import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

/// Service de géolocalisation GPS avec stratégie robuste multi-étapes.
///
/// Résout les problèmes courants rencontrés sur **émulateur Android Studio** :
/// - Timeout silencieux lié au `FOREGROUND_SERVICE`
/// - GPS provider inactif si le signal n'est pas injecté manuellement
///
/// ### Stratégie de récupération de position
///
/// 1. **Vérification du service GPS** – Si désactivé, retourne `null` immédiatement.
/// 2. **Vérification / demande de permission** – Gère les états `denied` et
///    `deniedForever`.
/// 3. **Dernière position connue** ([Geolocator.getLastKnownPosition]) – Rapide,
///    fonctionne même si le GPS vient juste d'être activé.
/// 4. **Position fraîche** ([Geolocator.getCurrentPosition]) – Fallback avec
///    `LocationAccuracy.high` (GPS satellitaire), timeout 30 s.
///
/// ### Utilisation
/// ```dart
/// final geo = GeolocationService();
/// final position = await geo.getCurrentPosition();
/// if (position != null) {
///   print('${position.latitude}, ${position.longitude}');
/// }
/// ```
///
/// ### Configuration requise (AndroidManifest.xml)
/// ```xml
/// <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
/// <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
/// <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
/// ```
class GeolocationService {
  /// Tente de récupérer la position GPS avec une stratégie robuste :
  /// 1. Vérifie les services et permissions
  /// 2. Essaie d'abord la dernière position connue (rapide, fonctionne sur émulateur)
  /// 3. Fallback sur getCurrentPosition avec haute précision (GPS provider)
  ///
  /// Retourne `null` si :
  /// - Le GPS est désactivé
  /// - Les permissions sont refusées
  /// - Un timeout survient (signal GPS non injecté sur émulateur)
  Future<Position?> getCurrentPosition() async {
    try {
      // ── Étape 1 : Service GPS activé ? ──────────────────────────────────
      final enabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('GEO: Service GPS activé = $enabled');

      if (!enabled) {
        debugPrint('GEO ERROR: GPS désactivé. Activer les services de localisation.');
        return null;
      }

      // ── Étape 2 : Vérification / demande de permissions ─────────────────
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('GEO: Permission initiale = $permission');

      if (permission == LocationPermission.denied) {
        debugPrint('GEO: Demande de permission en cours...');
        permission = await Geolocator.requestPermission();
        debugPrint('GEO: Permission après demande = $permission');
      }

      if (permission == LocationPermission.denied) {
        debugPrint('GEO ERROR: Permission refusée.');
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('GEO ERROR: Permission refusée définitivement. Aller dans les paramètres.');
        return null;
      }

      debugPrint('GEO: Permission OK ($permission). Récupération de la position...');

      // ── Étape 3 : Essai avec la dernière position connue (rapide) ────────
      // Très utile sur émulateur Android : si une position a déjà été injectée,
      // elle est retournée immédiatement sans attendre un nouveau fix GPS.
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint(
            'GEO: Dernière position connue utilisée : '
            'lat=${lastKnown.latitude}, lng=${lastKnown.longitude}, '
            'précision=${lastKnown.accuracy}m',
          );
          return lastKnown;
        }
        debugPrint('GEO: Aucune dernière position connue disponible.');
      } catch (e) {
        debugPrint('GEO: getLastKnownPosition a échoué : $e');
      }

      // ── Étape 4 : getCurrentPosition avec haute précision (GPS provider) ─
      // LocationAccuracy.high force l'utilisation du GPS provider (satellitaire),
      // ce qui est nécessaire sur émulateur Android Studio avec signal GPS injecté.
      // LocationAccuracy.medium utilise le network provider qui ne fonctionne
      // pas sur émulateur sans accès à une vraie antenne réseau.
      debugPrint('GEO: Tentative getCurrentPosition (GPS provider, accuracy=high)...');

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      debugPrint(
        'GEO: Position obtenue : '
        'lat=${position.latitude}, lng=${position.longitude}, '
        'précision=${position.accuracy}m, altitude=${position.altitude}m',
      );

      return position;
    } on TimeoutException {
      debugPrint(
        'GEO ERROR: Timeout — le GPS provider n\'a pas répondu en 30s.\n'
        'Sur émulateur : s\'assurer que le signal GPS est injecté via\n'
        '  Extended Controls > Location > Set Location (lat=36.4510, lng=10.7350)\n'
        '  et que "Enable GPS signal" est activé.',
      );
      return null;
    } catch (e, stackTrace) {
      debugPrint('GEO ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }
}
