1. Informations générales
- Projet : waiting_room_app --- application Flutter de gestion
  d'une salle d'attente.
- Sujet du TP : développer une application Offline-First avec
  stockage local SQLite, géolocalisation et synchronisation avec
  Supabase.
- Agent IA utilisé : ChatGPT (GPT-6).
- Environnement de développement : Antigravity, Flutter et Dart.
- Environnement d'exécution : émulateur Android.
- Langue des échanges : principalement français.
- Méthode de travail : progression étape par étape, partage du
  code existant, vérification des commandes et des erreurs, puis
  correction et explication avant de passer à la suite.
2. Objectif du travail
L'objectif était de faire évoluer l'application Flutter de gestion d'une
file d'attente afin qu'elle puisse fonctionner même sans connexion
Internet, enregistrer les clients sur l'appareil, récupérer leur
position géographique lorsque cela est autorisé et synchroniser les
données avec Supabase lorsque le réseau est disponible.

Le travail devait notamment permettre de :
- conserver les clients localement avec SQLite ;
- continuer à utiliser l'application en mode hors ligne ;
- enregistrer la latitude et la longitude du client lorsque la
  géolocalisation est disponible ;
- synchroniser les clients en attente avec Supabase ;
- recevoir les changements distants grâce à Supabase Realtime ;
- tester les services et l'affichage avec des tests automatisés ;
- exécuter l'application sur un émulateur Android.
3. Démarche de travail suivie
Étape 1 --- Examiner le projet Flutter existant
Le travail a commencé par l'examen du projet waiting_room_app et de
son code existant, notamment le gestionnaire de file d'attente
QueueProvider.

L'objectif était de conserver la structure de l'application et de faire
évoluer progressivement ses fonctionnalités, sans recommencer le projet
depuis zéro.

Le projet utilisait déjà Flutter, Provider et Supabase. La suite du TP a
consisté à ajouter le stockage local et la géolocalisation, puis à
adapter le provider pour coordonner ces services.
Étape 2 --- Vérifier et installer les dépendances
Le fichier pubspec.yaml a été adapté pour ajouter les packages
nécessaires au TP.

Les principales dépendances utilisées sont :
- provider pour partager l'état de la file d'attente ;
- flutter_dotenv pour charger les variables de configuration ;
- supabase_flutter pour communiquer avec Supabase ;
- sqflite pour utiliser SQLite sur l'appareil ;
- path et path_provider pour gérer les chemins de stockage ;
- geolocator pour récupérer la position géographique ;
- uuid pour générer des identifiants uniques.
Pour les tests, les packages suivants ont également été utilisés :
- sqflite_common_ffi pour utiliser SQLite dans les tests exécutés
  sur ordinateur ;
- mockito pour simuler des services ;
- build_runner pour générer les classes mock.
Les dépendances ont été installées avec :
flutter pub get
Cette commande récupère les packages déclarés dans pubspec.yaml.
Étape 3 --- Créer le service de stockage local SQLite
Un nouveau fichier lib/local_queue_service.dart a été créé pour
séparer la gestion de la base de données du reste de l'application.

Une table locale appelée local_clients a été utilisée pour conserver
les informations des clients.

Les champs principaux sont :
- id : identifiant unique du client ;
- name : nom du client ;
- lat : latitude GPS, si disponible ;
- lng : longitude GPS, si disponible ;
- created_at : date et heure de création ;
- is_synced : indique si le client a déjà été synchronisé avec
  Supabase.
Le service permet notamment d'initialiser la base, d'insérer un client,
de récupérer les clients, de récupérer les clients non synchronisés, de
marquer un client comme synchronisé et de supprimer un client.

Un mode de base de données en mémoire a également été prévu pour isoler
les tests et éviter de modifier les données persistantes de
l'application.
Étape 4 --- Adapter QueueProvider au fonctionnement Offline-First
Le fichier lib/queue_provider.dart a été adapté pour coordonner
SQLite, Supabase et le service de géolocalisation.

Le provider conserve la liste des clients et expose les opérations
nécessaires à l'interface.

Lors de l'ajout d'un client, le fonctionnement prévu est le suivant :
1. Nettoyer le nom saisi avec trim() afin d'éliminer les espaces
   inutiles.
2. Demander au service de géolocalisation de récupérer la position
   courante.
3. Générer un identifiant unique avec Uuid.
4. Créer les informations du client, notamment son nom, ses coordonnées
   et sa date de création.
