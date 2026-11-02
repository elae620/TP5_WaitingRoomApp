import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Interface commune pour le stockage local des clients.
abstract class LocalQueueService {
  /// Crée automatiquement l'implémentation adaptée à la plateforme :
  /// - SQLite sur mobile / desktop
  /// - Stockage en mémoire sur le web
  factory LocalQueueService({bool inMemory = false}) {
    if (kIsWeb) {
      return InMemoryQueueService();
    }
    return SqliteQueueService(inMemory: inMemory);
  }

  Future<void> insertClientLocally(Map<String, dynamic> client);

  Future<List<Map<String, dynamic>>> getClients();

  Future<List<Map<String, dynamic>>> getUnsyncedClients();

  Future<void> markClientAsSynced(String id);

  Future<void> deleteClientLocally(String id);

  Future<void> close();
}

// ──────────────────────────────────────────────
//  Implémentation SQLite (mobile / desktop)
// ──────────────────────────────────────────────

class SqliteQueueService implements LocalQueueService {
  static const String tableName = 'local_clients';

  final bool inMemory;

  Database? _database;
  Future<Database>? _databaseFuture;

  SqliteQueueService({this.inMemory = false});

  /// Retourne la base existante ou l'ouvre une seule fois.
  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _databaseFuture ??= _initDB();

    try {
      _database = await _databaseFuture!;
      return _database!;
    } catch (_) {
      _databaseFuture = null;
      rethrow;
    }
  }

  /// Initialise la base SQLite.
  Future<Database> _initDB() async {
    if (inMemory) {
      return openDatabase(':memory:', version: 1, onCreate: _onCreate);
    }

    final dbPath = await getDatabasesPath();
    final fullPath = join(dbPath, 'waiting_room.db');

    return openDatabase(fullPath, version: 1, onCreate: _onCreate);
  }

  /// Crée la table lors de la première ouverture.
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

  /// Ajoute un client ou remplace l'enregistrement
  /// portant le même identifiant.
  @override
  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    final db = await database;

    await db.insert(
      tableName,
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retourne tous les clients, du plus ancien au plus récent.
  @override
  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;

    return db.query(tableName, orderBy: 'created_at ASC');
  }

  /// Retourne uniquement les clients à synchroniser.
  @override
  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    final db = await database;

    return db.query(
      tableName,
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
  }

  /// Marque un client comme synchronisé.
  @override
  Future<void> markClientAsSynced(String id) async {
    final db = await database;

    await db.update(
      tableName,
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteClientLocally(String id) async {
    final db = await database;

    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Ferme la base de données.
  @override
  Future<void> close() async {
    final db = _database ?? await _databaseFuture;

    _database = null;
    _databaseFuture = null;

    if (db != null) {
      await db.close();
    }
  }
}

// ──────────────────────────────────────────────
//  Implémentation en mémoire (web)
// ──────────────────────────────────────────────

class InMemoryQueueService implements LocalQueueService {
  final List<Map<String, dynamic>> _clients = [];

  @override
  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    final id = client['id'];
    _clients.removeWhere((c) => c['id'] == id);
    _clients.add(Map<String, dynamic>.from(client));
  }

  @override
  Future<List<Map<String, dynamic>>> getClients() async {
    final sorted = List<Map<String, dynamic>>.from(_clients)
      ..sort((a, b) =>
          (a['created_at'] as String).compareTo(b['created_at'] as String));
    return sorted;
  }

  @override
  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    return _clients.where((c) => c['is_synced'] == 0).toList();
  }

  @override
  Future<void> markClientAsSynced(String id) async {
    final index = _clients.indexWhere((c) => c['id'] == id);
    if (index != -1) {
      _clients[index] = {..._clients[index], 'is_synced': 1};
    }
  }

  @override
  Future<void> deleteClientLocally(String id) async {
    _clients.removeWhere((c) => c['id'] == id);
  }

  @override
  Future<void> close() async {
    _clients.clear();
  }
}
