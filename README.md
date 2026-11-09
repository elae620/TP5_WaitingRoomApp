# Waiting Room App – TP5 Flutter

> Application Flutter de salle d'attente avec **géolocalisation GPS**, persistance locale **SQLite**, synchronisation temps réel **Supabase** et gestion d'état via **Provider**.

---

## 📋 Table des matières

- [Aperçu](#aperçu)
- [Fonctionnalités](#fonctionnalités)
- [Architecture](#architecture)
- [Technologies utilisées](#technologies-utilisées)
- [Structure du projet](#structure-du-projet)
- [Installation et configuration](#installation-et-configuration)
- [Configuration de l'émulateur Android](#configuration-de-lémulateur-android)
- [Lancer les tests](#lancer-les-tests)
- [Logs attendus](#logs-attendus)
- [Documentation du code](#documentation-du-code)
- [Auteur](#auteur)

---

## Aperçu

Waiting Room est une application Flutter qui permet de gérer une file d'attente de clients. Chaque client est enregistré avec :

- Son **nom**
- Sa **position GPS** (latitude, longitude) au moment de l'ajout
- Sa **date/heure** d'inscription
- Son **statut de synchronisation** avec Supabase

L'application fonctionne **hors ligne** (SQLite comme source de vérité locale) et se synchronise automatiquement avec Supabase dès qu'une connexion réseau est disponible.

---

## Fonctionnalités

| Fonctionnalité | Description |
|---|---|
| ➕ Ajout de client | Enregistrement avec nom + coordonnées GPS |
| 📍 Géolocalisation GPS | Récupération robuste avec `getLastKnownPosition` + fallback `getCurrentPosition` |
| 💾 Persistance locale | SQLite via `sqflite` (offline-first) |
| ☁️ Synchronisation Supabase | Insertion automatique dès que la connexion est disponible ; ID attribué par la base |
| 🔄 Temps réel | Écoute du stream Supabase pour les mises à jour distantes |
| ⏩ Client suivant | Retire le premier client de la file |
| 🗑️ Suppression | Suppression locale + distante |
| 📶 Détection réseau | `connectivity_plus` pour déclencher la sync au retour en ligne |

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                     UI Layer                     │
│         WaitingRoomApp / WaitingRoomPage          │
│              (StatefulWidget + Consumer)          │
└──────────────────────┬──────────────────────────┘
                       │ Provider
┌──────────────────────▼──────────────────────────┐
│               QueueProvider                      │
│        (ChangeNotifier – State Manager)          │
│                                                  │
│  addClient()  removeClient()  nextClient()       │
│  _syncLocalToRemote()  _listen()  initialize()   │
└──────┬──────────────────────┬───────────────────┘
       │                      │
┌──────▼──────┐    ┌──────────▼───────┐    ┌──────────────────┐
│ Geolocation │    │ LocalQueueService │    │  SupabaseClient  │
│  Service    │    │   (sqflite)       │    │  (realtime +     │
│             │    │                   │    │   insert)        │
│getLastKnown │    │ insertClientLocal │    │ stream(clients)  │
│getCurrentPos│    │ getUnsyncedClients│    │ insert()         │
└─────────────┘    └───────────────────┘    └──────────────────┘
```

### Flux de données – Ajout d'un client

```
User taps "Add"
      │
      ▼
QueueProvider.addClient(name)
      │
      ├─► GeolocationService.getCurrentPosition()
      │         │
      │         ├─► getLastKnownPosition()       ← rapide (cache)
      │         └─► getCurrentPosition(high)     ← fallback GPS
      │
      ├─► LocalQueueService.insertClientLocally(...)   ← SQLite
      │
      ├─► notifyListeners()    ← UI rafraîchie immédiatement
      │
      └─► _syncLocalToRemote() ← unawaited, async vers Supabase
```

---

## Technologies utilisées

| Package | Version | Usage |
|---------|---------|-------|
| `flutter` | SDK | Framework UI |
| `provider` | ^6.0.0 | Gestion d'état (`ChangeNotifier`) |
| `geolocator` | ^11.0.0 | Récupération de la position GPS |
| `sqflite` | ^2.3.0 | Base de données locale SQLite |
| `supabase_flutter` | ^2.7.0 | Backend temps réel + auth anonyme |
| `connectivity_plus` | ^6.0.0 | Détection de la connectivité réseau |
| `flutter_dotenv` | ^5.1.0 | Variables d'environnement (`.env`) |
| `uuid` | ^4.0.0 | Génération d'identifiants uniques |
| `path_provider` | ^2.1.1 | Chemin vers le répertoire SQLite |

---

## Structure du projet

```
waiting_room_app/
├── android/
│   └── app/
│       ├── build.gradle.kts          # minSdk = 21 (requis par geolocator)
│       └── src/main/
│           └── AndroidManifest.xml   # Permissions GPS + FOREGROUND_SERVICE
├── lib/
│   ├── main.dart                     # Init Supabase + Provider
│   ├── waiting_room_app.dart         # UI principale (WaitingRoomApp + Page)
│   ├── queue_provider.dart           # Gestionnaire d'état (ChangeNotifier)
│   ├── geolocation_service.dart      # Service GPS robuste (multi-stratégie)
│   ├── local_queue_service.dart      # Couche d'accès SQLite
│   └── models/
│       └── client.dart               # Modèle Client (id, name, lat, lng, ...)
├── test/
│   ├── client_test.dart              # Tests unitaires du modèle Client
│   └── local_queue_service_test.dart # Tests SQLite (base in-memory)
├── docs/                             # Documentation complémentaire
├── pubspec.yaml                      # Dépendances et assets
├── .env                              # Variables Supabase (non versionné)
└── README.md                         # Ce fichier
```

---

## Installation et configuration

### 1. Prérequis

- **Flutter SDK** ≥ 3.10 ([flutter.dev](https://flutter.dev))
- **Android Studio** avec un émulateur API 21+ (ou appareil physique)
- Un projet **Supabase** avec la table `clients`

### 2. Cloner le dépôt

```bash
git clone https://github.com/elae620/TP5_WaitingRoomApp.git
cd TP5_WaitingRoomApp
```

### 3. Configurer Supabase

Créer un fichier `.env` à la racine du projet :

```env
SUPABASE_URL=https://xxxxxxxxxxxxxxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### Schéma Supabase

Pour une nouvelle base, créer la table avec un identifiant auto-incrémenté :

```sql
CREATE TABLE clients (
  id         BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name       TEXT NOT NULL,
  lat        DOUBLE PRECISION,
  lng        DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Pour la table existante dont `id` est de type `TEXT`, exécuter une fois le SQL
suivant dans **Supabase → SQL Editor**. Il conserve les IDs actuels et configure
une séquence pour les nouveaux IDs numériques :

```sql
CREATE SEQUENCE IF NOT EXISTS public.clients_id_seq;
ALTER TABLE public.clients
  ALTER COLUMN id SET DEFAULT nextval('public.clients_id_seq')::text;

SELECT setval('public.clients_id_seq',
  COALESCE((SELECT MAX(id::bigint) FROM public.clients
            WHERE id ~ '^[0-9]+$'), 1),
  EXISTS (SELECT 1 FROM public.clients WHERE id ~ '^[0-9]+$'));
```

Les lignes dont l'ID est déjà un UUID gardent leur ID. Les nouvelles lignes
recevront le prochain numéro disponible.

```sql
-- Activer Row Level Security
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

-- L'application ouvre une session Supabase anonyme : son rôle SQL est authenticated.
CREATE POLICY "authenticated_all" ON public.clients
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

L'application utilise la connexion anonyme Supabase ; activer le fournisseur
**Anonymous Sign-Ins** dans les paramètres d'authentification du projet. Ne
publiez jamais une clé `service_role` dans l'application ou dans le dépôt.

### 4. Installer les dépendances et lancer

```bash
flutter pub get
flutter run
```

---

## Configuration de l'émulateur Android

Le GPS **ne fonctionne pas automatiquement** sur l'émulateur. Il faut injecter une position manuellement.

### Étapes obligatoires

1. Lancer l'émulateur depuis Android Studio
2. Cliquer sur **`⋮`** (Extended Controls)
3. Aller dans l'onglet **`Location`**
4. Saisir les coordonnées de test :
   - **Latitude** : `36.4510`
   - **Longitude** : `10.7350`
5. Cocher **`Enable GPS signal`** ✅
6. Cliquer sur **`Set Location`**
7. Lancer : `flutter run`

### Pourquoi `LocationAccuracy.high` ?

| Précision | Provider utilisé | Fonctionne sur émulateur |
|-----------|-----------------|--------------------------|
| `medium` | Network (WiFi/Cell) | ❌ Non (pas de vraie antenne) |
| `high` | GPS satellitaire | ✅ Oui (avec signal injecté) |

### Permissions AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<!-- Obligatoire depuis Android 9 (API 28) -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
```

> ⚠️ **Sans `FOREGROUND_SERVICE`**, Geolocator produit un **timeout silencieux** sur Android 9+.

---

## Lancer les tests

```bash
# Tous les tests
flutter test

# Tests du modèle Client
flutter test test/client_test.dart

# Tests de la couche SQLite
flutter test test/local_queue_service_test.dart

# Analyse statique
flutter analyze
```

---

## Logs attendus

### ✅ GPS disponible (position en cache)

```
GEO: Service GPS activé = true
GEO: Permission initiale = LocationPermission.whileInUse
GEO: Permission OK (...). Récupération de la position...
GEO: Dernière position connue utilisée : lat=36.451, lng=10.7349983, précision=5.0m
Position reçue : 36.451, 10.7349983
ADD: Client saved locally: <nom>
```

### ✅ GPS fix frais

```
GEO: Aucune dernière position connue disponible.
GEO: Tentative getCurrentPosition (GPS provider, accuracy=high)...
GEO: Position obtenue : lat=36.451, lng=10.735, précision=5.0m, altitude=0.0m
```

### ⚠️ GPS désactivé

```
GEO: Service GPS activé = false
GEO ERROR: GPS désactivé. Activer les services de localisation.
```

### ⚠️ Timeout (signal GPS non injecté)

```
GEO ERROR: Timeout — le GPS provider n'a pas répondu en 30s.
Sur émulateur : s'assurer que le signal GPS est injecté via
  Extended Controls > Location > Set Location (lat=36.4510, lng=10.7350)
```

---

## Documentation du code

Chaque fichier Dart est documenté avec des commentaires **dartdoc** (`///`).

| Fichier | Contenu documenté |
|---------|-------------------|
| [`lib/models/client.dart`](lib/models/client.dart) | Modèle `Client` – champs, `fromMap`, `toMap` |
| [`lib/local_queue_service.dart`](lib/local_queue_service.dart) | Service SQLite – toutes les méthodes CRUD |
| [`lib/geolocation_service.dart`](lib/geolocation_service.dart) | Service GPS – stratégie multi-étapes |
| [`lib/queue_provider.dart`](lib/queue_provider.dart) | `QueueProvider` – cycle de vie, sync, FIFO |
| [`lib/main.dart`](lib/main.dart) | Initialisation Supabase + Provider |
| [`lib/waiting_room_app.dart`](lib/waiting_room_app.dart) | Widgets UI – `WaitingRoomApp`, `WaitingRoomPage` |

---

## Dépôt

[TP5_WaitingRoomApp sur GitHub](https://github.com/elae620/TP5_WaitingRoomApp)

Workshop 5 Flutter — Géolocalisation GPS + SQLite offline-first + Supabase temps réel
