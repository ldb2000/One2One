# Menu « / » — commandes de bloc à la frappe

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Taper `/` ouvre un menu filtrable qui convertit la ligne courante en titre, liste, citation ou séparateur — avec des puces et cases à cocher réellement dessinées.

**Architecture:** Un `SlashController` détecte le `/` dans `Coordinator.textDidChange`, affiche un `NSPanel` non-activant positionné sous le curseur, capte les touches via `textView(_:doCommandBy:)`, et applique la commande choisie par `MarkdownBlockCommands`. Le catalogue est une structure pure, testable sans interface.

**Tech Stack:** Swift 6, AppKit (`NSTextView`, `NSPanel`, `NSTextInputClient`, TextKit 1), SwiftUI pour le contenu du panneau, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-03-editeur-slash-blocs-design.md`, section « Le menu `/` ». Les entrées **IA sont hors périmètre** de ce plan (décision utilisateur du 2026-08-04). Mermaid et draw.io restent au plan suivant.

---

## Deux prérequis, traités en tâches 1 et 2

L'enquête sur le code (`docs/superpowers/specs/2026-08-04-frontieres-de-bloc-constat.md`) a établi deux défauts qui rendraient le menu contre-productif.

**Les frontières de bloc se perdent.** `MarkdownParser` n'émet qu'un `\n` entre blocs, `MarkdownSerializer` les rejoint par un seul `\n`. Certaines paires se relisent alors différemment en CommonMark. Le menu crée précisément ces paires : convertir une ligne en citation produit citation→paragraphe, qui absorbe le paragraphe suivant.

**Les marqueurs de liste ne sont pas dessinés.** `StyleRenderer` traduit `.mdListInfo` en simple indentation (`StyleRenderer.swift:84-90`). Une entrée « Case à cocher » donnerait un item invisible, dont le code de bascule (`EditorTextView.swift:127-157`) est mort par-dessus le marché : il compare les 6 premiers caractères à `"- [ ] "` dans un storage qui contient `"tâche"`.

## File map

| Chemin | Responsabilité | Action |
|---|---|---|
| `OneToOne/Markdown/Markdown/MarkdownSerializer.swift` | frontières de bloc | modifier |
| `OneToOne/Markdown/Core/StyleRenderer.swift` | dessin des marqueurs de liste | modifier |
| `OneToOne/Markdown/Core/EditorTextView.swift` | clic sur case à cocher | modifier |
| `OneToOne/Markdown/Slash/SlashCommand.swift` | modèle d'une entrée | créer |
| `OneToOne/Markdown/Slash/SlashCatalog.swift` | catalogue, filtrage, groupement | créer |
| `OneToOne/Markdown/Slash/SlashPanel.swift` | `NSPanel` + liste SwiftUI | créer |
| `OneToOne/Markdown/Slash/SlashController.swift` | détection, navigation, application | créer |
| `OneToOne/Markdown/Core/EditorRepresentable.swift` | hôte du contrôleur | modifier |
| `Tests/MarkdownRoundTripTests.swift` | frontières de bloc | modifier |
| `Tests/SlashCatalogTests.swift` | filtrage et groupement | créer |
| `Tests/SlashControllerTests.swift` | détection et application | créer |

---

### Task 1 : frontières de bloc à la sérialisation

**Files:**
- Modify: `OneToOne/Markdown/Markdown/MarkdownSerializer.swift`
- Test: `Tests/MarkdownRoundTripTests.swift`

- [ ] **Step 1 : établir la liste réelle des paires à risque**

Le constat en liste cinq, mais **elles n'ont pas été revérifiées** et proviennent d'un sous-agent dont le comportement s'est révélé peu fiable. Ne les prends pas pour argent comptant.

Écris un test temporaire qui, pour chaque paire ordonnée de types de blocs (paragraphe, h1, h2, citation, séparateur, bloc de code, item de liste), construit le markdown des deux blocs séparés par un **seul** `\n`, le parse, et vérifie si les deux blocs survivent distinctement. Rapporte la matrice complète.

Les cinq paires annoncées à risque :

| Précédent | Suivant | Effet annoncé |
|---|---|---|
| paragraphe | paragraphe | fusionnent |
| paragraphe | séparateur `---` | devient un titre H2 Setext |
| citation | paragraphe | absorbé dans la citation |
| citation | citation | fusionnent |
| item de liste | paragraphe | absorbé dans l'item |

Confirme, infirme, complète. C'est cette matrice mesurée qui pilote l'implémentation, pas le tableau ci-dessus.

- [ ] **Step 2 : écrire les fixtures d'aller-retour**

Pour chaque paire que ta matrice montre à risque, ajoute une fixture dans `Tests/MarkdownRoundTripTests.swift` avec la ligne vide, sous la forme qui doit survivre. Exemple pour paragraphe→paragraphe : `"Avant\n\nAprès"`.

Lance et constate l'échec. Rapporte les messages exacts.

- [ ] **Step 3 : contrainte à ne pas casser**

`Tests/MarkdownRoundTripTests.swift` contient déjà une fixture **qui passe** : `"texte avant\n```json\n{\n  \"a\": 1\n}\n```\ntexte après"` — un paragraphe collé à un bloc de code, sans ligne vide, dans les deux sens.

Une règle qui insérerait une ligne vide entre *toute* paire de blocs la casserait sans nécessité. Ta règle doit être dérivée de ta matrice, pas appliquée uniformément.

- [ ] **Step 4 : implémenter**

Dans `MarkdownSerializer.serialize`, insère une ligne vide entre deux lignes de sortie consécutives selon la règle que ta matrice impose. La règle doit se calculer à partir des attributs déjà présents (`.mdBlockType`, `.mdListInfo`) — n'introduis pas de nouvel attribut, ce serait un état de plus à désynchroniser.

Attention : deux items d'une **même** liste ne doivent pas être séparés par une ligne vide, le comportement actuel étant correct.

- [ ] **Step 5 : vérifier**

```bash
swift test --filter Markdown
swift test --skip CalendarImportEventTests
```

Toutes les fixtures existantes doivent continuer de passer.

- [ ] **Step 6 : vérification par mutation**

Neutralise ta règle, confirme que les nouvelles fixtures échouent. Neutralise l'exception « items de la même liste », confirme qu'une fixture de liste échoue. Restaure.

- [ ] **Step 7 : committer**

```bash
git commit -m "fix(markdown): préserver les frontières de bloc à la sérialisation"
```

---

### Task 2 : dessiner les marqueurs de liste

**Files:**
- Modify: `OneToOne/Markdown/Core/StyleRenderer.swift`
- Modify: `OneToOne/Markdown/Core/EditorTextView.swift`
- Test: `Tests/StyleRendererTests.swift`

- [ ] **Step 1 : choisir le mécanisme et le justifier**

Le storage ne contient **pas** les marqueurs (`"tâche"`, pas `"- [ ] tâche"`), et il ne doit pas les contenir — la sérialisation les régénère depuis `.mdListInfo`.

Deux voies. Étudie-les et choisis, en expliquant pourquoi :

1. `NSParagraphStyle` + `NSTextList`, mécanisme AppKit natif pour les listes.
2. Un `NSTextAttachment` en tête de ligne portant le marqueur dessiné, sur le modèle d'`ImageAttachmentFactory`.

La voie 2 a un précédent dans le code mais insère un caractère dans le storage, ce qui se répercuterait sur la sérialisation et sur les plages de `MarkdownBlockCommands` — vérifie avant de t'y engager.

**Si aucune des deux ne marche proprement en TextKit 1, arrête-toi et dis-le** plutôt que de forcer.

- [ ] **Step 2 : écrire les tests**

Dans `Tests/StyleRendererTests.swift` : une puce, un item numéroté, une case cochée et une décochée reçoivent bien un marqueur visible ; l'indentation existante est préservée ; la sérialisation reste inchangée (le marqueur ne fuit pas dans le markdown).

Ce dernier point est le plus important : la branche a corrigé quatre fois des variantes de « un artefact d'affichage se retrouve dans le fichier ».

- [ ] **Step 3 : implémenter le dessin**

- [ ] **Step 4 : réparer la bascule des cases à cocher**

`EditorTextView.mouseDown` (`:127-157`) teste `"- [ ] "` littéral dans `string` — mort, le storage ne contient pas ces caractères. Réécris-le pour lire `.mdListInfo` à la position cliquée, vérifier `kind == .task`, et basculer `checked` dans l'attribut.

Le clic doit être restreint à la zone du marqueur, comme aujourd'hui. `onTaskToggle` (`EditorRepresentable.swift:54-56`) existe déjà pour pousser le changement.

- [ ] **Step 5 : vérifier, muter, committer**

```bash
swift test --skip CalendarImportEventTests
Scripts/bump-and-build.sh dev
```

Le script modifie `Info.plist` — reverte avant de committer. Tu ne peux pas vérifier le rendu visuellement ; ne prétends pas l'avoir fait.

```bash
git commit -m "feat(markdown): dessiner les marqueurs de liste et réparer la bascule des cases"
```

---

### Task 3 : le catalogue

**Files:**
- Create: `OneToOne/Markdown/Slash/SlashCommand.swift`
- Create: `OneToOne/Markdown/Slash/SlashCatalog.swift`
- Test: `Tests/SlashCatalogTests.swift`

Logique pure, sans interface — c'est la partie la plus facilement testable, écris-la en premier.

- [ ] **Step 1 : écrire les tests**

Couvre : filtrage par texte (sur le libellé, les mots-clés et les alias, insensible à la casse et aux accents) ; groupement dans l'ordre déclaré ; groupes vides omis ; entrées filtrées par `MarkdownFeature` (un champ en `.basic` ne montre pas les titres).

- [ ] **Step 2 : le modèle**

`SlashCommand` porte : une clé stable, un libellé français, des mots-clés, un raccourci affiché à droite (`#`, `##`, `-`…), un groupe, l'action à appliquer, et le `MarkdownFeature` requis.

