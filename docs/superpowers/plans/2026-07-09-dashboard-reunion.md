# Redesign écran Réunion — Dashboard « Vue d'ensemble » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformer l'écran de réunion en dashboard : un onglet « Vue d'ensemble » (grille de cartes réordonnables/masquables réutilisant le système de panneaux existant), une carte Présence, une modale « Gérer les participants », un statut de présence « En attente », le tout dans le thème crème/rouge existant.

**Architecture:** On réutilise `PanelLayoutEntry` + `RightSidebarPanelID` (drag-réordonner + show/hide + persistance JSON) mais rendu en **grille** (nouveau `OverviewDashboard`) au lieu de la sidebar verticale, qui est retirée. Les cartes de contenu existantes (`ActionsPanel`/`ProjectsPanel`/`CapturePanel`) sont réutilisées telles quelles ; on ajoute `PresenceCard`, `TranscriptionCard`, une carte agenda manager, un conteneur `DashboardCard`, et `ManageParticipantsSheet`. Le statut de présence passe à 3 cas en gardant les raw values existantes (zéro migration).

**Tech Stack:** Swift 6, SwiftUI, SwiftData, EventKit (mapping calendrier). Framework de test : Swift Testing (`import Testing`).

## Global Constraints

- **Thème** : réutiliser `MeetingTheme` (`canvasCream`, `surfaceCream`, `accentOrange`, `hairline`, `softShadow`, `titleSerif`, `sectionLabel`, `meta`). Pas de nouvelle palette.
- **Zéro migration SwiftData** : `MeetingAttendanceStatus` garde ses raw values `"participant"`/`"absent"` ; le champ persisté `participantStatusesJSON: String` ne change ni de nom ni de type. Nouveau raw `"pending"`.
- **Nom d'enum inchangé** : garder `RightSidebarPanelID` et `AppSettings.rightSidebarLayoutJSON` (pas de renommage — évite la churn ; déviation assumée vs la suggestion « recommandée » de la spec).
- **Réutilisation stricte** de la logique participants existante (`addParticipant`/`removeParticipant`/`setParticipantStatus`/`participantStatus`/`addAdhocParticipant`/`removeAllParticipants`/`resyncFromCalendar`/`availableCollaborators`) — aucune nouvelle logique métier.
- **Commentaires & libellés UI en français ; symboles/code en anglais.**
- **Build & test** : `swift build` compile ; `swift test --skip CalendarImportEventTests --filter <Suite>` pour les tests unitaires. `MenuBarStatsTests.test_badge_twelve_compact` est un échec **pré-existant** date-dependent, sans rapport — l'ignorer. Le rendu SwiftUI (grille, cartes, modale) n'est pas testable en `swift test` → vérification manuelle sur app packagée (`Scripts/bump-and-build.sh dev`).

## File Structure

**Modifiés :**
- `OneToOne/Models/MeetingModels.swift` — `MeetingAttendanceStatus` (3 cas, raw compat, labels), `participantsDescription`.
- `OneToOne/Services/CalendarMeetingImportService.swift` — mapping EKParticipantStatus → 3 statuts (fonction pure).
- `OneToOne/Views/MeetingView.swift` — `addParticipant` (`.present`), onglet `.overview`, retrait sidebar fixe, présentation de la modale.
- `OneToOne/Views/Meeting/MeetingDetailsBlock.swift` — références `.absent` → `.refused`, chip.
- `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift` — 3 nouveaux cas.
- `OneToOne/Views/Meeting/MeetingTabsUnderline.swift` — date + bouton « Personnaliser ».
- `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` — badge type de réunion (kind).

**Nouveaux :**
- `OneToOne/Services/Live/PresenceStats.swift` — helper pur (compteurs + %).
- `OneToOne/Views/Meeting/Dashboard/DashboardCard.swift` — conteneur de carte.
- `OneToOne/Views/Meeting/Dashboard/PresenceCard.swift`
- `OneToOne/Views/Meeting/Dashboard/TranscriptionCard.swift`
- `OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift` — grille + mode édition (drag/hide/persist).
- `OneToOne/Views/Meeting/ManageParticipantsSheet.swift`
- Tests : `Tests/AttendanceStatusTests.swift`, `Tests/PresenceStatsTests.swift`, extension de `Tests/PanelLayoutEntryTests.swift`.

---

## Task 1 : Statut de présence « En attente » (3 statuts, zéro migration)

**Files:**
- Modify: `OneToOne/Models/MeetingModels.swift:43-64` (enum) et `:216-222` (`participantsDescription`)
- Modify: `OneToOne/Services/CalendarMeetingImportService.swift:78` (mapping)
- Modify: `OneToOne/Views/MeetingView.swift:1058-1062` (`addParticipant`)
- Modify: `OneToOne/Views/Meeting/MeetingDetailsBlock.swift` (références `.absent`)
- Test: `Tests/AttendanceStatusTests.swift`

**Interfaces:**
- Produces:
  - `enum MeetingAttendanceStatus { case present /* raw "participant" */; case refused /* raw "absent" */; case pending /* raw "pending" */ }` avec `label` FR et `sfSymbol`.
  - `static func MeetingAttendanceStatus.fromCalendar(_ ek: EKParticipantStatus) -> MeetingAttendanceStatus`

- [ ] **Step 1 : Écrire les tests (échec attendu)**

Créer `Tests/AttendanceStatusTests.swift` :

```swift
import Testing
import EventKit
@testable import OneToOne

struct AttendanceStatusTests {

    // Rétro-compatibilité : les raw values persistées ne changent pas.
    @Test func rawValuesRemainStableForExistingData() {
        #expect(MeetingAttendanceStatus.present.rawValue == "participant")
        #expect(MeetingAttendanceStatus.refused.rawValue == "absent")
        #expect(MeetingAttendanceStatus.pending.rawValue == "pending")
    }

    @Test func oldPersistedRawDecodesToNewCases() {
        #expect(MeetingAttendanceStatus(rawValue: "participant") == .present)
        #expect(MeetingAttendanceStatus(rawValue: "absent") == .refused)
        #expect(MeetingAttendanceStatus(rawValue: "pending") == .pending)
        #expect(MeetingAttendanceStatus(rawValue: "inconnu") == nil)
    }

    @Test func labelsAreFrench() {
        #expect(MeetingAttendanceStatus.present.label == "Présent")
        #expect(MeetingAttendanceStatus.refused.label == "A refusé")
        #expect(MeetingAttendanceStatus.pending.label == "En attente")
    }

    @Test func calendarMappingCoversAllStatuses() {
        #expect(MeetingAttendanceStatus.fromCalendar(.declined) == .refused)
        #expect(MeetingAttendanceStatus.fromCalendar(.tentative) == .pending)
        #expect(MeetingAttendanceStatus.fromCalendar(.pending) == .pending)
        #expect(MeetingAttendanceStatus.fromCalendar(.accepted) == .present)
        #expect(MeetingAttendanceStatus.fromCalendar(.unknown) == .present)
    }

    @Test func allCasesHasThree() {
        #expect(MeetingAttendanceStatus.allCases.count == 3)
    }
}
```

