import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'geolocation_service.dart';
import 'local_queue_service.dart';
import 'models/client.dart';

/// Gestionnaire d'état principal de l'application (pattern Provider).
///
/// [QueueProvider] est un [ChangeNotifier] qui orchestre :
/// - La **persistance locale** (SQLite via [LocalQueueService]) – offline-first
/// - La **géolocalisation GPS** (via [GeolocationService])
/// - La **synchronisation Supabase** (upsert + écoute temps réel)
/// - La **détection réseau** (connectivity_plus) pour déclencher la sync
///   automatiquement au retour de la connexion
///
/// ### Cycle de vie
/// ```dart
/// // Dans main.dart
/// ChangeNotifierProvider(
///   create: (_) => QueueProvider()..initialize(),
///   child: const WaitingRoomApp(),
/// )
/// ```
///
/// ### Architecture de synchronisation
/// ```
/// UI ──► addClient() ──► SQLite (immédiat) ──► notifyListeners()
///                    └──► _syncLocalToRemote() (unawaited, arrière-plan)
///                              │
///                    Supabase.upsert() ──► markClientAsSynced()
/// ```
///
/// ### Résistance aux pannes réseau
/// Les clients créés hors ligne sont marqués `is_synced = 0` et re-synchronisés
/// dès que [Connectivity.onConnectivityChanged] signale un retour en ligne.
class QueueProvider extends ChangeNotifier {
  final SupabaseClient _supabase;
  final LocalQueueService _localDb;
  final GeolocationService _geoService;

  List<Client> _clients = [];

  /// Liste ordonnée (croissant par `created_at`) des clients en file d'attente.
  List<Client> get clients => _clients;

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _syncing = false;
  bool _syncRequested = false;
  String? _syncError;

  /// Dernière erreur de synchronisation, affichée dans l'interface.
  String? get syncError => _syncError;

  /// Crée un [QueueProvider] avec des dépendances injectables (facilitant les tests).
  ///
  /// En production, les valeurs par défaut utilisent les singletons Supabase.
  /// En test, on peut passer des mocks pour [supabase], [localDb] et [geoService].
  QueueProvider({
    SupabaseClient? supabase,
    LocalQueueService? localDb,
    GeolocationService? geoService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _localDb = localDb ?? LocalQueueService(),
        _geoService = geoService ?? GeolocationService();

  /// Initialise le provider : charge les données locales, démarre l'écoute
  /// Supabase et lance une première synchronisation.
  ///
  /// À appeler une fois après la création (voir `main.dart`).
  Future<void> initialize() async {
    await _reloadFromLocal();
    _listen();
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        _syncLocalToRemote();
      }
    });
    await _syncLocalToRemote();
  }

  /// Recharge la liste des clients depuis SQLite et notifie l'UI.
  Future<void> _reloadFromLocal() async {
    final rows = await _localDb.getClients();
    _clients = rows.map(Client.fromMap).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    notifyListeners();
  }

  /// Écoute le stream Supabase en temps réel et maintient la base locale à jour.
  ///
  /// Flux de traitement :
  /// 1. Insère / met à jour en local chaque ligne reçue de Supabase
  /// 2. Supprime en local les clients synchronisés qui ont disparu à distance
  /// 3. Recharge et notifie l'UI
  void _listen() {
    _sub = _supabase
        .from('clients')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .listen(
      (rows) async {
        final remoteIds = rows.map((r) => r['id'].toString()).toSet();

        for (final row in rows) {
          await _localDb.insertClientLocally({
            'id': row['id'].toString(),
            'name': row['name'],
            'lat': row['lat'],
            'lng': row['lng'],
            'created_at': row['created_at'].toString(),
            'is_synced': 1,
          });
        }

        // Supprimer en local les clients synchronisés qui n'existent plus à distance
        final local = await _localDb.getClients();
        for (final c in local) {
          if (c['is_synced'] == 1 && !remoteIds.contains(c['id'])) {
            await _localDb.deleteClient(c['id'] as String);
          }
        }
        await _reloadFromLocal();
      },
      onError: (e) => debugPrint('Stream error: $e'),
    );
  }

  /// Synchronise les clients non synchronisés (is_synced = 0) vers Supabase.
  ///
  /// - Utilise un verrou [_syncing] pour éviter les appels concurrents.
  /// - En cas d'échec d'un client individuel, continue avec les suivants.
  /// - Appelé automatiquement après [addClient] et au retour en ligne.
  Future<void> _syncLocalToRemote() async {
    if (_syncing) {
      // A client may have been added after the current batch was read.
      // Queue another pass so it is not left pending until connectivity changes.
      _syncRequested = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncRequested = false;
        final unsynced = await _localDb.getUnsyncedClients();
        for (final client in unsynced) {
          try {
            final localId = client['id'] as String;
            final remote = Map<String, dynamic>.from(client)
              ..remove('id')
              ..remove('is_synced');
            final inserted = await _supabase
                .from('clients')
                .insert(remote)
                .select('id')
                .single();
            await _localDb.replaceClientId(
              localId,
              inserted['id'].toString(),
            );
            _syncError = null;
          } catch (e) {
            _syncError = e.toString();
            debugPrint('Sync failed for ${client['id']}: $e');
          }
        }
      } while (_syncRequested);
      await _reloadFromLocal();
      if (_syncError != null) notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  /// Ajoute un nouveau client à la file d'attente.
  ///
  /// Étapes :
  /// 1. Récupère la position GPS via [GeolocationService] (peut retourner `null`)
  /// 2. Génère un identifiant local temporaire et insère le client en SQLite
  ///    avec `is_synced = 0` (Supabase attribuera l'ID définitif)
  /// 3. Notifie l'UI immédiatement ([_reloadFromLocal])
  /// 4. Lance la synchronisation Supabase en arrière-plan (non bloquant)
  ///
  /// Lance une exception si l'insertion locale échoue.
  /// Un [name] vide ou composé uniquement d'espaces est ignoré.
  Future<void> addClient(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;

    try {
      debugPrint('ADD: Getting location...');

      final position = await _geoService.getCurrentPosition();
      if (position == null) {
        debugPrint('ATTENTION : position GPS introuvable.');
      } else {
        debugPrint(
          'Position reçue : ${position.latitude}, ${position.longitude}',
        );
      }
      debugPrint('ADD: Saving client locally...');

      final id = const Uuid().v4();

      await _localDb.insertClientLocally({
        'id': id,
        'name': trimmedName,
        'lat': position?.latitude,
        'lng': position?.longitude,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'is_synced': 0,
      });

      debugPrint('ADD: Client saved locally: $trimmedName');

      await _reloadFromLocal();

      debugPrint('ADD: UI refreshed. Starting Supabase sync.');

      unawaited(_syncLocalToRemote());
    } catch (e, stackTrace) {
      debugPrint('ADD FAILED: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Supprime un client par son [id] localement et dans Supabase.
  ///
  /// La suppression locale est immédiate ; la suppression distante peut
  /// échouer silencieusement (mode hors ligne) sans bloquer l'UI.
  Future<void> removeClient(String id) async {
    await _localDb.deleteClient(id);
    await _reloadFromLocal();
    try {
      await _supabase.from('clients').delete().eq('id', id);
    } catch (e) {
      debugPrint('Remove failed (offline ?): $e');
    }
  }

  /// Retire le premier client de la file (FIFO).
  ///
  /// Sans effet si la file est vide.
  Future<void> nextClient() async {
    if (_clients.isEmpty) return;
    await removeClient(_clients.first.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
