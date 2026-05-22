# Rapport — refactor templates + flow simplifié — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre la génération du rapport 100 % template-driven (préambule éditable, plus de schéma JSON dans le prompt), supprimer la boucle Critiquer/Réviser/Valider/Auto, rendre les actions extraites éditables (assignee + échéance inline), injecter les attachments dans le contexte, et ne déclencher "Ajouter au rapport manager" que via le clic-droit existant.

**Architecture:** Génération en deux passes — passe 1 (markdown libre selon template), passe 2 (extraction structurée via prompt hardcoded). `Meeting.summary` overwrite simple (plus de `ReportRevision` côté UI). `CollaboratorMatcher` fuzzy résout les assignees LLM. Suppression des affordances ✨ par puce.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation, AppKit (NSMenu pour clic-droit déjà branché dans `MeetingHighlightableTextView`).

---

## File map

| Path | Responsibility |
|---|---|
| `OneToOne/Models/ReportTemplate.swift` (modify) | Ajout `preamble: String` + default seed |
| `OneToOne/Models/OtherModels.swift` (modify) | Ajout `ActionTask.unresolvedAssigneeName: String?` |
| `OneToOne/Services/BuiltInTemplates.swift` (modify) | `Seed.preamble` + backfill au seed |
| `OneToOne/Services/CollaboratorMatcher.swift` (new) | Match fuzzy nom LLM → Collaborator |
| `OneToOne/Services/AIReportService.swift` (modify) | `generate` sans JSON schema, +`extractStructured`, +`attachmentsBlock` |
| `OneToOne/Views/MeetingView.swift` (modify) | Suppression boutons Critiquer/Réviser/Valider/Auto + picker version + ✨ par puce |
| `OneToOne/Views/Meeting/MeetingActionsSidebar.swift` (modify) | Menus inline assignee + échéance par row + chip unresolved |
| `OneToOne/Views/Settings/ReportTemplateEditorView.swift` (modify) | Champ Préambule éditable |
| `Tests/CollaboratorMatcherTests.swift` (new) | Tests exact/accents/fuzzy/ambigu |

Total : 1 nouveau service, 1 nouveau test, 7 modifications.

**Notes types existants** :
- `ActionTask.collaborator: Collaborator?`, `completedAt: Date?`, init `(title:, dueDate:)`
- `Collaborator.pinLevel: Int`, `name: String`
- `MeetingAttachment.fileName: String`, `extractedText: String` (toujours non-nil, peut être vide)
- `Meeting.attachments: [MeetingAttachment]`
- Le clic-droit "Ajouter au rapport manager" existe déjà dans `MeetingHighlightableTextView.swift:331` — pas de nouveau code clic-droit, on supprime juste les ✨ icons par puce.

---

### Task 1: Model fields (ReportTemplate.preamble + ActionTask.unresolvedAssigneeName)

**Files:**
- Modify: `OneToOne/Models/ReportTemplate.swift`
- Modify: `OneToOne/Models/OtherModels.swift`

- [ ] **Step 1: Ajouter `preamble` à ReportTemplate**

Dans `OneToOne/Models/ReportTemplate.swift`, dans le bloc `@Model final class ReportTemplate { ... }`, juste après `var promptBody: String`, ajouter :

```swift
/// Préambule système injecté en tête du prompt de génération. Permet de
/// personnaliser le ton/rôle de l'assistant par template. Default = ancien
/// préambule hardcoded de `AIReportService.generate`.
var preamble: String = "Tu es l'assistant de synthèse de OneToOne."
```

Et dans l'init signature, ajouter le paramètre :
```swift
init(name: String,
     kind: ReportTemplateKind,
     promptBody: String = "",
     preamble: String = "Tu es l'assistant de synthèse de OneToOne.",
     sections: [TemplateSection] = [],
     historyMode: HistoryMode = .none,
     historyN: Int = 0,
     historyK: Int = 0,
     isBuiltIn: Bool = false) {
```

Et juste après `self.promptBody = promptBody`, ajouter :
```swift
self.preamble = preamble
```

- [ ] **Step 2: Ajouter `unresolvedAssigneeName` à ActionTask**

Dans `OneToOne/Models/OtherModels.swift`, dans `@Model final class ActionTask`, juste après `var completedAt: Date? = nil`, ajouter :
```swift
/// Quand l'extraction LLM 2e passe renvoie un nom d'assignee qui ne matche
/// AUCUN collaborator (même via CollaboratorMatcher fuzzy), on stocke le
/// nom brut ici. L'UI affiche un chip orange "💡 Auto : <nom>" cliquable
/// qui ouvre la sheet de recherche pré-remplie sur ce nom.
var unresolvedAssigneeName: String? = nil
```

