# CLAUDE.md — OneToOne

App macOS **SwiftUI + SwiftData** (manager d'architectes : suivi projets, entretiens 1:1,
STT/diarisation on-device via MLX, services IA). Voir [`docs/architecture.md`](docs/architecture.md)
pour l'architecture complète et [`docs/cleanup-report.md`](docs/cleanup-report.md) pour la revue.

## Build & Run

OneToOne est un **exécutable SwiftPM** (pas de projet Xcode).

```bash
swift build                       # build debug
swift test                        # tests (Swift Testing + XCTest)
Scripts/bump-and-build.sh dev     # build debug + package .app + install ~/Applications + lance
Scripts/bump-and-build.sh prod    # build release + install /Applications (sudo si nécessaire)
```

### ⚠️ MLX / Metal — `default.metallib` requis

**`swift build` ne compile PAS les shaders Metal de MLX** (`mlx-swift`). Sans `default.metallib`,
MLX crashe à la première opération GPU (STT, LLM local…).

- `Scripts/bump-and-build.sh` **embarque un `default.metallib` prébuilt** (récupéré depuis
  `Mickey.app`, même version MLX) dans le bundle `.app` — c'est ce qui rend l'app exécutable.
  Cf. `Scripts/prepare-mlx-metallib.sh`.
- Pour builder/tester une **dépendance MLX en standalone** (ex. `gemma-4-swift-mlx` / `Gemma4Swift`),
  il faut **`xcodebuild` (pas `swift build`)** car lui compile les shaders Metal :

```bash
# Build CLI (Release)
xcodebuild -scheme gemma4-cli -configuration Release \
  -destination "platform=macOS" -derivedDataPath .build/xcode \
  -skipMacroValidation build

# Binaire
.build/xcode/Build/Products/Release/gemma4-cli

# Tests
xcodebuild -scheme Gemma4Swift -destination "platform=macOS" \
  -derivedDataPath .build/xcode -skipMacroValidation test
```

> `gemma-4-swift-mlx` (VincentGourbin) est un projet **fonctionnel** confirmé. Référence :
> https://github.com/VincentGourbin/gemma-4-swift-mlx

## Endpoints IA et compatibilité historique

- Les nouvelles installations proposent **LM Studio** (`.lmStudio`), sans modèle
  présélectionné ; **OpenRouter** (`.openRouter`) et **Ollama** (`.ollama`) sont aussi
  des endpoints principaux, avec catalogue et transport communs.
- `Services/AI/` contient les profils, le Trousseau et le transport compatible OpenAI.
  `AIClient` fige les réglages avant le réseau ; `Views/Settings/AISettingsView.swift`
  gère le brouillon, le catalogue et le test indépendant de l'enregistrement.
- Les anciens stores gardent leur fournisseur, sauf Direct qui migre vers LM Studio.
  Ne pas changer le défaut persisté
  `providerRaw` (`.direct`) sans examiner la migration ; l'initialiseur des nouveaux
  objets choisit `.lmStudio`.
- Le classement des mails suit le même client ; un endpoint hors boucle locale exige
  `allowRemoteMailClassification`. Les backups n'exportent ni clés ni références.
- Ne pas utiliser `AsyncBytes.lines` pour le nouveau SSE : cette API omet les lignes
  vides, qui délimitent les événements. Tests : `Tests/AIEndpointTests.swift`.
- Niveau de raisonnement par profil (`AIEndpointProfile.reasoning`) : « défaut » ne
  change rien à la requête. LM Studio **ignore** les paramètres de raisonnement de
  l'API (vérifié 0.4.23) : consigne système du template Qwen, ou préremplissage
  `</think>` pour désactiver, réservé aux modèles Qwen. Ollama lit `reasoning_effort`,
  OpenRouter `reasoning.effort`. Limite de sortie par défaut 24 576 ; l'ancienne valeur
  8 192 d'un profil sans clé `reasoning` est relevée une fois au décodage.
  ADR : `docs/adr/2026-09-05-raisonnement-configurable.md`.
- Utiliser `EditableTextField` pour les champs IA, y compris `isSecure: true` pour
  les clés. Le coordinateur doit renouveler son binding au changement de profil.
  Le catalogue OpenRouter est public ; la clé reste requise pour la génération.

### Inférence locale conservée

Le moteur Direct et Gemma4Swift sont retirés. Les anciens profils Direct migrent vers
LM Studio sans modèle choisi. Les champs persistés restent lisibles ; aucun poids du
cache HuggingFace partagé n’est supprimé. MLXLLM reste une dépendance transitive de
la transcription ; MLXEmbedders et les composants audio restent nécessaires.