- [ ] **Step 2 : Lancer → échec attendu**

Run: `swift test --skip CalendarImportEventTests --filter AttendanceStatusTests`
Expected: FAIL — `.present`/`.refused`/`.fromCalendar` n'existent pas encore.

- [ ] **Step 3 : Remplacer l'enum**

Dans `OneToOne/Models/MeetingModels.swift`, remplacer l'enum (lignes 43-64) par :

```swift
/// Statut de présence d'un collaborateur à une réunion.
/// Persisté par collaborateur dans `Meeting.participantStatusesJSON`.
/// ⚠️ Les raw values (`"participant"`/`"absent"`) sont conservées pour la
/// compatibilité des données existantes ; ne pas les renommer.
enum MeetingAttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case present = "participant"
    case refused = "absent"
    case pending = "pending"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .present: return "Présent"
        case .refused: return "A refusé"
        case .pending: return "En attente"
        }
    }

    var sfSymbol: String {
        switch self {
        case .present: return "person.fill.checkmark"
        case .refused: return "person.fill.xmark"
        case .pending: return "person.fill.questionmark"
        }
    }

    /// Mappe un statut de participation EventKit vers un statut de présence.
    static func fromCalendar(_ ek: EKParticipantStatus) -> MeetingAttendanceStatus {
        switch ek {
        case .declined: return .refused
        case .tentative, .pending: return .pending
        default: return .present   // accepted, unknown, delegated…
        }
    }
}
```

