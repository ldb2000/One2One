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