- **Embeddings** : `EmbeddingService` route vers **MLXEmbedders** in-process par défaut
  (`intfloat/multilingual-e5-base`, préfixes `query:`/`passage:`) ; Ollama reste
  disponible en legacy (`onetoone_embedding_backend` = `ollama`).
  ⚠️ **nomic-embed-text-v1.5 est inchargeable via MLXEmbedders** (bug upstream
  NomicBert : positions absolues exigées alors que le checkpoint est rotary →
  « Key embeddings.position_embeddings… ») ; `BAAI/bge-m3` ne publie pas de
  safetensors (seulement `pytorch_model.bin`, illisible par `loadWeights`).

### Cache HuggingFace
Les modèles sont chargés depuis `~/.cache/huggingface/hub` (téléchargés au 1er usage si absents).
Si « Error reading 'config.json' » : le snapshot pointé par `refs/main` doit contenir **à la fois**
`config.json` + l'index + le tokenizer **et** les `*.safetensors` (un téléchargement partiel peut
éclater métadonnées et poids sur deux snapshots).

## Éditeur

On s'inspire d'[AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) pour l'éditeur : commandes `/`,
paragraphes déplaçables, ajout de blocs. **Aucun code d'AppFlowy n'est repris** (Dart/Flutter et
React/Slate, sous AGPL-3.0) — seules la conception et les bibliothèques MIT qu'il utilise le sont.

Le module vit dans `OneToOne/Markdown/` : TextKit 1, **le markdown reste la source de vérité**
(pas de modèle de blocs). Voir `STATUS.md` pour l'état et les défauts connus.

## Écran de réunion (refonte 2026-09)