Structure reprise d'AppFlowy (`slash-menu-options.ts` : clé, libellé, mots-clés, alias, raccourci, groupe, filtrage contextuel). C'est de la conception, pas du code copié.

- [ ] **Step 3 : le catalogue**

| Groupe | Entrées |
|---|---|
| **Blocs de base** | Texte, Titre 1 `#`, Titre 2 `##`, Titre 3 `###`, Liste à puces `-`, Liste numérotée `1.`, Case à cocher `[]`, Citation `>`, Séparateur `---` |
| **Média** | Image (ouvre un sélecteur de fichier) |

**Hors périmètre de ce plan** : les entrées IA (décision utilisateur), mermaid, draw.io, le bloc de code, les mentions `@`, les tableaux.

Le séparateur et le bloc de code ne sont **pas** convertibles par `MarkdownBlockCommands` — sa signature les refuse depuis le commit `f20b979`, parce qu'ils détruisaient des données. Le séparateur doit donc être une **insertion** de nouvelle ligne, pas une conversion. Traite-le comme tel, ou retire-le du catalogue et dis-le.

- [ ] **Step 4 : vérifier, muter, committer**

---

### Task 4 : le panneau

**Files:**
- Create: `OneToOne/Markdown/Slash/SlashPanel.swift`

- [ ] **Step 1 : lire le précédent du projet**

