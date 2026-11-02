import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:waiting_room_app/queue_provider.dart';
import 'package:waiting_room_app/local_queue_service.dart';

import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Display client name and GPS coordinates', (tester) async {
    final provider = QueueProvider.forTesting(insertClient: (name) async {});

    // Injecter un client de test dans le provider
    // sera fait à l'étape suivante.

    await tester.pumpWidget(
      ChangeNotifierProvider<QueueProvider>.value(
        value: provider,
        child: const MaterialApp(home: WaitingRoomScreen()),
      ),
    );

    expect(find.text('No one in queue yet...'), findsOneWidget);

    provider.dispose();
  });
}
