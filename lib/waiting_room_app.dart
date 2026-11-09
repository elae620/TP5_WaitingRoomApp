import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'queue_provider.dart';

/// Widget racine de l'application Waiting Room.
///
/// Configure le thème Material et définit [WaitingRoomPage] comme écran
/// principal.
class WaitingRoomApp extends StatelessWidget {
  const WaitingRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waiting Room',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const WaitingRoomPage(),
    );
  }
}

/// Page principale affichant la file d'attente.
///
/// Permet à l'utilisateur de :
/// - **Ajouter** un client (champ texte + bouton « Add »)
/// - **Voir** la liste ordonnée des clients avec leur date d'inscription
/// - **Supprimer** un client individuel (icône poubelle)
/// - **Passer au suivant** (bouton « Next Client » – supprime le premier de la file)
///
/// Utilise [Consumer] de `provider` pour se reconstruire automatiquement
/// dès que [QueueProvider] notifie un changement.
class WaitingRoomPage extends StatefulWidget {
  const WaitingRoomPage({super.key});
  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage> {
  final _controller = TextEditingController();

  /// Lit le nom saisi, appelle [QueueProvider.addClient] et gère les erreurs.
  ///
  /// Affiche un [SnackBar] si le champ est vide ou si l'ajout échoue.
  Future<void> _add() async {
    final name = _controller.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a client name.')),
      );
      return;
    }

    _controller.clear();

    try {
      await context.read<QueueProvider>().addClient(name);
    } catch (e, stackTrace) {
      debugPrint('Add client error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add client: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting Room'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Enter name'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _add, child: const Text('Add')),
              ],
            ),
            Consumer<QueueProvider>(
              builder: (context, provider, _) {
                final error = provider.syncError;
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Échec de synchronisation Supabase : $error',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Consumer<QueueProvider>(
                builder: (context, provider, _) {
                  if (provider.clients.isEmpty) {
                    return const Center(child: Text('No one in queue yet...'));
                  }
                  return ListView.builder(
                    itemCount: provider.clients.length,
                    itemBuilder: (context, i) {
                      final c = provider.clients[i];
                      final location = c.lat != null && c.lng != null
                          ? 'Lat: ${c.lat}, Lng: ${c.lng}'
                          : 'Position indisponible';
                      return Card(
                        child: ListTile(
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.createdAt.toString().split(' ')[0]}\n$location',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => provider.removeClient(c.id),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => context.read<QueueProvider>().nextClient(),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next Client'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}