Spec `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` (branche
`docs/refonte-reunion-programme`, jamais fusionnée dans la pile), plan directeur
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` (décisions **D0–D11** au §4),
bilan `docs/adr/2026-09-08-refonte-ecran-reunion-bilan.md`, comptes rendus de session
`docs/superpowers/specs/refonte-2026-09/journal-des-lots.md`.

**Structure.** Trois espaces (`Réunion`, `Rapport`, `Ressources`) × trois modes (`Préparer`,
`En séance`, `Relire`), routés par la fonction pure `Services/Meeting/MeetingSpaceRouting.swift`.
Les vues vivent sous `Views/Meeting/` : `Spaces/**` (bandeau d'indicateurs, notes ↔
transcription, rail d'actions de 330 px, poste de pilotage), `Session/**` (séance plein écran),
`Resources/**` (tiroir de 396 px), `Capture/**`, `OneOnOne/**` (deux rôles), `Workshop/**`
(planches Excalidraw derrière `workshopEnabled`), plus `Views/Project/ProjectCardPanel.swift`
(fiche de 430 px). Voir `docs/architecture.md` §8.

**Règles.**
- **Rien ne s'ajoute dans `MeetingView.swift`** — on en retire. C'est un routeur.
- Aucune couleur hors `One2OneToken`, aucune fonte hors `Font.plexSans` / `.plexMono` ou leur
  pendant `NSFont` — un `NSViewRepresentable` ignore le `.font()` de l'environnement SwiftUI
  (c'est ce qui a fait sortir le titre de réunion en fonte système pendant quatre lots).
- L'état d'écran est dans `MeetingScreenModel` (`@Observable`), jamais en `@Binding`
  traversant plus d'un niveau.
- Toute règle métier est une **fonction pure testée avant sa vue** : `MeetingSpaceRouting`,
  `MeetingKPIBuilder`, `MeetingKPI.Level.teinte`, `ReminderRules`, `CommitmentsRailModel`…
- Les raccourcis clavier sont déclarés **une fois**, dans `Views/Menus/AppShortcut.swift` ;
  `Tests/AppShortcutsTests.swift` refuse un second déclarant non nommé. Depuis le 2026-09-09,
  `⌘K` ouvre la **palette** et l'assistant de réunion est en `⌘⇧K`
  (`docs/adr/2026-09-09-palette-commande-k.md`) : la table n'est plus propre à la réunion.
- Les semis de recette sont des extensions de `RefonteDemoSeed`, **idempotentes** ; la table
  des écrans photographiables est `Services/Debug/RecetteScreen.swift`.

**Protocole de recette visuelle, et ses sept pièges.**

```bash
swift build -c release
Scripts/recette-app.sh /tmp/recette         # refuse un binaire périmé (--force pour outrepasser)
Scripts/recette-run.sh --app /tmp/recette/OneToOne.app --screen 1a
```

1. **Isolation du store** : `HOME` **ne suffit pas** — `NSHomeDirectory()` l'ignore pour une
   application en bundle. C'est `CFFIXED_USER_HOME` qui compte. `recette-run.sh` pose les deux
   et **tue le processus** si le store n'apparaît pas dans le home jetable ; un semis dans le
   store de production s'est déjà produit (2026-09-07).
2. **Ciblage par pid, jamais par nom** : redimensionner avec
   `AXUIElementCreateApplication(<mon pid>)`, capturer avec `screencapture -l <numéro de
   fenêtre>`. **Jamais AppleScript** — `first process whose unix id is …` résout mal le
   processus quand deux instances partagent le `CFBundleIdentifier`, et une fenêtre de
   production a été redimensionnée ainsi. Le bundle de recette porte pour cela un
   `CFBundleIdentifier` suffixé `.recette`.
3. **Verrou d'écran** : `ioreg -n Root -d1 -r | grep -q 'CGSSessionScreenIsLocked"=Yes'`
   — **sans espaces** autour du `=`. Verrouillé, toute capture est noire et le
   redimensionnement échoue en silence ; le script refuse.
4. **Teams** : le script refuse si une fenêtre `MSTeams` ou `zoom.us` porte un titre de
   réunion ou d'appel (`Scripts/window-titles.swift`, `CGWindowListCopyWindowInfo`).
5. **Binaire périmé** : l'erreur la plus coûteuse de la refonte — deux heures d'observations
   fausses sur un bundle construit depuis un binaire d'il y a trois lots. Le script compare
   le `md5` copié et l'horodatage des sources.
6. **Préférences et état de fenêtres non isolés** : `CFFIXED_USER_HOME` isole
   `NSHomeDirectory()`, **pas `cfprefsd`** — les réglages du bundle `.recette` restent dans le
   vrai `~/Library/Preferences/<bundle id>.plist`, partagé par tous les bundles de même
   identifiant. Le 2026-09-09, il portait un cadre de fenêtre principale à `x = 2048`, sur un
   écran débranché depuis : fenêtre hors de tout écran, jamais rendue, `onAppear` jamais parti,
   aucun semis — et la fenêtre d'un **autre** processus OneToOne, lancé sept heures plus tôt
   hors bundle, a été photographiée à sa place. Trois heures perdues. `recette-run.sh` lance
   donc avec `-ApplePersistenceIgnoreState YES` et, sous `--reset`, fait `defaults delete
   <bundle id>` + `killall cfprefsd` — **seulement** sur un identifiant suffixé `.recette`.
   Corollaire : `ps -Ao pid,lstart,command | grep -i onetoone` avant toute capture ; une
   fenêtre OneToOne n'est pas forcément la sienne.
7. **Lire le store de recette sans son journal WAL** rend zéro partout : les écritures
   récentes vivent dans `OneToOne.store-wal`. Copier les **trois** fichiers (`.store`, `-wal`,
   `-shm`) avant tout `sqlite3`. Une mesure a conclu « l'application ne sème rien » sur un
   store qui portait soixante-seize projets. Le garde-fou de `recette-run.sh` compte désormais
   les gabarits intégrés ainsi : l'existence du fichier de store ne prouve que son
   emplacement, pas que l'interface a été rendue.

## Règles de travail

1. Lire `STATUS.md` avant de commencer.
2. Une PR = une intention. Si le périmètre dérive, s'arrêter et me demander.
3. `swift test` avant de proposer la PR. (Le `--skip CalendarImportEventTests`
   historique n'est plus nécessaire depuis que `MeetingNotificationService`
   n'instancie `UNUserNotificationCenter` que dans un bundle `.app`.)
4. Mettre à jour `STATUS.md` en fin de session : état, prochaine action, date.
5. Pas de dépendance nouvelle sans justification dans la PR.
6. En cas de doute sur un choix structurant : proposer, ne pas décider.

## Conventions

- Branche par tâche, PR obligatoire, pas de commit sur `master` (branche principale du dépôt).
- Commits conventionnels.
- Décision structurante → ADR dans `docs/adr/`.
- Commentaires & libellés UI en **français** ; symboles/code en anglais.
- Énums persistées SwiftData stockées en `…Raw: String` + wrapper calculé (contournement bug SwiftData).
- Services : `enum` namespace (fonctions statiques pures) ou `class` singleton `@MainActor` `.shared`.
- Schéma SwiftData versionné dans `Models/SchemaVersions.swift` (lightweight migration).