- [ ] **Step 3: Build**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne && swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Models/ReportTemplate.swift OneToOne/Models/OtherModels.swift
git commit -m "feat(report-refactor): champs preamble (template) + unresolvedAssigneeName (action)"
```

---

### Task 2: Built-in templates — préambule dans Seed

**Files:**
- Modify: `OneToOne/Services/BuiltInTemplates.swift`

- [ ] **Step 1: Étendre le struct Seed**

Localiser le `struct Seed` (autour de la ligne 8-15). Modifier pour ajouter un champ `preamble`. Trouver le bloc :
```swift
struct Seed {
    let name: String
    let kind: ReportTemplateKind
    ...
```

Ajouter `let preamble: String` après `let kind: ReportTemplateKind`.

- [ ] **Step 2: Étendre `init` du Seed et propagation à ReportTemplate**

Repérer la création de `ReportTemplate` à partir du Seed (autour de la ligne 45) :
```swift
ReportTemplate(
    name: seed.name,
    kind: seed.kind,
    promptBody: ...,
    sections: ...,
    ...
)
```

Ajouter `preamble: seed.preamble` aux arguments.

- [ ] **Step 3: Renseigner `preamble` dans chacun des 12 Seed**

Pour CHAQUE Seed (d1_general, d2_oneToOne, d3_manager, d4_copil, d5_cosui, d6_codir, d7_preparation, d8_restitution, d9_workshop, d10_metier, d11_initiative, d12_custom) ajouter le champ `preamble:` avec la valeur par défaut. Si un Seed mérite un préambule spécifique, on garde le générique pour cette première passe :

```swift
preamble: "Tu es l'assistant de synthèse de OneToOne.",
```

- [ ] **Step 4: Backfill au seed**

Localiser la fonction qui itère sur les builts existants (probablement `seedIfNeeded` ou similaire — grep `seed` dans le fichier). Pour chaque built déjà inséré, s'assurer que `template.preamble` est non-vide ; sinon, set au seed default.

Si la fonction est `static func seedIfNeeded(in context: ModelContext)`, ajouter avant la création éventuelle :
```swift
let existingBuiltIns = (try? context.fetch(FetchDescriptor<ReportTemplate>(
    predicate: #Predicate { $0.isBuiltIn == true }
))) ?? []
for tpl in existingBuiltIns {
    if tpl.preamble.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        tpl.preamble = "Tu es l'assistant de synthèse de OneToOne."
    }
}
try? context.save()
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`. Si la signature de l'init de Seed est différente du grep initial, adapter.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/BuiltInTemplates.swift
git commit -m "feat(report-refactor): preamble dans built-in templates + backfill seed"
```

---

### Task 3: ReportTemplateEditorView — champ Préambule

**Files:**
- Modify: `OneToOne/Views/Settings/ReportTemplateEditorView.swift`

- [ ] **Step 1: Localiser le formulaire**

```bash
grep -n "promptBody\|TextEditor" OneToOne/Views/Settings/ReportTemplateEditorView.swift | head
```
Repérer le `TextEditor(text: $template.promptBody)` ou équivalent.

- [ ] **Step 2: Ajouter un champ Préambule au-dessus du Prompt**

Juste avant le bloc Prompt (`TextEditor` ou `LabeledContent` pour `promptBody`), ajouter :

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Préambule système")
        .font(.subheadline.bold())
    Text("Injecté en tête du prompt. Définit le rôle/ton de l'assistant.")
        .font(.caption2).foregroundStyle(.secondary)
    TextEditor(text: Binding(
        get: { template.preamble },
        set: { template.preamble = $0; template.updatedAt = Date() }
    ))
    .font(.body)
    .frame(minHeight: 60)
    .border(Color.secondary.opacity(0.2))
}
.padding(.bottom, 8)
```

Si le formulaire utilise un `Form` SwiftUI, encapsuler dans une `Section("Préambule") { ... }` à la place.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Settings/ReportTemplateEditorView.swift
git commit -m "feat(report-refactor): éditeur préambule dans ReportTemplateEditorView"
```

---

### Task 4: CollaboratorMatcher (TDD)

**Files:**
- Create: `OneToOne/Services/CollaboratorMatcher.swift`
- Create: `Tests/CollaboratorMatcherTests.swift`

- [ ] **Step 1: Écrire le test failing**

