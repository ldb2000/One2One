# Spécifications — Composant WYSIWYG Markdown pour OneToOne

| | |
|---|---|
| **Version** | 0.2 (draft) |
| **Auteur** | Lolo |
| **Date** | 22 mai 2026 |
| **Projet** | OneToOne (gestion de réunions, transcription, rapports IA) |
| **Statut** | Pré-validation — à confirmer avant plan d'implémentation |

---

## 1. Objectif

Fournir un **composant SwiftUI réutilisable** permettant d'éditer en WYSIWYG **tout champ texte markdown** de l'application OneToOne. Le composant accepte/produit du Markdown CommonMark et remplace l'éditeur plain-text actuel (`MarkdownEditorView`) tout en conservant la compatibilité avec le rendu lecture stylisé (`MeetingHighlightableTextView`).

Le composant doit s'adapter à des contextes très différents : titre court inline, zone de notes multi-lignes, éditeur plein écran pour un résumé de réunion. **Même API, configurations différentes.**

### 1.1 Inventaire des champs OneToOne v1

| Champ SwiftData | Mode visé | Formatages utiles | État actuel |
|---|---|---|---|
| `Meeting.title` | inline single-line | gras, italique | plain `TextField` |
| `Meeting.summary` | full editor | tous | `MeetingHighlightableTextView` (lecture stylée, édition plain) |
| `Meeting.liveNotes` | compact multi-line | tous sauf code-blocks | `MarkdownEditorView` (plain) |
| `Meeting.notes` (legacy) | compact multi-line | gras, italique, listes | plain `TextEditor` |
| `Meeting.prepNotes` | compact multi-line | tous + checkboxes interactives | `MarkdownEditorView` |
| `Collaborator.standingPrepNotes` | compact multi-line | tous + checkboxes | `MarkdownEditorView` |
| `Project.standingPrepNotes` | compact multi-line | tous + checkboxes | `MarkdownEditorView` |
| `ReportRevision.body` | full editor | tous | `MeetingHighlightableTextView` lecture seule |
| `Note.text` | compact multi-line | gras, italique, listes | plain `TextEditor` |
| `Project.notes`, `Collaborator.notes` | compact multi-line | gras, italique, listes | plain `TextEditor` |
| `Project.planningText` | compact multi-line | gras, italique, listes | plain `TextEditor` |
| `TranscriptSegment.text` annotations | inline multi-line | gras, italique, code | non éditable actuellement |

### 1.2 Périmètre de remplacement

- **Remplace** : `MarkdownEditorView` (édition) sur tous ses call-sites.
- **Réutilise / coexiste** : `MeetingHighlightableTextView` reste pour le rendu lecture-seule avec highlights manager (ses besoins de range-tagging sont spécifiques).
- **Optionnel** : la nouvelle API peut couvrir aussi le mode lecture-seule, auquel cas `MeetingHighlightableTextView` devient un wrapper léger autour du nouvel éditeur en `readOnly` + `highlightedRanges`.

---

## 2. Principes directeurs

1. **Un seul composant, plusieurs visages** : la même base technique sert tous les cas via configuration.
2. **API SwiftUI idiomatique** : binding `String`, modificateurs en chaîne, intégration naturelle dans `Form`, `List`, `VStack`.
3. **Drop-in replacement** : remplacer un `MarkdownEditorView` existant doit demander 1 ligne de modification.
4. **Markdown in / Markdown out** : le binding expose toujours du `String` Markdown. Pas de fuite d'`NSAttributedString` côté hôte.
5. **Configurable par instance** : chaque champ active/désactive granulairement les formatages.
6. **Aucune dépendance externe lourde** : pas de bibliothèque tierce sauf `swift-markdown` (Apple, déjà éprouvé) si nécessaire pour le parser.
7. **Co-existence** avec l'écosystème actuel : `MeetingHighlightableTextView` continue de fonctionner pendant la migration progressive.

---

## 3. Hypothèses de cadrage

