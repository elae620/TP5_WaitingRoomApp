import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:waiting_room_app/geolocation_service.dart';
import 'package:waiting_room_app/local_queue_service.dart';
import 'package:waiting_room_app/queue_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'queue_provider_geolocation_test.mocks.dart';

@GenerateMocks([GeolocationService])
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late LocalQueueService localDb;
  late MockGeolocationService mockGeoService;
  late QueueProvider provider;

  setUp(() async {
    localDb = LocalQueueService(inMemory: true);
    mockGeoService = MockGeolocationService();

    provider = QueueProvider.forTestingWithServices(
      localDb: localDb,
      geoService: mockGeoService,
    );
  });

  tearDown(() async {
    provider.dispose();
    await localDb.close();
  });

  test('addClient saves client with GPS coordinates', () async {
    final mockPosition = Position(
      longitude: -122.4194,
      latitude: 37.7749,
      timestamp: DateTime.now(),
      accuracy: 5.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

    when(mockGeoService.getCurrentPosition())
        .thenAnswer((_) async => mockPosition);

    await provider.addClient('Test User');

    expect(provider.clients.length, 1);
    expect(provider.clients.first['name'], 'Test User');
    expect(provider.clients.first['lat'], 37.7749);
    expect(provider.clients.first['lng'], -122.4194);
  });
}