Dans `Tests/CollaboratorMatcherTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

final class CollaboratorMatcherTests: XCTestCase {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    func test_exactMatchInParticipants() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        let bob = Collaborator(name: "Bob MARTIN")
        ctx.insert(alice); ctx.insert(bob)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = [alice]
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Alice DUPONT",
            in: meeting,
            all: [alice, bob]
        )
        XCTAssertEqual(res?.name, "Alice DUPONT")
    }

    @MainActor
    func test_accentInsensitive() throws {
        let ctx = try makeContext()
        let zoe = Collaborator(name: "Zoé MERCIER")
        ctx.insert(zoe)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = [zoe]
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "ZOE MERCIER",
            in: meeting,
            all: [zoe]
        )
        XCTAssertEqual(res?.name, "Zoé MERCIER")
    }

    @MainActor
    func test_fallbackToFavorite() throws {
        let ctx = try makeContext()
        let charlie = Collaborator(name: "Charlie BRUN")
        charlie.pinLevel = 2
        ctx.insert(charlie)
        let meeting = Meeting(title: "M", date: Date())
        meeting.participants = []
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Charlie BRUN",
            in: meeting,
            all: [charlie]
        )
        XCTAssertEqual(res?.name, "Charlie BRUN")
    }

    @MainActor
    func test_fallbackToAll() throws {
        let ctx = try makeContext()
        let dani = Collaborator(name: "Dani ROCHE")
        ctx.insert(dani)
        let meeting = Meeting(title: "M", date: Date())
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Dani ROCHE",
            in: meeting,
            all: [dani]
        )
        XCTAssertEqual(res?.name, "Dani ROCHE")
    }

    @MainActor
    func test_noMatchReturnsNil() throws {
        let ctx = try makeContext()
        let alice = Collaborator(name: "Alice DUPONT")
        ctx.insert(alice)
        let meeting = Meeting(title: "M", date: Date())
        ctx.insert(meeting)
        try ctx.save()

        let res = CollaboratorMatcher.match(
            name: "Inconnu PERSONNE",
            in: meeting,
            all: [alice]
        )
        XCTAssertNil(res)
    }
}
```

- [ ] **Step 2: Confirmer RED**

```bash
swift test --filter CollaboratorMatcherTests 2>&1 | tail -10
```
Expected: FAIL `cannot find 'CollaboratorMatcher' in scope`.

- [ ] **Step 3: Implémenter le service**

Dans `OneToOne/Services/CollaboratorMatcher.swift` :