| # | Hypothèse | À valider |
|---|---|---|
| H1 | Cible : **macOS 15+ uniquement** (OneToOne est mac-only, pas de roadmap iOS) | ✅ / modifier |
| H2 | Packaging : **module interne** dans le repo (`OneToOne/Markdown/`), pas de SPM externe en v1 | ✅ / modifier |
| H3 | Le composant ne gère pas la persistance SwiftData : il expose un `@Binding String`, SwiftData sync via `@Bindable` modèle | ✅ / modifier |
| H4 | Pas de tableaux ni d'images en v1 | ✅ / modifier |
| H5 | Markdown : **CommonMark strict** v1, extensions GFM (task lists pour les checkboxes) **dès v1** car déjà utilisées dans les prep notes | ✅ / modifier |
| H6 | Édition **purement WYSIWYG**, pas de mode "source" affiché | ✅ / modifier |
| H7 | Undo/redo natif via `NSTextStorage` / `NSUndoManager` | ✅ / modifier |
| H8 | Compatible avec le contexte multi-fenêtre de OneToOne (`WindowGroup` 1to1-meeting, prep-standalone) — pas de singleton/global | ✅ / modifier |
| H9 | TextKit 2 (macOS 14+ stable) | ✅ / modifier |
| H10 | Pas de SPM externe pour réduire la surface de dépendances ; package interne préféré tant que pas d'autre client identifié | ✅ / modifier |

---

## 4. API publique

### 4.1 Vues exposées

Trois variantes pour couvrir tous les modes, partageant le même cœur :

```swift
/// Champ single-line, remplace TextField. Pas de retour à la ligne.
public struct MarkdownField: View {
    public init(_ placeholder: String, text: Binding<String>)
}

/// Zone multi-line compacte sans toolbar. Remplace TextEditor /
/// MarkdownEditorView actuel.
public struct MarkdownTextEditor: View {
    public init(text: Binding<String>)
}

/// Éditeur complet avec toolbar. Pour résumés, notes longues, prep.
public struct MarkdownEditor: View {
    public init(text: Binding<String>)
}
```

### 4.2 Modificateurs de configuration

Style "modifier chain" SwiftUI :

```swift
MarkdownEditor(text: $meeting.summary)
    .markdownFeatures([.bold, .italic, .code, .link,
                       .heading(.h2), .heading(.h3),
                       .bulletList, .orderedList, .taskList,
                       .blockquote])
    .markdownPlaceholder("Résumé de la réunion…")
    .markdownToolbar(.pinned)              // .floating | .pinned | .hidden
    .markdownMaxListDepth(3)
    .markdownAutoFocus(true)
    .markdownDebounce(.milliseconds(300))
    .markdownOnChange { newMarkdown in /* debounced */ }
    .markdownReadOnly(false)
    .markdownHighlights([NSRange(...), ...])  // compat MeetingHighlightableTextView
```

### 4.3 Énumérations de configuration

```swift
public enum MarkdownFeature: Hashable {
    // Inline
    case bold, italic, inlineCode, link
    case strikethrough              // GFM v1
    // Blocs
    case heading(HeadingLevel)
    case bulletList, orderedList
    case taskList                   // GFM v1 — utilisé pour les checkboxes prep
    case blockquote, codeBlock, thematicBreak
}

public enum HeadingLevel: Int { case h1 = 1, h2, h3, h4, h5, h6 }

public enum MarkdownToolbarPlacement {
    case hidden, floating, pinned
}
```

### 4.4 Presets

Pour éviter à l'hôte de ré-énumérer les features à chaque usage :

```swift
public extension Set where Element == MarkdownFeature {
    /// Titres et tags
    static let inlineOnly: Set<MarkdownFeature> = [.bold, .italic, .inlineCode, .link]

    /// Notes courtes, descriptions
    static let basic: Set<MarkdownFeature> = inlineOnly.union([.bulletList, .orderedList])

    /// Prep notes (avec checkboxes interactives)
    static let prep: Set<MarkdownFeature> = basic.union([.taskList, .blockquote, .heading(.h2), .heading(.h3)])

    /// Résumés post-LLM, rapports
    static let full: Set<MarkdownFeature> = [/* tout */]
}
```

### 4.5 Usage typique OneToOne

