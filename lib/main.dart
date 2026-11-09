import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'queue_provider.dart';
import 'waiting_room_app.dart';

/// Point d'entrée de l'application **Waiting Room App** (TP5 Flutter).
///
/// Séquence d'initialisation :
/// 1. Charge les variables d'environnement depuis `.env`
///    ([SUPABASE_URL] et [SUPABASE_ANON_KEY])
/// 2. Initialise le client Supabase
/// 3. Établit une session anonyme (robuste au mode hors-ligne)
/// 4. Monte l'arbre de widgets avec [ChangeNotifierProvider] / [QueueProvider]
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Connexion anonyme : nécessite du réseau au premier lancement.
  // On l'entoure d'un try/catch pour que l'app démarre aussi hors-ligne.
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession == null) {
    try {
      await auth.signInAnonymously();
    } catch (e) {
      debugPrint('Anonymous sign-in failed (offline ?): $e');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => QueueProvider()..initialize(),
      child: const WaitingRoomApp(),
    ),
  );
}