```swift
import Foundation
import SwiftData

/// Résout un nom de collaborateur retourné par un LLM en `Collaborator`
/// concret, ou nil si aucun match raisonnable n'existe.
///
/// Ordre :
/// 1. Match exact (case + accent-insensible) parmi `meeting.participants`
/// 2. Match exact parmi collabs avec `pinLevel >= 1`
/// 3. Match exact parmi tous les collabs non-archivés
///
/// Tous les comparatifs normalisent via `lowercased() + folding(diacriticInsensitive)`.
/// Pas de matching fuzzy "contains" en V1 — trop ambigu, on préfère nil →
/// affichage chip "💡 Auto : <nom>" pour confirmation utilisateur.
@MainActor
enum CollaboratorMatcher {

    static func match(name: String,
                      in meeting: Meeting,
                      all: [Collaborator]) -> Collaborator? {
        let target = normalize(name)
        guard !target.isEmpty else { return nil }

        // 1. Participants
        if let hit = meeting.participants.first(where: { normalize($0.name) == target }) {
            return hit
        }
        // 2. Favoris (pinLevel >= 1)
        let favorites = all.filter { $0.pinLevel >= 1 && !$0.isArchived }
        if let hit = favorites.first(where: { normalize($0.name) == target }) {
            return hit
        }
        // 3. Tous non-archivés
        let actives = all.filter { !$0.isArchived }
        if let hit = actives.first(where: { normalize($0.name) == target }) {
            return hit
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter CollaboratorMatcherTests 2>&1 | tail -10
```
Expected: PASS 5/5.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/CollaboratorMatcher.swift Tests/CollaboratorMatcherTests.swift
git commit -m "feat(report-refactor): CollaboratorMatcher (résolution nom LLM → Collaborator)"
```

---

### Task 5: AIReportService.generate — refactor sans JSON schema + préambule + attachments

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Localiser `generate(meeting:in:settings:...)`**

```bash
grep -n "static func generate(" OneToOne/Services/AIReportService.swift
```
Repérer la fonction `generate(meeting:in:settings:additionalContext:onProgress:)` (autour de la ligne 93).

- [ ] **Step 2: Réécrire le corps de la fonction**

Remplacer le bloc entier `static func generate(meeting:...) ... return parse(raw) }` (lignes ~93-161) par :

```swift
@MainActor
static func generate(
    meeting: Meeting,
    in context: ModelContext,
    settings: AppSettings,
    additionalContext: String = "",
    onProgress: AIClient.ProgressCallback? = nil
) async throws -> MeetingReportData {
    let template = meeting.reportTemplate ?? defaultTemplate(for: meeting.kind, in: context)
    let history = template.map { HistoryContextBuilder.build(for: meeting, template: $0, in: context) } ?? ""
    let preamble = template?.preamble ?? "Tu es l'assistant de synthèse de OneToOne."
    let body = template?.promptBody ?? ""
    let sections = template?.sections ?? []

    // 1. Resolve {{vars}} in the body.
    var resolved = TemplateVariableResolver.resolve(prompt: body, for: meeting, in: context)

    // 2. Historique inline ou append.
    let hasHistoryPlaceholder = resolved.contains("{{historique_n}}")
        || resolved.contains("{{project.historique_n}}")
    resolved = resolved.replacingOccurrences(of: "{{historique_n}}", with: history)
    resolved = resolved.replacingOccurrences(of: "{{project.historique_n}}", with: history)
    var historyAppendix = ""
    if !history.isEmpty, !hasHistoryPlaceholder {
        historyAppendix = "\n\nContexte historique (extraits de réunions précédentes) :\n\(history)\n"
    }
    if !additionalContext.isEmpty {
        historyAppendix += "\n\nContexte sémantique (RAG, extraits pertinents) :\n\(additionalContext)\n"
    }

    // 3. Documents joints (extraction script).
    let attachmentsBlock = buildAttachmentsBlock(
        for: meeting,
        promptLen: resolved.count + historyAppendix.count
    )

    // 4. Sections schema.
    var sectionsBlock = ""
    if !sections.isEmpty {
        sectionsBlock = "\n\n# Sections attendues (respecte cet ordre, un # par titre):\n"
        for (idx, s) in sections.enumerated() {
            sectionsBlock += "\(idx + 1). **\(s.title)** — \(s.hint)\n"
        }
    }

    // 5. Prompt final — markdown libre, plus de schéma JSON.
    let finalPrompt = """
    \(preamble)

    \(resolved)\(historyAppendix)\(attachmentsBlock)
    \(sectionsBlock)

    Produis un rapport en markdown français, structuré autour des sections
    demandées ci-dessus, concis et factuel. Pas de JSON, pas d'en-tête XML —
    uniquement le markdown du rapport.
    """

    reportLog.info("generate(meeting): template=\(template?.name ?? "default", privacy: .public) historyChars=\(history.count) attachmentsChars=\(attachmentsBlock.count)")
    let markdown = try await AIClient.send(prompt: finalPrompt, settings: settings, onProgress: onProgress)

    // 6. Extraction structurée 2e passe.
    let extracted = await extractStructured(markdown: markdown, meeting: meeting, settings: settings)

    return MeetingReportData(
        summary: markdown,
        keyPoints: extracted.keyPoints,
        decisions: extracted.decisions,
        openQuestions: extracted.openQuestions,
        actions: extracted.actions,
        alerts: extracted.alerts
    )
}

private static func buildAttachmentsBlock(for meeting: Meeting, promptLen: Int) -> String {
    let docs = meeting.attachments.compactMap { att -> (String, String)? in
        let txt = att.extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty else { return nil }
        return (att.fileName, txt)
    }
    guard !docs.isEmpty else { return "" }
    let totalBudget = 30_000 - promptLen
    guard totalBudget > 1000 else { return "" }
    let perDoc = max(500, totalBudget / docs.count)
    var block = "\n\n# Documents joints à cette réunion\n"
    for (name, txt) in docs {
        block += "## \(name)\n"
        block += String(txt.prefix(perDoc)) + "\n\n"
    }
    return block
}
```

- [ ] **Step 3: Vérifier que `MeetingReportData` existe avec ces champs**

```bash
grep -n "struct MeetingReportData\|MeetingReportData(" OneToOne/Services/AIReportService.swift | head
```
Si la struct existe et expose `summary, keyPoints, decisions, openQuestions, actions, alerts`, OK. Sinon, adapter le `return` ci-dessus aux champs réels (ou laisser le compilateur dicter).

- [ ] **Step 4: Build (échouera tant que `extractStructured` n'existe pas — c'est Task 6)**

```bash
swift build 2>&1 | tail -5
```
Expected: échec sur `extractStructured` undefined → c'est attendu, Task 6 le fournit. Pas de commit pour l'instant.

---

### Task 6: AIReportService.extractStructured (2e passe)

**Files:**
- Modify: `OneToOne/Services/AIReportService.swift`

- [ ] **Step 1: Repérer le type des `actions` / `alerts` dans `MeetingReportData`**

```bash
grep -n "var actions\|var alerts\|var keyPoints\|var decisions\|var openQuestions" OneToOne/Services/AIReportService.swift | head -10
```
Probablement `actions: [ExtractedAction]` et `alerts: [ExtractedAlert]`. Note les noms exacts.

- [ ] **Step 2: Ajouter la fonction `extractStructured`**

À la fin du `enum`/`struct AIReportService` (mais avant `}`), avant `parse(...)` :

```swift
struct ExtractedFacts {
    var keyPoints: [String]
    var decisions: [String]
    var openQuestions: [String]
    var actions: [ExtractedAction]
    var alerts: [ExtractedAlert]