Ajouter `import EventKit` en tête de `MeetingModels.swift` s'il n'y est pas déjà (vérifier ; sinon l'ajouter après les imports existants).

- [ ] **Step 4 : Mettre à jour `participantsDescription`**

Dans `OneToOne/Models/MeetingModels.swift`, le `switch` de `participantsDescription` (lignes ~216-222) doit couvrir 3 cas :

```swift
    var participantsDescription: String {
        participants.map { collaborator in
            switch participantStatus(for: collaborator) {
            case .present:
                return collaborator.name
            case .refused:
                return "\(collaborator.name) (a refusé)"
            case .pending:
                return "\(collaborator.name) (en attente)"
            }
        }
        .joined(separator: ", ")
    }
```

Le fallback de `participantStatus(for:)` (ligne ~197) retourne `.participant` → le remplacer par `.present`.

- [ ] **Step 5 : Mettre à jour les usages de `.participant`/`.absent`**

- `OneToOne/Views/MeetingView.swift:1060` : `meeting.setParticipantStatus(.participant, for: c)` → `.present`.
- `OneToOne/Views/Meeting/MeetingDetailsBlock.swift` : remplacer les références `MeetingAttendanceStatus.absent` (dans le chip participant, la comparaison `participantStatus(p) == .absent`, l'icône) par `.refused`. Chercher toutes les occurrences de `.absent` dans ce fichier et les passer à `.refused`. Le `ForEach(MeetingAttendanceStatus.allCases)` du menu de statut affichera désormais automatiquement les 3 statuts.
- `OneToOne/Services/CalendarMeetingImportService.swift:78` : remplacer
  `status: attendee.participantStatus == .declined ? .absent : .participant`
  par `status: MeetingAttendanceStatus.fromCalendar(attendee.participantStatus)`.
- Chercher dans tout le repo les autres usages : `grep -rn "\.participant\b\|MeetingAttendanceStatus.absent\|\.absent\b" OneToOne/` et corriger ceux qui portent sur `MeetingAttendanceStatus` (ex. `resyncFromCalendar` utilise déjà `attendee.status`, pas de changement ; `CalendarMeetingAttendee.status` reste de type `MeetingAttendanceStatus`).

- [ ] **Step 6 : Lancer les tests → succès**

Run: `swift test --skip CalendarImportEventTests --filter AttendanceStatusTests`
Expected: PASS (6 tests). Puis `swift build` → doit compiler (toutes les références `.participant`/`.absent` corrigées).

- [ ] **Step 7 : Commit**

```bash
git add OneToOne/Models/MeetingModels.swift OneToOne/Services/CalendarMeetingImportService.swift OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingDetailsBlock.swift Tests/AttendanceStatusTests.swift
git commit -m "feat(reunion): statut de présence En attente (3 statuts, raw compat)"
```

---

## Task 2 : Étendre `RightSidebarPanelID` (presence / transcription / managerAgenda)

**Files:**
- Modify: `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift`
- Test: `Tests/PanelLayoutEntryTests.swift` (extension)

**Interfaces:**
- Produces: `RightSidebarPanelID` avec `.presence`, `.transcription`, `.managerAgenda` (en plus de `.actions`/`.projects`/`.capture`), chacun avec `defaultTitle` et `systemImage`.

> Ordre des `allCases` = layout par défaut. Placer les nouveaux cas AVANT les existants pour que la grille par défaut mette Présence + Transcription en tête : `presence, transcription, actions, capture, projects, managerAgenda`.

- [ ] **Step 1 : Écrire le test (échec attendu)**

Ajouter à `Tests/PanelLayoutEntryTests.swift` (dans la suite existante) :

```swift
    @Test func defaultLayoutContainsNewCards() {
        let ids = PanelLayoutEntry.defaultLayout.map(\.id)
        #expect(ids.contains(.presence))
        #expect(ids.contains(.transcription))
        #expect(ids.contains(.managerAgenda))
        #expect(ids.first == .presence)   // Présence en tête
    }

    @Test func decodeMigratesNewCardsAtEnd() {
        // JSON ancien (avant l'ajout des cartes) : seulement actions/projects/capture.
        let old = #"[{"id":"actions","visible":true},{"id":"projects","visible":false},{"id":"capture","visible":true}]"#
        let entries = PanelLayoutEntry.decode(old)
        let ids = entries.map(\.id)
        // Les 3 anciens préservés dans l'ordre + les nouveaux ajoutés en queue, visibles.
        #expect(Array(ids.prefix(3)) == [.actions, .projects, .capture])
        #expect(ids.contains(.presence))
        #expect(ids.contains(.transcription))
        #expect(ids.contains(.managerAgenda))
        #expect(entries.first(where: { $0.id == .projects })?.visible == false) // visibilité préservée
        #expect(entries.first(where: { $0.id == .presence })?.visible == true)  // nouveau → visible
    }
```

- [ ] **Step 2 : Lancer → échec attendu**

Run: `swift test --skip CalendarImportEventTests --filter PanelLayoutEntryTests`
Expected: FAIL — `.presence`/`.transcription`/`.managerAgenda` n'existent pas.

- [ ] **Step 3 : Étendre l'enum**

Remplacer le contenu de `OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift` par :

```swift
import Foundation
import SwiftUI

/// Identifiants des cartes configurables du dashboard réunion (onglet
/// « Vue d'ensemble »). L'ordre des `allCases` détermine le layout par défaut.
enum RightSidebarPanelID: String, CaseIterable, Codable, Identifiable {
    case presence
    case transcription
    case actions
    case capture
    case projects
    case managerAgenda

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .presence:      return "Présence"
        case .transcription: return "Transcription"
        case .actions:       return "Actions"
        case .capture:       return "Capture"
        case .projects:      return "Projets affectés"
        case .managerAgenda: return "Agenda manager"
        }
    }

    var systemImage: String {
        switch self {
        case .presence:      return "person.3.fill"
        case .transcription: return "waveform"
        case .actions:       return "checklist"
        case .capture:       return "camera"
        case .projects:      return "folder.fill"
        case .managerAgenda: return "list.bullet.rectangle"
        }
    }
}
```

- [ ] **Step 4 : Lancer → succès**

Run: `swift test --skip CalendarImportEventTests --filter PanelLayoutEntryTests`
Expected: PASS (tests existants + 2 nouveaux). `swift build` → compile (ConfigurableRightSidebar a un `switch` non exhaustif maintenant — cf. note ci-dessous).

> ⚠️ Ajouter les 3 nouveaux cas rend le `switch id` de `ConfigurableRightSidebar.panelContent` (`:178-201`) non exhaustif → le build cassera. Comme la sidebar est retirée en Task 7, ajouter un `default: EmptyView()` temporaire au `switch` de `ConfigurableRightSidebar.panelContent` pour que le build passe ici (il sera supprimé avec le fichier en Task 7). Modifier `ConfigurableRightSidebar.swift` : après le `case .capture:` du switch, ajouter `default: EmptyView()`.

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Views/Meeting/Sidebar/RightSidebarPanelID.swift OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift Tests/PanelLayoutEntryTests.swift
git commit -m "feat(reunion): cartes presence/transcription/managerAgenda dans le layout"
```

---

## Task 3 : Helper `PresenceStats` (pur, TDD) + `PresenceCard`

**Files:**
- Create: `OneToOne/Services/Live/PresenceStats.swift`
- Create: `OneToOne/Views/Meeting/Dashboard/PresenceCard.swift`
- Create: `OneToOne/Views/Meeting/Dashboard/DashboardCard.swift`
- Test: `Tests/PresenceStatsTests.swift`

**Interfaces:**
- Produces:
  - `struct PresenceStats { let present: Int; let refused: Int; let pending: Int; let total: Int; var percent: Int }`
  - `static func PresenceStats.compute(statuses: [MeetingAttendanceStatus]) -> PresenceStats`
  - `struct DashboardCard<Content: View>` : conteneur (titre, systemImage, poignée en mode édition, badge/compteur optionnel, actions d'en-tête, contenu).
  - `struct PresenceCard: View` avec init `init(meeting:settings:onManage:)`.

- [ ] **Step 1 : Écrire les tests de `PresenceStats` (échec attendu)**

Créer `Tests/PresenceStatsTests.swift` :

```swift
import Testing
@testable import OneToOne

struct PresenceStatsTests {

    @Test func countsAndPercent() {
        let s = PresenceStats.compute(statuses:
            Array(repeating: .present, count: 39)
            + Array(repeating: .refused, count: 3))
        #expect(s.present == 39)
        #expect(s.refused == 3)
        #expect(s.pending == 0)
        #expect(s.total == 42)
        #expect(s.percent == 93)   // round(39/42*100) = 92.857 → 93
    }

    @Test func withPending() {
        let s = PresenceStats.compute(statuses: [.present, .present, .pending, .refused])
        #expect(s.present == 2)
        #expect(s.pending == 1)
        #expect(s.refused == 1)
        #expect(s.total == 4)
        #expect(s.percent == 50)
    }

    @Test func emptyIsZeroPercent() {
        let s = PresenceStats.compute(statuses: [])
        #expect(s.total == 0)
        #expect(s.percent == 0)
    }
}
```

- [ ] **Step 2 : Lancer → échec attendu**

Run: `swift test --skip CalendarImportEventTests --filter PresenceStatsTests`
Expected: FAIL — `PresenceStats` introuvable.

- [ ] **Step 3 : Implémenter `PresenceStats`**

Créer `OneToOne/Services/Live/PresenceStats.swift` :

```swift
import Foundation

/// Compteurs de présence dérivés des statuts des participants d'une réunion.
struct PresenceStats {
    let present: Int
    let refused: Int
    let pending: Int
    let total: Int

    /// Pourcentage de présents sur le total, arrondi ; 0 si aucun participant.
    var percent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(present) / Double(total) * 100).rounded())
    }

    static func compute(statuses: [MeetingAttendanceStatus]) -> PresenceStats {
        PresenceStats(
            present: statuses.filter { $0 == .present }.count,
            refused: statuses.filter { $0 == .refused }.count,
            pending: statuses.filter { $0 == .pending }.count,
            total: statuses.count)
    }
}
```

- [ ] **Step 4 : Lancer → succès**

Run: `swift test --skip CalendarImportEventTests --filter PresenceStatsTests`
Expected: PASS (3 tests).

- [ ] **Step 5 : Créer le conteneur `DashboardCard`**

Créer `OneToOne/Views/Meeting/Dashboard/DashboardCard.swift` :

```swift
import SwiftUI

