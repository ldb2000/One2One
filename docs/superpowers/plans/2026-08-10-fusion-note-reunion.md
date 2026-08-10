# Fusion Note / Réunion — plan d'implémentation

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les étapes
> utilisent la syntaxe case à cocher (`- [ ]`).

**But :** supprimer les quatre modèles de texte libre daté (`Note`, `NoteAttachment`,
`ProjectInfoEntry`, `ProjectCollaboratorEntry`), tous vides dans le store réel, en faisant d'une
note un `Meeting` de kind `.note` — une réunion avec soi-même.

**Architecture :** `MeetingKind` gagne un cas `.note`. Une note est un `Meeting` sans audio ni
participant obligatoire, dont le corps vit dans `liveNotes` et les pièces jointes dans
`MeetingAttachment`. Trois unités pures nouvelles portent les règles partagées :
`MeetingStatsScope` (exclusion des notes des statistiques), `NoteFactory` (création unique quel
que soit le point d'entrée), `MeetingView.visibleSections(for:)` (onglets par kind). Les écrans
existants sont repointés, puis les quatre modèles sont supprimés.

**Pile :** Swift 6, SwiftPM (pas de projet Xcode), SwiftUI, SwiftData, CoreSpotlight, Swift Testing
et XCTest.

**Spec :** `docs/superpowers/specs/2026-08-10-fusion-note-reunion-design.md`

## Contraintes globales

- Branche `feat/fusion-note-reunion`. **Aucun commit sur `master`.** Commits conventionnels.
- Commentaires et libellés d'interface **en français** ; symboles et code en anglais.
- Aucune dépendance nouvelle.
- **Jamais `git commit -a` ni `git add -A`.** L'arbre de travail porte un chantier éditeur en
  cours, sans rapport avec celui-ci (`Package.swift`, `Vendor/`, `OneToOne/Markdown/…`). Chaque
  commit énumère ses chemins explicitement. Vérifier avec `git status --short` avant de committer
  que rien d'étranger n'est indexé.
- Tests neufs en **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`), libellés en
  français. Les conteneurs de test neufs se construisent avec
  `Schema(CurrentSchema.models)` + `ModelConfiguration(isStoredInMemoryOnly: true)`.
- Vérification après chaque tâche : `swift test --skip CalendarImportEventTests`.
  Le `--skip` évite un crash d'environnement hors bundle applicatif ; voir `STATUS.md`.
- Énums persistées SwiftData en `…Raw: String` + wrapper calculé — `Meeting.kind` respecte déjà
  cette forme, ne pas l'altérer.
- L'app doit **compiler et les tests passer à la fin de chaque tâche**. L'ordre des tâches est
  contraint par cette règle : les suppressions de modèles arrivent après le repointage de tous
  leurs lecteurs.

---

### Task 1: `MeetingKind.note` et l'exclusion des statistiques

**Files:**
- Modify: `OneToOne/Models/MeetingModels.swift:10-47`
- Create: `OneToOne/Services/MeetingStatsScope.swift`
- Modify: `OneToOne/Services/MenuBarStats.swift:65-66`
- Modify: `OneToOne/Views/DetailsViews.swift:52-54`, `:901-905`, `:1157-1161`
- Test: `Tests/MeetingStatsScopeTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit : `MeetingKind.note` ; `MeetingStatsScope.held(_ meetings: [Meeting]) -> [Meeting]`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/MeetingStatsScopeTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("MeetingStatsScope — une note ne compte pas comme une réunion tenue")
struct MeetingStatsScopeTests {

    @Test("Une note est écartée")
    func noteIsExcluded() {
        let note = Meeting(title: "Note", date: Date())
        note.kind = .note
        #expect(MeetingStatsScope.held([note]).isEmpty)
    }

    @Test("Un 1:1 est conservé")
    func oneToOneIsKept() {
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        #expect(MeetingStatsScope.held([meeting]).count == 1)
    }

    @Test("L'ordre d'entrée est préservé")
    func orderIsPreserved() {
        let a = Meeting(title: "A", date: Date())
        a.kind = .global
        let note = Meeting(title: "N", date: Date())
        note.kind = .note
        let b = Meeting(title: "B", date: Date())
        b.kind = .project
        #expect(MeetingStatsScope.held([a, note, b]).map(\.title) == ["A", "B"])
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter MeetingStatsScopeTests`
Expected: échec de compilation — `cannot find 'MeetingStatsScope' in scope` et
`type 'MeetingKind' has no member 'note'`.

- [ ] **Step 3: Ajouter le cas `.note` à `MeetingKind`**

Dans `OneToOne/Models/MeetingModels.swift`, ajouter le cas **en dernier** (l'ordre pilote celui
des sélecteurs existants, ne pas le perturber) :

```swift
    /// Entretien 1:1 avec le manager direct.
    case manager  = "manager"   // 1:1 avec le manager direct
    /// Note libre — une réunion avec soi-même : ni audio, ni transcription, ni rapport.
    case note     = "note"
```

Et dans les deux `switch` :

```swift
        case .note:     return "Note"
```
```swift
        case .note:     return "note.text"
```

- [ ] **Step 4: Créer `MeetingStatsScope`**

Créer `OneToOne/Services/MeetingStatsScope.swift` :

```swift
import Foundation

/// Portée des réunions qui comptent comme « réellement tenues ».
///
/// Une note est un `Meeting` de kind `.note` — une réunion avec soi-même. Elle
/// ne représente aucun temps passé, ne doit pas noircir la heatmap d'activité,
/// ni apparaître dans la liste des réunions d'un collaborateur (elle a sa
/// propre section). Quatre appelants partagent donc cette règle : le calcul des
/// stats du jour, les deux montages de `MeetingHeatmapView`, et le décompte
/// hebdomadaire « Temps passé en réunions » de la barre latérale.
enum MeetingStatsScope {

    /// Ne conserve que les réunions réellement tenues, dans l'ordre d'entrée.
    static func held(_ meetings: [Meeting]) -> [Meeting] {
        meetings.filter { $0.kind != .note }
    }
}
```

- [ ] **Step 5: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter MeetingStatsScopeTests`
Expected: 3 tests, tous verts.

- [ ] **Step 6: Brancher les trois appelants**

Dans `OneToOne/Services/MenuBarStats.swift`, `TodayStatsCalculator.compute`, remplacer :

```swift
        let all = (try? context.fetch(descriptor)) ?? []
```

par :

```swift
        let all = MeetingStatsScope.held((try? context.fetch(descriptor)) ?? [])
```

Dans `OneToOne/Views/Sidebar.swift`, `weeklyTimeBreakdown` (~ligne 1024), la boucle
« 2. Réunions ad hoc » alimente le widget « Temps passé en réunions » — une note y compterait :

```swift
        for meeting in MeetingStatsScope.held(meetings) where meeting.date >= weekStart && meeting.date < weekEnd {
```

Dans `OneToOne/Views/DetailsViews.swift`, fiche projet (~ligne 52) :

```swift
                    MeetingHeatmapView(
                        meetings: MeetingStatsScope.held(
                            allMeetings.filter { $0.project?.persistentModelID == project.persistentModelID }
                        )
                    )
```

Fiche collaborateur (~ligne 901) :

```swift
                    MeetingHeatmapView(
                        meetings: MeetingStatsScope.held(
                            allMeetings.filter { meeting in
                                meeting.participants.contains(where: { $0.persistentModelID == collaborator.persistentModelID })
                            }
                        )
                    )
```

Et le `GroupBox("Réunions")` de la fiche collaborateur (~ligne 1157), qui sinon afficherait les
notes **en double** avec la section Notes juste en dessous. Introduire une variable locale au
début du `GroupBox` et l'utiliser aux deux endroits :

```swift
                GroupBox("Réunions") {
                    let heldMeetings = MeetingStatsScope.held(collaborator.meetings)
                    if heldMeetings.isEmpty {
                        // … message inchangé …
                    } else {
                        ForEach(heldMeetings.sorted(by: { $0.date > $1.date })) { meeting in
```

- [ ] **Step 7: Vérifier la suite complète**

Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression.

Deux effets de bord attendus, tous deux dus au fait que ces vues itèrent `MeetingKind.allCases` :
un filtre « Note » apparaît dans le menu Type de `MeetingsListView` — la tâche 8 l'en retire —
et dans celui de `RAGChatView:110`, où il est **souhaité** et ne demande aucun code : interroger
ses notes par l'IA. Le sélecteur de kind de `MeetingTopChromeBar:97` gagne lui aussi « Note »,
c'est le chemin de conversion note ↔ réunion.

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Models/MeetingModels.swift OneToOne/Services/MeetingStatsScope.swift \
        OneToOne/Services/MenuBarStats.swift OneToOne/Views/DetailsViews.swift \
        Tests/MeetingStatsScopeTests.swift
git commit -m "feat(reunion): ajoute le kind note et l'exclut des statistiques d'activité"
```

---

### Task 2: `NoteFactory`

**Files:**
- Create: `OneToOne/Services/NoteFactory.swift`
- Test: `Tests/NoteFactoryTests.swift`

**Interfaces:**
- Consomme : `MeetingKind.note` (tâche 1).
- Produit : `NoteFactory.make(body:title:date:project:collaborator:) -> Meeting`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/NoteFactoryTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteFactory — une note est une réunion avec soi-même")
struct NoteFactoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    @Test("Le kind est note et le corps va dans liveNotes")
    func kindAndBody() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Idée du jour")
        context.insert(note)
        #expect(note.kind == .note)
        #expect(note.liveNotes == "Idée du jour")
    }

    @Test("Le projet est rattaché")
    func projectIsLinked() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)
        let note = NoteFactory.make(body: "REX", title: "REX", project: project)
        context.insert(note)
        #expect(note.project?.code == "REFSI")
    }

    @Test("Le collaborateur devient participant, et le lien survit à la sauvegarde")
    func collaboratorBecomesParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let note = NoteFactory.make(body: "Point de vigilance", collaborator: collab)
        context.insert(note)
        try context.save()

        // Second contexte sur le même conteneur. C'est la seule façon de sortir
        // de la carte d'identité du premier : un `fetch` sur le contexte qui a
        // fait le `save` rend l'instance déjà en mémoire, et l'assertion serait
        // tautologique. Le dépôt ne fait nulle part cette distinction
        // (cf. `Tests/SwiftDataTests.swift`) ; ici elle compte, parce que
        // `NoteFactory` pose la relation AVANT l'insertion.
        let verifier = ModelContext(container)
        let fetchedNotes = try verifier.fetch(FetchDescriptor<Meeting>())
        #expect(fetchedNotes.count == 1)
        #expect(fetchedNotes.first?.participants.map(\.name) == ["Alice"])
        // Côté inverse, relu lui aussi depuis le second contexte.
        let fetchedCollabs = try verifier.fetch(FetchDescriptor<Collaborator>())
        #expect(fetchedCollabs.first?.meetings.count == 1)
    }

    @Test("Sans collaborateur, aucun participant")
    func noCollaboratorMeansNoParticipant() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Note libre")
        context.insert(note)
        #expect(note.participants.isEmpty)
    }
}
```

⚠️ Vérifier la signature réelle de `Collaborator.init` dans `OneToOne/Models/OtherModels.swift`
avant de lancer, et l'ajuster si elle demande d'autres arguments.

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter NoteFactoryTests`
Expected: `cannot find 'NoteFactory' in scope`.

- [ ] **Step 3: Créer `NoteFactory`**

Créer `OneToOne/Services/NoteFactory.swift` :

```swift
import Foundation

/// Fabrique la même note quel que soit le point d'entrée : note rapide du
/// menubar, écran « Notes », section Notes d'une fiche, commandes `/ajout-*`
/// de l'assistant. Une note est un `Meeting` de kind `.note`.
///
/// Le corps va dans `liveNotes` — le champ que relie l'onglet du corps de
/// `MeetingView`. Le nom de ce champ est un héritage (« notes live » d'une
/// réunion enregistrée) ; le renommer traverserait la sauvegarde et les
/// gabarits de rapport, il est donc conservé tel quel.
enum NoteFactory {

    /// Crée une note **sans l'insérer** dans un contexte : l'appelant
    /// `insert` puis `save`, ce qui lui laisse le choix du moment.
    static func make(body: String = "",
                     title: String = "",
                     date: Date = Date(),
                     project: Project? = nil,
                     collaborator: Collaborator? = nil) -> Meeting {
        let note = Meeting(title: title, date: date)
        note.kind = .note
        note.liveNotes = body
        note.project = project
        if let collaborator {
            note.participants = [collaborator]
        }
        return note
    }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter NoteFactoryTests`
Expected: 4 tests verts.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/NoteFactory.swift Tests/NoteFactoryTests.swift
git commit -m "feat(note): fabrique une note comme reunion solo via NoteFactory"
```

---

### Task 3: onglets de `MeetingView` filtrés par kind

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift:162-171` (enum), `:263` (navigationTitle), `:417-423` (mainPanel)
- Modify: `OneToOne/Views/Meeting/MeetingTabsUnderline.swift:5-21`, `:42-53`
- Modify: `OneToOne/Views/Meeting/MeetingTopChromeBar.swift:49-56`
- Test: `Tests/MeetingVisibleSectionsTests.swift`

**Interfaces:**
- Consomme : `MeetingKind.note` (tâche 1).
- Produit : `MeetingView.visibleSections(for kind: MeetingKind) -> [MeetingView.MeetingSection]`
  et `MeetingView.MeetingSection.label(for kind: MeetingKind) -> String`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/MeetingVisibleSectionsTests.swift` :

```swift
import Testing
@testable import OneToOne

@Suite("MeetingView — onglets visibles selon le kind")
struct MeetingVisibleSectionsTests {

    @Test("Une note n'a que son corps et ses documents")
    func noteHasTwoSections() {
        #expect(MeetingView.visibleSections(for: .note) == [.liveNotes, .documents])
    }

    @Test("Un 1:1 garde les six onglets")
    func oneToOneKeepsAll() {
        #expect(MeetingView.visibleSections(for: .oneToOne) == MeetingView.MeetingSection.allCases)
    }

    @Test("L'onglet du corps s'intitule Note pour une note, Notes live sinon")
    func bodyTabLabelFollowsKind() {
        #expect(MeetingView.MeetingSection.liveNotes.label(for: .note) == "Note")
        #expect(MeetingView.MeetingSection.liveNotes.label(for: .oneToOne) == "Notes live")
        #expect(MeetingView.MeetingSection.documents.label(for: .note) == "Documents")
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter MeetingVisibleSectionsTests`
Expected: `type 'MeetingView' has no member 'visibleSections'`.

- [ ] **Step 3: Implémenter les deux fonctions pures**

Dans `OneToOne/Views/MeetingView.swift`, sous l'enum `MeetingSection`, ajouter à l'enum :

```swift
        var id: String { rawValue }

        /// Libellé affiché. Pour une note, « Notes live » n'a pas de sens :
        /// l'onglet du corps s'appelle simplement « Note ».
        func label(for kind: MeetingKind) -> String {
            if self == .liveNotes && kind == .note { return "Note" }
            return rawValue
        }
    }

    /// Onglets visibles pour un kind donné. Une note n'a ni préparation, ni
    /// transcription, ni rapport, ni vue d'ensemble : seulement son corps et
    /// ses pièces jointes.
    static func visibleSections(for kind: MeetingKind) -> [MeetingSection] {
        kind == .note ? [.liveNotes, .documents] : MeetingSection.allCases
    }
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter MeetingVisibleSectionsTests`
Expected: 3 tests verts.

- [ ] **Step 5: Consommer la liste dans la barre d'onglets**

Dans `OneToOne/Views/Meeting/MeetingTabsUnderline.swift`, ajouter deux entrées au-dessus de
`@Namespace` :

```swift
    /// Onglets à afficher, fournis par l'appelant (`MeetingView.visibleSections(for:)`).
    let sections: [MeetingView.MeetingSection]
    /// Kind de la réunion : pilote le libellé de l'onglet du corps.
    let kind: MeetingKind
```

Remplacer `ForEach(MeetingView.MeetingSection.allCases)` par `ForEach(sections)`, et dans
`tab(_:)` remplacer `Text(section.rawValue)` par `Text(section.label(for: kind))`.

Dans `MeetingView.mainPanel` (~ligne 417), passer les deux :

```swift
            MeetingTabsUnderline(
                selection: $activeSection,
                sections: Self.visibleSections(for: meeting.kind),
                kind: meeting.kind,
                attachmentsCount: meeting.attachments.count,
                hasReport: !meeting.summary.isEmpty,
                date: meeting.date,
                isEditingLayout: $isEditingLayout
            )
```

- [ ] **Step 6: Rendre l'onglet actif toujours valide**

Un changement de kind peut laisser `activeSection` sur un onglet devenu invisible. Ajouter sur
`mainPanel` (ou sur le `VStack` du `body`) :

```swift
        .onChange(of: meeting.kind) { _, newKind in
            let visible = Self.visibleSections(for: newKind)
            if !visible.contains(activeSection) {
                activeSection = visible[0]
            }
        }
```

Et à l'ouverture, pour une note créée alors que `activeSection` vaut `.overview` par défaut :

```swift
        .onAppear {
            let visible = Self.visibleSections(for: meeting.kind)
            if !visible.contains(activeSection) {
                activeSection = visible[0]
            }
        }
```

- [ ] **Step 7: Masquer le chrome d'enregistrement pour une note**

Dans `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`, `body` (~ligne 49), envelopper les
quatre contrôles qui n'ont aucun sens sans audio. `breadcrumb` (qui porte le sélecteur de kind,
donc la conversion note → réunion) et `moreMenu` restent toujours visibles :

```swift
            HStack(spacing: 10) {
                breadcrumb
                Spacer()
                if meeting.kind != .note {
                    recorderPill
                    captureButton
                    templatePickerButton
                    reportButton
                }
                moreMenu
            }
```

- [ ] **Step 8: Titre de fenêtre**

Dans `MeetingView` (~ligne 263) :

```swift
        .navigationTitle(meeting.title.isEmpty
                         ? (meeting.kind == .note ? "Note" : "Réunion")
                         : meeting.title)
```

- [ ] **Step 9: Vérifier la suite complète**

Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression.

- [ ] **Step 10: Commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingTabsUnderline.swift \
        OneToOne/Views/Meeting/MeetingTopChromeBar.swift Tests/MeetingVisibleSectionsTests.swift
git commit -m "feat(reunion): filtre les onglets et le chrome selon le kind"
```

---

### Task 4: indexer les réunions dans Spotlight

**Files:**
- Modify: `OneToOne/Services/SpotlightIndexService.swift`
- Modify: `OneToOne/OneToOneApp.swift:259`
- Modify: `OneToOne/Views/SettingsView.swift:1106`
- Modify: `OneToOne/Views/MeetingView.swift` (fermeture, suppression)
- Modify: `OneToOne/Views/MeetingsListView.swift` (suppression)
- Test: `Tests/SpotlightMeetingIndexTests.swift`

**Interfaces:**
- Consomme : `MeetingKind.note` (tâche 1).
- Produit : `SpotlightIndexService.makeMeetingItemForTesting(_:) -> CSSearchableItem`,
  `index(meeting:)`, `remove(meeting:)`,
  `indexAll(projects:collaborators:meetings:)`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/SpotlightMeetingIndexTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("Spotlight — indexation des réunions et des notes")
@MainActor
struct SpotlightMeetingIndexTests {

    @Test("Une note porte son titre et son corps, sans transcription")
    func noteItemCarriesBody() {
        let note = Meeting(title: "Idée archi", date: Date())
        note.kind = .note
        note.liveNotes = "Découpler le module de facturation"
        note.mergedTranscript = "NE DOIT PAS ETRE INDEXE"

        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(note)
        let description = item.attributeSet.contentDescription ?? ""

        #expect(item.attributeSet.displayName == "Idée archi")
        #expect(description.contains("Découpler le module de facturation"))
        #expect(!description.contains("NE DOIT PAS ETRE INDEXE"))
        #expect(item.domainIdentifier == "meetings")
    }

    @Test("Un 1:1 porte son résumé court et le nom du participant en mot-clé")
    func oneToOneItemCarriesSummaryAndParticipant() {
        let meeting = Meeting(title: "1:1 Alice", date: Date())
        meeting.kind = .oneToOne
        meeting.shortSummary = "Montée en charge sur le socle"

        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(meeting)
        #expect((item.attributeSet.contentDescription ?? "").contains("Montée en charge sur le socle"))
        #expect((item.attributeSet.keywords ?? []).contains("OneToOne"))
    }

    @Test("Une réunion sans titre reste identifiable")
    func untitledMeetingHasFallbackName() {
        let meeting = Meeting(title: "", date: Date())
        let item = SpotlightIndexService.shared.makeMeetingItemForTesting(meeting)
        #expect(item.attributeSet.displayName?.isEmpty == false)
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter SpotlightMeetingIndexTests`
Expected: `value of type 'SpotlightIndexService' has no member 'makeMeetingItemForTesting'`.

- [ ] **Step 3: Ajouter la fabrique d'item et les entrées/sorties d'index**

Dans `OneToOne/Services/SpotlightIndexService.swift`, à la suite de `makeCollaboratorItem` :

```swift
    /// Item Spotlight d'une réunion — notes comprises, puisqu'une note est une
    /// réunion de kind `.note`. Les transcriptions (`rawTranscript`,
    /// `mergedTranscript`) sont **volontairement exclues** : elles pèsent des
    /// heures de texte et sont déjà interrogeables par le RAG.
    private func makeMeetingItem(_ meeting: Meeting) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let isNote = meeting.kind == .note
        let fallback = isNote ? "Note sans titre" : "Réunion sans titre"
        let displayName = meeting.title.isEmpty ? fallback : meeting.title

        attributes.title = "OneToOne — \(displayName)"
        attributes.displayName = displayName
        attributes.contentDescription = [
            meeting.date.formatted(date: .abbreviated, time: .omitted),
            meeting.shortSummary,
            meeting.liveNotes,
            meeting.notes
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " | ")

        var keywords = ["OneToOne", meeting.kind.label]
        if isNote { keywords.append("note") }
        if let projectName = meeting.project?.name, !projectName.isEmpty {
            keywords.append(projectName)
        }
        keywords.append(contentsOf: meeting.participants.map(\.name))
        attributes.keywords = keywords.filter { !$0.isEmpty }

        return CSSearchableItem(uniqueIdentifier: meetingIdentifier(meeting),
                                domainIdentifier: "meetings",
                                attributeSet: attributes)
    }

    private func meetingIdentifier(_ meeting: Meeting) -> String {
        "meeting-\(meeting.ensuredStableID.uuidString)"
    }

    /// Test hook only.
    func makeMeetingItemForTesting(_ meeting: Meeting) -> CSSearchableItem {
        makeMeetingItem(meeting)
    }

    func index(meeting: Meeting) {
        CSSearchableIndex.default().indexSearchableItems([makeMeetingItem(meeting)]) { error in
            if let error { print("[Spotlight] Indexing meeting failed: \(error)") }
        }
    }

    func remove(meeting: Meeting) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [meetingIdentifier(meeting)]) { error in
                if let error { print("[Spotlight] Delete meeting failed: \(error)") }
            }
    }
```

⚠️ `makeMeetingItem` appelle `ensuredStableID`, qui **sauvegarde** si l'identifiant était nil
(backfill de migration). C'est voulu et sans danger, mais cela impose que la fabrique tourne sur
le main actor : marquer `SpotlightIndexService` ou ces membres `@MainActor` si le compilateur le
réclame, et déclarer la suite de test `@MainActor` (déjà fait à l'étape 1).

- [ ] **Step 4: Élargir `indexAll` et la requête de diagnostic**

```swift
    func indexAll(projects: [Project], collaborators: [Collaborator], meetings: [Meeting]) {
```

et, dans le corps, après la boucle des collaborateurs :

```swift
        items.append(contentsOf: meetings.map { makeMeetingItem($0) })
```

Dans `fetchIndexedItemCount`, ajouter le domaine à la chaîne de requête :

```swift
        let query = CSSearchQuery(queryString: "domainIdentifier == 'projects' || domainIdentifier == 'project-info' || domainIdentifier == 'project-collaborator-info' || domainIdentifier == 'collaborators' || domainIdentifier == 'meetings'", queryContext: queryContext)
```

(Les deux domaines `project-*` disparaîtront en tâche 12, avec les modèles qu'ils indexent.)

- [ ] **Step 5: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter SpotlightMeetingIndexTests`
Expected: 3 tests verts.

- [ ] **Step 6: Brancher les appelants**

`OneToOne/OneToOneApp.swift:259` — récupérer les réunions comme les projets et collaborateurs
voisins, puis :

```swift
            SpotlightIndexService.shared.indexAll(projects: allProjects,
                                                  collaborators: allCollabs,
                                                  meetings: allMeetings)
```

`OneToOne/Views/SettingsView.swift:1106` — même chose ; ajouter un
`@Query private var meetings: [Meeting]` à la vue si elle n'en a pas.

`OneToOne/Views/MeetingView.swift` — indexer à la **fermeture**, pas à la sauvegarde :
l'éditeur de notes appelle `saveContext()` à chaque frappe (`:567-568`), l'indexation y
martèlerait CoreSpotlight.

```swift
        .onDisappear {
            SpotlightIndexService.shared.index(meeting: meeting)
        }
```

Dans `deleteMeeting()` (~ligne 2637), avant `context.delete(meeting)` :

```swift
        SpotlightIndexService.shared.remove(meeting: meeting)
```

`OneToOne/Views/MeetingsListView.swift`, `deleteMeetings(offsets:)` :

```swift
        for index in offsets {
            SpotlightIndexService.shared.remove(meeting: sorted[index])
            context.delete(sorted[index])
        }
```

- [ ] **Step 7: Vérifier la suite complète**

Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression.

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Services/SpotlightIndexService.swift OneToOne/OneToOneApp.swift \
        OneToOne/Views/SettingsView.swift OneToOne/Views/MeetingView.swift \
        OneToOne/Views/MeetingsListView.swift Tests/SpotlightMeetingIndexTests.swift
git commit -m "feat(spotlight): indexe les reunions et les notes, hors transcriptions"
```

---

### Task 5: l'écran « Notes » sur `Meeting`

**Files:**
- Modify: `OneToOne/Views/AllNotesView.swift` (réécriture)
- Test: `Tests/NoteListFilteringTests.swift`

**Interfaces:**
- Consomme : `NoteFactory.make(...)` (tâche 2), `MeetingKind.note` (tâche 1).
- Produit : `NoteListFilter.matches(_ note: Meeting, query: String, scope: NoteListFilter.Scope) -> Bool`
  et `enum NoteListFilter.Scope { case all, project, collaborator }` — la logique de filtrage
  sort de la vue pour être testable, la vue ne fait plus que l'afficher.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/NoteListFilteringTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NoteListFilter — portée et recherche de l'écran Notes")
struct NoteListFilteringTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("La portée Projet ne garde que les notes rattachées à un projet")
    func projectScope() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)
        let attached = NoteFactory.make(body: "a", project: project)
        let orphan = NoteFactory.make(body: "b")
        context.insert(attached); context.insert(orphan)

        #expect(NoteListFilter.matches(attached, query: "", scope: .project))
        #expect(!NoteListFilter.matches(orphan, query: "", scope: .project))
    }

    @Test("La portée Collaborateur ne garde que les notes avec un participant")
    func collaboratorScope() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        let about = NoteFactory.make(body: "a", collaborator: collab)
        let orphan = NoteFactory.make(body: "b")
        context.insert(about); context.insert(orphan)

        #expect(NoteListFilter.matches(about, query: "", scope: .collaborator))
        #expect(!NoteListFilter.matches(orphan, query: "", scope: .collaborator))
    }

    @Test("La recherche porte sur le titre, le corps, le projet et les participants")
    func searchFields() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let collab = Collaborator(name: "Alice")
        context.insert(project); context.insert(collab)
        let note = NoteFactory.make(body: "Découplage facturation", title: "REX",
                                    project: project, collaborator: collab)
        context.insert(note)

        #expect(NoteListFilter.matches(note, query: "rex", scope: .all))
        #expect(NoteListFilter.matches(note, query: "facturation", scope: .all))
        #expect(NoteListFilter.matches(note, query: "refonte", scope: .all))
        #expect(NoteListFilter.matches(note, query: "alice", scope: .all))
        #expect(!NoteListFilter.matches(note, query: "zzz", scope: .all))
    }

    @Test("La valeur brute du kind note est celle qu'attendent les prédicats SwiftData")
    func rawValueMatchesPredicateLiteral() {
        // Les `#Predicate` filtrent sur `kindRaw`, une colonne stockée, avec le
        // littéral "note" — ils ne peuvent pas traverser le wrapper calculé
        // `kind`, et un initialiseur de `@Query` ne peut pas héberger de `let`
        // préalable. Renommer cette rawValue viderait silencieusement l'écran
        // Notes, la section Notes des fiches, le gabarit de rapport et le
        // contexte de l'assistant. Ce test est le seul garde-fou.
        #expect(MeetingKind.note.rawValue == "note")
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter NoteListFilteringTests`
Expected: `cannot find 'NoteListFilter' in scope`.

- [ ] **Step 3: Extraire le filtre dans `AllNotesView.swift`**

En tête de `OneToOne/Views/AllNotesView.swift`, au-dessus de `struct AllNotesView` :

```swift
/// Filtrage de l'écran « Notes ». Sorti de la vue pour être testable : la vue
/// n'a plus qu'à afficher le résultat.
enum NoteListFilter {

    /// Portée de filtrage. `.all` n'écarte rien ; `.project` ne garde que les
    /// notes rattachées à un projet, `.collaborator` celles qui portent au
    /// moins un participant.
    enum Scope: String, CaseIterable, Identifiable {
        case all = "Toutes"
        case project = "Projet"
        case collaborator = "Collaborateur"
        var id: String { rawValue }
    }

    static func matches(_ note: Meeting, query: String, scope: Scope) -> Bool {
        switch scope {
        case .all: break
        case .project: if note.project == nil { return false }
        case .collaborator: if note.participants.isEmpty { return false }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if note.title.localizedCaseInsensitiveContains(q) { return true }
        if note.liveNotes.localizedCaseInsensitiveContains(q) { return true }
        if note.project?.name.localizedCaseInsensitiveContains(q) == true { return true }
        return note.participants.contains { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter NoteListFilteringTests`
Expected: 3 tests verts.

- [ ] **Step 5: Réécrire la vue sur `Meeting`**

Dans `AllNotesView` :

1. Remplacer la requête :

```swift
    /// `kindRaw` et non `kind` : `#Predicate` travaille sur les colonnes
    /// stockées, pas sur le wrapper calculé. Le littéral "note" est la
    /// `rawValue` de `MeetingKind.note`.
    @Query(filter: #Predicate<Meeting> { $0.kindRaw == "note" },
           sort: \Meeting.date, order: .reverse)
    private var notes: [Meeting]
```

2. `@State private var editingNote: Note?` et `newNote: Note?` → un seul
   `@State private var openedNote: Meeting?`.
3. `scopeFilter` passe de `ScopeFilter` à `NoteListFilter.Scope` ; supprimer l'enum
   `ScopeFilter` local.
4. `filtered` devient :

```swift
    private var filtered: [Meeting] {
        notes.filter { NoteListFilter.matches($0, query: searchText, scope: scopeFilter) }
    }
```

5. Les lignes deviennent des liens de navigation, comme dans `MeetingsListView:414-416` :

```swift
                        ForEach(filtered) { note in
                            NavigationLink {
                                MeetingView(meeting: note)
                            } label: {
                                AllNotesRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    SpotlightIndexService.shared.remove(meeting: note)
                                    context.delete(note)
                                    try? context.save()
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
```

6. La création insère puis ouvre la note :

```swift
    private func startNewNote(project: Project? = nil, collaborator: Collaborator? = nil) {
        let note = NoteFactory.make(project: project, collaborator: collaborator)
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        openedNote = note
    }
```

avec, sur le corps de la vue :

```swift
        .navigationDestination(item: $openedNote) { note in
            MeetingView(meeting: note)
        }
```

7. Adapter `AllNotesRow` : `let note: Meeting` ; `note.body` → `note.liveNotes` ;
   `note.updatedAt` → `note.date` ; `note.collaborator` → `note.participants.first`.

- [ ] **Step 6: Supprimer le tunnel « rapport manager » dupliqué**

`MeetingView` porte déjà ce flux (`ManagerClassificationSheet`, `:271`) et une note est
désormais une réunion : le duplicata n'a plus lieu d'être. Supprimer de `AllNotesView` :
`PendingNoteAdd`, `pendingNoteAdd`, `noteSuggestedCategory`, `noteIsClassifying`,
`noteSuggestedElaboration`, `noteIsElaborating`, `noteInitialElaboration`,
`noteElaborationFromAI`, `noteElaborationFallbackReason`, `noteSnippetFor`,
`startAddToManagerReport`, `confirmAddNote`, le `.sheet(item: $pendingNoteAdd)` et l'entrée
« Ajouter au rapport manager » du menu contextuel. Si `settingsList` / `settings` ne sert plus
à rien, le retirer aussi.

- [ ] **Step 7: Vérifier**

Run: `swift build && swift test --skip CalendarImportEventTests`
Expected: compile ; aucune régression. `NoteEditorSheet` n'est plus référencée ici — elle
disparaît en tâche 6.

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Views/AllNotesView.swift Tests/NoteListFilteringTests.swift
git commit -m "feat(note): l'ecran Notes liste des reunions de kind note"
```

---

### Task 6: `NotesSection` sur `Meeting`

**Files:**
- Modify: `OneToOne/Views/NotesSection.swift` (réécriture, suppression de `NoteEditorSheet` et `NoteRow`)
- Modify: `OneToOne/Views/DetailsViews.swift:655`, `:1223` (appels inchangés, à vérifier)
- Test: `Tests/NotesSectionScopeTests.swift`

**Interfaces:**
- Consomme : `NoteFactory.make(...)`, `NoteListFilter` (tâche 5).
- Produit : `NotesSection.notes(for target: NotesSection.Target, in all: [Meeting]) -> [Meeting]`
  — statique et pure, testable sans monter la vue.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/NotesSectionScopeTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("NotesSection — les notes d'une fiche")
struct NotesSectionScopeTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Une fiche projet ne montre que les notes de ce projet")
    func projectTarget() throws {
        let context = try makeContext()
        let a = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        let b = Project(code: "B", name: "Beta", domain: "d", phase: "Build")
        context.insert(a); context.insert(b)
        let noteA = NoteFactory.make(body: "a", project: a)
        let noteB = NoteFactory.make(body: "b", project: b)
        context.insert(noteA); context.insert(noteB)

        let result = NotesSection.notes(for: .project(a), in: [noteA, noteB])
        #expect(result.map(\.liveNotes) == ["a"])
    }

    @Test("Une fiche collaborateur ne montre que les notes où il participe")
    func collaboratorTarget() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)
        let noteAlice = NoteFactory.make(body: "a", collaborator: alice)
        let noteBob = NoteFactory.make(body: "b", collaborator: bob)
        context.insert(noteAlice); context.insert(noteBob)

        let result = NotesSection.notes(for: .collaborator(alice), in: [noteAlice, noteBob])
        #expect(result.map(\.liveNotes) == ["a"])
    }

    @Test("Une vraie réunion n'est pas une note")
    func heldMeetingIsNotANote() throws {
        let context = try makeContext()
        let project = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        context.insert(project)
        let meeting = Meeting(title: "Comité", date: Date())
        meeting.kind = .project
        meeting.project = project
        context.insert(meeting)

        #expect(NotesSection.notes(for: .project(project), in: [meeting]).isEmpty)
    }

    @Test("Les notes sont triées du plus récent au plus ancien")
    func sortedByDateDescending() throws {
        let context = try makeContext()
        let project = Project(code: "A", name: "Alpha", domain: "d", phase: "Build")
        context.insert(project)
        let old = NoteFactory.make(body: "vieille", date: Date(timeIntervalSince1970: 1_000), project: project)
        let recent = NoteFactory.make(body: "récente", date: Date(timeIntervalSince1970: 2_000), project: project)
        context.insert(old); context.insert(recent)

        #expect(NotesSection.notes(for: .project(project), in: [old, recent]).map(\.liveNotes)
                == ["récente", "vieille"])
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter NotesSectionScopeTests`
Expected: `type 'NotesSection' has no member 'notes'`.

- [ ] **Step 3: Réécrire `NotesSection`**

Remplacer le contenu de `OneToOne/Views/NotesSection.swift` par une section adossée à `Meeting` :

```swift
import SwiftUI
import SwiftData

/// Section « Notes » embarquée dans `ProjectDetailView` ou
/// `CollaboratorDetailView`. Une note est un `Meeting` de kind `.note` : la
/// section liste celles de la cible, du plus récent au plus ancien, et ouvre
/// `MeetingView` — il n'y a plus d'éditeur en feuille.
struct NotesSection: View {

    /// Entité propriétaire des notes affichées.
    enum Target {
        case project(Project)
        case collaborator(Collaborator)
    }

    let target: Target

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Meeting> { $0.kindRaw == "note" },
           sort: \Meeting.date, order: .reverse)
    private var allNotes: [Meeting]
    @State private var openedNote: Meeting?

    /// Notes de la cible, triées du plus récent au plus ancien. Statique et
    /// pure : testable sans monter la vue.
    static func notes(for target: Target, in all: [Meeting]) -> [Meeting] {
        let scoped = all.filter { note in
            guard note.kind == .note else { return false }
            switch target {
            case .project(let p):
                return note.project?.persistentModelID == p.persistentModelID
            case .collaborator(let c):
                return note.participants.contains { $0.persistentModelID == c.persistentModelID }
            }
        }
        return scoped.sorted { $0.date > $1.date }
    }

    private var notes: [Meeting] { Self.notes(for: target, in: allNotes) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Notes", systemImage: "note.text")
                        .font(.headline)
                    Spacer()
                    Button { createNote() } label: {
                        Label("Ajouter", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if notes.isEmpty {
                    Text("Aucune note. Clique « Ajouter » pour en créer une.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(notes) { note in
                            NavigationLink {
                                MeetingView(meeting: note)
                            } label: {
                                NoteRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    SpotlightIndexService.shared.remove(meeting: note)
                                    context.delete(note)
                                    try? context.save()
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .navigationDestination(item: $openedNote) { note in
            MeetingView(meeting: note)
        }
    }

    // ⚠️ `navigationDestination(item:)` doit se trouver dans la pile de
    // navigation qui porte les `NavigationLink` ci-dessus. Si SwiftUI se plaint
    // (« A navigationDestination for … was declared earlier on the stack »), ou
    // si l'ouverture pousse deux fois, retirer ce modificateur et laisser la
    // note nouvellement créée apparaître en tête de liste : l'utilisateur la
    // clique. Vérifier à l'écran avant de conclure.

    private func createNote() {
        let note: Meeting
        switch target {
        case .project(let p):      note = NoteFactory.make(project: p)
        case .collaborator(let c): note = NoteFactory.make(collaborator: c)
        }
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        openedNote = note
    }
}

// MARK: - Row

/// Ligne d'une note : titre (ou première ligne du corps en repli), aperçu et date.
private struct NoteRow: View {
    let note: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Text(note.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    private var displayTitle: String {
        let t = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let firstLine = note.liveNotes.split(separator: "\n").first.map(String.init) ?? ""
        let stripped = firstLine.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? "Sans titre" : String(stripped.prefix(60))
    }

    private var preview: String {
        let lines = note.liveNotes.split(separator: "\n").map(String.init)
        let skipFirst = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let body = skipFirst ? lines.dropFirst() : ArraySlice(lines)
        return body.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
```

`NoteEditorSheet` (ancien `:146-355`) disparaît intégralement, y compris sa gestion de pièces
jointes : celles-ci passent désormais par l'onglet « Documents » de `MeetingView`.

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter NotesSectionScopeTests`
Expected: 4 tests verts.

- [ ] **Step 5: Vérifier les deux montages**

`DetailsViews:655` (`NotesSection(target: .project(project))`) et `:1223`
(`NotesSection(target: .collaborator(collaborator))`) ne changent pas d'appel. Vérifier qu'ils
compilent et qu'aucune autre référence à `NoteEditorSheet` ne subsiste :

Run: `grep -rn "NoteEditorSheet" --include="*.swift" OneToOne Tests`
Expected: aucun résultat.

- [ ] **Step 6: Vérifier la suite complète**

Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Views/NotesSection.swift Tests/NotesSectionScopeTests.swift
git commit -m "feat(note): la section Notes des fiches liste des reunions de kind note"
```

---

### Task 7: note rapide, recherche latérale et gabarit de rapport

**Files:**
- Modify: `OneToOne/Views/Menubar/QuickNotePopover.swift:62-81`
- Modify: `OneToOne/Views/Sidebar.swift:133-150`
- Modify: `OneToOne/Services/ReportTemplating.swift:180-190`
- Test: `Tests/ReportTemplatingCollabNotesTests.swift`

**Interfaces:**
- Consomme : `NoteFactory.make(...)` (tâche 2).
- Produit : rien de nouveau ; ce sont les derniers lecteurs de `Note` qui basculent.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/ReportTemplatingCollabNotesTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ReportTemplating — les notes d'un collaborateur alimentent le gabarit")
@MainActor
struct ReportTemplatingCollabNotesTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Seules les notes du collaborateur remontent, du plus récent au plus ancien")
    func collabNotesAreScopedAndSorted() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        let bob = Collaborator(name: "Bob")
        context.insert(alice); context.insert(bob)

        let old = NoteFactory.make(body: "ancienne", date: Date(timeIntervalSince1970: 1_000), collaborator: alice)
        let recent = NoteFactory.make(body: "récente", date: Date(timeIntervalSince1970: 2_000), collaborator: alice)
        let other = NoteFactory.make(body: "de Bob", collaborator: bob)
        context.insert(old); context.insert(recent); context.insert(other)
        try context.save()

        let rendered = ReportTemplating.collabNotesForTesting(for: alice, in: context)
        #expect(rendered.contains("récente"))
        #expect(rendered.contains("ancienne"))
        #expect(!rendered.contains("de Bob"))
        #expect(rendered.range(of: "récente")!.lowerBound < rendered.range(of: "ancienne")!.lowerBound)
    }

    @Test("Une vraie réunion du collaborateur n'est pas une note")
    func heldMeetingIsExcluded() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        context.insert(alice)
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        meeting.participants = [alice]
        meeting.liveNotes = "contenu du 1:1"
        context.insert(meeting)
        try context.save()

        #expect(!ReportTemplating.collabNotesForTesting(for: alice, in: context).contains("contenu du 1:1"))
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter ReportTemplatingCollabNotesTests`
Expected: `type 'ReportTemplating' has no member 'collabNotesForTesting'`.

- [ ] **Step 3: Repointer `collabNotes` sur les notes-réunions**

Dans `OneToOne/Services/ReportTemplating.swift` — le type qui porte `collabNotes` s'appelle
`TemplateVariableResolver`, **pas** `ReportTemplating` (erreur du plan initial, corrigée en
tâche 7) — remplacer le corps de `collabNotes` :

```swift
    @MainActor
    private static func collabNotes(for collab: Collaborator?, in context: ModelContext) -> String {
        guard let collab else { return "" }
        // Une note est un `Meeting` de kind `.note` dont le collaborateur est
        // participant. `#Predicate` ne sait pas traverser une relation
        // to-many : on filtre le kind côté base, le participant en mémoire.
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.kindRaw == "note" },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let notes = ((try? context.fetch(descriptor)) ?? []).filter { note in
            note.participants.contains { $0.persistentModelID == collab.persistentModelID }
        }
        return notes.prefix(5).map { "- \(Self.truncate($0.liveNotes, to: 200))" }.joined(separator: "\n")
    }

    /// Test hook only.
    @MainActor
    static func collabNotesForTesting(for collab: Collaborator, in context: ModelContext) -> String {
        collabNotes(for: collab, in: context)
    }
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter ReportTemplatingCollabNotesTests`
Expected: 2 tests verts.

- [ ] **Step 5: Note rapide du menubar**

Dans `OneToOne/Views/Menubar/QuickNotePopover.swift`, remplacer `save()` — aucun changement
visuel, seul l'objet créé change :

```swift
    /// Crée une note (`Meeting` de kind `.note`) à partir du texte saisi
    /// (ignorée si vide après trim), la rattache au projet ou au collaborateur
    /// sélectionné le cas échéant, persiste, indexe, puis ferme le popover.
    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var project: Project?
        var collaborator: Collaborator?
        switch linkTarget {
        case .none: break
        case .project(let pid):
            project = projects.first(where: { $0.persistentModelID == pid })
        case .collaborator(let cid):
            collaborator = collaborators.first(where: { $0.persistentModelID == cid })
        }

        let note = NoteFactory.make(body: trimmed, project: project, collaborator: collaborator)
        context.insert(note)
        try? context.save()
        SpotlightIndexService.shared.index(meeting: note)
        onDismiss()
    }
```

- [ ] **Step 6: Recherche de la barre latérale**

Dans `OneToOne/Views/Sidebar.swift`, `noteMatches` (~ligne 146) et les deux prédicats qui
l'appellent. `Project` et `Collaborator` n'ont plus de relation `notes` : le rapprochement passe
par les réunions. Ajouter à la vue une requête de notes si elle n'en a pas :

```swift
    @Query(filter: #Predicate<Meeting> { $0.kindRaw == "note" })
    private var allNotes: [Meeting]
```

puis :

```swift
    private func projectMatches(_ p: Project, _ q: String) -> Bool {
        p.name.localizedCaseInsensitiveContains(q) ||
        p.code.localizedCaseInsensitiveContains(q) ||
        p.domain.localizedCaseInsensitiveContains(q) ||
        notes(ofProject: p).contains(where: { noteMatches($0, q) })
    }

    private func collabMatches(_ c: Collaborator, _ q: String) -> Bool {
        c.name.localizedCaseInsensitiveContains(q) ||
        c.role.localizedCaseInsensitiveContains(q) ||
        notes(ofCollaborator: c).contains(where: { noteMatches($0, q) })
    }

    private func notes(ofProject p: Project) -> [Meeting] {
        allNotes.filter { $0.project?.persistentModelID == p.persistentModelID }
    }

    private func notes(ofCollaborator c: Collaborator) -> [Meeting] {
        allNotes.filter { note in
            note.participants.contains { $0.persistentModelID == c.persistentModelID }
        }
    }

    private func noteMatches(_ n: Meeting, _ q: String) -> Bool {
        n.title.localizedCaseInsensitiveContains(q) ||
        n.liveNotes.localizedCaseInsensitiveContains(q)
    }
```

- [ ] **Step 7: Vérifier qu'il ne reste aucun lecteur de `Note`**

Run: `grep -rn "\bNote(" --include="*.swift" OneToOne | grep -v "NoteFactory\|QuickNote\|MarkdownNote"`
Expected: aucun résultat.
Run: `swift build && swift test --skip CalendarImportEventTests`
Expected: compile ; aucune régression.

- [ ] **Step 8: Commit**

```bash
git add OneToOne/Views/Menubar/QuickNotePopover.swift OneToOne/Views/Sidebar.swift \
        OneToOne/Services/ReportTemplating.swift Tests/ReportTemplatingCollabNotesTests.swift
git commit -m "feat(note): note rapide, recherche laterale et gabarit sur les reunions de kind note"
```

---

### Task 8: supprimer `Note` et `NoteAttachment`

**Files:**
- Delete: `OneToOne/Models/Note.swift`
- Modify: `OneToOne/Models/Project.swift:114-115`
- Modify: `OneToOne/Models/OtherModels.swift:75-76`
- Modify: `OneToOne/Models/SchemaVersions.swift:46-47`
- Modify: `OneToOne/OneToOneApp.swift:361-363` — `repairStoreIfNeeded` déduplique les
  `NoteAttachment.stableID` au démarrage ; ce bloc part avec le modèle. **Omission du plan
  initial, trouvée en tâche 7 : sans lui, cette tâche ne compile pas.**
- Modify: `OneToOne/Views/MeetingsListView.swift:102-108`, `:165`
- ~~`OneToOne/Views/ChatbotView.swift`~~ — **déjà fait en tâche 7** (son `@Query` de notes était
  un lecteur vivant de `Note` qu'il fallait basculer pour tenir la postcondition de cette
  tâche-là). Ne reste qu'à vérifier.
- Modify: `Tests/ManagerCRGeneratorTests.swift:23`, `Tests/ManagerReportServiceTests.swift:16`

**Interfaces:**
- Consomme : tâches 5 à 7 (plus aucun lecteur de `Note`).
- Produit : un schéma sans `Note` ni `NoteAttachment`.

- [ ] **Step 1: Vérifier le contexte du chatbot (déjà basculé en tâche 7)**

`ChatbotView` lisait `Note` par un `@Query` ; la tâche 7 l'a basculé sur
`#Predicate<Meeting> { $0.kindRaw == "note" }`, avec `n.liveNotes` au lieu de `n.body`,
`n.date` au lieu de `n.updatedAt`, et `n.participants.first?.name` au lieu de
`n.collaborator?.name`. Il n'y a donc rien à écrire ici — seulement à confirmer :

Run: `grep -n "Note\b" OneToOne/Views/ChatbotView.swift | grep -v "NoteFactory\|// \|/// "`
Expected: aucun résultat.

- [ ] **Step 1 bis: Retirer la déduplication des `NoteAttachment` au démarrage**

Dans `OneToOne/OneToOneApp.swift` (~ligne 361), `repairStoreIfNeeded` déduplique les
`stableID` de plusieurs modèles. Supprimer le bloc qui vise `NoteAttachment` :

```swift
            deduplicateOptional(context: context, label: "NoteAttachment",
                                fetch: FetchDescriptor<NoteAttachment>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
```

Les autres appels à `deduplicateOptional` restent. Sans cette suppression, la tâche ne compile
pas — le modèle disparaît à l'étape 3.

- [ ] **Step 2: Exclure les notes de la liste des réunions**

Dans `OneToOne/Views/MeetingsListView.swift`, `filteredMeetings` (~`:102`), première ligne :

```swift
        // Les notes ont leur propre écran ; les mêler aux réunions rendrait le
        // compteur et les filtres de cette liste ambigus.
        var result = MeetingStatsScope.held(meetings)
```

et dans le menu de filtre Type (~`:165`), n'offrir que les kinds réellement présents ici :

```swift
                    ForEach(MeetingKind.allCases.filter { $0 != .note }) { kind in
```

- [ ] **Step 3: Supprimer le modèle et ses relations**

```bash
git rm OneToOne/Models/Note.swift
```

Dans `OneToOne/Models/Project.swift`, supprimer les lignes 114-115 :

```swift
    @Relationship(deleteRule: .cascade, inverse: \Note.project)
    var notes: [Note] = []
```

Dans `OneToOne/Models/OtherModels.swift`, supprimer les lignes 75-76 (même bloc sur
`Collaborator`).

Dans `OneToOne/Models/SchemaVersions.swift`, retirer `Note.self,` et `NoteAttachment.self,` de
`SchemaV1.models`.

- [ ] **Step 4: Mettre à jour les conteneurs de test**

Retirer `Note.self` de la liste `Schema([...])` dans `Tests/ManagerCRGeneratorTests.swift:23`
et `Tests/ManagerReportServiceTests.swift:16`.

- [ ] **Step 5: Vérifier**

Run: `grep -rn "\bNote\b\|NoteAttachment" --include="*.swift" OneToOne Tests | grep -v "NoteFactory\|QuickNote\|MarkdownNote\|NoteMerge\|NoteRow\|NoteList\|NotesSection\|liveNotes\|prepNotes\|followUpNotes\|standingPrepNotes\|// \|/// "`
Expected: aucun résultat (hors commentaires et noms composés).
Run: `swift build && swift test --skip CalendarImportEventTests`
Expected: compile ; aucune régression.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Models/Note.swift OneToOne/Models/Project.swift \
        OneToOne/Models/OtherModels.swift OneToOne/Models/SchemaVersions.swift \
        OneToOne/Views/ChatbotView.swift OneToOne/Views/MeetingsListView.swift \
        Tests/ManagerCRGeneratorTests.swift Tests/ManagerReportServiceTests.swift
git status --short   # rien d'etranger ne doit etre indexe
git commit -m "refactor(modele): supprime Note et NoteAttachment, remplaces par le kind note"
```

---

### Task 9: les commandes de l'assistant vers leur modèle naturel

**Files:**
- Create: `OneToOne/Services/ChatbotEntryCommands.swift`
- Modify: `OneToOne/Views/ChatbotView.swift:63-78` (définitions), `:754-757` (dispatch),
  `:905-940` (`handleProjectInfoCommand`), `:940-980` (`handleCollaboratorProjectCommand`),
  `:1070-1160` (recherche locale), `:709-711` et `:763` (textes d'aide)
- Test: `Tests/ChatbotEntryCommandsTests.swift`

**Interfaces:**
- Consomme : `NoteFactory.make(...)` (tâche 2).
- Produit : `ChatbotEntryCommands.addProjectInfo(content:project:in:) throws -> Meeting`,
  `addCollaboratorInfo(content:project:collaborator:in:) throws -> Meeting`,
  `addCollaboratorAction(content:project:collaborator:in:) throws -> ActionTask`.

Les gestionnaires actuels sont des méthodes privées d'une `View` : intestables. L'écriture est
donc extraite dans un service ; la vue garde l'analyse de la saisie et les messages de retour.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Tests/ChatbotEntryCommandsTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Commandes /ajout-* — chaque entrée vers son modèle naturel")
@MainActor
struct ChatbotEntryCommandsTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Une info projet en phase Build devient une note titrée REX")
    func projectInfoOnBuildIsRex() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        context.insert(project)

        let note = try ChatbotEntryCommands.addProjectInfo(
            content: "Le socle a tenu la charge", project: project, in: context)

        #expect(note.kind == .note)
        #expect(note.title == "REX")
        #expect(note.liveNotes == "Le socle a tenu la charge")
        #expect(note.project?.code == "REFSI")
    }

    @Test("Une info projet hors phase Build devient une note titrée Info projet")
    func projectInfoOutsideBuild() throws {
        let context = try makeContext()
        let project = Project(code: "DATA24", name: "Plateforme Data", domain: "Data", phase: "Run")
        context.insert(project)

        let note = try ChatbotEntryCommands.addProjectInfo(
            content: "Cadrage lancé", project: project, in: context)
        #expect(note.title == "Info projet")
    }

    @Test("Une info collaborateur devient une note où il est participant")
    func collaboratorInfoBecomesNote() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        context.insert(project); context.insert(alice)

        let note = try ChatbotEntryCommands.addCollaboratorInfo(
            content: "Monte en compétence sur le socle",
            project: project, collaborator: alice, in: context)

        #expect(note.kind == .note)
        #expect(note.title == "Info Alice")
        #expect(note.participants.map(\.name) == ["Alice"])
        #expect(note.project?.code == "REFSI")
    }

    @Test("Une action collaborateur devient un ActionTask, et aucune note")
    func collaboratorActionBecomesTask() throws {
        let context = try makeContext()
        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        context.insert(project); context.insert(alice)

        let task = try ChatbotEntryCommands.addCollaboratorAction(
            content: "Rédiger la DAT", project: project, collaborator: alice, in: context)

        #expect(task.title == "Rédiger la DAT")
        #expect(task.destinataire == .collaborateur)
        #expect(task.collaborator?.name == "Alice")
        #expect(task.project?.code == "REFSI")
        #expect(!task.isCompleted)

        let notes = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.kindRaw == "note" }))
        #expect(notes.isEmpty)
    }
}
```

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter ChatbotEntryCommandsTests`
Expected: `cannot find 'ChatbotEntryCommands' in scope`.

- [ ] **Step 3: Créer le service**

Créer `OneToOne/Services/ChatbotEntryCommands.swift` :

```swift
import Foundation
import SwiftData

/// Écritures des commandes `/ajout-*` de l'assistant. Sorties de la vue pour
/// être testables : `ChatbotView` garde l'analyse de la saisie et les messages
/// de retour, ce service crée les objets.
///
/// Chaque entrée va vers son modèle naturel : une information devient une note
/// (`Meeting` de kind `.note`), une action devient un `ActionTask` — elle porte
/// un état d'achèvement, elle appartient donc à la vue « Actions ».
@MainActor
enum ChatbotEntryCommands {

    /// Information datée sur un projet. Le titre porte la catégorie que
    /// `ProjectInfoEntry` stockait dans un champ dédié.
    static func addProjectInfo(content: String,
                               project: Project,
                               in context: ModelContext) throws -> Meeting {
        let title = project.phase == "Build" ? "REX" : "Info projet"
        let note = NoteFactory.make(body: content, title: title, project: project)
        context.insert(note)
        try context.save()
        SpotlightIndexService.shared.index(meeting: note)
        return note
    }

    /// Information sur un collaborateur dans le contexte d'un projet.
    static func addCollaboratorInfo(content: String,
                                    project: Project,
                                    collaborator: Collaborator,
                                    in context: ModelContext) throws -> Meeting {
        let note = NoteFactory.make(body: content,
                                    title: "Info \(collaborator.name)",
                                    project: project,
                                    collaborator: collaborator)
        context.insert(note)
        try context.save()
        SpotlightIndexService.shared.index(meeting: note)
        return note
    }

    /// Action déléguée à un collaborateur sur un projet.
    static func addCollaboratorAction(content: String,
                                      project: Project,
                                      collaborator: Collaborator,
                                      in context: ModelContext) throws -> ActionTask {
        let task = ActionTask(title: content)
        task.project = project
        task.collaborator = collaborator
        task.destinataire = .collaborateur
        context.insert(task)
        try context.save()
        return task
    }
}
```

- [ ] **Step 4: Lancer le test et vérifier qu'il passe**

Run: `swift test --filter ChatbotEntryCommandsTests`
Expected: 4 tests verts.

- [ ] **Step 5: Brancher `ChatbotView` sur le service**

Dans `handleProjectInfoCommand`, remplacer le bloc de création par :

```swift
        do {
            let note = try ChatbotEntryCommands.addProjectInfo(
                content: content, project: project, in: context)
            return "Information ajoutee au projet \(project.name) [\(note.title)] avec la date du jour."
        } catch {
            return "Impossible d'ajouter l'information: \(error.localizedDescription)"
        }
```

Remplacer le paramètre `kind: String` de `handleCollaboratorProjectCommand` par un discriminant
typé, déclaré dans la vue :

```swift
    /// Nature de l'entrée créée par les commandes `/ajout-*-collab-projet`.
    private enum CollaboratorEntryKind { case information, action }
```

Dispatch (`:754-757`) :

```swift
        if let response = handleCollaboratorProjectCommand(trimmed, commandPrefix: "/ajout-info-collab-projet", entryKind: .information) {
            return response
        }
        if let response = handleCollaboratorProjectCommand(trimmed, commandPrefix: "/ajout-action-collab-projet", entryKind: .action) {
            return response
        }
```

Fin du corps de `handleCollaboratorProjectCommand` :

```swift
        do {
            switch entryKind {
            case .information:
                _ = try ChatbotEntryCommands.addCollaboratorInfo(
                    content: content, project: project, collaborator: collaborator, in: context)
                return "Information ajoutee pour \(collaborator.name) sur le projet \(project.name)."
            case .action:
                _ = try ChatbotEntryCommands.addCollaboratorAction(
                    content: content, project: project, collaborator: collaborator, in: context)
                return "Action ajoutee pour \(collaborator.name) sur le projet \(project.name)."
            }
        } catch {
            return "Impossible d'ajouter l'entree: \(error.localizedDescription)"
        }
```

- [ ] **Step 6: Repointer les trois réponses hors-ligne**

`responseForProjectInfoQuery` (~`:1080`) — les notes du projet :

```swift
        let lines = matchingProjects.map { project in
            let projectNotes = notes.filter { $0.project?.persistentModelID == project.persistentModelID }
                .sorted(by: { $0.date > $1.date }).prefix(5)
            let details = projectNotes.isEmpty
                ? "Aucune information datee."
                : projectNotes.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)) [\($0.title)] \($0.liveNotes)" }.joined(separator: "\n")
            return "Projet \(project.name):\n\(details)"
        }
```

`responseForRexQuery` (~`:1128`) — les notes titrées `REX` :

```swift
        func rexNotes(of project: Project) -> [Meeting] {
            notes.filter {
                $0.project?.persistentModelID == project.persistentModelID && $0.title == "REX"
            }
            .sorted(by: { $0.date > $1.date })
        }

        let sourceProjects = matchingProjects.isEmpty
            ? projects.filter { !rexNotes(of: $0).isEmpty }
            : matchingProjects
        guard !sourceProjects.isEmpty else { return "Aucun REX projet trouve." }

        let sections = sourceProjects.sorted(by: { $0.name < $1.name }).map { project in
            let lines = rexNotes(of: project).prefix(5)
                .map { "- \($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.liveNotes)" }
            return "Projet \(project.name):\n" + (lines.isEmpty ? "- Aucun REX date" : lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
```

`responseForCollaboratorProjectQuery` (~`:1148`) — les notes d'un projet où un collaborateur
participe. Remplacer le `flatMap` sur `project.collaboratorEntries` par :

```swift
        let entries: [(Project, Meeting)] = notes.compactMap { note in
            guard let project = note.project else { return nil }
            let projectMatch = matchingProjects.isEmpty
                || matchingProjects.contains(where: { $0.persistentModelID == project.persistentModelID })
            let collaboratorMatch = matchingCollaborators.isEmpty
                || note.participants.contains(where: { participant in
                    matchingCollaborators.contains(where: { $0.persistentModelID == participant.persistentModelID })
                })
            guard projectMatch && collaboratorMatch else { return nil }
            return (project, note)
        }
```

et adapter le rendu en dessous : `entry.date` → `note.date`, `entry.content` → `note.liveNotes`,
`entry.collaborator?.name` → `note.participants.first?.name`.

- [ ] **Step 7: Mettre à jour les textes d'aide**

Dans les définitions `SlashCommandDef` (`:63-78`), le repli hors-ligne (`:709-711`) et le message
« Commande inconnue » (`:763`) : `/cherche` accepte désormais `type:note` en plus de
`type:1:1|projet|archi|globale`. Ajouter `note` à la liste des types acceptés par
`handleSearchCommand`, et aux trois textes.

- [ ] **Step 8: Vérifier**

Run: `swift build && swift test --skip CalendarImportEventTests`
Expected: compile ; aucune régression.

- [ ] **Step 9: Commit**

```bash
git add OneToOne/Services/ChatbotEntryCommands.swift OneToOne/Views/ChatbotView.swift \
        Tests/ChatbotEntryCommandsTests.swift
git commit -m "feat(assistant): les commandes ajout creent une note ou une action"
```

---

### Task 10: retirer les deux sections de la fiche projet

**Files:**
- Modify: `OneToOne/Views/DetailsViews.swift:204-267`, `:269-355`, `:753-775`

**Interfaces:**
- Consomme : `NotesSection` réécrite (tâche 6).
- Produit : rien.

- [ ] **Step 1: Supprimer les deux `GroupBox`**

Dans `OneToOne/Views/DetailsViews.swift`, supprimer intégralement :

- le `GroupBox` des lignes **204 à 267** — titre « REX / Infos projet » ou
  « Infos projet / OneToOne » selon la phase ;
- le `GroupBox` des lignes **269 à 355** — « Informations / actions collaborateurs ».

`NotesSection(target: .project(project))` (ligne 655) reprend les informations ; les actions
collaborateur passent par la vue « Actions » via `ActionTask`.

- [ ] **Step 2: Supprimer les fonctions devenues orphelines**

`addProjectInfoEntry` (`:753`), `deleteProjectInfoEntry` (`:761`) et la fonction qui crée un
`ProjectCollaboratorEntry` (`:769`), ainsi que les `@State` qui ne servaient qu'à ces sections
(dont `selectedCollaboratorForProjectEntry`). Le compilateur signale les restes.

- [ ] **Step 3: Vérifier**

Run: `swift build`
Expected: compile sans avertissement de variable inutilisée.
Run: `grep -n "ProjectInfoEntry\|ProjectCollaboratorEntry" OneToOne/Views/DetailsViews.swift`
Expected: aucun résultat.
Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/DetailsViews.swift
git status --short   # rien d'etranger ne doit etre indexe
git commit -m "refactor(projet): retire les sections d'entrees datees de la fiche projet"
```

---

### Task 11: `MailProjectMatcher` sur les participants des réunions

**Files:**
- Modify: `OneToOne/Services/MailProjectMatcher.swift:42-53`
- Modify: `OneToOne/Services/MailAutoIndexService.swift:125-126`
- Test: `Tests/MailProjectMatcherTests.swift` (ajout d'une suite)

**Interfaces:**
- Consomme : rien.
- Produit : `MailProjectMatcher.projectEntries(from projects: [Project], meetings: [Meeting]) -> [ProjectEntry]`
  (signature élargie ; l'ancienne disparaît).

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter à `Tests/MailProjectMatcherTests.swift` :

```swift
    func test_projectEntries_agregeLesEmailsDesParticipantsDesReunions() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        alice.email = "Alice@April.com"
        let manager = Collaborator(name: "Manager")
        manager.email = "manager@april.com"
        project.projectManager = manager
        context.insert(project); context.insert(alice); context.insert(manager)

        let meeting = Meeting(title: "Comité", date: Date())
        meeting.kind = .project
        meeting.project = project
        meeting.participants = [alice]
        context.insert(meeting)

        let entries = MailProjectMatcher.projectEntries(from: [project], meetings: [meeting])
        #expect(entries.count == 1)
        #expect(entries[0].collaboratorEmails.contains("alice@april.com"))
        #expect(entries[0].collaboratorEmails.contains("manager@april.com"))
    }

    func test_projectEntries_dedoublonneLesEmails() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let project = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let alice = Collaborator(name: "Alice")
        alice.email = "alice@april.com"
        context.insert(project); context.insert(alice)

        var meetings: [Meeting] = []
        for index in 0..<3 {
            let meeting = Meeting(title: "Comité \(index)", date: Date())
            meeting.kind = .project
            meeting.project = project
            meeting.participants = [alice]
            context.insert(meeting)
            meetings.append(meeting)
        }

        let entries = MailProjectMatcher.projectEntries(from: [project], meetings: meetings)
        XCTAssertEqual(entries[0].collaboratorEmails.filter { $0 == "alice@april.com" }.count, 1)
    }

    func test_projectEntries_ignoreLesReunionsDUnAutreProjet() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let refsi = Project(code: "REFSI", name: "Refonte SI", domain: "Courtage", phase: "Build")
        let data = Project(code: "DATA24", name: "Plateforme Data", domain: "Data", phase: "Run")
        let bob = Collaborator(name: "Bob")
        bob.email = "bob@april.com"
        context.insert(refsi); context.insert(data); context.insert(bob)

        let meeting = Meeting(title: "Comité Data", date: Date())
        meeting.kind = .project
        meeting.project = data
        meeting.participants = [bob]
        context.insert(meeting)

        let entries = MailProjectMatcher.projectEntries(from: [refsi], meetings: [meeting])
        XCTAssertFalse(entries[0].collaboratorEmails.contains("bob@april.com"))
    }
```

⚠️ `MailProjectMatcherTests` est un fichier **XCTest** : ces trois cas sont donc écrits en
XCTest (`XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertFalse`) et non en Swift Testing, pour
rester homogène avec le fichier. Remplacer les `#expect` du premier cas par des `XCTAssertTrue`
en conséquence, et ajouter `import SwiftData` en tête du fichier s'il n'y est pas.

- [ ] **Step 2: Lancer le test et vérifier qu'il échoue**

Run: `swift test --filter MailProjectMatcherTests`
Expected: erreur d'arité — `extra argument 'meetings' in call`.

- [ ] **Step 3: Élargir `projectEntries`**

Dans `OneToOne/Services/MailProjectMatcher.swift` :

```swift
    /// Prépare les entrées de matching depuis les projets actifs.
    ///
    /// Les emails viennent des **participants des réunions du projet** —
    /// c'est le signal réel : les entrées collaborateur typées qui servaient
    /// autrefois de source n'ont jamais été alimentées. `Meeting.project`
    /// n'a pas de relation inverse déclarée, les réunions sont donc fournies
    /// par l'appelant.
    static func projectEntries(from projects: [Project], meetings: [Meeting]) -> [ProjectEntry] {
        projects.filter { !$0.isArchived }.map { p in
            var emails = meetings
                .filter { $0.project?.persistentModelID == p.persistentModelID }
                .flatMap { $0.participants }
                .map { $0.email.lowercased() }
            if let e = p.projectManager?.email.lowercased() { emails.append(e) }
            if let e = p.technicalArchitect?.email.lowercased() { emails.append(e) }

            var seen = Set<String>()
            let unique = emails.filter { !$0.isEmpty && seen.insert($0).inserted }
            return ProjectEntry(code: p.code, name: p.name, collaboratorEmails: unique)
        }
    }
```

- [ ] **Step 4: Adapter l'appelant**

Dans `OneToOne/Services/MailAutoIndexService.swift` (~`:125`) :

```swift
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        let entries = MailProjectMatcher.projectEntries(from: projects, meetings: meetings)
```

- [ ] **Step 5: Lancer les tests et vérifier qu'ils passent**

Run: `swift test --filter MailProjectMatcherTests`
Expected: tous verts, y compris les cas préexistants (ils construisent des `ProjectEntry` à la
main et ne sont pas concernés par la nouvelle signature).

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/MailProjectMatcher.swift OneToOne/Services/MailAutoIndexService.swift \
        Tests/MailProjectMatcherTests.swift
git commit -m "feat(mail): tire les emails de projet des participants des reunions"
```

---

### Task 12: supprimer `ProjectInfoEntry` et `ProjectCollaboratorEntry`

**Files:**
- Modify: `OneToOne/Models/Project.swift:105-109`, `:148-180` (les deux `@Model`)
- Modify: `OneToOne/Models/SchemaVersions.swift:29-30`
- Modify: `OneToOne/Services/BackupService.swift:59-66`, `:110-111`, `:344-350`, `:603`, `:645-660`
- Modify: `OneToOne/Services/SpotlightIndexService.swift:16-17`, `:38`, `:57-58`, `:70`, `:109-155`
- Modify: `Tests/ManagerCRGeneratorTests.swift:21`, `Tests/ManagerReportServiceTests.swift:14`,
  `Tests/QuickLaunchRouterTests.swift:14`, `Tests/QuickLaunchURLHandlerTests.swift:15`

**Interfaces:**
- Consomme : tâches 9 à 11 (plus aucun lecteur des deux modèles).
- Produit : un schéma sans les deux modèles.

- [ ] **Step 1: Vérifier qu'il ne reste aucun lecteur**

Run: `grep -rn "ProjectInfoEntry\|ProjectCollaboratorEntry\|infoEntries\|collaboratorEntries" --include="*.swift" OneToOne Tests`
Expected: uniquement les déclarations de modèle, les relations de `Project`, `SchemaVersions`,
`BackupService`, `SpotlightIndexService` et les quatre conteneurs de test — c'est-à-dire
exactement ce que cette tâche supprime. **Tout autre résultat signale une tâche précédente
incomplète : s'arrêter et la reprendre.**

- [ ] **Step 2: Nettoyer `SpotlightIndexService`**

Supprimer `makeInfoItem`, `makeCollaboratorEntryItem`, `infoIdentifier`,
`collaboratorEntryIdentifier`, et les quatre lignes qui les appellent dans `indexAll` (`:16-17`),
`index(project:)` (`:57-58`) et `remove(project:)` (`:70`). Cette dernière devient :

```swift
    /// Retire un projet de l'index. Idempotent : supprimer un identifiant absent
    /// de l'index est sans effet (no-op).
    func remove(project: Project) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [projectIdentifier(project)]) { error in
            if let error {
                print("[Spotlight] Delete failed: \(error)")
            }
        }
    }
```

Retirer les deux domaines morts de `fetchIndexedItemCount` :

```swift
        let query = CSSearchQuery(queryString: "domainIdentifier == 'projects' || domainIdentifier == 'collaborators' || domainIdentifier == 'meetings'", queryContext: queryContext)
```

Et corriger le commentaire d'en-tête qui énumère les domaines (`:78-82`) : il ne reste que
`projects`, `collaborators` et `meetings`.

- [ ] **Step 3: Nettoyer `BackupService`**

Supprimer `ProjectInfoEntryDTO` (`:59-64`) et `ProjectCollaboratorEntryDTO` (`:65-70`), les deux
propriétés de `ProjectDTO` (`:110-111`), les deux `map` de l'export (`:344-350`), la variable
`pendingCollaboratorEntries` (`:603`) et les deux boucles d'import (`:645-660`).

Ajouter au commentaire d'en-tête du fichier :

```swift
// Les sauvegardes écrites avant la fusion Note/Réunion contiennent encore des
// clés `infoEntries` et `collaboratorEntries` : `JSONDecoder` ignore les clés
// qu'aucune propriété ne réclame, elles restent donc lisibles. Ces tableaux
// étaient vides dans toutes les bases connues.
```

- [ ] **Step 4: Supprimer les modèles et leurs relations**

Dans `OneToOne/Models/Project.swift` : supprimer les deux blocs de relation (`:105-109`) et les
deux déclarations `@Model` `ProjectInfoEntry` (`:147-159`) et `ProjectCollaboratorEntry`
(`:161-180`), commentaires de documentation compris.

Dans `OneToOne/Models/SchemaVersions.swift` : retirer `ProjectInfoEntry.self,` et
`ProjectCollaboratorEntry.self,` de `SchemaV1.models`.

Mettre à jour le commentaire d'en-tête de `SchemaV1` pour consigner l'écart assumé :

```swift
/// ⚠️ Quatre types ont été retirés le 2026-08-10 (`Note`, `NoteAttachment`,
/// `ProjectInfoEntry`, `ProjectCollaboratorEntry`) **sans** créer de `SchemaV2` :
/// leurs tables étaient vides dans toutes les bases connues, et le snapshot
/// nested n'existe que pour préserver des données. Voir
/// `docs/superpowers/specs/2026-08-10-fusion-note-reunion-design.md`.
```

- [ ] **Step 5: Mettre à jour les quatre conteneurs de test**

Retirer `ProjectInfoEntry.self,` et `ProjectCollaboratorEntry.self,` des listes `Schema([...])`
de `Tests/ManagerCRGeneratorTests.swift`, `Tests/ManagerReportServiceTests.swift`,
`Tests/QuickLaunchRouterTests.swift`, `Tests/QuickLaunchURLHandlerTests.swift`.

- [ ] **Step 6: Vérifier**

Run: `grep -rn "ProjectInfoEntry\|ProjectCollaboratorEntry\|infoEntries\|collaboratorEntries" --include="*.swift" OneToOne Tests`
Expected: aucun résultat.
Run: `swift build && swift test --skip CalendarImportEventTests`
Expected: compile ; aucune régression.

- [ ] **Step 7: Commit**

```bash
git add OneToOne/Models/Project.swift OneToOne/Models/SchemaVersions.swift \
        OneToOne/Services/BackupService.swift OneToOne/Services/SpotlightIndexService.swift \
        Tests/ManagerCRGeneratorTests.swift Tests/ManagerReportServiceTests.swift \
        Tests/QuickLaunchRouterTests.swift Tests/QuickLaunchURLHandlerTests.swift
git status --short   # rien d'etranger ne doit etre indexe
git commit -m "refactor(modele): supprime les entrees datees projet, vides et remplacees par les notes"
```

---

### Task 13: vérification sur données réelles et clôture

**Files:**
- Modify: `STATUS.md`

**Interfaces:**
- Consomme : toutes les tâches précédentes.
- Produit : la preuve que la migration passe sur le store réel.

Cette tâche ne contient pas de code : c'est la seule garantie que le plan ne peut pas
automatiser (simuler l'ancien schéma exigerait de conserver les classes supprimées).

- [ ] **Step 1: Sauvegarder le store réel**

```bash
cp -R ~/Library/Application\ Support/OneToOne \
      ~/Library/Application\ Support/OneToOne.backup-2026-08-10-fusion-note
ls -la ~/Library/Application\ Support/OneToOne.backup-2026-08-10-fusion-note/OneToOne.store
```

Expected: le fichier existe et pèse environ 33 Mo.

- [ ] **Step 2: Relever l'état avant**

```bash
sqlite3 ~/Library/Application\ Support/OneToOne.backup-2026-08-10-fusion-note/OneToOne.store \
  "select count(*) from ZMEETING;" "select count(*) from ZNOTE;"
```

Expected: `163` puis `0`. Si `ZNOTE` n'est plus à zéro, **arrêter** : la prémisse de la
suppression sans `SchemaV2` ne tient plus, il faut un `SchemaV2` avec un stage de migration.

- [ ] **Step 3: Construire et lancer**

```bash
Scripts/bump-and-build.sh dev
```

Expected: l'app démarre sans erreur de migration. En cas d'échec CoreData :

```bash
rm -rf ~/Library/Application\ Support/OneToOne
cp -R ~/Library/Application\ Support/OneToOne.backup-2026-08-10-fusion-note \
      ~/Library/Application\ Support/OneToOne
```

puis reprendre avec un `SchemaV2` (snapshot nested + `MigrationStage`).

- [ ] **Step 4: Dérouler les huit contrôles à l'écran**

1. note rapide depuis le menubar → elle apparaît dans « Notes » ;
2. l'ouvrir → deux onglets (« Note », « Documents »), pas six, pas de barre d'enregistrement ;
3. changer son kind en « One-to-One » dans le fil d'Ariane → les six onglets reviennent ;
4. temps passé du menubar et heatmap d'un projet **inchangés** après création d'une note ;
5. fiche collaborateur → la note est dans la section Notes et **pas** en double dans le
   `GroupBox("Réunions")` ;
6. fiche projet → les deux anciens `GroupBox` d'entrées datées ont disparu, la section Notes
   les remplace ;
7. Réglages → réindexer Spotlight, puis rechercher dans Spotlight un mot présent dans une note
   → elle remonte, **et cliquer le résultat ouvre bien la note** (le routage est couvert par des
   tests, l'ouverture réelle ne l'est pas) ;
7 bis. depuis l'écran « Notes », cliquer « Nouvelle note » → la note s'ouvre **une seule fois**,
   sans double poussée de navigation et sans avertissement SwiftUI en console
   (« A navigationDestination for … was declared earlier on the stack »). C'est le seul contrôle
   qui peut trancher la cohabitation `NavigationLink` + `navigationDestination(item:)` ; si elle
   se révèle fautive, le repli est de retirer ce modificateur et de laisser la note nouvellement
   créée apparaître en tête de liste ;
8. sauvegarder puis restaurer via `BackupService` → la note survit.

Noter dans `STATUS.md` chaque contrôle **réellement effectué**, et lesquels restent dus. Ne pas
écrire qu'un contrôle est passé sans l'avoir vu à l'écran.

- [ ] **Step 5: Vérification standard**

Run: `swift test --skip CalendarImportEventTests`
Expected: aucune régression par rapport aux échecs préexistants listés dans `STATUS.md`.

- [ ] **Step 6: Mettre à jour `STATUS.md`**

Ajouter une entrée datée : ce qui est livré (quatre modèles supprimés, kind `.note`, indexation
Spotlight des réunions, emails de projet tirés des participants), ce qui est vérifié à l'écran,
ce qui reste dû, et la prochaine action.

Consigner aussi les deux points laissés ouverts par la spec : le sort de `Meeting.notes` (champ
distinct de `liveNotes`, encore lu par les gabarits) et le renommage éventuel de `liveNotes`.

- [ ] **Step 7: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): consigne la fusion Note/Reunion et les controles a l'ecran"
```

---

## Ordre et dépendances

```
1 (kind + stats) ─┬─► 2 (NoteFactory) ─┬─► 5 (ecran Notes) ─┐
                  │                    ├─► 6 (NotesSection) ┤
                  ├─► 3 (onglets)      └─► 7 (rapide/laterale/gabarit)
                  └─► 4 (Spotlight)                          │
                                                             ▼
                                                    8 (supprimer Note)
                                                             │
                        9 (commandes) ─► 10 (fiche projet) ──┤
                        11 (mail) ───────────────────────────┤
                                                             ▼
                                                12 (supprimer les entrees)
                                                             │
                                                             ▼
                                                13 (verification reelle)
```

Les tâches 5, 6, 7 sont indépendantes entre elles et peuvent être menées en parallèle une fois
2 terminée. Les tâches 9, 10, 11 sont indépendantes entre elles. Les tâches 8 et 12 sont des
verrous : elles exigent que **tous** leurs lecteurs soient repointés.