    static let empty = ExtractedFacts(
        keyPoints: [], decisions: [], openQuestions: [], actions: [], alerts: []
    )
}

/// Passe 2 : extrait actions / alerts / décisions / questions / points clés
/// depuis le markdown produit par `generate`. Le prompt ci-dessous est
/// volontairement hardcoded (pas éditable) car il garantit le contrat JSON
/// attendu par le reste de l'app. Si on rend le schéma éditable, le parser
/// `parse(...)` casse silencieusement.
@MainActor
static func extractStructured(
    markdown: String,
    meeting: Meeting,
    settings: AppSettings
) async -> ExtractedFacts {
    let prompt = """
    Analyse ce compte-rendu de réunion et extrais les éléments structurés
    pour alimenter la base de données. Réponds EXCLUSIVEMENT en JSON strict
    avec ce schéma :
    {
      "keyPoints": ["..."],
      "decisions": ["..."],
      "openQuestions": ["..."],
      "actions": [
        { "title": "...", "assignee": "Nom complet ou null", "deadline": "YYYY-MM-DD ou null" }
      ],
      "alerts": [
        { "title": "...", "detail": "...", "severity": "Critique|Élevé|Modéré|Faible" }
      ]
    }

    Règles :
    - Tableaux vides `[]` si rien ne s'applique
    - `assignee` = nom complet exact si mentionné, sinon null
    - `deadline` = format ISO YYYY-MM-DD ou null
    - Pas d'invention — uniquement ce qui est explicitement dans le compte-rendu

    Compte-rendu à analyser :
    \(markdown)
    """

    do {
        let raw = try await AIClient.send(prompt: prompt, settings: settings)
        let parsed = parse(raw)
        return ExtractedFacts(
            keyPoints: parsed.keyPoints,
            decisions: parsed.decisions,
            openQuestions: parsed.openQuestions,
            actions: parsed.actions,
            alerts: parsed.alerts
        )
    } catch {
        reportLog.warning("extractStructured failed: \(error.localizedDescription, privacy: .public) — keeping markdown only")
        return .empty
    }
}
```

**Note** : `parse(raw)` existant (dans AIReportService) retourne déjà un `MeetingReportData`. On en extrait les champs structurés (le `summary` qu'il retourne n'est pas utilisé ici car il vient du markdown passé en entrée du LLM, on garde le markdown original).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`. Si erreur sur les types `ExtractedAction`/`ExtractedAlert`, vérifier les noms exacts via `grep -n "struct Extracted\|struct.*Action {" OneToOne/Services/AIReportService.swift`.

- [ ] **Step 4: Commit (combine Task 5 + 6)**

```bash
git add OneToOne/Services/AIReportService.swift
git commit -m "feat(report-refactor): generate sans JSON schema + extractStructured 2e passe + attachmentsBlock"
```

---

### Task 7: Résolution assignee dans le hook de génération

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift` (ou wherever `AIReportService.generate` est appelé et les `actions` insérées en SwiftData)

- [ ] **Step 1: Localiser le point d'insertion des actions**

```bash
grep -n "AIReportService.generate\|ActionTask(\|.actions.forEach\|for action in" OneToOne/Views/MeetingView.swift | head
```
Repérer le bloc qui prend `result.actions` et crée des `ActionTask` SwiftData.

- [ ] **Step 2: Remplacer la résolution naïve par CollaboratorMatcher**

Le bloc actuel ressemble probablement à :
```swift
for ext in result.actions {
    let t = ActionTask(title: ext.title, dueDate: parseDeadline(ext.deadline))
    if let name = ext.assignee {
        t.collaborator = allCollaborators.first { $0.name == name }
    }
    t.meeting = meeting
    context.insert(t)
}
```

Remplacer par :
```swift
let allCollabs = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
for ext in result.actions {
    let t = ActionTask(title: ext.title, dueDate: parseDeadline(ext.deadline))
    if let name = ext.assignee, !name.isEmpty {
        if let match = CollaboratorMatcher.match(name: name, in: meeting, all: allCollabs) {
            t.collaborator = match
        } else {
            t.unresolvedAssigneeName = name
        }
    }
    t.meeting = meeting
    context.insert(t)
}
```

Le nom de variable `result.actions` / `ext` peut varier — adapter au code réel. Le helper `parseDeadline` doit déjà exister (sinon `ISO8601DateFormatter().date(from: name + "T00:00:00Z")`).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(report-refactor): résolution assignee via CollaboratorMatcher + fallback unresolved"
```

