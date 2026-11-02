import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'geolocation_service.dart';
import 'local_queue_service.dart';

class QueueProvider extends ChangeNotifier {
  QueueProvider({
    LocalQueueService? localDb,
    SupabaseClient? supabase,
    GeolocationService? geoService,
  }) : _localDb = localDb ?? LocalQueueService(),
       _supabase = supabase ?? Supabase.instance.client,
       _geoService = geoService ?? GeolocationService(),
       _insertClientForTesting = null;

  // Constructeur réservé aux tests unitaires.
  QueueProvider.forTesting({
    required Future<void> Function(String name) insertClient,
  }) : _localDb = null,
       _supabase = null,
       _geoService = null,
       _insertClientForTesting = insertClient;

  // Constructeur réservé aux tests de géolocalisation.
  QueueProvider.forTestingWithServices({
    required LocalQueueService localDb,
    required GeolocationService geoService,
  }) : _localDb = localDb,
       _supabase = null,
       _geoService = geoService,
       _insertClientForTesting = null;

  final LocalQueueService? _localDb;
  final SupabaseClient? _supabase;
  final GeolocationService? _geoService;

  final Future<void> Function(String name)? _insertClientForTesting;

  List<Map<String, dynamic>> _clients = [];

  List<Map<String, dynamic>> get clients => List.unmodifiable(_clients);

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _isDisposed = false;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  Future<void> initialize() async {
    if (_isInitialized || _isLoading || _isDisposed) return;

    _isLoading = true;
    _notifyIfAlive();

    try {
      // Charger d'abord les données locales.
      await _refreshLocalClients();

      // L'app est utilisable dès que les données locales sont chargées.
      _isInitialized = true;
      _isLoading = false;
      _notifyIfAlive();

      // Tenter la synchronisation distante en arrière-plan
      // (échoue silencieusement hors ligne).
      unawaited(_fetchRemoteClients());
      _setupRealtimeSubscription();
      unawaited(syncPendingClients());
    } catch (e) {
      // Même en cas d'erreur, l'app reste fonctionnelle en local.
      _isInitialized = true;
      debugPrint('Erreur lors de l\'initialisation : $e');
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  Future<void> _fetchRemoteClients() async {
    final db = _localDb;
    final remote = _supabase;
    if (db == null || remote == null || _isDisposed) return;

    try {
      final rows = await remote.from('clients').select();
      debugPrint('CLIENTS RECUPERES : $rows');

      for (final row in rows) {
        await db.insertClientLocally({...row, 'is_synced': 1});
      }

      await _refreshLocalClients();
    } catch (e) {
      debugPrint('ERREUR SUPABASE : $e');
    }
  }

  Future<void> _refreshLocalClients() async {
    final db = _localDb;
    if (db == null || _isDisposed) return;

    _clients = await db.getClients();
    _notifyIfAlive();
  }

  Future<void> addClient(String name) async {
    final trimmedName = name.trim();

    if (trimmedName.isEmpty) return;

    // Compatibilité avec les anciens tests unitaires.
    final testInsert = _insertClientForTesting;
    if (testInsert != null) {
      await testInsert(trimmedName);
      return;
    }

    // Récupérer la position GPS.
    final position = await _geoService?.getCurrentPosition();

    final db = _localDb!;

    final client = <String, dynamic>{
      'id': const Uuid().v4(),
      'name': trimmedName,
      'lat': position?.latitude,
      'lng': position?.longitude,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_synced': 0,
    };

    // Enregistrer le client dans SQLite.
    await db.insertClientLocally(client);
    await _refreshLocalClients();

    // Synchroniser avec Supabase en arrière-plan.
    unawaited(syncPendingClients());
  }

  Future<void> syncPendingClients() async {
    if (_isSyncing || _isDisposed) return;

    final db = _localDb;
    final remote = _supabase;

    // Le constructeur de test n'utilise aucun service distant.
    if (db == null || remote == null) return;

    _isSyncing = true;
    _notifyIfAlive();

    try {
      final pending = await db.getUnsyncedClients();

      for (final client in pending) {
        try {
          final remoteClient = Map<String, dynamic>.from(client)
            ..remove('is_synced')
            ..remove('id');

          await remote.from('clients').insert(remoteClient);

          await db.markClientAsSynced(client['id'].toString());
        } catch (error) {
          debugPrint(
            'Échec de synchronisation du client '
            '${client['id']}: $error',
          );
        }
      }

      await _refreshLocalClients();
    } catch (error) {
      debugPrint('Erreur de synchronisation : $error');
    } finally {
      _isSyncing = false;
      _notifyIfAlive();
    }
  }

  void _setupRealtimeSubscription() {
    final remote = _supabase;

    if (remote == null || _subscription != null || _isDisposed) {
      return;
    }

    _subscription = remote
        .from('clients')
        .stream(primaryKey: ['id'])
        .listen(
          (rows) async {
            final db = _localDb;
            if (db == null || _isDisposed) return;

            try {
              for (final row in rows) {
                await db.insertClientLocally({...row, 'is_synced': 1});
              }

              await _refreshLocalClients();
            } catch (error) {
              debugPrint('Erreur Realtime : $error');
            }
          },
          onError: (Object error) {
            debugPrint('Erreur du flux Realtime : $error');
          },
        );
  }

  Future<void> removeClient(String id) async {
    final db = _localDb;
    final remote = _supabase;

    if (db == null || remote == null) return;

    await db.deleteClientLocally(id);
    await _refreshLocalClients();

    try {
      await remote.from('clients').delete().eq('id', id);
    } catch (error) {
      debugPrint('Échec de suppression distante : $error');
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) return;

    final firstClient = _clients.first;
    await removeClient(firstClient['id'] as String);
  }

  void _notifyIfAlive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}
