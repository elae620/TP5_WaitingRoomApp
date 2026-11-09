import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Service d'accès à la base de données SQLite locale.
///
/// Implémente le pattern **offline-first** : toutes les données sont d'abord
/// persistées localement avant d'être synchronisées avec Supabase.
///
/// La table [tableName] (`local_clients`) stocke :
/// - `id`         – UUID v4 (clé primaire)
/// - `name`       – Nom du client
/// - `lat` / `lng` – Coordonnées GPS (nullable)
/// - `created_at` – Horodatage ISO 8601 (UTC)
/// - `is_synced`  – Flag de synchronisation (0 = non synchronisé, 1 = synchronisé)
///
/// ### Utilisation typique
/// ```dart
/// final service = LocalQueueService();
/// await service.insertClientLocally({...});
/// final unsynced = await service.getUnsyncedClients();
/// ```
///
/// ### Mode in-memory (tests)
/// Passer `inMemory: true` pour obtenir une base SQLite en mémoire vive,
/// isolée entre les tests et sans effet de bord sur le disque.
class LocalQueueService {
  static Database? _database;

  /// Nom de la table SQLite utilisée pour stocker les clients.
  static const String tableName = 'local_clients';

  /// Si `true`, la base de données est créée en mémoire (pour les tests unitaires).
  final bool _inMemory;

  /// Crée une instance de [LocalQueueService].
  ///
  /// [inMemory] : `true` pour une base en mémoire (tests), `false` (défaut)
  /// pour une base persistée dans le répertoire de l'application.
  LocalQueueService({bool inMemory = false}) : _inMemory = inMemory;

  /// Retourne l'instance [Database] (singleton paresseux).
  ///
  /// La base est initialisée à la première demande via [_initDB].
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  /// Initialise la base de données SQLite.
  ///
  /// - En mode normal : crée `waiting_room.db` dans le répertoire système.
  /// - En mode in-memory : ouvre une base temporaire en RAM.
  Future<Database> _initDB() async {
    if (_inMemory) {
      return openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: _onCreate,
      );
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'waiting_room.db');
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  /// Callback appelé lors de la création initiale de la base.
  ///
  /// Crée la table [tableName] avec le schéma approprié.
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lat REAL,
        lng REAL,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Insère ou remplace un client dans la base locale.
  ///
  /// Utilise [ConflictAlgorithm.replace] pour gérer les upserts (cas où
  /// Supabase retourne un client déjà présent en local).
  ///
  /// [client] doit contenir les clés : `id`, `name`, `created_at`, `is_synced`
  /// (les champs `lat` et `lng` sont optionnels).
  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert(
      tableName,
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retourne tous les clients triés par date d'inscription croissante.
  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;
    return db.query(tableName, orderBy: 'created_at ASC');
  }

  /// Retourne uniquement les clients dont `is_synced = 0`.
  ///
  /// Ces clients sont en attente d'envoi vers Supabase.
  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    final db = await database;
    return db.query(tableName, where: 'is_synced = ?', whereArgs: [0]);
  }

  /// Marque un client comme synchronisé (`is_synced = 1`).
  ///
  /// Appelé par [QueueProvider._syncLocalToRemote] après un `upsert` réussi.
  Future<void> markClientAsSynced(String id) async {
    final db = await database;
    await db.update(
      tableName,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remplace l'identifiant temporaire local par l'ID auto-incrémenté distant.
  Future<void> replaceClientId(String oldId, String newId) async {
    final db = await database;
    await db.transaction((txn) async {
      final remoteRow = await txn.query(
        tableName,
        where: 'id = ?',
        whereArgs: [newId],
        limit: 1,
      );
      if (remoteRow.isNotEmpty) {
        await txn.delete(tableName, where: 'id = ?', whereArgs: [oldId]);
        await txn.update(
          tableName,
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [newId],
        );
      } else {
        await txn.update(
          tableName,
          {'id': newId, 'is_synced': 1},
          where: 'id = ?',
          whereArgs: [oldId],
        );
      }
    });
  }

  /// Supprime un client de la base locale par son [id].
  ///
  /// Cette opération est irréversible localement. La suppression distante
  /// est gérée séparément par [QueueProvider.removeClient].
  Future<void> deleteClient(String id) async {
    final db = await database;
    await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Ferme la connexion à la base de données et réinitialise le singleton.
  ///
  /// À appeler dans les tests (tearDown) pour libérer les ressources.
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