5. Enregistrer le client dans SQLite avec is_synced = 0.
6. Actualiser la liste affichée dans l'application.
7. Lancer une tentative de synchronisation avec Supabase en
   arrière-plan.
Si la connexion Internet est indisponible, le client reste enregistré
localement et peut être synchronisé ultérieurement.

Le provider contient également les méthodes de chargement des données
locales et distantes, de suppression, de passage au client suivant et
d'écoute des changements Realtime.
Étape 5 --- Ajouter le service de géolocalisation
Un fichier lib/geolocation_service.dart a été créé pour isoler la
logique GPS.

Le service utilise le package geolocator et effectue les vérifications
suivantes :
1. Vérifier si le service de localisation de l'appareil est activé.
2. Vérifier l'autorisation de localisation.
3. Demander la permission lorsque cela est nécessaire.
4. Ne pas récupérer la position si l'autorisation est refusée ou
   refusée définitivement.
5. Récupérer la position courante lorsque le service et l'autorisation
   sont disponibles.
6. Retourner une valeur null en cas d'indisponibilité ou d'erreur.
Cette organisation permet de ne pas mélanger le code GPS avec la logique
de gestion de la file d'attente.
Étape 6 --- Configurer les permissions Android
Pour permettre à l'application d'accéder à la localisation sur Android,
les permissions suivantes ont été ajoutées dans
android/app/src/main/AndroidManifest.xml, à l'intérieur de
<manifest> et avant <application> :
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
La permission précise permet de demander une localisation plus précise,
tandis que la permission approximative permet un accès moins précis.

L'application demande également l'autorisation à l'utilisateur pendant
son exécution. Après une modification du manifeste, un redémarrage ou
une reconstruction de l'application est nécessaire ; le hot reload seul
ne suffit pas toujours.
Étape 7 --- Adapter l'interface Flutter
Le fichier lib/main.dart contient l'écran principal
WaitingRoomScreen.

L'interface permet :
- de saisir le nom d'un client ;
- d'ajouter le client avec le bouton Add ;
- d'afficher le nombre de clients dans la file ;
- de consulter les clients enregistrés ;
- d'afficher les coordonnées GPS lorsqu'elles sont disponibles ;
- d'afficher Location not captured lorsque la position n'a pas été
  récupérée ;
- de supprimer un client ;
- de passer au client suivant avec le bouton correspondant.
L'interface observe le QueueProvider avec Provider afin de se mettre à
jour lorsque la liste des clients change.
Étape 8 --- Préparer la synchronisation avec Supabase
Le provider utilise la table distante clients de Supabase.

La logique de synchronisation comprend les opérations suivantes :
- récupérer les clients existants depuis Supabase au démarrage ;
- enregistrer localement les clients récupérés ;
- rechercher les clients locaux dont is_synced vaut 0 ;
- envoyer ces clients vers Supabase ;
- marquer localement un client comme synchronisé après un envoi réussi
  ;
- écouter les changements de la table avec Supabase Realtime.
En cas d'échec de synchronisation, les données locales restent
conservées. Cela permet de ne pas perdre les clients ajoutés lorsque le
réseau est indisponible.
Étape 9 --- Tester le service SQLite
Un fichier test/local_queue_service_test.dart a été utilisé pour
vérifier les principales opérations du service SQLite.

Les tests vérifient notamment l'insertion et la récupération des clients
ainsi que les opérations liées à leur état de synchronisation.

Une difficulté rencontrée concernait l'utilisation de SQLite dans les
tests exécutés sur ordinateur. L'erreur indiquait :
Bad state: databaseFactory not initialized
Pour utiliser sqflite_common_ffi, il faut initialiser le moteur FFI
avant l'utilisation de openDatabase() :
sqfliteFfiInit();
databaseFactory = databaseFactoryFfi;
Après cette initialisation, les tests peuvent utiliser une base SQLite
adaptée à l'environnement de test.
Étape 10 --- Tester la géolocalisation avec Mockito
Un fichier test/queue_provider_geolocation_test.dart a été préparé
pour vérifier que les coordonnées GPS sont bien enregistrées avec un
client.

Le principe du test est le suivant :
1. Créer un mock de GeolocationService.
2. Préparer une position fictive avec une latitude et une longitude
   connues.
3. Configurer Mockito pour que getCurrentPosition() retourne cette
   position.