```swift
// Titre de réunion
MarkdownField("Titre…", text: $meeting.title)
    .markdownFeatures(.inlineOnly)

// Notes live (pendant la réunion)
MarkdownTextEditor(text: $meeting.liveNotes)
    .markdownFeatures(.basic)
    .markdownPlaceholder("Notes live…")

// Préparation (checkboxes interactives)
MarkdownEditor(text: $meeting.prepNotes)
    .markdownFeatures(.prep)
    .markdownToolbar(.floating)
    .markdownPlaceholder("Points à aborder…")

// Résumé post-LLM
MarkdownEditor(text: $meeting.summary)
    .markdownFeatures(.full)
    .markdownToolbar(.pinned)
```

### 4.6 Comportement du binding

| Aspect | Comportement |
|---|---|
| Update interne (frappe) | Debounce 300 ms (configurable) avant push vers le binding |
| Update externe (LLM, sync) | Détection via comparaison `String`, re-parse, re-assignation de l'`NSAttributedString` interne |
| Préservation sélection sur update externe | Best-effort : matching position-based + fallback fin de texte |
| Update externe pendant édition | Évité côté OneToOne (LLM tourne hors-édition) ; en cas de conflit, la valeur externe gagne |

---

## 5. Architecture technique

### 5.1 Vue d'ensemble

```
┌─────────────────────────────────────────────────────────┐
│              OneToOne/Markdown (module interne)         │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Public API :                                      │ │
│  │  MarkdownField / MarkdownTextEditor / MarkdownEditor│ │
│  │  + modifiers                                       │ │
│  └────────────────────────────────────────────────────┘ │
│                          │                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │  NSViewRepresentable wrapper                       │ │
│  └────────────────────────────────────────────────────┘ │
│                          │                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │  EditorTextView (NSTextView sous-classé, TextKit2) │ │
│  │  + EditorTextStorage (NSTextStorage)               │ │
│  └────────────────────────────────────────────────────┘ │
│                          │                               │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Document Model (NSAttributedString + clés custom) │ │
│  └────────────────────────────────────────────────────┘ │
│                          │                               │
│  ┌──────────────────────┴─────────────────────────────┐ │
│  │  MarkdownParser  ←→  MarkdownSerializer            │ │
│  │  (swift-markdown)    (custom)                      │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          │
                          │  @Binding<String> markdown
                          ▼
                   Modèle SwiftData
                   (@Bindable Meeting / Project / Collaborator)
```

### 5.2 Stack technique

| Couche | Choix | Justification |
|---|---|---|
| Distribution | Module interne `OneToOne/Markdown/` | Pas d'autre client identifié, évite la friction SPM |
| UI publique | SwiftUI | Idiomatique pour OneToOne |
| Cœur édition | `NSTextView` sous-classé | Seule option viable WYSIWYG riche sur macOS |
| TextKit | TextKit 2 | macOS 15 = TK2 stable, futur-proof |
| Modèle | `NSAttributedString` avec clés custom typées | Compat directe avec `NSTextStorage`, range-API native |
| Parsing MD | `swift-markdown` (Apple, déjà disponible) | CommonMark, maintenu |
| Sérialisation | Visitor custom sur les runs `NSAttributedString` | swift-markdown ne sérialise pas depuis AS |
| Tests | XCTest + snapshots round-trip | Cohérent avec `Tests/` actuels |

### 5.3 Structure du module

```
OneToOne/Markdown/
├── Public/
│   ├── MarkdownField.swift
│   ├── MarkdownTextEditor.swift
│   ├── MarkdownEditor.swift
│   ├── MarkdownFeature.swift
│   ├── Modifiers.swift
│   └── Presets.swift
├── Core/
│   ├── EditorTextView.swift          (NSTextView sous-classé)
│   ├── EditorTextStorage.swift
│   ├── EditorRepresentable.swift     (NSViewRepresentable)
│   └── ShortcutDetector.swift        (auto-format à la frappe)
├── Model/
│   ├── MarkdownAttributeKeys.swift
│   ├── BlockType.swift
│   └── DocumentModel.swift
├── Markdown/
│   ├── MarkdownParser.swift
│   ├── MarkdownSerializer.swift
│   └── Escaping.swift
└── Toolbar/
    └── ToolbarView.swift
Tests/
└── MarkdownTests/
    ├── Fixtures/                     (.md + résultat NSAttributedString attendu)
    ├── ParserTests.swift
    ├── SerializerTests.swift
    ├── RoundTripTests.swift
    └── ConfigurationTests.swift
```