---

### Task 8: Supprimer Auto / Critiquer / Réviser / Valider + picker version

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Localiser le bloc de boutons rapport**

```bash
grep -n "isCritiquing\|isRevising\|isAutoLooping\|currentRevision\|Picker.*reportRevisions\|runAutoLoop\|runCritique\|runRevise\|validateCurrentRevision" OneToOne/Views/MeetingView.swift | head -30
```

Le toolbar des boutons rapport est autour des lignes 1247-1285 (`Button { Task { await runAutoLoop() } } label: { Label(isAutoLooping ? "Auto…" : "Auto", ...)`). Il contient 4 boutons + un picker version au-dessus.

- [ ] **Step 2: Garder uniquement le bouton "Générer"**

Remplacer le bloc HStack qui contient les 4 boutons (et inclut le picker version) par :
```swift
HStack {
    if let template = meeting.reportTemplate {
        Text("Template :")
            .font(.caption).foregroundStyle(.secondary)
        Text(template.name).font(.caption.bold())
    } else {
        Text("Template : Auto").font(.caption).foregroundStyle(.secondary)
    }
    Spacer()
    Button {
        Task { await runGenerate() }
    } label: {
        Label(isGenerating ? "Génère…" : "Générer",
              systemImage: "wand.and.stars")
    }
    .disabled(isGenerating)
    .help("Génère un nouveau rapport (écrase la version actuelle)")
}
.padding(.horizontal, 6).padding(.vertical, 4)
.background(
    RoundedRectangle(cornerRadius: 6)
        .fill(Color(nsColor: .controlBackgroundColor))
)
```

- [ ] **Step 3: Remplacer les @State et fonctions**

Localiser les déclarations `@State private var isCritiquing = false`, `isRevising`, `isAutoLooping`. Les supprimer. Ajouter `@State private var isGenerating = false`.

Localiser `private func runCritique()`, `runRevise()`, `runAutoLoop()`, `validateCurrentRevision()`, `currentRevision`, `currentCritique`. Les supprimer entièrement.

Localiser le code qui appelle `AIReportService.generate(...)` initialement (probablement dans une fonction `regenerateReport()` ou `runReport()`). Renommer ou créer `runGenerate()` :

```swift
private func runGenerate() async {
    isGenerating = true
    defer { Task { @MainActor in isGenerating = false } }
    do {
        let result = try await AIReportService.generate(
            meeting: meeting,
            in: context,
            settings: settings
        )
        await MainActor.run {
            meeting.summary = result.summary
            // Insertion des actions/alerts/decisions extraites — réutilise
            // le code existant ou le bloc de Task 7.
            applyExtracted(result, to: meeting)
            try? context.save()
        }
    } catch {
        print("[Rapport] génération échec: \(error)")
    }
}
```

Si une fonction `applyExtracted` n'existe pas, l'extraire du code existant qui faisait l'insertion des actions/alerts depuis l'ancien flow.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -15
```
Expected: `Build complete!`. Probable cascade d'erreurs (références à `currentRevision`, `isCritiquing` ailleurs dans MeetingView). Pour chacune, supprimer ou remplacer par `meeting.summary` / `isGenerating`. Si un appel à `currentRevision?.body` reste, le remplacer par `meeting.summary`.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(report-refactor): suppression Auto/Critiquer/Réviser/Valider + picker version"
```

---

### Task 9: Supprimer les ✨ "Ajouter au rapport manager" par puce

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift`

- [ ] **Step 1: Localiser le bloc**

```bash
grep -n "Ajouter au rapport manager\|sparkles\|plus.bubble" OneToOne/Views/MeetingView.swift | head
```

Repérer les blocs autour de la ligne 1958-1986 :
```swift
/// Original Label + trailing "Ajouter au rapport manager" affordance.
...
} label: { Label("Ajouter au rapport manager", systemImage: "plus.bubble") }
```

- [ ] **Step 2: Supprimer le bloc**

Supprimer entièrement la fonction (probablement un `@ViewBuilder private func ...`) qui rend le `Label + Ajouter au rapport manager affordance`, ET les appels à cette fonction dans le rendu du rapport. Laisser le rendu markdown brut sans icône ajoutée par puce.

Le clic-droit sur sélection reste fonctionnel via `MeetingHighlightableTextView` (déjà branché — pas de changement).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(report-refactor): suppression ✨ Ajouter au rapport manager par puce (clic-droit reste)"
```