4. Injecter le service simulé dans QueueProvider.
5. Ajouter un client.
6. Vérifier que le client est enregistré avec le nom et les coordonnées
   attendues.
La génération des mocks se fait avec :
dart run build_runner build --delete-conflicting-outputs
Cette commande génère le fichier de mocks utilisé par le test.

Le test est exécuté avec :
flutter test test/queue_provider_geolocation_test.dart
Une erreur databaseFactory not initialized a été rencontrée pendant
cette étape. Elle provenait de l'initialisation manquante de SQLite FFI
dans le test, et non du calcul des coordonnées GPS. L'initialisation de
sqflite_common_ffi doit donc être effectuée avant l'accès à la base.
Étape 11 --- Tester l'affichage avec un Widget Test
Un test de widget a été préparé dans
test/queue_provider_geolocation_widget_test.dart.

Son objectif est de vérifier que l'interface affiche correctement un
client et ses coordonnées.

Le test utilise des données connues, puis vérifie la présence du nom et
du texte correspondant à la position dans l'interface.

Exemples de vérifications :
expect(find.text('Sam'), findsOneWidget);
expect(find.textContaining('51.5074'), findsOneWidget);
Le test de widget permet ainsi de vérifier l'affichage sans dépendre
d'une vraie position GPS.
Étape 12 --- Vérifier le projet avec Flutter
Plusieurs commandes ont été utilisées pour contrôler le projet :
dart format lib test
flutter analyze
flutter test
- dart format met en forme les fichiers Dart.
- flutter analyze analyse le code et signale les erreurs
  potentielles, avertissements et problèmes de style.
- flutter test exécute les tests automatisés.
Pendant l'analyse, quelques remarques ont été relevées : utilisation de
l'ancien paramètre anonKey, variables locales inutilisées et conseils
de style dans le provider et les tests. Ces messages ont permis
d'identifier les parties du code à nettoyer.
Étape 13 --- Exécuter l'application sur l'émulateur Android
Le projet final a été exécuté sur un émulateur Android.

La procédure utilisée est :
1. Démarrer l'émulateur Android.
2. Vérifier qu'il est détecté par Flutter :
flutter devices
3. Depuis le terminal intégré d'Antigravity, se placer dans le dossier
   du projet.
4. Lancer l'application :
flutter run
Si plusieurs appareils sont détectés, on peut préciser l'identifiant de
l'émulateur :
flutter run -d ID_DE_L_EMULATEUR
L'application permet alors de tester l'ajout des clients, l'affichage de
la file, les coordonnées GPS et le comportement lorsque la localisation
n'est pas disponible.
Étape 14 --- Préparer la remise du TP
Avant la remise, il faut conserver les fichiers sources, les tests,
pubspec.yaml et pubspec.lock.

Le vrai fichier .env, qui contient les informations de connexion
Supabase, ne doit pas être publié. Il est préférable de fournir un
fichier .env.example sans valeurs secrètes.

Les commandes Git peuvent être utilisées pour vérifier et enregistrer
les modifications :
git status
git add .
git commit -m "Complete offline-first queue with geolocation"
git push
4. Questions et demandes formulées pendant l'accompagnement
Les demandes principales formulées pendant le travail étaient les
suivantes :
- Accompagner la réalisation du TP Flutter étape par étape, en
  français.
- Adapter les explications et les manipulations à Antigravity, utilisé
  comme environnement de développement.
- Examiner le code existant de QueueProvider avant de proposer des
  modifications.
- Ajouter la géolocalisation à l'application et expliquer les
  permissions Android.
- Vérifier le contenu de AndroidManifest.xml et confirmer
  l'emplacement des permissions.
- Expliquer pourquoi l'ajout d'un client peut prendre quelques
  secondes lorsque l'application demande la position GPS.
- Continuer le TP après validation de la partie géolocalisation.
- Aider à préparer les tests de géolocalisation avec Mockito.
- Expliquer et corriger l'erreur databaseFactory not initialized
  rencontrée pendant les tests.
- Examiner le code de main.dart et les remarques de
  flutter analyze.
- Continuer les étapes du TP en regroupant davantage d'étapes lorsque
  cela était possible.
- Préparer une documentation récapitulative à déposer avec le projet.
L'accompagnement a été réalisé à partir du projet existant et des
extraits de code et résultats de commandes partagés pendant les
échanges.
5. Concepts appris ou mobilisés
- Flutter et Dart : développement de l'application mobile et
  organisation du code.