`OneToOne/Views/OneToOneQuickPickerWindow.swift:9,18,23` construit déjà un `NSPanel` non-activant et flottant. Suis ce motif.

- [ ] **Step 2 : construire le panneau**

`NSPanel` sans bordure, `.nonactivatingPanel`, `level = .floating`, contenu SwiftUI hébergé par un `NSHostingView`. Le focus doit **rester dans le texte** — l'utilisateur continue de taper pendant que le menu filtre.

Groupes avec en-têtes, icône + libellé + raccourci à droite, surlignage de la sélection courante.

- [ ] **Step 3 : positionnement**

`textView.firstRect(forCharacterRange:actualRange:)` renvoie des coordonnées **écran** — vérifié sur cette pile TextKit 1 précise. Positionne le haut-gauche du panneau juste sous ce rectangle.

Clampe sur `window.screen?.visibleFrame` : si le panneau déborde en bas, bascule-le au-dessus du curseur.

- [ ] **Step 4 : vérifier et committer**

Le rendu ne se teste pas automatiquement ici. Vérifie que le build passe, et décris ce que tu n'as pas pu vérifier.

---

### Task 5 : le contrôleur

**Files:**
- Create: `OneToOne/Markdown/Slash/SlashController.swift`
- Test: `Tests/SlashControllerTests.swift`

C'est la tâche la plus délicate. Six pièges identifiés par l'enquête, tous à traiter.

- [ ] **Step 1 : détection**

Le `/` ouvre le menu s'il est en début de ligne ou précédé d'une espace. La détection s'insère dans `Coordinator.textDidChange`, à côté de `ShortcutDetector.apply`.

- [ ] **Step 2 : clavier**

`Coordinator` est déjà `NSTextViewDelegate` ; `textView(_:doCommandBy:)` est le point d'accroche. Aucun `keyDown`/`doCommandBy` n'existe encore dans le module.

| Touche | Effet |
|---|---|
| lettres | filtre en direct |
| ↑ ↓ | navigue |
| ⏎ / Tab | applique |
| Échap | ferme, conserve le `/` tapé |
| ⌫ avant le `/` | ferme |
| clic ailleurs | ferme |

- [ ] **Step 3 : suspendre la poussée vers le binding**