---

### Task 10: Édition inline assignee + échéance dans les task rows

**Files:**
- Modify: `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`

- [ ] **Step 1: Localiser la `taskRow(_:)` (lignes 121-173)**

```bash
grep -n "func taskRow\|Non assigné\|Pas d'échéance" OneToOne/Views/Meeting/MeetingActionsSidebar.swift | head
```

- [ ] **Step 2: Remplacer le HStack metadata par menus**

Le HStack actuel (lignes 149-165 environ) affiche "Non assigné · Pas d'échéance" en texte statique. Remplacer par :

```swift
HStack(spacing: 10) {
    rowAssigneeMenu(task)
    Text("·").foregroundColor(.secondary)
    rowDueDateMenu(task)
    Spacer()
}
.padding(.leading, 30)
```

Ajouter en helpers (dans le struct, avant `assigneeMenu`) :

```swift
@ViewBuilder
private func rowAssigneeMenu(_ task: ActionTask) -> some View {
    Menu {
        Button {
            task.collaborator = nil
            task.unresolvedAssigneeName = nil
            saveContext()
        } label: { Text("Non assigné") }
        if !participantCandidates.isEmpty {
            Divider()
            Section("Participants") {
                ForEach(participantCandidates) { c in
                    Button(c.name) {
                        task.collaborator = c
                        task.unresolvedAssigneeName = nil
                        saveContext()
                    }
                }
            }
        }
        if !favoriteCandidates.isEmpty {
            Divider()
            Section("Favoris") {
                ForEach(favoriteCandidates) { c in
                    Button(c.name) {
                        task.collaborator = c
                        task.unresolvedAssigneeName = nil
                        saveContext()
                    }
                }
            }
        }
    } label: {
        HStack(spacing: 4) {
            if let c = task.collaborator {
                AvatarMini(collaborator: c, tint: settings.meetingParticipantColor)
                Text(c.name).font(.caption).foregroundColor(.secondary)
            } else {
                Image(systemName: "person.crop.circle").font(.caption2).foregroundColor(.secondary)
                Text("Non assigné").font(.caption).foregroundColor(.secondary)
            }
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
}

@ViewBuilder
private func rowDueDateMenu(_ task: ActionTask) -> some View {
    Menu {
        Button("Aucune") {
            task.dueDate = nil
            saveContext()
        }
        Button("Aujourd'hui") {
            task.dueDate = Date()
            saveContext()
        }
        Button("Demain") {
            task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            saveContext()
        }
        Button("Dans 1 semaine") {
            task.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
            saveContext()
        }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
            if let dd = task.dueDate {
                Text(shortDate(dd)).font(.caption).foregroundColor(.secondary)
            } else {
                Text("Pas d'échéance").font(.caption).foregroundColor(.secondary)
            }
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
}
```

Le helper `saveContext()` existe déjà (propriété fournie en init). `shortDate` existe déjà.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingActionsSidebar.swift
git commit -m "feat(report-refactor): task rows menus inline assignee + échéance"
```

---

### Task 11: Chip "💡 Auto" pour unresolvedAssigneeName

**Files:**
- Modify: `OneToOne/Views/Meeting/MeetingActionsSidebar.swift`

- [ ] **Step 1: Ajouter une row chip dans `taskRow`**

Juste après le premier HStack de `taskRow` (qui contient title + ellipsis), avant le HStack metadata, ajouter :

```swift
if let hint = task.unresolvedAssigneeName, task.collaborator == nil {
    HStack(spacing: 6) {
        Image(systemName: "lightbulb.fill").foregroundStyle(.orange).font(.caption2)
        Text("Auto : \(hint)")
            .font(.caption2)
            .foregroundStyle(.orange)
        Spacer()
        Button("Choisir") {
            // Ouvre la sheet déjà existante pré-remplie sur le nom hint.
            showingAddCollaboratorSheet = true
            // ⚠ pré-remplir la query nécessite de passer hint dans la sheet ;
            // V1 = on ouvre simplement la sheet, user tape manuellement.
        }
        .buttonStyle(.borderless)
        .font(.caption2)
    }
    .padding(.leading, 30)
    .padding(.bottom, 2)
}
```

**Note** : pré-remplir la search query nécessiterait un binding `initialQuery: String?` sur `AddCollaboratorSheet`. V1 = ouvre simplement la sheet, user voit le hint, tape. Si gênant → suite : passer le hint en `@State private var pendingAssigneeQuery: String?` partagé.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingActionsSidebar.swift
git commit -m "feat(report-refactor): chip Auto:<nom> pour actions auto-extraites non-résolues"
```

