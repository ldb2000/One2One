# Rapport Manager — Design Spec

**Date :** 2026-05-05
**Sous-projet :** C (rapport pour mon manager) — issu d'une décomposition en 4 sous-projets indépendants (A. édition audio, B. édition transcription/rapport + vocabulaire, C. rapport manager, D. diarization).
**Statut :** Design validé, prêt pour implémentation plan.

## 1. Objectif

Permettre à l'utilisateur de constituer, au fil de ses réunions, un rapport de points à aborder avec son manager direct. Pendant le 1:1 manager, ces points sont cochés au fur et à mesure et annotés. À la fin, un compte-rendu spécifique est généré par IA en s'appuyant sur les notes manuelles, la transcription du 1:1, et la liste des points abordés. Les actions demandées par le manager sont extraites et matérialisées dans le système d'actions existant.

## 2. Décisions de conception (référence)

| # | Sujet | Décision |
|---|---|---|
| Q1 | Classification | Catégorie prédéfinie (A) + tag libre (B) + suggestion IA (C) |
| Q2 | Catégories | Set par défaut (8 valeurs) + liste éditable dans Paramètres |
| Q3 | Contexte enrichi | Stockage brut différé, enrichissement IA à la génération du CR |
| Q4 | 1:1 manager | Nouveau `MeetingKind.manager` |
| Q5 | Notes pendant 1:1 | Sidebar à cocher + zone notes par item, transcription croisée par l'IA |
| Q6 | Portée du rapport | Un seul rapport courant ; non-cochés reportés ; cochés archivés |
| Q7 | Historique | Page "Suivi manager" dédiée dans la sidebar |
| Q8 | Actions manager | `ActionTask` réutilisé avec `fromManager: Bool` + `managerMeeting` |
| Q9 | Sources de sélection | Transcription, rapport, notes, notes live |
| Q10 | Doublons | Permis silencieusement, marqués "doublon possible" avec lien croisé |
| Q11 | Suppression item | Highlight source supprimé automatiquement |
| Q12 | Stockage CR | Modèle `ManagerMeetingReport` indépendant |
| A | Highlights | Stockage offset (start, length) — décision technique A1 |
| B | Sélection texte | `NSTextView` wrappé en `NSViewRepresentable` — décision technique B1 |
| C | Reporting des non-cochés | Implicite via `archivedAt: Date?` — décision technique C1 |

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Settings (existant)                                             │
│   + managerName: String                                         │
│   + managerEmail: String                                        │
│   + managerCategoriesJSON: String  (liste éditable, défaut = 8) │
│   + managerReportPrompt: String   (prompt utilisateur éditable) │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Models (nouveaux)                                               │
│                                                                 │
│   ManagerReportItem                                             │
│     - rawSnippet, contextBefore, contextAfter                   │
│     - sourceMeeting → Meeting                                   │
│     - sourceField, sourceRangeStart, sourceRangeLength          │
│     - category, tag, aiSuggestedCategory                        │
│     - userNotes, isCompleted, archivedAt                        │
│     - archivedInMeeting → Meeting?                              │
│     - duplicateOfPID, isManual, manualOrder                     │
│                                                                 │
│   ManagerMeetingReport                                          │
│     - meeting → Meeting (1:1 type=manager)                      │
│     - generatedSummary, itemsSnapshotJSON, extractedActionsJSON │
│     - generatedAt, durationSeconds, modelUsed                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Modèles existants — extensions                                  │
│   MeetingKind  + .manager                                       │
│   ActionTask   + fromManager: Bool                              │
│                + managerMeeting → Meeting?                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Services (nouveaux)                                             │
│   ManagerReportService       (CRUD items, archivage, dédup)     │
│   ManagerCRGenerator         (prompt + appel IA + parse)        │
│   ManagerCategoryClassifier  (suggestion IA au check/ajout)     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Vues (nouvelles)                                                │
│   ManagerTrackingView      (page sidebar "Suivi manager")       │
│     ├── tab "Rapport courant"                                   │
│     ├── tab "Historique"                                        │
│     └── tab "Actions demandées"                                 │
│                                                                 │
│   ManagerAgendaSidebar     (sidebar dans MeetingView quand      │
│                             meeting.kind == .manager)           │
│   MeetingHighlightableTextView                                  │
│     (NSTextView wrappé, contextMenu "Ajouter au rapport         │
│      manager", highlight jaune persistant)                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Sidebar (existante) — ajout d'une entrée                        │
│   "Suivi manager" → ManagerTrackingView                         │
└─────────────────────────────────────────────────────────────────┘
```

### Flux principal

1. **Capture** : pendant n'importe quelle réunion, sélection texte → "Ajouter au rapport manager" → suggestion IA de catégorie (popup async) → item créé + highlight jaune persistant.
2. **Suivi** : vue "Suivi manager" pour consulter, réorganiser, ajouter manuellement, modifier catégorie/tag/notes.
3. **1:1 manager** : création meeting `kind = .manager` → `ManagerAgendaSidebar` ouverte automatiquement, items à cocher avec champ notes par item.
4. **Génération** : bouton "Générer CR manager" → `ManagerCRGenerator` → `ManagerMeetingReport` créé, items cochés archivés, sheet de revue des actions extraites.
5. **Suivi continu** : non-cochés reportés au prochain 1:1 manager. Actions matérialisées en `ActionTask(fromManager: true)` visibles dans tab dédié + dans `ActionsListView` globale avec badge.

## 4. Modèle de données

### 4.1 `AppSettings` — extensions

```swift
var managerName: String = ""
var managerEmail: String = ""
var managerCategoriesJSON: String = AppSettings.defaultManagerCategoriesJSON
var managerReportPrompt: String = AppSettings.defaultManagerReportPrompt

static let defaultCategories = [
    "Risque", "Décision", "RH", "Projet",
    "Reconnaissance", "Blocage", "Information", "Demande"
]
static var defaultManagerCategoriesJSON: String { /* JSON-encode defaultCategories */ }

var managerCategories: [String] {
    get { (try? JSONDecoder().decode([String].self,
            from: Data(managerCategoriesJSON.utf8))) ?? Self.defaultCategories }
    set { managerCategoriesJSON = (try? String(data: JSONEncoder().encode(newValue),
            encoding: .utf8)) ?? Self.defaultManagerCategoriesJSON }
}
```

### 4.2 `ManagerReportItem`

```swift
@Model
final class ManagerReportItem {
    var stableID: UUID = UUID()
    var createdAt: Date = Date()

    // Contenu source brut (stockage différé, enrichissement IA à la génération)
    var rawSnippet: String                  // phrase exacte sélectionnée
    var contextBefore: String = ""          // ~2 phrases avant
    var contextAfter: String = ""           // ~2 phrases après

    // Localisation source (pour highlight jaune)
    var sourceField: String                 // "transcript" | "mergedTranscript" | "summary" | "notes" | "liveNotes"
    var sourceRangeStart: Int               // offset UTF-16 (NSRange-compatible)
    var sourceRangeLength: Int

    // Classification
    var category: String = "Information"
    var tag: String = ""
    var aiSuggestedCategory: String?

    // Saisie utilisateur pendant le 1:1 manager
    var userNotes: String = ""

    // État
    var isCompleted: Bool = false
    var archivedAt: Date?
    var manualOrder: Int = 0
    var isManual: Bool = false

    // Doublon possible
    var duplicateOfPID: PersistentIdentifier?

    // Relations
    var sourceMeeting: Meeting?
    var archivedInMeeting: Meeting?

    init(rawSnippet: String, sourceField: String,
         sourceRangeStart: Int, sourceRangeLength: Int,
         sourceMeeting: Meeting?) { /* ... */ }
}
```

### 4.3 `ManagerMeetingReport`

```swift
@Model
final class ManagerMeetingReport {
    var stableID: UUID = UUID()
    var generatedAt: Date = Date()
    var generatedSummary: String = ""        // markdown
    var durationSeconds: Double = 0
    var modelUsed: String = ""

    var itemsSnapshotJSON: String = "[]"     // snapshot figé des items abordés
    var extractedActionsJSON: String = "[]"  // actions IA avant matérialisation

    var meeting: Meeting?
}
```

### 4.4 `MeetingKind` — extension

```swift
case manager = "manager"

var label: String {
    switch self {
    // existants...
    case .manager: return "1:1 Manager"
    }
}
var sfSymbol: String {
    switch self {
    // existants...
    case .manager: return "person.crop.square.filled.and.at.rectangle"
    }
}
```

### 4.5 `ActionTask` — extension

```swift
var fromManager: Bool = false
var managerMeeting: Meeting?
```

### 4.6 Relations & deleteRule

| Relation | deleteRule |
|---|---|
| `ManagerMeetingReport.meeting` | `.nullify` |
| `Meeting → ManagerMeetingReport` (inverse) | `.cascade` |
| `ManagerReportItem.sourceMeeting` | `.nullify` |
| `ManagerReportItem.archivedInMeeting` | `.nullify` |
| `ActionTask.managerMeeting` | `.nullify` |

### 4.7 Migration SwiftData

3 nouvelles classes (`ManagerReportItem`, `ManagerMeetingReport`) + 4 nouveaux champs sur `AppSettings` + 2 nouveaux champs sur `ActionTask`. Tous non-Optional avec valeurs par défaut → migration légère SwiftData (incrément `SchemaVersions.swift`). `MeetingKind` enum ajoute un case (rétrocompatible : meetings existants gardent leur `kindRaw`).

## 5. Composants UI

### 5.1 `MeetingHighlightableTextView` (composant clé, réutilisable)

Wrapper `NSViewRepresentable` autour de `NSTextView`.

**Responsabilités :**
- Affichage texte (read-only ou éditable) avec scroll vertical natif.
- Exposition de la sélection courante via callback.
- Highlight en jaune (`NSColor.systemYellow.withAlphaComponent(0.35)`) des ranges fournies.
- Menu contextuel "Ajouter au rapport manager" (raccourci ⇧⌘M) appelant `onAddToManagerReport(range, snippet)`.
- Re-rendu des highlights à chaque changement de texte ou de liste de ranges.

```swift
struct MeetingHighlightableTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let highlightedRanges: [NSRange]
    let onAddToManagerReport: (NSRange, String) -> Void
}
```

Utilisé pour : transcription brute, transcription fusionnée, summary, notes, notes live. `isEditable: false` dans cette V1 (édition = sub-projet B).

### 5.2 Popup de classification

Sheet léger affiché à l'ajout :

```
┌─ Classer ce point ─────────────────────────────┐
│ Aperçu : « …extrait sélectionné… »             │
│                                                │
│ Catégorie : [Risque ▼]    ← suggestion IA pré- │
│                              sélectionnée      │
│                                                │
│ Tag (optionnel) : [_______________]            │
│                                                │
│           [Annuler]   [Ajouter]                │
└────────────────────────────────────────────────┘
```

- Sheet ouvert immédiatement avec catégorie placeholder. Suggestion IA arrivant en async (timeout 3s) met à jour le picker.
- Réponse IA hors-liste → fallback `"Information"`, `aiSuggestedCategory = nil`.
- L'utilisateur peut toujours changer manuellement.

### 5.3 `ManagerTrackingView` (page sidebar "Suivi manager")

Page racine avec 3 tabs (segmented picker en header).

**Tab 1 — Rapport courant** (`archivedAt == nil`)
- Liste des items à aborder, drag-réorderable + filtres catégorie/tag.
- Chaque ligne : checkbox état, badge catégorie, snippet (3 lignes max), projet/meeting source (lien clic), date d'ajout, bouton "détails".
- Bouton "+ Ajouter manuellement" → sheet création (catégorie/tag/contenu/projet optionnel).
- Header compteur : "12 points à aborder · 3 cochés".

**Tab 2 — Historique** (`archivedAt != nil`)
- Timeline groupée par date d'archivage (`archivedInMeeting.date`).
- Filtres : catégorie, tag, plage de dates, recherche plein texte sur snippet/notes.
- Lien clic vers le `ManagerMeetingReport` correspondant.

**Tab 3 — Actions demandées par mon manager** (`ActionTask.fromManager == true`)
- Liste à faire / faites séparées.
- Filtres date / projet.
- Création manuelle possible.

### 5.4 `ManagerAgendaSidebar`

Affichée à droite de la `MeetingView` quand `meeting.kind == .manager`, en remplacement de `MeetingActionsSidebar`.

```
┌─ Agenda manager ───────────────────────────────┐
│ Filtre : [Toutes catégories ▼]                 │
│                                                │
│ ☐ [Risque] Migration K8s — pas de DRP          │
│   • Source : Réunion CODSI · 30/04             │
│   ┌──────────────────────────────────────────┐ │
│   │ Notes (réponse manager)…                 │ │
│   └──────────────────────────────────────────┘ │
│                                                │
│ ─── 3 cochés ───                               │
│ ☑ [Demande] Budget formation Q3                │
│   ┌─ Notes ─────────────────────────────────┐ │
│   │ Manager OK pour 5k€, à valider RH       │ │
│   └─────────────────────────────────────────┘ │
│                                                │
│ [+ Ajouter point]      [Générer CR manager]    │
└────────────────────────────────────────────────┘
```

- Click item → expand notes éditables.
- Cocher = `isCompleted = true` (pas d'archivage immédiat — l'archivage se fait à la génération du CR).
- Pas de popup de classification au check ici (catégorie déjà fixée à la création).
- Bouton "+ Ajouter point" → ajout direct dans le rapport courant.
- Bouton "Générer CR manager" disabled si aucun item coché.

### 5.5 Insertion dans `Sidebar` racine

Nouvelle entrée juste en-dessous de "Notes" :

```
- Tableau de bord
- Assistant IA
- Actions
- Réunions
- Notes
- Suivi manager  ← nouveau
- Collaborateurs Épinglés
- ...
```

### 5.6 Insertion dans `SettingsView`

Nouvelle section "Manager" :
- TextField nom du manager
- TextField email (optionnel)
- Liste éditable des catégories (add/remove/rename, drag pour réordonner)
- Editor du `managerReportPrompt`

## 6. Génération du CR manager

### 6.1 Service `ManagerCRGenerator`

```swift
@MainActor
struct ManagerCRGenerator {
    static func generate(
        meeting: Meeting,
        items: [ManagerReportItem],
        settings: AppSettings,
        context: ModelContext,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> ManagerMeetingReport
}
```

Précondition : `meeting.kind == .manager`, `items` = items où `isCompleted == true && archivedAt == nil`.

### 6.2 Construction du prompt

```
[SYSTEM]
Tu es l'assistant de OneToOne. Tu produis le compte-rendu d'un 1:1
avec le manager direct de l'utilisateur. Le compte-rendu doit
distinguer:
- les points abordés (avec ce qui a été dit / décidé pour chacun)
- les actions demandées par le manager (à matérialiser ensuite)
- les décisions prises
- les sujets à reporter à la prochaine session

Réponds UNIQUEMENT en markdown structuré, sections H2.
À la fin, inclus un bloc JSON ```json { "actions": [...] } ```
listant les actions demandées par le manager (titre court, due date
si mentionnée).

[CONTEXTE GLOBAL]
Manager : {settings.managerName}
Date du 1:1 : {meeting.date}
Durée : {meeting.durationSeconds}

[POINTS PRÉPARÉS — uniquement les COCHÉS]
Pour chaque item:
1. Catégorie + tag
2. Source : titre meeting source · projet · date
3. Extrait original (rawSnippet)
4. Contexte avant/après (contextBefore / contextAfter)
5. Notes prises pendant le 1:1 (userNotes)  ← priorité

[TRANSCRIPTION DU 1:1 MANAGER]
meeting.mergedTranscript (ou rawTranscript en fallback)

[INSTRUCTIONS]
- Pour chaque item, restitue :
  * ce qui a été dit (en t'appuyant en priorité sur userNotes,
    puis en complétant avec la transcription)
  * la position du manager si elle apparaît
  * les actions / décisions
- Si un point coché n'a pas de userNotes ET aucune trace dans la
  transcription, signale-le explicitement ("non couvert dans la
  transcription").
- N'invente pas. Si l'info manque, dis-le.

[PROMPT UTILISATEUR ÉDITABLE]
{settings.managerReportPrompt}
```

### 6.3 Étapes

1. Build prompt.
2. `AIClient.send(prompt:settings:onProgress:)` — réutilise l'API existante.
3. Parse réponse :
   - Markdown hors fence → `generatedSummary`.
   - Bloc JSON `actions` → liste d'actions à proposer.
4. Création `ManagerMeetingReport` :
   - `generatedSummary`, `itemsSnapshotJSON`, `extractedActionsJSON`, `meeting`, `durationSeconds`, `modelUsed`.
5. Archivage des items cochés (en mémoire, pas encore sauvegardé) :
   ```swift
   for item in items {
       item.archivedAt = Date()
       item.archivedInMeeting = meeting
   }
   ```
6. **Premier `try context.save()`** : persiste le `ManagerMeetingReport` et l'archivage des items. À ce stade, le CR existe et les items sont retirés du rapport courant, indépendamment de la suite. Si l'appel IA a échoué (étape 2), on n'arrive jamais ici → état inchangé.
7. Sheet de revue des actions extraites — l'utilisateur valide/édite/supprime.
8. À la confirmation du sheet : matérialisation des actions retenues en `ActionTask(fromManager: true, managerMeeting: meeting)` puis **second `try context.save()`**. Si l'utilisateur ferme le sheet sans valider, aucune `ActionTask` n'est créée (mais le CR et l'archivage restent — l'utilisateur peut relancer l'extraction depuis le `ManagerMeetingReport.extractedActionsJSON` plus tard).

### 6.4 Regénération

`ManagerCRGenerator.regenerate(report:)` :
- Source de vérité = `itemsSnapshotJSON` (figé à la première génération).
- Met à jour `generatedSummary`, `generatedAt`, `modelUsed`.
- Ne re-crée pas les `ActionTask` déjà matérialisées.

### 6.5 Service `ManagerCategoryClassifier`

Prompt court, async, timeout 3s :

```
Classe ce passage parmi les catégories suivantes :
{settings.managerCategories.joined(", ")}

Passage : "{snippet}"
Contexte projet : {projectName ?? "n/a"}

Réponds UNIQUEMENT par le nom exact d'une catégorie de la liste.
```

- Erreur / timeout / IA off → fallback `"Information"`, `aiSuggestedCategory = nil`.
- Réponse strictement matchée contre la liste (case-insensitive). Hors-liste → fallback.

### 6.6 Erreurs & cas limites

| Cas | Comportement |
|---|---|
| Aucun item coché à la génération | Bouton "Générer CR" disabled + tooltip |
| Transcription vide | Génération autorisée (CR s'appuie sur `userNotes`) ; bandeau warning |
| `managerName` vide | Génération bloquée : sheet "Configurez le nom de votre manager dans Paramètres" |
| Provider IA injoignable | Erreur dans bandeau de `ManagerAgendaSidebar`, items non archivés |
| Réponse IA non parseable | `generatedSummary` = brut, `extractedActionsJSON = []` |
| Quota / coupure réseau | Try/catch, état inchangé, message clair |

## 7. Edge cases UI & intégration

### 7.1 Sélection texte

| Cas | Comportement |
|---|---|
| Sélection vide | Menu disabled |
| Sélection < 3 chars | Menu disabled |
| Sélection > 1000 chars | Autorisé, warning dans le sheet |
| Multi-paragraphe (`\n`) | Autorisé, contexte extrait à partir des bords |
| Chevauchement avec highlight existant | Item créé silencieusement, `duplicateOfPID` rempli (overlap > 50%), badge "doublon possible" + lien croisé |
| Texte source édité (offsets décalés) | Highlight ignoré silencieusement au render, item conservé |

### 7.2 Extraction du contexte

`extractContext(text: String, range: NSRange) -> (before: String, after: String)`

1. `before` = jusqu'à 2 phrases qui précèdent `range.location`, en remontant tant qu'on trouve `[. ! ? …]` ou `\n\n`. Plafonné à 400 chars.
2. `after` = symétrique.
3. Bord de texte → contexte vide acceptable.

Réutilise la logique de `TextChunker.splitSentences` (RAGService.swift), factorisable plus tard.

### 7.3 Performance highlights

Texte transcription pouvant atteindre 50k+ chars avec 50+ items :
- Highlights appliqués en un seul pass via `NSTextStorage.beginEditing()/endEditing()`.
- Re-render uniquement quand la liste de ranges change. SwiftUI : `.id(highlightedRanges.hashValue)` sur le wrapper.

### 7.4 Suppression d'item & nettoyage du highlight

`ManagerReportService.delete(item:)` :
1. `context.delete(item)`
2. `context.save()`
3. La vue lisant les items via `@Query` recalcule sa liste de ranges → highlight retiré au prochain render. Pas d'opération directe sur le NSTextView.

Si l'item était archivé : suppression purge la référence dans `archivedInMeeting` mais ne touche pas le `ManagerMeetingReport` (snapshot figé).

### 7.5 Intégration `MeetingView`

- Si `meeting.kind == .manager` → affiche `ManagerAgendaSidebar` au lieu de `MeetingActionsSidebar`.
- Pour TOUS les meetings : zones texte transcription/summary/notes/liveNotes utilisent `MeetingHighlightableTextView` en remplacement des `Text`/`TextEditor` actuels. Migration progressive en un seul commit.

### 7.6 Backup

`BackupService.swift` doit lister les nouvelles entités : ajout de `ManagerReportItem` et `ManagerMeetingReport` au `Schema` SwiftData et au backup JSON. **Inclus dans le scope V1.**

### 7.7 Suppression d'un meeting

| Meeting supprimé | Effet |
|---|---|
| Source d'items (`sourceMeeting`) | Items deviennent orphelins (`sourceMeeting = nil`). Snippet et contexte stockés en clair → pas de perte d'info utile. |
| `kind == .manager` archivant des items | `ManagerMeetingReport` cascade-deleted. Items conservent `archivedAt`, lien `archivedInMeeting = nil`. Visibles dans tab Historique sans lien CR. |

### 7.8 Logs

`os.Logger(subsystem: "com.onetoone.app", category: "manager")` pour :
- création/suppression item
- ajout au rapport (snippet tronqué)
- suggestion IA reçue (catégorie)
- génération CR : durée, modèle, nb items, nb actions extraites
- échecs IA (timeout, parse, quota)

## 8. Tests

### 8.1 Unitaires (purs, sans UI ni IA réelle)

| Cible | Cas couverts |
|---|---|
| `ManagerReportService.add(snippet:range:source:)` | création nominale, offsets, doublon (overlap > 50%), ajout manuel sans source, fallback catégorie |
| `ManagerReportService.delete(item:)` | suppression, item archivé (`archivedInMeeting` nullifié uniquement) |
| `ManagerReportService.archiveCheckedItems(in:)` | archive uniquement `isCompleted && archivedAt == nil`, timestamps cohérents |
| `extractContext(text:range:)` | début/fin texte, multi-paragraphe, plafond 400 chars, range zéro |
| Validation offsets | range invalide ignoré, range valide rendu |
| `ManagerCRGenerator.buildPrompt` | items cochés uniquement, snapshot JSON, ordre sections, injection managerName, append managerReportPrompt |
| `ManagerCRGenerator.parseResponse` | markdown + json fence, sans fence, json malformé, multi-fences |
| `ManagerCategoryClassifier.match(response:)` | exact match (case-insensitive), hors-liste → nil, ponctuation/quotes |
| `AppSettings.managerCategories` | encoding/decoding, default si JSON corrompu |
| Migration SwiftData V2 → V3 | DB existante chargée sans erreur (snapshot bundlé) |

### 8.2 Intégration (IA mockée via protocole `AIClient`-like)

- `ManagerCRGenerator.generate(...)` end-to-end avec `MockAIClient` → vérifie création `ManagerMeetingReport`, archivage items, snapshot JSON.
- `ManagerCategoryClassifier.classify(...)` avec MockAIClient timeout → fallback `nil`.

### 8.3 UI

Pas de tests automatisés UI (cohérent avec le reste du projet). Validation manuelle via checklist DoD.

## 9. Critères de succès (Definition of Done)

1. ☑ Champ `managerName` dans Settings, configurable, persistant.
2. ☑ Catégories prédéfinies + édition libre dans Settings.
3. ☑ Sélection texte dans transcription/rapport/notes/liveNotes → ajout au rapport courant + highlight jaune persistant après reload.
4. ☑ Suggestion IA de catégorie avec sheet de confirmation à l'ajout.
5. ☑ Page "Suivi manager" dans la sidebar avec 3 tabs fonctionnels.
6. ☑ Création d'un meeting `kind = .manager` → sidebar agenda affichée automatiquement.
7. ☑ Items cochables avec notes manuelles éditables pendant le 1:1 manager.
8. ☑ Bouton "Générer CR manager" produit un `ManagerMeetingReport` et archive les cochés.
9. ☑ Items non-cochés reportés au prochain 1:1 manager.
10. ☑ Actions extraites par l'IA → sheet de revue → matérialisées en `ActionTask(fromManager: true)`.
11. ☑ Tab "Actions demandées" liste les `ActionTask.fromManager == true`.
12. ☑ Suppression d'item → highlight disparaît automatiquement de la source.
13. ☑ Doublons détectés et signalés avec lien croisé.
14. ☑ `BackupService` couvre les 2 nouvelles entités.
15. ☑ Tests unitaires passent.
16. ☑ Build vert.

## 10. Hors scope (follow-up V1.1)

- Édition de la transcription / rapport → sub-projet B
- Vocabulaire pour Whisper → sub-projet B
- Diarization / qui parle quand → sub-projet D
- Édition audio (couper le WAV) → sub-projet A
- Indexer `ManagerMeetingReport` dans Spotlight / RAG
- Étendre `/cherche` au corpus rapport manager
- Synchronisation des actions manager avec le profil collaborateur (décision Q8 reportée)

## 11. Risques & mitigations

| Risque | Mitigation |
|---|---|
| `NSTextView` wrapping fragile en SwiftUI | Encapsulation dans `MeetingHighlightableTextView` testée isolément ; fallback `Text + textSelection` lecture seule si bug bloquant |
| Offsets cassés après édition transcription (sub-projet B futur) | Décision A1 acceptée : highlight perdu silencieusement |
| Coût IA cumulé (classification × N + 1 génération) | Classification = prompt ~200 tokens. Génération = un appel par 1:1. Coût maîtrisé. |
| Migration SwiftData sur base existante | Tous nouveaux champs avec défauts non-Optional. Smoke test sur copie de la DB user avant release |
| Réponse IA parse failure | `generatedSummary` = brut, `extractedActionsJSON = []`. Pas de crash |