/// Conteneur commun d'une carte du dashboard réunion : en-tête (poignée en mode
/// édition + icône + titre + compteur/badge + actions) puis contenu.
struct DashboardCard<HeaderActions: View, Content: View>: View {
    let title: String
    let systemImage: String
    /// Petit compteur/badge affiché à droite du titre (ex. « 42 »), optionnel.
    var badge: String? = nil
    /// Mode édition (affiche la poignée de drag ⠿).
    var isEditing: Bool = false
    @ViewBuilder var headerActions: () -> HeaderActions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isEditing {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Glisser pour réordonner")
                }
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                if let badge {
                    Text(badge)
                        .font(MeetingTheme.meta)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Spacer()
                headerActions()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(MeetingTheme.surfaceCream)
                .shadow(color: MeetingTheme.softShadow, radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(MeetingTheme.hairline, lineWidth: 0.5)
        )
    }
}
```

- [ ] **Step 6 : Créer `PresenceCard`**

Créer `OneToOne/Views/Meeting/Dashboard/PresenceCard.swift` :

```swift
import SwiftUI

/// Carte « Présence » du dashboard : donut de taux de présence, compteurs par
/// statut, pile d'avatars, bouton « Gérer les participants ».
struct PresenceCard: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    var isEditing: Bool = false
    /// Ouvre la modale de gestion des participants.
    let onManage: () -> Void

    private var stats: PresenceStats {
        PresenceStats.compute(statuses: meeting.participants.map { meeting.participantStatus(for: $0) })
    }

    var body: some View {
        DashboardCard(title: "Présence", systemImage: "person.3.fill",
                      badge: "\(stats.total)", isEditing: isEditing) {
            EmptyView()
        } content: {
            let s = stats
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 20) {
                    donut(present: s.present, refused: s.refused, pending: s.pending,
                          total: s.total, percent: s.percent)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        legendRow(color: .green, count: s.present, label: "présents")
                        legendRow(color: MeetingTheme.accentOrange, count: s.refused, label: "ont refusé")
                        if s.pending > 0 {
                            legendRow(color: .orange, count: s.pending, label: "en attente")
                        }
                    }
                }
                MeetingAvatarStack(participants: meeting.participants,
                                   tint: { _ in settings.meetingParticipantColor })
                Button(action: onManage) {
                    Text("Gérer les participants")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func legendRow(color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)").font(.body)
        }
    }

    /// Donut : arc vert (présents) + arc rouge (refusés) + reste neutre (en attente),
    /// pourcentage centré.
    private func donut(present: Int, refused: Int, pending: Int, total: Int, percent: Int) -> some View {
        let denom = max(total, 1)
        let presentFrac = Double(present) / Double(denom)
        let refusedFrac = Double(refused) / Double(denom)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: presentFrac)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: presentFrac, to: presentFrac + refusedFrac)
                .stroke(MeetingTheme.accentOrange, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)").font(.system(size: 30, weight: .bold)) + Text("%").font(.callout.bold())
                Text("de présence").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
```

- [ ] **Step 7 : Compiler**

Run: `swift build`
Expected: build réussit.

- [ ] **Step 8 : Commit**

```bash
git add OneToOne/Services/Live/PresenceStats.swift OneToOne/Views/Meeting/Dashboard/DashboardCard.swift OneToOne/Views/Meeting/Dashboard/PresenceCard.swift Tests/PresenceStatsTests.swift
git commit -m "feat(reunion): carte Présence (donut + compteurs) + DashboardCard + PresenceStats"
```

---

## Task 4 : Modale « Gérer les participants » (`ManageParticipantsSheet`)

**Files:**
- Create: `OneToOne/Views/Meeting/ManageParticipantsSheet.swift`

**Interfaces:**
- Consumes: closures de `MeetingView` (mêmes signatures que `MeetingDetailsBlock`).
- Produces: `struct ManageParticipantsSheet: View` avec init :
  ```swift
  init(meeting: Meeting, settings: AppSettings,
       availableCollaborators: [Collaborator],
       collaboratorsCount: Int,
       newAdhocName: Binding<String>,
       addParticipant: @escaping (Collaborator) -> Void,
       removeParticipant: @escaping (Collaborator) -> Void,
       removeAllParticipants: @escaping () -> Void,
       setParticipantStatus: @escaping (MeetingAttendanceStatus, Collaborator) -> Void,
       participantStatus: @escaping (Collaborator) -> MeetingAttendanceStatus,
       addAdhoc: @escaping () -> Void,
       onResync: @escaping () -> Void,
       onClose: @escaping () -> Void)
  ```

- [ ] **Step 1 : Créer la modale**

Créer `OneToOne/Views/Meeting/ManageParticipantsSheet.swift` :

```swift
import SwiftUI

