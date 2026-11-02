import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/local_queue_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalQueueService service;

  setUp(() {
    service = LocalQueueService(inMemory: true);
  });

  tearDown(() async {
    await service.close();
  });

  test('insertClientLocally adds a client to the database', () async {
    await service.insertClientLocally({
      'id': 'test-123',
      'name': 'Alice',
      'lat': 40.71,
      'lng': -74.00,
      'created_at': '2026-10-20T10:00:00.000Z',
      'is_synced': 0,
    });

    final clients = await service.getClients();

    expect(clients, hasLength(1));
    expect(clients.first['name'], 'Alice');
    expect(clients.first['is_synced'], 0);
  });

  test('getUnsyncedClients returns only unsynced clients', () async {
    await service.insertClientLocally({
      'id': 'client-1',
      'name': 'Alice',
      'created_at': '2026-10-20T10:00:00.000Z',
      'is_synced': 0,
    });

    await service.insertClientLocally({
      'id': 'client-2',
      'name': 'Bob',
      'created_at': '2026-10-20T10:01:00.000Z',
      'is_synced': 1,
    });

    final unsynced = await service.getUnsyncedClients();

    expect(unsynced, hasLength(1));
    expect(unsynced.first['id'], 'client-1');
  });

  test('markClientAsSynced updates the synchronization status', () async {
    await service.insertClientLocally({
      'id': 'client-1',
      'name': 'Alice',
      'created_at': '2026-10-20T10:00:00.000Z',
      'is_synced': 0,
    });

    await service.markClientAsSynced('client-1');

    final unsynced = await service.getUnsyncedClients();

    expect(unsynced, isEmpty);
  });
}