---

### Task 12: Final build + test + smoke

**Files:** (aucun)

- [ ] **Step 1: Run tous les tests**

```bash
swift test 2>&1 | grep -E "Executed|failed|passed" | tail -10
```
Expected: tous PASS, dont 5 CollaboratorMatcherTests.

- [ ] **Step 2: Full build clean**

```bash
swift build 2>&1 | tail -3
```
Expected: `Build complete!`.

- [ ] **Step 3: Commit history check**

```bash
git log --oneline -14
```
Attendu : commits avec prefix `feat(report-refactor):` pour Tasks 1-11.

- [ ] **Step 4: Smoke test manuel**

Lance `swift run` et :
1. Préférences → Templates → ouvre un built-in → vérifier champ "Préambule système" visible et éditable.
2. Sur une réunion existante avec transcription : clic "Générer" → un seul bouton, plus de Auto/Critiquer/Réviser/Valider.
3. Vérifier que `meeting.summary` est mis à jour et que des actions apparaissent dans le panneau Actions, avec menus assignee + échéance cliquables.
4. Si l'extraction LLM renvoie un nom inconnu, chip orange "💡 Auto : <nom>" visible avec bouton Choisir.
5. Drop un pptx en attachment → re-Générer → vérifier dans Console.app que `attachmentsChars > 0`.
6. Sélectionner un bout du rapport rendu → clic-droit → "Ajouter au rapport manager" → sheet s'ouvre pré-remplie.
7. Plus aucune ✨ icône par puce dans le rapport.

---

## Self-review

**Spec coverage** :
- §2.1 `preamble` champ + default → Task 1 + 2 + 3. ✓
- §2.2 LLM markdown libre (plus de JSON schema dans generate) → Task 5. ✓
- §2.3 extractStructured 2e passe + prompt hardcoded → Task 6. ✓
- §2.4 un seul bouton Générer + plus de versions UI → Task 8. ✓
- §2.5 clic-droit uniquement (suppression ✨ par puce) → Task 9. ✓
- §2.6 task rows inline editing → Task 10. ✓
- §2.7 LLM assignee fuzzy + unresolvedAssigneeName → Tasks 4 + 7 + 11. ✓
- §2.8 pptx text extraction script-only → DÉJÀ OK (confirmé via `MeetingAttachmentService.importDocument` qui n'appelle pas le LLM). Pas de task nécessaire.
- §2.9 attachments dans le prompt → Task 5 (buildAttachmentsBlock). ✓
- §3.2 modèles → Task 1. ✓
- §3.6 helper assigneeMenu factorisé → Task 10 (rowAssigneeMenu/rowDueDateMenu). ✓
- §3.7 CollaboratorMatcher → Task 4. ✓
- §3.9 built-ins reseedés → Task 2 (backfill). ✓
- §4.1 UI un seul bouton Générer → Task 8. ✓
- §4.2 clic-droit sheet pré-remplie → Tâche existante déjà branchée (`MeetingHighlightableTextView`), pas de modif. ✓
- §4.3 task row chip → Task 11. ✓
- §5 erreurs (extract échoue → markdown préservé, attachment vide → ignoré) → Task 6 (catch logs + return .empty). ✓
- §6 tests CollaboratorMatcher → Task 4. ✓ Tests extractStructured = manuel V1 (markdown sample), pas dans plan unitaire — accepté.

Gap mineur : §6 mentionne "Tests extractStructured" mais on n'écrit pas de test unitaire faute de mock LLM. Reporté à plus tard.

**Placeholder scan** :
- Aucun "TBD" / "implement later".
- Quelques "adapter au code réel" inline (Tasks 5/7/8) avec instructions claires pour le subagent — acceptable car dépendances de noms internes (`MeetingReportData`, `parseDeadline`) sont fragiles. Le subagent peut grep pour s'aligner.

**Type consistency** :
- `ReportTemplate.preamble: String` cohérent partout (Tasks 1, 2, 3, 5). ✓
- `ActionTask.unresolvedAssigneeName: String?` cohérent (Tasks 1, 7, 10, 11). ✓
- `CollaboratorMatcher.match(name:in:all:) -> Collaborator?` cohérent (Tasks 4, 7). ✓
- `AIReportService.extractStructured(markdown:meeting:settings:) async -> ExtractedFacts` cohérent (Tasks 5, 6). ✓
- `ExtractedFacts.empty` cohérent (Task 6). ✓
- `isGenerating: Bool` remplace `isCritiquing`/`isRevising`/`isAutoLooping` (Task 8). ✓
- `runGenerate()` cohérent avec call site (Task 8). ✓

Aucune correction inline nécessaire.