/// Modale de gestion des participants : recherche, filtres par statut, resync,
/// changement de statut, retrait, ajout ad-hoc. Toute la logique métier est
/// fournie par `MeetingView` via closures (réutilisation de l'existant).
struct ManageParticipantsSheet: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let availableCollaborators: [Collaborator]
    let collaboratorsCount: Int
    @Binding var newAdhocName: String
    let addParticipant: (Collaborator) -> Void
    let removeParticipant: (Collaborator) -> Void
    let removeAllParticipants: () -> Void
    let setParticipantStatus: (MeetingAttendanceStatus, Collaborator) -> Void
    let participantStatus: (Collaborator) -> MeetingAttendanceStatus
    let addAdhoc: () -> Void
    let onResync: () -> Void
    let onClose: () -> Void

    /// Filtre de statut actif (nil = Tous).
    @State private var filter: MeetingAttendanceStatus? = nil
    @State private var query: String = ""

    private var counts: PresenceStats {
        PresenceStats.compute(statuses: meeting.participants.map { participantStatus($0) })
    }

    private var filteredParticipants: [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return meeting.participants.filter { c in
            (filter == nil || participantStatus(c) == filter)
            && (q.isEmpty || c.name.localizedCaseInsensitiveContains(q))
        }
    }

    /// Résultats annuaire (collaborateurs non-participants) quand on recherche.
    private var directoryMatches: [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return availableCollaborators.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 640, height: 720)
        .background(MeetingTheme.canvasCream)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gérer les participants").font(.title2.bold())
                Text("\(meeting.title) · \(meeting.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Rechercher un participant ou un collaborateur…", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
                Button { onResync() } label: { Label("Resync", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                filterChip(nil, "Tous", counts.total)
                filterChip(.present, "Présents", counts.present)
                filterChip(.refused, "Ont refusé", counts.refused)
                filterChip(.pending, "En attente", counts.pending)
                Spacer()
                Text("Collaborateurs \(collaboratorsCount)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func filterChip(_ status: MeetingAttendanceStatus?, _ label: String, _ count: Int) -> some View {
        let active = filter == status
        return Button { filter = status } label: {
            HStack(spacing: 6) {
                if let status { Circle().fill(color(for: status)).frame(width: 7, height: 7) }
                Text("\(label) \(count)").font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(active ? MeetingTheme.badgeBlack : Color.secondary.opacity(0.08)))
            .foregroundColor(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func color(for status: MeetingAttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .refused: return MeetingTheme.accentOrange
        case .pending: return .orange
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredParticipants, id: \.persistentModelID) { c in
                    participantRow(c); Divider()
                }
                if !directoryMatches.isEmpty {
                    Text("AJOUTER DEPUIS L'ANNUAIRE").font(MeetingTheme.sectionLabel)
                        .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 12)
                    ForEach(directoryMatches, id: \.persistentModelID) { c in
                        Button { addParticipant(c) } label: {
                            HStack(spacing: 12) {
                                AvatarMini(collaborator: c, tint: settings.meetingCollaboratorColor)
                                Text(c.name); Spacer()
                                Image(systemName: "plus.circle").foregroundColor(.secondary)
                            }.padding(.horizontal, 20).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func participantRow(_ c: Collaborator) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(collaborator: c, size: 34, tint: settings.meetingParticipantColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.body)
                Text(c.isAdhoc ? "Invité" : "Collaborateur").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                ForEach(MeetingAttendanceStatus.allCases) { s in
                    Button { setParticipantStatus(s, c) } label: { Label(s.label, systemImage: s.sfSymbol) }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(color(for: participantStatus(c))).frame(width: 7, height: 7)
                    Text(participantStatus(c).label).font(.caption)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            Button { removeParticipant(c) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                TextField("Ajouter un participant ad-hoc (nom)…", text: $newAdhocName)
                    .textFieldStyle(.plain).onSubmit { addAdhoc() }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
            Button("Ajouter") { addAdhoc() }
                .disabled(newAdhocName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        HStack {
            Button(role: .destructive) { removeAllParticipants() } label: {
                Label("Tout retirer", systemImage: "trash").foregroundColor(MeetingTheme.accentOrange)
            }.buttonStyle(.plain)
            Spacer()
            Button("Annuler") { onClose() }
            Button("Terminé") { onClose() }.buttonStyle(.borderedProminent).tint(MeetingTheme.accentOrange)
        }
        .padding(20)
    }
}
```

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit.

- [ ] **Step 3 : Commit**

```bash
git add OneToOne/Views/Meeting/ManageParticipantsSheet.swift
git commit -m "feat(reunion): modale Gérer les participants (recherche, filtres, statuts, ad-hoc)"
```

---

## Task 5 : Carte « Transcription » (`TranscriptionCard`)

**Files:**
- Create: `OneToOne/Views/Meeting/Dashboard/TranscriptionCard.swift`

**Interfaces:**
- Consumes: `LiveTranscriptionService.shared` (`@Published liveTranscript`, `isLive`, `statusMessage`), `DashboardCard`.
- Produces: `struct TranscriptionCard: View` avec init `init(isEditing:onExpand:)`.

> La diarisation (qui parle) est **post-enregistrement** (cf. feature transcription temps réel). Donc le toggle « Speakers » contrôle l'**affichage** d'un libellé locuteur si présent ; le bouton « Détecter » est présent pour la fidélité visuelle mais désactivé pendant l'enregistrement avec un `help` explicatif (aucune détection live n'existe — ne pas en inventer). L'icône agrandir ↗ appelle `onExpand()` (→ onglet Direct).

- [ ] **Step 1 : Créer la carte**

Créer `OneToOne/Views/Meeting/Dashboard/TranscriptionCard.swift` :

```swift
import SwiftUI

/// Carte « Transcription » du dashboard : aperçu de la transcription en direct.
/// La détection des locuteurs se fait après l'enregistrement (diarisation batch),
/// donc « Détecter » est un affordance désactivé en direct ; « Speakers » ne fait
/// qu'afficher/masquer d'éventuels libellés de locuteur.
struct TranscriptionCard: View {
    @ObservedObject private var live = LiveTranscriptionService.shared
    var isEditing: Bool = false
    /// Bascule vers l'onglet « Direct » plein écran.
    let onExpand: () -> Void

    @State private var showSpeakers: Bool = true

    var body: some View {
        DashboardCard(title: "Transcription", systemImage: "waveform", isEditing: isEditing) {
            HStack(spacing: 10) {
                Toggle("Speakers", isOn: $showSpeakers)
                    .toggleStyle(.switch).controlSize(.mini)
                    .fixedSize()
                Button { } label: { Label("Détecter", systemImage: "mic") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(live.isLive)
                    .help("La détection des locuteurs s'effectue après l'enregistrement")
                Button { onExpand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain)
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if live.isLive {
                    Label("En direct", systemImage: "circle.fill")
                        .font(.caption).foregroundColor(MeetingTheme.accentOrange)
                }
                ScrollView {
                    Text(live.liveTranscript.isEmpty ? "En écoute…" : live.liveTranscript)
                        .font(.body)
                        .foregroundColor(live.liveTranscript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120, maxHeight: 200)
                if let status = live.statusMessage {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
```

> Note : `showSpeakers` est un état d'affichage local ; le transcript live actuel n'expose pas encore de libellés de locuteur par segment, donc le toggle est prêt pour un usage futur sans rien casser. Ne pas ajouter de logique de diarisation ici.

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit.

- [ ] **Step 3 : Commit**

```bash
git add OneToOne/Views/Meeting/Dashboard/TranscriptionCard.swift
git commit -m "feat(reunion): carte Transcription (aperçu live + agrandir)"
```

---

## Task 6 : Grille `OverviewDashboard` (réordonner / masquer / persister)

**Files:**
- Create: `OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift`

**Interfaces:**
- Consumes: `PanelLayoutEntry`, `RightSidebarPanelID`, `AppSettings.rightSidebarLayoutJSON`, les cartes (`PresenceCard`, `TranscriptionCard`, `ActionsPanel`, `ProjectsPanel`, `CapturePanel`, `ManagerAgendaSidebar` ré-emballé), `DashboardCard`.
- Produces: `struct OverviewDashboard: View` avec init reprenant les paramètres nécessaires aux cartes :
  ```swift
  init(meeting: Meeting, settings: AppSettings, allCollaborators: [Collaborator],
       currentSlides: [SlideCapture], isEditing: Binding<Bool>,
       newTaskTitle: Binding<String>, selectedCollaborator: Binding<Collaborator?>,
       showNewTaskDueDate: Binding<Bool>, newTaskDueDate: Binding<Date?>,
       onAddTask: @escaping () -> Void, onDeleteTask: @escaping (ActionTask) -> Void,
       onToggleTaskCompletion: @escaping (ActionTask) -> Void,
       onShowSlides: @escaping () -> Void, onShowCaptureSetup: @escaping () -> Void,
       onManageParticipants: @escaping () -> Void, onExpandTranscript: @escaping () -> Void,
       saveContext: @escaping () -> Void)
  ```

> **Gabarit** : les cartes VISIBLES (issues de `PanelLayoutEntry`, filtrées : `.managerAgenda` n'apparaît que si `meeting.kind == .manager`) sont placées dans l'ordre du layout. Rangée « héro » = 2 premières cartes (col gauche ~1fr, col droite ~1.6fr). Cartes suivantes = grille 3 colonnes qui se replient sous ~900pt de large. Drag pour réordonner (même payload `rawValue` que l'existant) ; menu « Personnaliser » (toggles visibilité + réinitialiser) affiché quand `isEditing`.

- [ ] **Step 1 : Créer la grille**

Créer `OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift` :

```swift
import SwiftUI
import UniformTypeIdentifiers

/// Onglet « Vue d'ensemble » : grille de cartes réordonnables/masquables.
/// Réutilise le layout persisté (`PanelLayoutEntry` / `rightSidebarLayoutJSON`).
struct OverviewDashboard: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let currentSlides: [SlideCapture]
    @Binding var isEditing: Bool
    @Binding var newTaskTitle: String
    @Binding var selectedCollaborator: Collaborator?
    @Binding var showNewTaskDueDate: Bool
    @Binding var newTaskDueDate: Date?
    let onAddTask: () -> Void
    let onDeleteTask: (ActionTask) -> Void
    let onToggleTaskCompletion: (ActionTask) -> Void
    let onShowSlides: () -> Void
    let onShowCaptureSetup: () -> Void
    let onManageParticipants: () -> Void
    let onExpandTranscript: () -> Void
    let saveContext: () -> Void

    @State private var entries: [PanelLayoutEntry] = []

    /// Cartes visibles, dans l'ordre du layout, filtrées selon le kind.
    private var visibleIDs: [RightSidebarPanelID] {
        entries.filter { entry in
            guard entry.visible else { return false }
            if entry.id == .managerAgenda { return meeting.kind == .manager }
            return true
        }.map(\.id)
    }

    var body: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 900
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isEditing { editBar }
                    grid(narrow: narrow)
                }
                .padding(4)
            }
        }
        .onAppear {
            if entries.isEmpty { entries = PanelLayoutEntry.decode(settings.rightSidebarLayoutJSON) }
        }
    }

    @ViewBuilder
    private func grid(narrow: Bool) -> some View {
        let ids = visibleIDs
        VStack(spacing: 16) {
            // Rangée héro : 2 premières cartes.
            if ids.count >= 2 && !narrow {
                HStack(alignment: .top, spacing: 16) {
                    card(ids[0]).frame(maxWidth: .infinity)
                    card(ids[1]).frame(maxWidth: .infinity).layoutPriority(1)
                }
            }
            // Reste : grille 3 colonnes (ou 1 colonne si étroit).
            let rest = narrow ? ids : Array(ids.dropFirst(2))
            let columns = narrow
                ? [GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rest, id: \.self) { id in card(id) }
            }
        }
    }

    /// Une carte draggable/droppable en mode édition.
    @ViewBuilder
    private func card(_ id: RightSidebarPanelID) -> some View {
        cardContent(id)
            .modifier(DragReorderModifier(id: id, entries: $entries, enabled: isEditing, persist: persist))
    }

    @ViewBuilder
    private func cardContent(_ id: RightSidebarPanelID) -> some View {
        switch id {
        case .presence:
            PresenceCard(meeting: meeting, settings: settings, isEditing: isEditing, onManage: onManageParticipants)
        case .transcription:
            TranscriptionCard(isEditing: isEditing, onExpand: onExpandTranscript)
        case .actions:
            DashboardCard(title: "Actions", systemImage: "checklist", isEditing: isEditing) { EmptyView() } content: {
                ActionsPanel(meeting: meeting, settings: settings, allCollaborators: allCollaborators,
                             newTaskTitle: $newTaskTitle, selectedCollaborator: $selectedCollaborator,
                             showNewTaskDueDate: $showNewTaskDueDate, newTaskDueDate: $newTaskDueDate,
                             onAddTask: onAddTask, onDeleteTask: onDeleteTask,
                             onToggleTaskCompletion: onToggleTaskCompletion, saveContext: saveContext)
            }
        case .projects:
            DashboardCard(title: "Projets affectés", systemImage: "folder.fill", isEditing: isEditing) { EmptyView() } content: {
                ProjectsPanel(meeting: meeting)
            }
        case .capture:
            DashboardCard(title: "Capture", systemImage: "camera", isEditing: isEditing) { EmptyView() } content: {
                CapturePanel(currentSlides: currentSlides, onShowSlides: onShowSlides, onShowCaptureSetup: onShowCaptureSetup)
            }
        case .managerAgenda:
            DashboardCard(title: "Agenda manager", systemImage: "list.bullet.rectangle", isEditing: isEditing) { EmptyView() } content: {
                ManagerAgendaSidebar(meeting: meeting, settings: settings)
            }
        }
    }

    private var editBar: some View {
        HStack {
            Text("Glisser les cartes pour réordonner").font(.caption).foregroundColor(.secondary)
            Spacer()
            Menu {
                Section("Cartes visibles") {
                    ForEach(entries) { entry in
                        Button {
                            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[idx].visible.toggle(); persist()
                            }
                        } label: {
                            if entry.visible { Label(entry.id.defaultTitle, systemImage: "checkmark") }
                            else { Text(entry.id.defaultTitle) }
                        }
                    }
                }
                Divider()
                Button("Réinitialiser") { entries = PanelLayoutEntry.defaultLayout; persist() }
            } label: { Label("Cartes", systemImage: "gearshape") }
        }
    }

    private func persist() {
        settings.rightSidebarLayoutJSON = PanelLayoutEntry.encode(entries)
        saveContext()
    }
}

/// Drag & drop de réordonnancement d'une carte (payload = `RightSidebarPanelID.rawValue`).
private struct DragReorderModifier: ViewModifier {
    let id: RightSidebarPanelID
    @Binding var entries: [PanelLayoutEntry]
    let enabled: Bool
    let persist: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { NSItemProvider(object: id.rawValue as NSString) }
                .onDrop(of: [UTType.text], delegate: CardDropDelegate(targetID: id, entries: $entries, persist: persist))
        } else {
            content
        }
    }
}

private struct CardDropDelegate: DropDelegate {
    let targetID: RightSidebarPanelID
    @Binding var entries: [PanelLayoutEntry]
    let persist: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            guard let raw = obj as? String,
                  let dragID = RightSidebarPanelID(rawValue: raw), dragID != targetID else { return }
            DispatchQueue.main.async {
                guard let from = entries.firstIndex(where: { $0.id == dragID }),
                      let to = entries.firstIndex(where: { $0.id == targetID }) else { return }
                let moved = entries.remove(at: from)
                entries.insert(moved, at: to)
                persist()
            }
        }
        return true
    }
}
```

- [ ] **Step 2 : Compiler**

Run: `swift build`
Expected: build réussit. Si `ManagerAgendaSidebar` ré-emballé dans une carte pose un souci de layout (il a son propre fond plein cadre), acceptable pour ce build ; l'ajustement visuel se fait à la vérif manuelle.

- [ ] **Step 3 : Commit**

```bash
git add OneToOne/Views/Meeting/Dashboard/OverviewDashboard.swift
git commit -m "feat(reunion): OverviewDashboard (grille de cartes réordonnables)"
```

---

## Task 7 : Intégration `MeetingView` — onglet Vue d'ensemble, retrait sidebar, modale, chrome

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift` (enum, body, sectionContent, état modale)
- Modify: `OneToOne/Views/Meeting/MeetingTabsUnderline.swift` (date + Personnaliser)
- Modify: `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (badge kind)
- Delete: `OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift` (remplacé par la grille)

**Interfaces:**
- Consumes: `OverviewDashboard`, `ManageParticipantsSheet` (Tasks 4, 6).

- [ ] **Step 1 : Ajouter le cas `.overview` en tête de `MeetingSection`**

Dans `OneToOne/Views/MeetingView.swift`, enum `MeetingSection` (lignes 148-156), ajouter en **premier** :

```swift
    enum MeetingSection: String, CaseIterable, Identifiable {
        case overview = "Vue d'ensemble"
        case preparation = "Préparation"
        case liveNotes = "Notes live"
        case liveTranscript = "Direct"
        case transcript = "Transcription"
        case report = "Rapport"
        case documents = "Documents"
        var id: String { rawValue }
    }
```

Repérer l'état `@State private var activeSection` (par défaut `.liveNotes` dans le code actuel) et le passer à `.overview`.

- [ ] **Step 2 : Ajouter l'état de la modale et du mode édition**

Dans `MeetingView` (près des autres `@State`), ajouter :

```swift
    @State private var showParticipantsSheet = false
    @State private var isEditingLayout = false
```

- [ ] **Step 3 : Supprimer la sidebar fixe du `body`**

Dans `MeetingView.body`, remplacer le bloc `HStack(spacing: 0) { mainPanel… ; sidebar conditionnelle }` (lignes 231-269) par simplement le `mainPanel` pleine largeur :

```swift
            mainPanel
```

(Retirer tout le commentaire HStack/HSplitView et les deux branches `ManagerAgendaSidebar` / `ConfigurableRightSidebar`.)

- [ ] **Step 4 : Router `.overview` dans `sectionContent`**

Dans `sectionContent` (lignes 513-532), ajouter le case `.overview` en premier :

```swift
        case .overview:
            OverviewDashboard(
                meeting: meeting, settings: settings, allCollaborators: allCollaborators,
                currentSlides: currentSlides, isEditing: $isEditingLayout,
                newTaskTitle: $newTaskTitle, selectedCollaborator: $selectedCollaborator,
                showNewTaskDueDate: $showNewTaskDueDate, newTaskDueDate: $newTaskDueDate,
                onAddTask: addTask,
                onDeleteTask: { task in context.delete(task); saveContext() },
                onToggleTaskCompletion: { task in task.isCompleted.toggle(); saveContext() },
                onShowSlides: { showSlidesList = true },
                onShowCaptureSetup: { showCaptureSetup = true },
                onManageParticipants: { showParticipantsSheet = true },
                onExpandTranscript: { activeSection = .liveTranscript },
                saveContext: saveContext)
```

- [ ] **Step 5 : Présenter la modale participants**

Ajouter un `.sheet` sur le `body` de `MeetingView` (à côté des autres `.sheet`, ~lignes 273-304) :

```swift
        .sheet(isPresented: $showParticipantsSheet) {
            ManageParticipantsSheet(
                meeting: meeting, settings: settings,
                availableCollaborators: availableCollaborators,
                collaboratorsCount: allCollaborators.count,
                newAdhocName: $newAdhocName,
                addParticipant: addParticipant,
                removeParticipant: removeParticipant,
                removeAllParticipants: removeAllParticipants,
                setParticipantStatus: { status, c in setParticipantStatus(status, for: c) },
                participantStatus: { c in participantStatus(for: c) },
                addAdhoc: addAdhocParticipant,
                onResync: { resyncFromCalendarInMeetingView() },
                onClose: { showParticipantsSheet = false })
        }
```

> `resyncFromCalendar()` vit actuellement dans `MeetingDetailsBlock`, pas dans `MeetingView`. Pour le bouton Resync de la modale : soit exposer une closure depuis `MeetingDetailsBlock` (non trivial car la modale est présentée par MeetingView), soit dupliquer la logique de resync dans une méthode `MeetingView.resyncFromCalendarInMeetingView()`. **Choix** : déplacer/copier la logique de `resyncFromCalendar()` (MeetingDetailsBlock.swift:372-423) dans une méthode privée de `MeetingView` (elle a déjà `context`, `settings`, `meeting`), et faire pointer les DEUX appelants (le bouton Resync de `MeetingDetailsBlock` via une nouvelle closure `onResync` ajoutée à `MeetingDetailsBlock`, et la modale) vers cette méthode unique — DRY. Ajouter `let onResync: () -> Void` à `MeetingDetailsBlock` et brancher son bouton Resync dessus ; passer `onResync: { resyncFromCalendarInMeetingView() }` au call-site `MeetingDetailsBlock` (MeetingView.swift:378-395).

- [ ] **Step 6 : Bouton « Personnaliser » + date dans `MeetingTabsUnderline`**

Modifier `OneToOne/Views/Meeting/MeetingTabsUnderline.swift` : ajouter deux paramètres et les afficher à droite (après le `Spacer()`), le bouton Personnaliser ne s'affichant que sur l'onglet Vue d'ensemble :

```swift
    let date: Date
    /// Bascule le mode édition de la grille ; affiché seulement sur Vue d'ensemble.
    @Binding var isEditingLayout: Bool
```

Après le `Spacer()` (ligne 22), avant la fermeture du `HStack` :

```swift
            Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                .font(.caption).foregroundColor(.secondary)
            if selection == .overview {
                Button { isEditingLayout.toggle() } label: {
                    Label("Personnaliser", systemImage: "square.grid.2x2")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
```

Mettre à jour le call-site (MeetingView.swift:396-401) :
```swift
            MeetingTabsUnderline(
                selection: $activeSection,
                attachmentsCount: meeting.attachments.count,
                hasReport: !meeting.summary.isEmpty,
                showLiveTab: settings.liveTranscriptionEnabled,
                date: meeting.date,
                isEditingLayout: $isEditingLayout)
```

- [ ] **Step 7 : Badge type de réunion dans le chrome**

Dans `OneToOne/Views/Meeting/MeetingTopChromeBar.swift`, `breadcrumb` (lignes 56-62), remplacer le simple `Text(meeting.kind.label)` du cas sans projet par un badge (pill) réutilisant le pattern `audioStatusBadge` :

```swift
            } else {
                Label(meeting.kind.label, systemImage: meeting.kind.sfSymbol)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    .foregroundColor(.primary)
            }
```

- [ ] **Step 8 : Supprimer `ConfigurableRightSidebar`**

```bash
git rm OneToOne/Views/Meeting/Sidebar/ConfigurableRightSidebar.swift
```

> Vérifier qu'aucun autre fichier ne référence `ConfigurableRightSidebar` : `grep -rn "ConfigurableRightSidebar" OneToOne/` — seul `MeetingView.body` l'utilisait (retiré au Step 3). `PanelHeader.swift` et son `DragModifier` ne sont plus utilisés non plus (la grille a son propre `DragReorderModifier`) → si `grep -rn "PanelHeader" OneToOne/` ne renvoie plus rien d'autre, `git rm OneToOne/Views/Meeting/Sidebar/PanelHeader.swift` aussi. Conserver `PanelLayoutEntry.swift` et `RightSidebarPanelID.swift` (réutilisés par la grille). Retirer le `default: EmptyView()` temporaire n'est plus nécessaire puisque le fichier est supprimé.

- [ ] **Step 9 : Compiler + tests**

Run: `swift build`
Expected: build réussit. Corriger toute référence résiduelle (état `activeSection` initial, `actionsCollapsed` devenu inutilisé → le retirer s'il n'est plus référencé).

Run: `swift test --skip CalendarImportEventTests`
Expected: PASS hormis l'échec pré-existant `MenuBarStatsTests.test_badge_twelve_compact`.

- [ ] **Step 10 : Vérification manuelle (app packagée)**

Run: `Scripts/bump-and-build.sh dev`
Vérifier :
- Onglet « Vue d'ensemble » ouvert par défaut : grille avec Présence (donut/compteurs) + Transcription en héro, puis Actions/Capture/Projets ; carte Agenda manager visible uniquement en `.manager`.
- « Personnaliser » : poignées ⠿, drag pour réordonner, menu Cartes (masquer/afficher/réinitialiser), persistance après relance.
- Carte Présence → « Gérer les participants » ouvre la modale : recherche, filtres (Tous/Présents/Ont refusé/En attente), changement de statut, ad-hoc, Resync, Tout retirer, Terminé.
- Statuts : un participant passé « En attente » se reflète dans le donut et les filtres.
- Carte Transcription : aperçu live, agrandir ↗ → onglet Direct.
- Autres onglets (Préparation, Notes live, Direct, Transcription, Rapport, Documents) : pleine largeur, sans sidebar, fonctionnels.
- Chrome : badge de type de réunion affiché ; date sur la rangée d'onglets.

- [ ] **Step 11 : Commit**

```bash
git add OneToOne/Views/MeetingView.swift OneToOne/Views/Meeting/MeetingTabsUnderline.swift OneToOne/Views/Meeting/MeetingTopChromeBar.swift OneToOne/Views/Meeting/MeetingDetailsBlock.swift
git commit -m "feat(reunion): onglet Vue d'ensemble, retrait sidebar fixe, modale participants, chrome"
```

---

## Récapitulatif vérifications manuelles (app packagée)

Non couvrables par `swift test` (rendu SwiftUI, persistance layout, modale, donut) — à vérifier via `Scripts/bump-and-build.sh dev` :
1. Grille Vue d'ensemble fidèle + cartes selon `kind`.
2. Personnaliser : drag-réordonner, masquer/afficher, réinitialiser, persistance.
3. Carte Présence (donut/compteurs) + ouverture modale.
4. Modale : recherche, filtres, statuts (dont En attente), ad-hoc, resync, tout retirer.
5. Carte Transcription : live + agrandir → Direct.
6. Régression : onglets existants pleine largeur, sans perte de fonction ; `.manager` conserve l'agenda (en carte).