---

## 6. Périmètre fonctionnel

### 6.1 Formatages inline (v1)

| Élément | Raccourci | Markdown produit | Feature flag |
|---|---|---|---|
| Gras | ⌘B | `**texte**` | `.bold` |
| Italique | ⌘I | `*texte*` | `.italic` |
| Code inline | ⌘E | `` `texte` `` | `.inlineCode` |
| Lien | ⌘K | `[texte](url)` | `.link` |
| Barré | ⌘⇧X | `~~texte~~` | `.strikethrough` |

### 6.2 Blocs (v1)

| Élément | Raccourci / déclencheur | Markdown | Feature flag |
|---|---|---|---|
| Titre H1→H3 | ⌘⌥1/2/3 ou `# ` en début de ligne | `# `, `## `, `### ` | `.heading(.h1)` etc. |
| Liste à puces | ⌘⇧8 ou `- ` | `- item` | `.bulletList` |
| Liste numérotée | ⌘⇧7 ou `1. ` | `1. item` | `.orderedList` |
| **Checkbox** | `- [ ]` à la frappe ou clic toggle | `- [ ]` / `- [x]` | `.taskList` |
| Citation | ⌘⇧> ou `> ` | `> texte` | `.blockquote` |
| Bloc de code | ⌘⇧C ou ` ``` ` | ` ```lang\n…\n``` ` | `.codeBlock` |
| Séparateur | `---` | `---` | `.thematicBreak` |

### 6.3 Saisie "Markdown shortcuts" (auto-format)

Conversion à la frappe :

| Saisie | Résultat |
|---|---|
| `**bold** ` | **bold** |
| `*italic* ` | *italic* |
| `` `code` `` | `code` |
| `# ` (début de ligne) | H1 |
| `- ` ou `* ` | entrée dans une liste à puces |
| `- [ ] ` ou `- [x] ` | checkbox interactive |
| `> ` | blockquote |
| `[label](url)` | lien |

Si une feature n'est pas autorisée par la configuration, le shortcut Markdown correspondant est **désactivé** (texte tapé reste littéral).

### 6.4 Mode single-line (`MarkdownField`)

- `Enter` interdit (ou émet `onSubmit` comme `TextField`).
- Blocs automatiquement désactivés indépendamment de la configuration.
- Hauteur fixée à une ligne, scroll horizontal si dépassement.

### 6.5 Hors périmètre v1

| Feature | Justification |
|---|---|
| Tables | YAGNI — peu utilisé dans les notes OneToOne |
| Images | Complexité (gestion fichiers, upload, embed) sans usage immédiat |
| Footnotes / maths | Non-pertinent pour notes de réunion |
| Mode source raw | WYSIWYG only — l'utilisateur n'a pas besoin de voir le markdown brut |
| Collaboration temps réel | Mono-utilisateur côté OneToOne |
| Mentions `@user` / `#projet` | Reporté v2 — utile pour références cross-meetings |
| Coloration syntaxique des code-blocks | Reporté v2 |

---

## 7. Modèle de données

### 7.1 Clés d'attributs

Plutôt qu'un `AttributeScope` (Foundation `AttributedString`), on utilise des `NSAttributedString.Key` typées pour compat directe avec `NSTextStorage` :

