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

## Provider IA « Directe » (LLM local in-process)

- `Services/DirectLLMClient.swift` charge un modèle MLX via **mlx-swift-lm** (`loadModelContainer`
  + `ChatSession`) et génère **in-process, sans réseau** (≠ Ollama). Défaut = `.direct` (`AppSettings`).
- Modèle par défaut : `mlx-community/gemma-4-26b-a4b-it-8bit` (réglable : `AppSettings.directModelRepo`
  / Réglages → IA).
- **Gemma 4 (26b-a4b, 31b) = MoE** : le `mlx-swift-lm` officiel ne gère que le Gemma 4 **dense**
  → erreur « Unhandled keys [experts, …] ». On dépend donc de **`Gemma4Swift`** (`gemma-4-swift-mlx`),
  qui enregistre une implémentation **MoE** des types `gemma4`/`gemma4_text` dans `LLMTypeRegistry.shared`
  via `Gemma4Registration.register()` (appelé par `DirectLLMClient`). `mlx-swift-lm` est sur `branch: main`
  (requis par Gemma4Swift + fournit `LLMTypeRegistry`).
- Modèles **denses** (Qwen3.5, Gemma 3…) fonctionnent sans Gemma4Swift.
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
