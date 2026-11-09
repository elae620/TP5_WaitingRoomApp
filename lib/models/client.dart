/// {@template client}
/// Modèle de données représentant un client dans la file d'attente.
///
/// Chaque client possède :
/// - un identifiant unique [id] (attribué par Supabase après synchronisation)
/// - un [name] (nom affiché dans la liste)
/// - des coordonnées GPS optionnelles [lat] / [lng]
/// - un horodatage [createdAt] (UTC)
/// - un flag [isSynced] indiquant si l'enregistrement a été envoyé à Supabase
/// {@endtemplate}
class Client {
  /// Identifiant unique du client (temporaire localement, puis attribué par Supabase).
  final String id;

  /// Nom du client tel que saisi par l'utilisateur.
  final String name;

  /// Latitude GPS au moment de l'ajout (null si GPS indisponible).
  final double? lat;

  /// Longitude GPS au moment de l'ajout (null si GPS indisponible).
  final double? lng;

  /// Date et heure d'inscription du client (UTC).
  final DateTime createdAt;

  /// Indique si le client a été synchronisé avec Supabase.
  ///
  /// `true`  → enregistrement présent dans la table distante
  /// `false` → en attente de synchronisation (mode hors ligne)
  final bool isSynced;

  /// {@macro client}
  Client({
    required this.id,
    required this.name,
    this.lat,
    this.lng,
    required this.createdAt,
    this.isSynced = true,
  });

  /// Crée un [Client] à partir d'une [Map] issue de SQLite ou de Supabase.
  ///
  /// Les champs `lat` et `lng` sont optionnels (peuvent être `null`).
  /// Le champ `is_synced` est interprété comme un entier (0 = false, 1 = true).
  factory Client.fromMap(Map<String, dynamic> m) {
    return Client(
      id: m['id'].toString(),
      name: m['name'] as String,
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      createdAt: DateTime.parse(m['created_at'].toString()),
      isSynced: (m['is_synced'] as num?)?.toInt() == 1,
    );
  }

  /// Convertit le [Client] en [Map] compatible SQLite / Supabase.
  ///
  /// Le flag `is_synced` est encodé comme un entier (0 ou 1)
  /// pour la compatibilité avec SQLite qui ne gère pas les booléens natifs.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lat': lat,
      'lng': lng,
      'created_at': createdAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  @override
  String toString() => 'Client(id: $id, name: $name, created_at: $createdAt)';
}
