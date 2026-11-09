import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:waiting_room_app/local_queue_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LocalQueueService service;

  setUp(() {
    service = LocalQueueService(inMemory: true);
  });

  tearDown(() async {
    await service.close();
  });

  test('insertClientLocally adds a record to the database', () async {
    await service.insertClientLocally({
      'id': 'test-123',
      'name': 'Alice',
      'lat': 40.71,
      'lng': -74.00,
      'created_at': '2024-01-01T00:00:00Z',
      'is_synced': 0,
    });

    final clients = await service.getUnsyncedClients();
    expect(clients.length, 1);
    expect(clients[0]['name'], 'Alice');
  });

  test('markClientAsSynced removes client from unsynced list', () async {
    await service.insertClientLocally({
      'id': 'a1',
      'name': 'Bob',
      'lat': null,
      'lng': null,
      'created_at': '2024-01-01T00:00:00Z',
      'is_synced': 0,
    });
    await service.markClientAsSynced('a1');

    expect(await service.getUnsyncedClients(), isEmpty);
    expect((await service.getClients()).length, 1);
  });
}