```swift
public extension NSAttributedString.Key {
    static let mdBold       = NSAttributedString.Key("mdBold")
    static let mdItalic     = NSAttributedString.Key("mdItalic")
    static let mdInlineCode = NSAttributedString.Key("mdInlineCode")
    static let mdLink       = NSAttributedString.Key("mdLink")          // value: URL
    static let mdStrikethrough = NSAttributedString.Key("mdStrikethrough")
    static let mdBlockType  = NSAttributedString.Key("mdBlockType")     // value: BlockType
    static let mdListInfo   = NSAttributedString.Key("mdListInfo")      // value: ListInfo
    static let mdCodeLanguage = NSAttributedString.Key("mdCodeLanguage")
}

public enum BlockType: String, Codable {
    case paragraph, h1, h2, h3, h4, h5, h6, blockquote, codeBlock, thematicBreak
}

public struct ListInfo: Codable, Hashable {
    public enum Kind: String, Codable { case bullet, ordered, task }
    public let kind: Kind
    public let level: Int
    public let index: Int?       // pour ordered
    public let checked: Bool?    // pour task
}
```

### 7.2 Invariants

- Attributs de bloc appliqués à des paragraphes entiers (entre `\n`).
- `mdInlineCode` exclut `mdBold` et `mdItalic` (cohérence CommonMark).
- Les attributs internes ne fuient **jamais** dans l'API publique : tout passe par le `String` Markdown.

---

## 8. Conversion Markdown ↔ Modèle

### 8.1 Markdown → `NSAttributedString` (chargement / sync externe)

1. Parse via `swift-markdown` → AST.
2. Visitor récursif → `NSMutableAttributedString` avec attributs custom.
3. Application des attributs selon la config de l'instance : un H4 dans le markdown parsé alors que la config n'autorise que H1-H3 → dégradé en H3 (politique par défaut — à valider).

### 8.2 `NSAttributedString` → Markdown (binding update)

