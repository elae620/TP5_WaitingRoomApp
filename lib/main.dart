import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:waiting_room_app/queue_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null ||
      supabaseUrl.isEmpty ||
      supabaseKey == null ||
      supabaseKey.isEmpty) {
    throw Exception(
      'Configuration Supabase manquante. '
      'Vérifiez le fichier .env.',
    );
  }

  bool supabaseAvailable = false;
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
    supabaseAvailable = true;
  } catch (e) {
    debugPrint('Supabase non disponible (mode hors ligne) : $e');
  }

  runApp(WaitingRoomApp(supabaseAvailable: supabaseAvailable));
}

class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key, this.supabaseAvailable = true});

  final bool supabaseAvailable;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<QueueProvider>(
      create: (_) {
        final provider = QueueProvider(
          supabase: supabaseAvailable ? Supabase.instance.client : null,
        );
        unawaited(provider.initialize());
        return provider;
      },
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WaitingRoomScreen(),
      ),
    );
  }
}

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addClient() async {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez saisir le nom du client.')),
      );
      return;
    }

    try {
      await context.read<QueueProvider>().addClient(name);

      if (!mounted) return;
      _controller.clear();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l’ajout : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QueueProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Waiting Room'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Client Name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addClient(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addClient, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Clients in Queue: ${provider.clients.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (provider.isLoading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: provider.clients.isEmpty
                  ? const Center(child: Text('No one in queue yet...'))
                  : ListView.builder(
                      itemCount: provider.clients.length,
                      itemBuilder: (context, index) {
                        final client = provider.clients[index];
                        final name = client['name'] as String;
                        final id = client['id'].toString();
                        final createdAt = client['created_at'] as String;

                        final date = DateTime.parse(createdAt).toLocal();

                        final lat = client['lat'] as num?;
                        final lng = client['lng'] as num?;

                        final locationText = lat != null && lng != null
                            ? '📍 ${lat.toStringAsFixed(4)}, '
                                  '${lng.toStringAsFixed(4)}'
                            : '📍 Location not captured';

                        return Card(
                          child: ListTile(
                            leading: const Icon(
                              Icons.person,
                              color: Colors.indigo,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              client['lat'] == null
                                  ? '📍 Location not captured'
                                  : '📍 ${client['lat'].toStringAsFixed(4)}, '
                                        '${client['lng'].toStringAsFixed(4)}',
                            ),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Remove client',
                              onPressed: () async {
                                try {
                                  await context
                                      .read<QueueProvider>()
                                      .removeClient(id);
                                } catch (error) {
                                  if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erreur lors de la '
                                        'suppression : $error',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('nextClientButton'),
        tooltip: 'Next Client',
        onPressed: () async {
          try {
            await context.read<QueueProvider>().nextClient();
          } catch (error) {
            if (!context.mounted) return;

            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Erreur : $error')));
          }
        },
        child: const Icon(Icons.skip_next),
      ),
    );
  }
}
