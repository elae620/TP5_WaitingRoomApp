import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room_app/models/client.dart';

void main() {
  group('Client model', () {
    test('fromMap crée un Client correct', () {
      final map = {
        'id': 'abc-123',
        'name': 'Alice',
        'created_at': '2026-10-20T10:00:00.000Z',
      };

      final client = Client.fromMap(map);

      expect(client.id, 'abc-123');
      expect(client.name, 'Alice');
      expect(client.createdAt, DateTime.parse('2026-10-20T10:00:00.000Z'));
    });

    test('toMap renvoie les bonnes clés', () {
      final client = Client(
        id: '1',
        name: 'Bob',
        createdAt: DateTime.utc(2026, 10, 20),
      );

      final map = client.toMap();

      expect(map['id'], '1');
      expect(map['name'], 'Bob');
      expect(map['created_at'], '2026-10-20T00:00:00.000Z');
    });
  });
}