1. Découpage en blocs via changement de `mdBlockType` / `mdListInfo`.
2. Émission des préfixes de bloc.
3. Itération des runs inline, émission des délimiteurs avec **imbrication canonique** (`**_x_**` plutôt que `_**x**_`).
4. Échappement des caractères Markdown littéraux (`*`, `_`, `` ` ``, `[`, `]`, etc.).

### 8.3 Round-trip

**Exigence forte** : `serialize(parse(md)) == md` pour tout markdown produit par le composant.

Normalisations acceptables et documentées pour le markdown externe (LLM, import) :
- `_italic_` → `*italic*`
- `__bold__` → `**bold**`
- listes ordonnées renumérotées (`3. item` → `1. item` si premier de la liste)

---

## 9. UI / UX

### 9.1 Modes d'utilisation

| Vue | Hauteur | Toolbar | Blocs autorisés | Cas d'usage OneToOne |
|---|---|---|---|---|
| `MarkdownField` | 1 ligne | non | non | `Meeting.title` |
| `MarkdownTextEditor` | flexible | non | oui (selon config) | `Meeting.liveNotes`, `Note.text`, descriptions |
| `MarkdownEditor` | flexible | oui | oui | `Meeting.summary`, `prepNotes`, `ReportRevision.body` |

### 9.2 Toolbar macOS

| Placement | Comportement |
|---|---|
| `.floating` | Barre flottante au-dessus du composant, repositionnée à la sélection |
| `.pinned` | Intégrée en haut du composant, toujours visible |
| `.hidden` | Pas de toolbar — uniquement raccourcis clavier |

### 9.3 Intégration SwiftUI native

- Respect de `.disabled()`, `.focused()`, `.onSubmit { }`, `.environment(\.font)`.
- Compatible avec `Form`, `List`, `VStack` (mesure intrinsèque correcte).
- Dark mode et `accentColor` respectés.
- Compatible avec `MarkdownEditorView` actuel : migration progressive call-site par call-site.

### 9.4 Comportements clavier

| Touche | Comportement |
|---|---|
| `Enter` dans une liste | Nouvel item ; sur item vide : sort de la liste |
| `Tab` / `Shift+Tab` | Indente / désindente dans une liste |
| `Backspace` en début de bloc spécial | Revient à paragraphe |
| `⌘Z` / `⌘⇧Z` | Undo / redo via `NSUndoManager` |
| Clic sur checkbox | Toggle `[ ]` ↔ `[x]` |

### 9.5 Compat highlights manager

Le composant accepte un modifier optionnel pour reproduire le comportement actuel de `MeetingHighlightableTextView` (mise en évidence jaune sur des `NSRange` arbitraires, callback "Ajouter au rapport manager") :

```swift
MarkdownEditor(text: $meeting.summary)
    .markdownReadOnly(true)
    .markdownHighlights(rangesFromManagerReport)
    .markdownContextMenu { range, snippet in
        Button("Ajouter au rapport manager") { /* ... */ }
    }
```

---

## 10. Intégration OneToOne

### 10.1 Cas concret : édition d'un résumé post-LLM

```swift
struct MeetingView: View {
    @Bindable var meeting: Meeting
    var body: some View {
        VStack(alignment: .leading) {
            MarkdownField("Titre", text: $meeting.title)
                .markdownFeatures(.inlineOnly)

            MarkdownEditor(text: $meeting.summary)
                .markdownFeatures(.full)
                .markdownToolbar(.pinned)
                .markdownPlaceholder("Le résumé apparaîtra ici…")
                .frame(minHeight: 200)

            MarkdownTextEditor(text: $meeting.liveNotes)
                .markdownFeatures(.basic)
                .markdownPlaceholder("Notes live…")
        }
    }
}
```

### 10.2 Synchronisation SwiftData

- `@Bindable` sur les `@Model` SwiftData → propagation automatique des changements.
- Debounce 300 ms côté composant avant push au binding → réduit les `context.save()` excessifs.
- Pas de conflit multi-device (OneToOne est mono-utilisateur, local-first).

### 10.3 Réécriture par LLM en cours d'édition

Scénario : l'utilisateur édite un résumé, clique "Reformule" → appel `AIReportService.generate(...)` qui écrase `meeting.summary`.

| Cas | Comportement attendu |
|---|---|
| Édition utilisateur active + LLM termine | Le composant accepte la nouvelle valeur, re-parse, preserve la sélection si position toujours valide |
| LLM streaming (chunks partiels) | API optionnelle `onExternalUpdate` permet à l'hôte de désactiver l'édition pendant le streaming |
| Conflit (utilisateur a tapé pendant le streaming) | La valeur externe gagne — c'est le choix de l'hôte (LLM relancé par l'utilisateur, il est conscient de l'écrasement) |

### 10.4 Compat checkboxes prep

Le mode `.taskList` doit produire :
- À la frappe : `- [ ] ` détecté → bullet checkbox visuel
- Clic sur checkbox : toggle `[ ]` ↔ `[x]` dans le markdown
- Cohérence avec le carryover (`PrepCarryoverService.extractUncheckedItems`) : le markdown produit doit matcher `/^(\s*)- \[ \] (.+)$/`

---

## 11. Tests

### 11.1 Tests unitaires

| Suite | Périmètre |
|---|---|
| `ParserTests` | Fixtures `.md` → `NSAttributedString` attendu (snapshots) |
| `SerializerTests` | Modèle programmé → `.md` attendu |
| `RoundTripTests` | `serialize(parse(md)) == md` sur fixtures CommonMark |
| `ConfigurationTests` | Features désactivées → shortcuts inactifs, dégradation correcte |
| `PrepCheckboxCompatTests` | Items générés sont compatibles avec `PrepCarryoverService.extractUncheckedItems` |

### 11.2 Tests d'intégration

| Scénario | Vérification |
|---|---|
| Frappe au clavier simulée | État du `NSTextStorage` |
| Update externe du binding | Resync correct |
| Préservation sélection sur update externe | Caret reste à la position logique |
| Clic checkbox toggle | Markdown `[ ]` ↔ `[x]` |

### 11.3 Suite de référence

Sous-ensemble pertinent de la [CommonMark spec test suite](https://spec.commonmark.org/) (inline + listes + headings + blockquote).

### 11.4 Tests dans l'app OneToOne

| Champ | Cas testé |
|---|---|
| `Meeting.title` | Single-line, bold/italic OK, pas de retour à la ligne |
| `Meeting.summary` | Full editor, regen LLM préserve curseur |
| `Meeting.prepNotes` | Checkboxes cliquables, carryover OK |
| `Collaborator.standingPrepNotes` | Drain vers Meeting.prepNotes inchangé |
| `ReportRevision.body` | Lecture-seule + highlights = pas de régression vs `MeetingHighlightableTextView` |

---

## 12. Migration progressive

| Phase | Périmètre | Stratégie |
|---|---|---|
| 1 — Coexistence | Composant disponible, anciens `MarkdownEditorView` intacts | Pas de breaking change |
| 2 — Champs prep | `Meeting.prepNotes`, `Collaborator.standingPrepNotes`, `Project.standingPrepNotes` migrés (checkboxes) | Validation utilisateur sur le drag-from-context-panel |
| 3 — Champs résumé | `Meeting.summary`, `ReportRevision.body` (lecture seule via `markdownReadOnly`) | Vérifie compatibilité highlights |
| 4 — Champs annexes | `Note.text`, `Project.notes`, `Collaborator.notes`, `Meeting.liveNotes` | Migration mécanique |
| 5 — Champs single-line | `Meeting.title` | Remplace `TextField` par `MarkdownField` |
| 6 — Cleanup | Suppression `MarkdownEditorView` historique | Une fois tous les call-sites migrés |

---

## 13. Évolutions futures

| Version | Fonctionnalité | Justification |
|---|---|---|
| v1.1 | Tables GFM | Si demande explicite |
| v1.2 | Mentions `@collab` / `#projet` | Références cross-meetings utiles pour rapports |
| v1.3 | Images embed (depuis Capture screenshots) | Lien naturel avec `SlideCapture` existants |
| v1.4 | Coloration syntaxique code-blocks (Splash) | Cas de niche |
| v1.5 | Footnotes, maths KaTeX | Probablement YAGNI |
| v2.0 | Extraction en SPM externe | Si autre projet réutilise |

---

## 14. Questions ouvertes

| # | Question | Décision attendue |
|---|---|---|
| Q1 | **Nom du module** : `OneToOne/Markdown/`, `OneToOne/Editor/`, autre ? | À choisir |
| Q2 | **macOS-only confirmé** ? Si futur iOS, anticiper `NSViewRepresentable` → factor `UIViewRepresentable` parallèle ? | Confirmer mac-only |
| Q3 | **TextKit 2 strict** ou fallback TK1 ? TK2 macOS 15 est stable mais des bugs Apple traînent. | TK2 par défaut, fallback documenté |
| Q4 | **Politique de dégradation** : H4 dans markdown externe alors que `.h4` non listé → dégrade en H3 ? respecte le markdown source ? | Spec à figer |
| Q5 | **Coexistence avec `MeetingHighlightableTextView`** : on garde séparé ou on bascule tout sur le nouveau via `markdownHighlights` ? | À trancher après POC |
| Q6 | **Mention `@`/`#`** : prévoir l'API d'extension dès v1 même si implémentation v1.2 ? | Recommandé : oui (API surface) |
| Q7 | **Style visuel** : neutre SwiftUI (font système, accent OS) ou thème OneToOne via env-value ? | Neutre par défaut, modifier `.markdownTheme(...)` v1.1 |
| Q8 | **Localisation** : FR par défaut (placeholders, toolbar tooltips). i18n v2 ? | FR-only v1 |
| Q9 | **A11y VoiceOver** : annonces "titre niveau 2", "élément de liste", etc. | Niveau d'exigence à définir |
| Q10 | **Migration `Meeting.summary`** : remplace `MeetingHighlightableTextView` complètement ou cohabitation prolongée ? | À trancher après phase 3 migration |

---

## 15. Livrables attendus

| Livrable | État |
|---|---|
| Validation des hypothèses (§3) et réponses aux questions (§14) | À faire avant plan |
| POC : `NSViewRepresentable` autour de `NSTextView` + gras/italique + checkboxes + round-trip MD basique | Phase 0 |
| Spec détaillée de la sérialisation (overlaps, escaping, listes imbriquées) | À détailler dans le plan |
| Tests round-trip CommonMark + fixtures OneToOne (prep notes, summaries) | Phase 1 |
| Migration progressive (cf. §12) | Phases 2-6 |
| Cleanup `MarkdownEditorView` historique | Phase 6 |