- Provider / ChangeNotifier : partage de l'état de la file
  d'attente et notification des changements à l'interface.
- SQLite / sqflite : stockage persistant des clients directement
  sur l'appareil.
- Offline-First : conception permettant de continuer à utiliser
  l'application sans connexion Internet.
- Supabase : base de données distante utilisée pour partager les
  clients.
- Supabase Realtime : réception des changements distants afin de
  maintenir les données à jour.
- Geolocator : vérification du service GPS, gestion des
  permissions et récupération de la position.
- Permissions Android : déclaration dans le manifeste et demande
  d'autorisation pendant l'exécution.
- Latitude et longitude : coordonnées géographiques utilisées pour
  représenter la position d'un client.
- UUID : génération d'identifiants uniques pour les clients.
- Injection de dépendances : possibilité de fournir un service GPS
  ou une base de données depuis l'extérieur du provider.
- Mockito et mocks : simulation d'un service réel pour rendre les
  tests indépendants du GPS.
- Unit Test : vérification d'une logique isolée, comme
  l'enregistrement d'un client et de ses coordonnées.
- Widget Test : vérification de l'affichage des informations dans
  l'interface Flutter.
- sqflite_common_ffi : utilisation de SQLite dans les tests
  exécutés sur l'environnement de développement.
- Programmation asynchrone : utilisation de Future, async,
  await et unawaited() pour les opérations GPS, base de données et
  réseau.
- Build Runner : génération automatique des classes mock à partir
  des annotations.
- Débogage progressif : lecture des messages d'erreur,
  identification de leur origine et correction avant de continuer.
6. Difficultés et précautions
- Délai de récupération GPS : l'ajout d'un client peut prendre un
  peu de temps, car l'application attend la réponse du service de
  localisation. Il faut attendre la fin de l'opération avant de
  conclure que l'ajout a échoué.
- Permission de localisation : les permissions doivent être
  déclarées dans AndroidManifest.xml, puis autorisées par
  l'utilisateur pendant l'exécution.
- Position indisponible : si le GPS est désactivé ou si
  l'autorisation est refusée, les coordonnées peuvent être null.
  L'application doit pouvoir afficher Location not captured.
- Erreur SQLite dans les tests : databaseFactory not initialized
  signifie que le moteur SQLite FFI n'a pas été initialisé avant
  l'appel à openDatabase().
- Tests indépendants : il faut utiliser une base temporaire ou en
  mémoire et fermer les ressources après les tests.
- Dépendances injectées : les services GPS, SQLite et Supabase
  doivent pouvoir être remplacés ou isolés dans les tests.
- Synchronisation réseau : une erreur Supabase ne doit pas
  entraîner la perte du client enregistré localement.
- Configuration Supabase : les noms des colonnes dans la table
  distante doivent correspondre aux champs utilisés dans le code.
- Fichier .env : les clés et informations sensibles ne doivent
  pas être déposées dans un dépôt public.
- Analyse statique : les messages de flutter analyze doivent
  être examinés. Les avertissements de style ne sont pas tous des
  erreurs bloquantes.
- Émulateur Android : pour tester la géolocalisation, il faut
  autoriser l'application et définir une position simulée dans les
  contrôles de l'émulateur.
7. Bilan
Le TP5 a permis de faire évoluer l'application Flutter
waiting_room_app vers une architecture Offline-First intégrant le
stockage local SQLite, la géolocalisation et la synchronisation avec
Supabase.

Le travail a été réalisé progressivement : examen du projet existant,
installation des dépendances, création du service SQLite, adaptation de
QueueProvider, ajout du service GPS, configuration des permissions
Android, adaptation de l'interface, préparation des tests et exécution
sur un émulateur Android.

Les tests ont également permis de découvrir l'importance de l'isolation
des dépendances et de l'initialisation de SQLite FFI dans un
environnement de test.

L'application finale est exécutée sur un émulateur Android et permet de
gérer les clients de la file d'attente avec leurs coordonnées GPS
lorsque la localisation est disponible.
8. Transparence sur l'utilisation de l'IA
ChatGPT (GPT-6) a été utilisé comme assistant pédagogique tout au long
du TP5 pour expliquer les notions, examiner le code partagé, proposer
des modifications adaptées au projet existant, aider à interpréter les
erreurs et guider les tests.

Le développement et les vérifications ont été effectués progressivement
par l'étudiante dans son environnement Flutter avec Antigravity et un
émulateur Android.