Le texte `/requête` transite par `textDidChange` → `serialize` → binding **débouncé à 0,3 s** (`MarkdownTextEditor.swift:14`). Une requête tapée lentement se persiste dans SwiftData puis disparaît.

Annule la tâche de debounce tant que le panneau est ouvert.

- [ ] **Step 4 : effacer la requête et appliquer**

`insertText("", replacementRange: queryRange)` — vérifié : le délégué est appelé, `pendingStyleRange` est positionné, l'annulation est enregistrée. Une mutation directe de `textStorage` ne déclenche rien.

Puis applique la commande via `MarkdownBlockCommands`, restyle la plage de ligne, et appelle `didChangeText()`.

- [ ] **Step 5 : ne pas déclencher de raccourci inline parasite**

`textDidChange` repasse par `ShortcutDetector.apply` avec le caractère précédant le curseur. Appliquer un bloc juste après un `*`, `_` ou `` ` `` peut déclencher un raccourci parasite. Vérifie, et neutralise si nécessaire.

- [ ] **Step 6 : le type de bloc se propage au Retour**

Vérifié : `"## Titre"` + ⏎ + `"corps"` donne `"## Titre\n## corps"` — `typingAttributes` hérite du bloc précédent, et rien n'override `insertNewline`.

Souhaitable pour une liste, indésirable pour un titre. Après application d'un titre par le menu, le Retour doit revenir au paragraphe. Traite ce cas et teste-le.

- [ ] **Step 7 : ne pas passer par `MarkdownEditorRegistry`**

Ce singleton (`EditableTextField.swift:225-242`) n'est pas isolé et ses clés sont fournies par l'appelant ; deux vues sur le même objet partagent l'identifiant. Le contrôleur doit obtenir son éditeur depuis le `Coordinator`, pas depuis ce registre.

- [ ] **Step 8 : tests**

Teste ce qui est testable sans interface : détection du `/` selon le contexte, extraction de la requête, application de la commande sur un storage, comportement du Retour après un titre. Le panneau lui-même n'est pas testable dans ce projet — dis-le franchement plutôt que d'inventer une couverture.

- [ ] **Step 9 : vérifier, muter, committer**

---

### Task 6 : branchement et vérification

**Files:**
- Modify: `OneToOne/Markdown/Core/EditorRepresentable.swift`

- [ ] **Step 1 : héberger le contrôleur**

`Coordinator` détient déjà `weak var textView` et `dismantleNSView` (`:67-70`) est le point de démontage existant, à côté du `unregister`. Ferme et libère le panneau là.

- [ ] **Step 2 : vérification complète**

```bash
swift test --skip CalendarImportEventTests
Scripts/bump-and-build.sh dev
```

Dans l'app : taper `/` dans les notes d'un entretien, filtrer, choisir un titre, vérifier que la ligne se convertit sans perdre son gras. Vérifier qu'Échap referme en conservant le `/`. Vérifier qu'une case à cocher apparaît et se coche au clic.

- [ ] **Step 3 : committer**

---

## Échecs préexistants — ne pas traiter ni masquer

- `MenuBarStatsTests.test_badge_twelve_compact`
- `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` (sensible à l'heure)
- crash `CalendarImportEventTests` (`bundleProxyForCurrentProcess is nil`), d'où le `--skip`
- `TranscriptEditServiceTests.test_delete_shiftsLaterSegmentsByRemovedDuration` (flaky)

## Règles de travail sur cette branche

- **Ne touche aucun fichier hors de ta tâche.** `K8s_Monitor_Prototype.html`, à la racine, n'appartient pas à ce chantier et ne doit jamais être supprimé ni modifié.
- L'état de l'arbre de travail est un **constat**, jamais un objectif — ne supprime rien pour « nettoyer ».
- N'amende aucun commit existant.
- N'écris aucun commentaire dont tu n'as pas vérifié le contenu. Sept ont été épinglés sur cette branche, dont deux venaient du plan lui-même.
- Un test vert ne prouve rien : après chaque implémentation, neutralise-la et vérifie qu'un test échoue.

## Ce que ce plan ne couvre pas

- **Entrées IA** du menu — décision utilisateur du 2026-08-04, à revoir plus tard.
- **Mermaid, draw.io** — plan suivant.
- **Tableaux GFM et blocs HTML** effacés par le parser : la pire perte connue, antérieure au chantier, chantier propre.
- **Titres markdown** (`![a](url "titre")`) perdus.
- **Marqueurs d'emphase doublés** autour d'un run imbriqué, et longueur d'`emitInline`.
- **Câblage des boutons de la barre d'outils** non testé (closures SwiftUI).
