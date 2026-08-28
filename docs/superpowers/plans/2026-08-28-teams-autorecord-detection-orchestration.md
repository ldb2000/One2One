# Teams auto-record — détection & orchestration (plan 1/2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Détecter un appel Microsoft Teams, proposer par notification système de créer la réunion OneToOne correspondante, démarrer l'enregistrement, puis enchaîner à la fin de l'appel sur la finalisation de la transcription et la génération du rapport.

**Architecture:** Trois déclencheurs locaux convergent vers une machine à états unique. Toute la logique décisionnelle est écrite en **fonctions pures** (`step`, `match`, `reduce`) testables sans AppKit, sans EventKit et sans `UNUserNotificationCenter` ; les classes `@MainActor` ne font qu'observer le système et appliquer des effets. La création de réunion et l'ouverture de fenêtre réutilisent intégralement le chemin existant `CalendarMeetingImportService.importEvent` + `QuickLaunchRouter` + `MeetingView(autoStartRecording:)`. Le rapport réutilise `AIReportService.generate`.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, SwiftData, EventKit, UserNotifications, ScreenCaptureKit (lecture seule, énumération de fenêtres). Tests : Swift Testing (`@Suite`/`@Test`/`#expect`) pour les fonctions pures, XCTest + `ModelContainer` en mémoire pour l'intégration SwiftData.

**Spec de référence :** [`docs/superpowers/specs/2026-08-28-teams-autorecord-popup-design.md`](../specs/2026-08-28-teams-autorecord-popup-design.md) (v2.1).

**Plan suivant :** `2026-08-28-teams-autorecord-double-piste-audio.md` ajoute la capture de l'audio système. Ce plan-ci s'arrête au micro seul, qui est le mode de repli D-6 déjà prévu par la spec : l'application est fonctionnelle à la fin du plan 1.

## Global Constraints

- Branche : `feat/teams-autorecord-popup`, partant de `master`. Aucun commit sur `master`.
- Commits conventionnels. Une PR = une intention.
- Commentaires et libellés d'interface en **français** ; symboles et code en anglais.
- Services : `enum` namespace (fonctions statiques pures) ou `class` singleton `@MainActor` `.shared`.
- **Aucune nouvelle dépendance** SwiftPM.
- **Aucune migration SwiftData** : aucun champ ajouté à `Meeting`, aucun champ d'état. Deux clés ajoutées à `AppSettings` uniquement (valeurs par défaut, lightweight migration sûre).
- **Aucune modification d'`Info.plist`.**
- Deployment target : `.macOS("15.0")` (déclaré dans `Package.swift`).
- Vérification avant PR : `swift test --skip CalendarImportEventTests`.
- Mettre `STATUS.md` à jour en fin de chantier.

## File Structure

| Fichier | Responsabilité |
|---|---|
| `OneToOne/Services/Teams/TeamsCallObservation.swift` | **Créé.** Fonction pure de détection : titre → « ressemble à un appel », et machine à états 5 s / 30 s / cooldown. Zéro import AppKit. |
| `OneToOne/Services/Teams/TeamsCallMonitor.swift` | **Créé.** Singleton `@MainActor` : observe `NSWorkspace`, interroge `SCShareableContent` si la permission est déjà là, appelle la fonction pure. |
| `OneToOne/Services/Teams/TeamsCallMatchService.swift` | **Créé.** `enum` namespace pur : apparie un instant à un `CalendarMeetingEvent` à ±2 min. |
| `OneToOne/Services/Teams/TeamsAutoRecordState.swift` | **Créé.** `enum` namespace pur : phases, événements, effets, et `reduce`. |
| `OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift` | **Créé.** Singleton `@MainActor` : applique les effets de `reduce`. Le seul fichier qui connaisse à la fois SwiftData, les notifications et le routeur. |
| `OneToOne/Services/Teams/TeamsReportAvailability.swift` | **Créé.** `enum` namespace pur : un provider IA peut-il générer un rapport en l'état de la configuration ? |
| `OneToOne/Services/MeetingNotificationService.swift` | **Modifié.** 4 catégories et 8 actions de plus, fusionnées dans l'enregistrement existant. |
| `OneToOne/Services/TeamsLauncher.swift` | **Modifié.** Émet le déclencheur 2. |
| `OneToOne/Services/MenuBarController.swift` | **Modifié.** État `RECORDING` (icône rouge + pulse) et clic vers la réunion en cours. |
| `OneToOne/Models/AppSettings.swift` | **Modifié.** Deux clés. |
| `OneToOne/AppDelegate.swift` | **Modifié.** Démarrage du moniteur, observateurs des nouvelles notifications. |

Le dossier `Services/Teams/` isole le chantier : cinq fichiers courts, une responsabilité chacun, dont trois sans aucune dépendance au framework.

---

### Task 1 : la fonction pure de détection

**Files:**
- Create: `OneToOne/Services/Teams/TeamsCallObservation.swift`
- Test: `Tests/TeamsCallObservationTests.swift`

**Interfaces:**
- Consumes: `AgendaProjectResolver.normalizedKey(_:)` (existant, `OneToOne/Services/AgendaProjectResolver.swift`) — normalise un titre en tokens minuscules sans accents ni ponctuation, joints par des espaces.
- Produces: `TeamsCallState`, `TeamsObservationInput`, `TeamsObservationDecision`, `TeamsCallObservation.titleLooksLikeCall(_:)`, `TeamsCallObservation.step(state:input:)`.

> **Pourquoi pas le regex de la spec.** `§3` propose `/\b(call|meeting|appel|réunion|…)\b/i`. Les frontières de mot ICU sur des caractères accentués sont une source de faux négatifs (`réunion`), et le dépôt possède déjà `AgendaProjectResolver.normalizedKey`, qui replie les accents et découpe en tokens. On compare des tokens à un ensemble : plus robuste, plus rapide à tester, et DRY.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsCallObservationTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// La détection d'appel Teams est une heuristique : elle se trompe. Ces tests
/// verrouillent les seuils qui la rendent supportable — 5 s de stabilité avant
/// d'émettre, 30 s d'absence avant de conclure à la fin, 30 s de cooldown entre
/// deux émissions. Les abaisser est une décision, pas un détail.
@Suite("TeamsCallObservation — heuristique de détection d'appel")
struct TeamsCallObservationTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func input(_ present: Bool, _ title: String, _ offset: TimeInterval) -> TeamsObservationInput {
        TeamsObservationInput(isTeamsWindowPresent: present,
                              windowTitle: title,
                              now: t0.addingTimeInterval(offset))
    }

    // MARK: - Reconnaissance du titre

    @Test("Un titre vide ne ressemble pas à un appel")
    func emptyTitle() {
        #expect(!TeamsCallObservation.titleLooksLikeCall(""))
    }

    @Test("Un titre français accentué est reconnu")
    func frenchTitle() {
        #expect(TeamsCallObservation.titleLooksLikeCall("Réunion hebdo | Microsoft Teams"))
    }

    @Test("Un titre anglais est reconnu")
    func englishTitle() {
        #expect(TeamsCallObservation.titleLooksLikeCall("Weekly Call — Microsoft Teams"))
    }

    @Test("Un titre sans mot d'appel n'est pas reconnu")
    func chatTitle() {
        #expect(!TeamsCallObservation.titleLooksLikeCall("Discussion | Microsoft Teams"))
    }

    // MARK: - Machine à états

    @Test("5 s pile de stabilité suffisent à émettre callStarted")
    func exactlyFiveSeconds() {
        var state = TeamsCallState()
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5)) == .callStarted)
    }

    @Test("4,9 s ne suffisent pas")
    func justUnderFiveSeconds() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 4.9)) == .none)
    }

    @Test("Aucune fenêtre Teams → aucune décision")
    func noTeamsWindow() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(false, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "Réunion", 10)) == .none)
    }

    @Test("Une fenêtre qui disparaît avant 5 s ramène à l'état initial sans rien émettre")
    func flickerIsIgnored() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 2)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 3)) == .none)
        // Le compteur est reparti de 3 s, pas de 0 s : 5 s après 3 s → 8 s.
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 8)) == .callStarted)
    }

    @Test("Deux détections à moins de 30 s d'écart n'émettent qu'un seul callStarted")
    func cooldownMergesDetections() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5)) == .callStarted)
        // La fenêtre disparaît brièvement puis revient : pas de second popup.
        _ = TeamsCallObservation.step(state: &state, input: input(false, "", 6))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 7))
        #expect(TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 12)) == .none)
    }

    @Test("30 s pile d'absence concluent à la fin de l'appel")
    func endAfterThirtySeconds() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 10)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 39.9)) == .none)
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 40)) == .callEnded)
    }

    @Test("Un retour de la fenêtre avant 30 s annule la fin d'appel")
    func returningWindowCancelsEnd() {
        var state = TeamsCallState()
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 0))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 5))
        _ = TeamsCallObservation.step(state: &state, input: input(false, "", 10))
        _ = TeamsCallObservation.step(state: &state, input: input(true, "Réunion", 20))
        #expect(TeamsCallObservation.step(state: &state, input: input(false, "", 45)) == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsCallObservationTests`
Expected: échec de compilation — « cannot find 'TeamsCallObservation' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/TeamsCallObservation.swift` :

```swift
import Foundation

/// Décision rendue par un tick d'observation.
enum TeamsObservationDecision: Equatable {
    case none
    case callStarted
    case callEnded
}

/// État interne de l'observation Teams. Sans dépendance framework : c'est ce
/// qui rend la machine testable sans lancer d'application.
struct TeamsCallState: Equatable {
    enum Phase: String, Equatable {
        /// Rien en vue.
        case idle
        /// Une fenêtre plausible est apparue, on attend qu'elle se stabilise.
        case observing
        /// Appel considéré comme actif ; `callStarted` a été émis.
        case stable
    }
    var phase: Phase = .idle
    /// Instant depuis lequel la fenêtre est présente sans interruption.
    var stableSince: Date?
    /// Instant depuis lequel la fenêtre a disparu, alors qu'on était en `stable`.
    var absentSince: Date?
    /// Dernier `callStarted` émis — sert au cooldown.
    var lastEmittedAt: Date?
}

/// Entrée d'un tick d'observation. `isTeamsWindowPresent` vaut vrai si une
/// fenêtre Teams est au premier plan, ou — quand l'énumération est disponible —
/// si elle existe quelque part (cf. `TeamsCallMonitor`).
struct TeamsObservationInput: Equatable {
    let isTeamsWindowPresent: Bool
    let windowTitle: String
    let now: Date
}

/// Heuristique « un appel Teams est en cours », en fonctions pures.
///
/// Philosophie (spec §3) : **pas de popup vaut mieux qu'un faux positif**. Un
/// popup non sollicité crée une réunion et démarre un enregistrement — bruit,
/// dérangement, ménage à faire. Les seuils ci-dessous sont volontairement hauts.
enum TeamsCallObservation {

    /// Durée de présence ininterrompue avant de conclure à un appel.
    static let stabilityDelay: TimeInterval = 5
    /// Durée d'absence avant de conclure à la fin de l'appel.
    static let absenceDelay: TimeInterval = 30
    /// Deux `callStarted` séparés de moins que ça sont fusionnés.
    static let cooldown: TimeInterval = 30

    /// Mots, en forme normalisée (minuscules, sans accents), dont la présence
    /// dans le titre d'une fenêtre Teams fait suspecter un appel. Liste **en
    /// dur** : voir spec §14 Q12. L'ajuster demande de constater des faux
    /// positifs réels, pas de les imaginer.
    static let callTokens: Set<String> = [
        "call", "meeting", "appel", "reunion", "conference", "meet", "visio"
    ]

    /// Vrai si le titre contient l'un des `callTokens`. La comparaison passe
    /// par `AgendaProjectResolver.normalizedKey`, qui replie les accents et la
    /// ponctuation : « Réunion hebdo | Microsoft Teams » → « reunion hebdo
    /// microsoft teams ».
    static func titleLooksLikeCall(_ title: String) -> Bool {
        let tokens = AgendaProjectResolver.normalizedKey(title).split(separator: " ")
        return tokens.contains { callTokens.contains(String($0)) }
    }

    /// Avance la machine d'un tick et rend la décision correspondante.
    /// `state` est modifié en place ; la fonction reste pure au sens où sa
    /// sortie ne dépend que de `state` et `input`.
    static func step(state: inout TeamsCallState, input: TeamsObservationInput) -> TeamsObservationDecision {
        let matches = input.isTeamsWindowPresent && titleLooksLikeCall(input.windowTitle)

        guard matches else {
            switch state.phase {
            case .stable:
                guard let since = state.absentSince else {
                    state.absentSince = input.now
                    return .none
                }
                guard input.now.timeIntervalSince(since) >= absenceDelay else { return .none }
                state.phase = .idle
                state.absentSince = nil
                state.stableSince = nil
                return .callEnded
            case .observing:
                // Simple clignotement : on repart de zéro sans rien émettre.
                state.phase = .idle
                state.stableSince = nil
                return .none
            case .idle:
                return .none
            }
        }

        state.absentSince = nil

        switch state.phase {
        case .idle:
            state.phase = .observing
            state.stableSince = input.now
            return .none

        case .observing:
            guard let since = state.stableSince,
                  input.now.timeIntervalSince(since) >= stabilityDelay else { return .none }
            state.phase = .stable
            if let last = state.lastEmittedAt,
               input.now.timeIntervalSince(last) < cooldown {
                // Même appel, détecté à nouveau : on ne redemande rien.
                return .none
            }
            state.lastEmittedAt = input.now
            return .callStarted

        case .stable:
            return .none
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsCallObservationTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/TeamsCallObservation.swift Tests/TeamsCallObservationTests.swift
git commit -m "feat(teams): heuristique pure de detection d'appel Teams"
```

---

### Task 2 : l'appariement avec l'agenda

**Files:**
- Create: `OneToOne/Services/Teams/TeamsCallMatchService.swift`
- Test: `Tests/TeamsCallMatchServiceTests.swift`

**Interfaces:**
- Consumes: `CalendarMeetingEvent` (existant, `OneToOne/Services/CalendarMeetingImportService.swift`) — `struct` avec `id: String`, `title: String`, `startDate: Date`, `endDate: Date`, `calendarTitle: String`, `attendees: [CalendarMeetingAttendee]`, `teamsJoinURL: String?`, `isCancelled: Bool`, `isAllDay: Bool`, et son initialiseur mémberwise interne.
- Produces: `TeamsCallMatch`, `TeamsCallMatchService.match(events:at:tolerance:)`.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsCallMatchServiceTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// L'appariement est le second garde-fou contre les faux positifs : même si la
/// fenêtre Teams ressemble à un appel, aucun popup n'est émis sans événement
/// d'agenda commençant à ±2 min. Ces tests verrouillent la tolérance.
@Suite("TeamsCallMatchService — appariement appel ↔ agenda")
struct TeamsCallMatchServiceTests {

    private let now = Date(timeIntervalSinceReferenceDate: 2_000_000)

    private func event(_ id: String, startOffset: TimeInterval, cancelled: Bool = false) -> CalendarMeetingEvent {
        let start = now.addingTimeInterval(startOffset)
        return CalendarMeetingEvent(
            id: id,
            title: "Réunion \(id)",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarTitle: "Pro",
            attendees: [],
            teamsJoinURL: "https://teams.microsoft.com/l/meetup-join/\(id)",
            isCancelled: cancelled,
            isAllDay: false)
    }

    @Test("Un événement commencé il y a 1 min correspond")
    func matchesOneMinuteAgo() {
        let e = event("A", startOffset: -60)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .matched(e))
    }

    @Test("Un événement commençant dans 2 min pile correspond")
    func matchesExactlyTwoMinutesAhead() {
        let e = event("A", startOffset: 120)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .matched(e))
    }

    @Test("Un événement commencé il y a 3 min ne correspond pas")
    func noMatchThreeMinutesAgo() {
        #expect(TeamsCallMatchService.match(events: [event("A", startOffset: -180)], at: now) == .none)
    }

    @Test("Aucun événement → aucune correspondance")
    func noEvents() {
        #expect(TeamsCallMatchService.match(events: [], at: now) == .none)
    }

    @Test("Deux événements dans la fenêtre → ambiguïté, pas de choix arbitraire")
    func ambiguousMatch() {
        let a = event("A", startOffset: -30)
        let b = event("B", startOffset: 30)
        #expect(TeamsCallMatchService.match(events: [a, b], at: now) == .ambiguous([a, b]))
    }

    @Test("Un événement annulé est ignoré")
    func cancelledIsIgnored() {
        #expect(TeamsCallMatchService.match(events: [event("A", startOffset: 0, cancelled: true)],
                                            at: now) == .none)
    }

    @Test("Un événement sans lien Teams est ignoré")
    func withoutTeamsURLIsIgnored() {
        let start = now
        let e = CalendarMeetingEvent(id: "A", title: "Point interne",
                                     startDate: start, endDate: start.addingTimeInterval(1800),
                                     calendarTitle: "Pro", attendees: [],
                                     teamsJoinURL: nil, isCancelled: false, isAllDay: false)
        #expect(TeamsCallMatchService.match(events: [e], at: now) == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsCallMatchServiceTests`
Expected: échec de compilation — « cannot find 'TeamsCallMatchService' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/TeamsCallMatchService.swift` :

```swift
import Foundation

/// Résultat de l'appariement entre un appel détecté et l'agenda.
enum TeamsCallMatch: Equatable {
    /// Aucun événement plausible : on n'émet **aucun** popup (spec §10).
    case none
    case matched(CalendarMeetingEvent)
    /// Plusieurs événements plausibles. Le coordinateur ne choisit pas à la
    /// place de l'utilisateur : il n'émet pas de popup de démarrage.
    case ambiguous([CalendarMeetingEvent])
}

/// Apparie un instant à un événement d'agenda. Fonctions pures : le service ne
/// lit pas EventKit lui-même, l'appelant lui passe les événements du jour
/// (`CalendarAgendaService.events(for:)`).
enum TeamsCallMatchService {

    /// Tolérance autour du `startDate` de l'événement (spec D-2).
    static let tolerance: TimeInterval = 120

    /// Retourne l'événement dont le `startDate` tombe dans
    /// `[instant − tolerance, instant + tolerance]`.
    ///
    /// Les événements annulés et ceux sans lien Teams sont écartés : sans lien
    /// Teams, rien ne dit que l'appel détecté est celui-là.
    static func match(events: [CalendarMeetingEvent],
                      at instant: Date,
                      tolerance: TimeInterval = tolerance) -> TeamsCallMatch {
        let candidates = events.filter { event in
            guard !event.isCancelled, !event.isAllDay else { return false }
            guard let url = event.teamsJoinURL, !url.isEmpty else { return false }
            return abs(event.startDate.timeIntervalSince(instant)) <= tolerance
        }
        switch candidates.count {
        case 0:  return .none
        case 1:  return .matched(candidates[0])
        default: return .ambiguous(candidates)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsCallMatchServiceTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/TeamsCallMatchService.swift Tests/TeamsCallMatchServiceTests.swift
git commit -m "feat(teams): appariement pur appel Teams vers evenement d'agenda"
```

---

### Task 3 : le moniteur `NSWorkspace`

**Files:**
- Create: `OneToOne/Services/Teams/TeamsCallMonitor.swift`
- Test: `Tests/TeamsCallMonitorTests.swift`

**Interfaces:**
- Consumes: `TeamsCallObservation.step(state:input:)`, `TeamsCallState`, `TeamsObservationInput`, `TeamsObservationDecision` (Task 1).
- Produces: `TeamsCallMonitor.shared`, `TeamsCallMonitor.start()`, `TeamsCallMonitor.stop()`, les noms de notification `TeamsCallMonitor.callStartedNotification` et `TeamsCallMonitor.callEndedNotification`, et la fonction pure `TeamsCallMonitor.teamsWindowTitle(in:)`.

> **Ce qui est testable et ce qui ne l'est pas.** `NSWorkspace` et `SCShareableContent` ne se simulent pas en test unitaire. On extrait donc la seule décision non triviale de cette classe — « parmi ces fenêtres, laquelle est une fenêtre Teams d'appel ? » — en fonction pure sur une liste de paires `(bundleID, title)`. Le reste de la classe est du câblage, couvert par le test manuel de `§9`.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsCallMonitorTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Le moniteur choisit une fenêtre parmi celles que le système lui présente.
/// C'est la seule décision de la classe qui puisse se tromper silencieusement,
/// donc la seule qu'on isole en fonction pure.
@Suite("TeamsCallMonitor — sélection de la fenêtre Teams")
struct TeamsCallMonitorTests {

    @Test("Une fenêtre Teams dont le titre évoque un appel est retenue")
    func picksCallWindow() {
        let windows = [
            (bundleID: "com.apple.Safari", title: "Réunion budget"),
            (bundleID: "com.microsoft.teams2", title: "Réunion hebdo | Microsoft Teams")
        ]
        #expect(TeamsCallMonitor.teamsWindowTitle(in: windows) == "Réunion hebdo | Microsoft Teams")
    }

    @Test("Les deux identifiants de bundle Teams sont acceptés")
    func acceptsBothBundleIdentifiers() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.microsoft.teams", title: "Weekly call")]) == "Weekly call")
    }

    @Test("Une fenêtre Teams de discussion n'est pas retenue")
    func ignoresChatWindow() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.microsoft.teams2", title: "Discussion | Microsoft Teams")]) == nil)
    }

    @Test("Une fenêtre non-Teams au titre évocateur n'est pas retenue")
    func ignoresNonTeamsApp() {
        #expect(TeamsCallMonitor.teamsWindowTitle(
            in: [(bundleID: "com.apple.Safari", title: "Réunion hebdo")]) == nil)
    }

    @Test("Aucune fenêtre → rien")
    func emptyList() {
        #expect(TeamsCallMonitor.teamsWindowTitle(in: []) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsCallMonitorTests`
Expected: échec de compilation — « cannot find 'TeamsCallMonitor' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/TeamsCallMonitor.swift` :

```swift
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

private let teamsLog = Logger(subsystem: "com.onetoone.app", category: "teams")

/// Surveille localement Microsoft Teams et publie `callStarted` / `callEnded`.
/// C'est le **déclencheur 1** de la spec §3 : le moins fiable des trois, et le
/// seul qui puisse produire un faux positif — d'où les seuils de
/// `TeamsCallObservation`.
///
/// Aucune API Microsoft n'est utilisée (décision T-A) : on n'observe que ce que
/// macOS expose, c'est-à-dire l'app au premier plan et les titres de fenêtres.
@MainActor
final class TeamsCallMonitor: NSObject {

    static let shared = TeamsCallMonitor()

    /// Publiée quand un appel est considéré comme démarré. Sans `userInfo` :
    /// l'appariement avec l'agenda est le travail du coordinateur.
    static let callStartedNotification = Notification.Name("OneToOne.TeamsCallMonitor.callStarted")
    static let callEndedNotification = Notification.Name("OneToOne.TeamsCallMonitor.callEnded")

    static let teamsBundleIdentifiers: Set<String> = ["com.microsoft.teams", "com.microsoft.teams2"]

    /// Cadence d'échantillonnage. Les seuils de `TeamsCallObservation` sont de
    /// 5 s et 30 s : une seconde suffit largement et reste négligeable.
    private static let tickInterval: TimeInterval = 1.0

    private var state = TeamsCallState()
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private override init() { super.init() }

    // MARK: - Cycle de vie

    /// Arme l'observation. Idempotent.
    func start() {
        guard timer == nil else { return }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(
                nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in await self?.tick() }
                })
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    /// Désarme l'observation et libère timer et observateurs.
    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { nc.removeObserver($0) }
        workspaceObservers.removeAll()
        timer?.invalidate()
        timer = nil
        state = TeamsCallState()
    }

    // MARK: - Sélection de fenêtre (pure)

    /// Retourne le titre de la première fenêtre appartenant à Teams et dont le
    /// titre évoque un appel. Fonction pure, testée sans système.
    nonisolated static func teamsWindowTitle(in windows: [(bundleID: String, title: String)]) -> String? {
        windows.first { window in
            teamsBundleIdentifiers.contains(window.bundleID)
                && TeamsCallObservation.titleLooksLikeCall(window.title)
        }?.title
    }

    // MARK: - Observation

    /// Un tick : construit l'entrée, avance la machine, publie la décision.
    private func tick() async {
        let observed = await observeWindows()
        var input = TeamsObservationInput(isTeamsWindowPresent: observed != nil,
                                          windowTitle: observed ?? "",
                                          now: Date())
        // `titleLooksLikeCall` sera réévalué par `step` ; on lui passe le titre
        // brut pour que la machine reste seule juge.
        if observed == nil { input = TeamsObservationInput(isTeamsWindowPresent: false, windowTitle: "", now: input.now) }

        switch TeamsCallObservation.step(state: &state, input: input) {
        case .none:
            break
        case .callStarted:
            teamsLog.info("teams call started (source 1)")
            NotificationCenter.default.post(name: Self.callStartedNotification, object: nil)
        case .callEnded:
            teamsLog.info("teams call ended (source 1)")
            NotificationCenter.default.post(name: Self.callEndedNotification, object: nil)
        }
    }

    /// Titre de la fenêtre Teams pertinente, ou `nil`.
    ///
    /// Deux niveaux, par ordre de qualité décroissante :
    /// 1. si la permission d'enregistrement d'écran est **déjà** accordée,
    ///    `SCShareableContent` énumère toutes les fenêtres, arrière-plan
    ///    compris — Teams n'a alors pas besoin d'être au premier plan ;
    /// 2. sinon, on se rabat sur l'app au premier plan.
    ///
    /// `CGPreflightScreenCaptureAccess()` ne déclenche **aucune** demande de
    /// permission : tant que l'utilisateur n'a pas enregistré une réunion à
    /// deux pistes, on reste silencieusement au niveau 2 (spec D-11).
    private func observeWindows() async -> String? {
        if CGPreflightScreenCaptureAccess() {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false)
                let windows = content.windows.compactMap { window -> (bundleID: String, title: String)? in
                    guard let bundleID = window.owningApplication?.bundleIdentifier,
                          let title = window.title, !title.isEmpty else { return nil }
                    return (bundleID: bundleID, title: title)
                }
                return Self.teamsWindowTitle(in: windows)
            } catch {
                teamsLog.warning("SCShareableContent indisponible: \(error.localizedDescription)")
                // On retombe sur le premier plan plutôt que de conclure « absent ».
            }
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              Self.teamsBundleIdentifiers.contains(bundleID) else { return nil }
        return Self.teamsWindowTitle(in: [(bundleID: bundleID, title: frontmostWindowTitle(of: front) ?? "")])
    }

    /// Titre de la fenêtre principale de l'app donnée, via l'API d'accessibilité
    /// publique `NSRunningApplication` + `CGWindowListCopyWindowInfo`.
    private func frontmostWindowTitle(of app: NSRunningApplication) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == app.processIdentifier,
                  let name = info[kCGWindowName as String] as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }
}
```

> **Note pour l'implémenteur.** `kCGWindowName` n'est renseigné que si la
> permission d'enregistrement d'écran est accordée. Sans elle, le niveau 2
> retourne un titre vide et la détection par la source 1 ne fonctionne pas —
> c'est exactement la dégradation décrite par D-11, et les déclencheurs 2 et 3
> (Task 7) couvrent le cas. Ne pas ajouter de demande de permission ici.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsCallMonitorTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/TeamsCallMonitor.swift Tests/TeamsCallMonitorTests.swift
git commit -m "feat(teams): moniteur NSWorkspace avec enumeration de fenetres opportuniste"
```

---

### Task 4 : les catégories de notification

**Files:**
- Modify: `OneToOne/Services/MeetingNotificationService.swift`
- Test: `Tests/MeetingNotificationCategoriesTests.swift`

**Interfaces:**
- Produces: `MeetingNotificationService.makeCategories()`, les identifiants publics `MeetingNotificationService.TeamsCategory` et `MeetingNotificationService.TeamsAction`, les méthodes d'émission `notifyTeamsCallDetected(meetingTitle:meetingStableID:)`, `notifyTeamsCallEnded(meetingStableID:)`, `notifyTeamsTranscriptReady(segmentCount:meetingStableID:)`, et les noms de notification `teamsActionNotification`.

> **Le piège que ce test verrouille.** `registerCategories()` appelle
> `center.setNotificationCategories([...])`, qui **remplace** l'ensemble
> enregistré. Enregistrer les nouvelles catégories depuis le coordinateur
> effacerait les quatre existantes, et les notifications de réunion perdraient
> silencieusement leurs boutons. D'où l'extraction de `makeCategories()` en
> source unique, et un test qui compte.

- [ ] **Step 1: Write the failing test**

Créer `Tests/MeetingNotificationCategoriesTests.swift` :

```swift
import Testing
import Foundation
import UserNotifications
@testable import OneToOne

/// `setNotificationCategories` remplace l'ensemble enregistré. Ces tests
/// garantissent que les catégories Teams s'**ajoutent** aux catégories réunion
/// au lieu de les écraser — une régression qui, sans test, ne se verrait qu'à
/// l'usage, sous la forme de notifications sans boutons.
@Suite("MeetingNotificationService — catalogue de catégories")
struct MeetingNotificationCategoriesTests {

    @Test("Les neuf catégories sont enregistrées ensemble")
    func allCategoriesPresent() {
        let ids = Set(MeetingNotificationService.makeCategories().map(\.identifier))
        #expect(ids == [
            "MEETING_PRE_START", "MEETING_START", "MEETING_END", "RECORDING_STARTED",
            "TEAMS_CALL_DETECTED", "TEAMS_CALL_LINK", "TEAMS_CALL_ENDED",
            "TEAMS_TRANSCRIPT_READY", "TEAMS_RECORDING_ERROR"
        ])
    }

    @Test("Aucun identifiant de catégorie en double")
    func noDuplicateIdentifiers() {
        let all = MeetingNotificationService.makeCategories().map(\.identifier)
        #expect(all.count == Set(all).count)
    }

    @Test("Le popup de détection propose démarrer, snooze et ignorer")
    func detectedCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_DETECTED" }
        #expect(category?.actions.map(\.identifier) == ["START_RECORD", "SNOOZE_TEAMS_5", "DISMISS_TEAMS"])
    }

    @Test("Le popup de liaison propose de lier ou d'ignorer")
    func linkCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_LINK" }
        #expect(category?.actions.map(\.identifier) == ["LINK_TO_CURRENT", "DISMISS_TEAMS"])
    }

    @Test("Le popup de fin propose arrêter et continuer")
    func endedCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_CALL_ENDED" }
        #expect(category?.actions.map(\.identifier) == ["STOP_AND_FINALIZE", "CONTINUE_RECORDING"])
    }

    @Test("Le popup de transcription prête propose générer et plus tard")
    func transcriptCategoryActions() {
        let category = MeetingNotificationService.makeCategories()
            .first { $0.identifier == "TEAMS_TRANSCRIPT_READY" }
        #expect(category?.actions.map(\.identifier) == ["GENERATE_REPORT", "SKIP_REPORT"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MeetingNotificationCategoriesTests`
Expected: échec de compilation — « type 'MeetingNotificationService' has no member 'makeCategories' ».

- [ ] **Step 3: Write minimal implementation**

Dans `OneToOne/Services/MeetingNotificationService.swift`, ajouter après l'`enum Action` existant :

```swift
    /// Catégories du parcours Teams auto-record (spec §5). Distinctes de
    /// `Category`, qui reste privé aux notifications de réunion.
    enum TeamsCategory {
        static let detected = "TEAMS_CALL_DETECTED"
        /// Variante émise quand un enregistrement tourne déjà : on propose de
        /// lier l'appel à la réunion en cours plutôt que d'en créer une
        /// seconde (spec D-10).
        static let link = "TEAMS_CALL_LINK"
        static let ended = "TEAMS_CALL_ENDED"
        static let transcriptReady = "TEAMS_TRANSCRIPT_READY"
        static let error = "TEAMS_RECORDING_ERROR"
    }

    /// Actions du parcours Teams. Les identifiants voyagent jusqu'au
    /// coordinateur via `teamsActionNotification`.
    enum TeamsAction {
        static let startRecord = "START_RECORD"
        static let linkToCurrent = "LINK_TO_CURRENT"
        static let snooze5 = "SNOOZE_TEAMS_5"
        static let dismiss = "DISMISS_TEAMS"
        static let stopAndFinalize = "STOP_AND_FINALIZE"
        static let continueRecording = "CONTINUE_RECORDING"
        static let generateReport = "GENERATE_REPORT"
        static let skipReport = "SKIP_REPORT"
        static let retrySTT = "RETRY_STT"
    }

    /// Posted quand l'utilisateur touche une action du parcours Teams.
    /// `userInfo` porte `actionID: String` et, si connue, `meetingID: String`.
    static let teamsActionNotification = Notification.Name("OneToOne.MeetingNotificationService.teamsAction")
```

Remplacer le corps de `registerCategories()` et ajouter le catalogue :

```swift
    private func registerCategories() {
        center.setNotificationCategories(Set(Self.makeCategories()))
    }

    /// Catalogue **unique** des catégories de l'application.
    ///
    /// `setNotificationCategories` remplace l'ensemble enregistré : tout ajout
    /// doit passer par ici, jamais par un second appel depuis un autre service.
    nonisolated static func makeCategories() -> [UNNotificationCategory] {
        let openAction = UNNotificationAction(identifier: Action.open,
                                              title: "Ouvrir", options: [.foreground])
        let teamsAction = UNNotificationAction(identifier: Action.teams,
                                               title: "Rejoindre Teams", options: [.foreground])
        let snoozeAction = UNNotificationAction(identifier: Action.snooze5,
                                                title: "Rappeler dans 5 min", options: [])

        let startRecord = UNNotificationAction(identifier: TeamsAction.startRecord,
                                               title: "Démarrer", options: [.foreground])
        let linkToCurrent = UNNotificationAction(identifier: TeamsAction.linkToCurrent,
                                                 title: "Lier à la réunion en cours",
                                                 options: [.foreground])
        let snoozeTeams = UNNotificationAction(identifier: TeamsAction.snooze5,
                                               title: "Dans 5 min", options: [])
        let dismissTeams = UNNotificationAction(identifier: TeamsAction.dismiss,
                                                title: "Ignorer", options: [.destructive])
        let stopAndFinalize = UNNotificationAction(identifier: TeamsAction.stopAndFinalize,
                                                   title: "Arrêter et finaliser", options: [.foreground])
        let continueRecording = UNNotificationAction(identifier: TeamsAction.continueRecording,
                                                     title: "Continuer l'enregistrement", options: [])
        let generateReport = UNNotificationAction(identifier: TeamsAction.generateReport,
                                                  title: "Générer le rapport", options: [.foreground])
        let skipReport = UNNotificationAction(identifier: TeamsAction.skipReport,
                                              title: "Plus tard", options: [])
        let retrySTT = UNNotificationAction(identifier: TeamsAction.retrySTT,
                                            title: "Retenter le STT", options: [.foreground])

        return [
            UNNotificationCategory(identifier: Category.preStart,
                                   actions: [teamsAction, openAction, snoozeAction],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.start,
                                   actions: [teamsAction, openAction], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.end,
                                   actions: [openAction], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.recording,
                                   actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.detected,
                                   actions: [startRecord, snoozeTeams, dismissTeams],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.link,
                                   actions: [linkToCurrent, dismissTeams],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.ended,
                                   actions: [stopAndFinalize, continueRecording],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.transcriptReady,
                                   actions: [generateReport, skipReport], intentIdentifiers: []),
            UNNotificationCategory(identifier: TeamsCategory.error,
                                   actions: [retrySTT, openAction], intentIdentifiers: [])
        ]
    }
```

`Category` et `Action` sont déclarés `private enum` : les rendre internes en retirant `private`, car `makeCategories()` est `nonisolated static` et le test y accède.

Ajouter les trois émetteurs, à la suite de `notifyRecordingStarted` :

```swift
    /// Popup « appel Teams détecté ». `meetingStableID` peut être vide tant
    /// que la réunion n'existe pas : le coordinateur la crée à l'acceptation.
    func notifyTeamsCallDetected(eventTitle: String, meetingStableID: String) {
        postTeams(category: TeamsCategory.detected,
                  title: "Appel Teams détecté : \(eventTitle)",
                  body: "Démarrer l'enregistrement dans OneToOne ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.detected")
    }

    func notifyTeamsCallEnded(meetingStableID: String) {
        postTeams(category: TeamsCategory.ended,
                  title: "Appel Teams terminé",
                  body: "Arrêter l'enregistrement et finaliser la transcription ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.ended")
    }

    func notifyTeamsTranscriptReady(segmentCount: Int, meetingStableID: String) {
        postTeams(category: TeamsCategory.transcriptReady,
                  title: "Transcription prête (\(segmentCount) segments)",
                  body: "Générer le rapport avec le provider IA ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.transcript")
    }

    /// Émission commune. Le `requestIdentifier` est dérivé du `stableID` de la
    /// réunion — **pas** de `persistentModelID`, que le modèle documente comme
    /// inutilisable en identifiant externe. Réémettre la même catégorie pour la
    /// même réunion écrase la précédente, ce qui évite les popups en double.
    private func postTeams(category: String, title: String, body: String,
                           meetingStableID: String, suffix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["meetingID": meetingStableID]
        let id = meetingStableID.isEmpty ? "teams.\(suffix)" : "\(meetingStableID).\(suffix)"
        let request = UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false))
        center.add(request) { error in
            if let error { print("[MeetingNotificationService] teams: \(error)") }
        }
    }
```

Dans `userNotificationCenter(_:didReceive:withCompletionHandler:)`, router les actions Teams **avant** la garde sur `meetingID` — le popup de détection peut arriver sans réunion créée. Remplacer le début de la méthode :

```swift
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let teamsActions: Set<String> = [
            TeamsAction.startRecord, TeamsAction.linkToCurrent,
            TeamsAction.snooze5, TeamsAction.dismiss,
            TeamsAction.stopAndFinalize, TeamsAction.continueRecording,
            TeamsAction.generateReport, TeamsAction.skipReport, TeamsAction.retrySTT
        ]
        if teamsActions.contains(actionID) {
            var info: [AnyHashable: Any] = ["actionID": actionID]
            if let id = userInfo["meetingID"] as? String, !id.isEmpty { info["meetingID"] = id }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.teamsActionNotification,
                                                object: nil, userInfo: info)
            }
            completionHandler()
            return
        }
        guard let meetingID = userInfo["meetingID"] as? String, !meetingID.isEmpty else {
            completionHandler()
            return
        }
        let teamsURL = userInfo["teamsURL"] as? String
```

(la ligne `let actionID = response.actionIdentifier` plus bas devient redondante : la supprimer.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MeetingNotificationCategoriesTests`
Expected: PASS, 6 tests.

> **Écart assumé avec la spec.** `§5` déclare quatre catégories Teams. Il en
> faut une cinquième pour honorer D-10 : quand un enregistrement tourne déjà,
> le popup doit proposer « Lier à la réunion en cours », un libellé que la
> catégorie de détection ne peut pas porter puisque ses actions sont fixées à
> l'enregistrement. Consigner cet écart dans la PR.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/MeetingNotificationService.swift Tests/MeetingNotificationCategoriesTests.swift
git commit -m "feat(teams): quatre categories de notification fusionnees au catalogue existant"
```

---

### Task 5 : la machine à états du coordinateur

**Files:**
- Create: `OneToOne/Services/Teams/TeamsAutoRecordState.swift`
- Test: `Tests/TeamsAutoRecordStateTests.swift`

**Interfaces:**
- Produces: `TeamsAutoRecordPhase`, `TeamsAutoRecordEvent`, `TeamsAutoRecordEffect`, `TeamsAutoRecordState.reduce(phase:event:)`.

> **Pourquoi une réduction pure.** C'est la pièce où les bugs coûtent cher — un
> enregistrement qui ne s'arrête pas, un popup qui revient en boucle, une
> réunion créée deux fois. En séparant « quelle est la nouvelle phase et que
> faut-il faire » (pur) de « comment le faire » (Task 7), la table de
> transitions se teste intégralement sans ouvrir une fenêtre.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsAutoRecordStateTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Table de transitions du parcours auto-record. Le chemin nominal, mais
/// surtout les sorties : refus, snooze, poursuite d'enregistrement, suppression
/// de la réunion en cours de route.
@Suite("TeamsAutoRecordState — machine à états du parcours")
struct TeamsAutoRecordStateTests {

    private func reduce(_ phase: TeamsAutoRecordPhase,
                        _ event: TeamsAutoRecordEvent) -> (TeamsAutoRecordPhase, [TeamsAutoRecordEffect]) {
        TeamsAutoRecordState.reduce(phase: phase, event: event)
    }

    @Test("Chemin nominal complet")
    func nominalPath() {
        var (phase, effects) = reduce(.idle, .callDetected(eventID: "EVT-1"))
        #expect(phase == .detected)
        #expect(effects == [.emitDetectedNotification(eventID: "EVT-1")])

        (phase, effects) = reduce(phase, .userStarted)
        #expect(phase == .recording)
        #expect(effects == [.createAndOpenMeeting, .setMenuBarRecording(true)])

        (phase, effects) = reduce(phase, .callEnded)
        #expect(phase == .callEnded)
        #expect(effects == [.emitEndedNotification])

        (phase, effects) = reduce(phase, .userStopAndFinalize)
        #expect(phase == .finalizing)
        #expect(effects == [.stopRecording, .setMenuBarRecording(false)])

        (phase, effects) = reduce(phase, .transcriptionFinalized(segmentCount: 42))
        #expect(phase == .readyForAI)
        #expect(effects == [.emitTranscriptReadyNotification(segmentCount: 42)])

        (phase, effects) = reduce(phase, .userGenerateReport)
        #expect(phase == .reporting)
        #expect(effects == [.generateReport])

        (phase, effects) = reduce(phase, .reportSucceeded)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Ignorer ramène au repos sans rien créer")
    func dismissReturnsToIdle() {
        let (phase, effects) = reduce(.detected, .userDismissed)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Snooze arme un rappel et attend")
    func snoozeSchedulesReminder() {
        var (phase, effects) = reduce(.detected, .userSnoozed)
        #expect(phase == .snoozed)
        #expect(effects == [.scheduleSnooze(minutes: 5)])

        (phase, effects) = reduce(phase, .snoozeElapsed(eventID: "EVT-1"))
        #expect(phase == .detected)
        #expect(effects == [.emitDetectedNotification(eventID: "EVT-1")])
    }

    @Test("Continuer l'enregistrement revient en capture sans rien arrêter")
    func continueRecordingResumes() {
        let (phase, effects) = reduce(.callEnded, .userContinue)
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    @Test("Reporter le rapport laisse la réunion prête, sans le générer")
    func skipReportKeepsMeetingReady() {
        let (phase, effects) = reduce(.readyForAI, .userSkipReport)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test("Un échec du provider IA n'efface pas le travail : on reste prêt à retenter")
    func reportFailureStaysReady() {
        let (phase, effects) = reduce(.reporting, .reportFailed)
        #expect(phase == .readyForAI)
        #expect(effects == [.notifyReportFailure])
    }

    @Test("La suppression de la réunion pendant la capture force l'arrêt")
    func deletionForcesStop() {
        let (phase, effects) = reduce(.recording, .meetingDeleted)
        #expect(phase == .idle)
        #expect(effects == [.stopRecording, .setMenuBarRecording(false)])
    }

    @Test("Une détection pendant un enregistrement en cours ne relance rien")
    func detectionDuringRecordingIsIgnored() {
        let (phase, effects) = reduce(.recording, .callDetected(eventID: "EVT-2"))
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    @Test("Un événement hors séquence ne change rien")
    func outOfOrderEventIsInert() {
        let (phase, effects) = reduce(.idle, .userStopAndFinalize)
        #expect(phase == .idle)
        #expect(effects.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsAutoRecordStateTests`
Expected: échec de compilation — « cannot find 'TeamsAutoRecordState' in scope ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/TeamsAutoRecordState.swift` :

```swift
import Foundation

/// Phases du parcours auto-record (spec §4). Cet état vit **en mémoire** dans
/// le coordinateur : rien n'est persisté sur la `Meeting` (spec §5). Un crash
/// de l'application perd le parcours en cours — c'est un choix assumé.
enum TeamsAutoRecordPhase: Equatable {
    case idle
    case detected
    case snoozed
    case recording
    case callEnded
    case finalizing
    case readyForAI
    case reporting
}

/// Ce qui arrive au parcours, qu'il vienne du système ou de l'utilisateur.
enum TeamsAutoRecordEvent: Equatable {
    /// Un des trois déclencheurs de §3 a conclu à un appel.
    case callDetected(eventID: String)
    case userStarted
    case userDismissed
    case userSnoozed
    case snoozeElapsed(eventID: String)
    case callEnded
    case userStopAndFinalize
    case userContinue
    case transcriptionFinalized(segmentCount: Int)
    case userGenerateReport
    case userSkipReport
    case reportSucceeded
    case reportFailed
    /// La réunion créée par le parcours a été supprimée sous nos pieds.
    case meetingDeleted
}

/// Ce qu'il faut faire. Le coordinateur (Task 7) est seul à savoir comment.
enum TeamsAutoRecordEffect: Equatable {
    case emitDetectedNotification(eventID: String)
    case createAndOpenMeeting
    case scheduleSnooze(minutes: Int)
    case emitEndedNotification
    case stopRecording
    case emitTranscriptReadyNotification(segmentCount: Int)
    case generateReport
    case notifyReportFailure
    case setMenuBarRecording(Bool)
}

/// Réduction pure du parcours. Toute transition non listée est inerte : un
/// événement hors séquence ne doit jamais faire dérailler la machine.
enum TeamsAutoRecordState {

    static func reduce(phase: TeamsAutoRecordPhase,
                       event: TeamsAutoRecordEvent) -> (TeamsAutoRecordPhase, [TeamsAutoRecordEffect]) {
        switch (phase, event) {

        case (.idle, .callDetected(let eventID)):
            return (.detected, [.emitDetectedNotification(eventID: eventID)])

        case (.detected, .userStarted):
            return (.recording, [.createAndOpenMeeting, .setMenuBarRecording(true)])

        case (.detected, .userDismissed):
            return (.idle, [])

        case (.detected, .userSnoozed):
            return (.snoozed, [.scheduleSnooze(minutes: 5)])

        case (.snoozed, .snoozeElapsed(let eventID)):
            return (.detected, [.emitDetectedNotification(eventID: eventID)])

        case (.snoozed, .userDismissed):
            return (.idle, [])

        case (.recording, .callEnded):
            return (.callEnded, [.emitEndedNotification])

        case (.recording, .meetingDeleted):
            return (.idle, [.stopRecording, .setMenuBarRecording(false)])

        case (.callEnded, .userStopAndFinalize):
            return (.finalizing, [.stopRecording, .setMenuBarRecording(false)])

        case (.callEnded, .userContinue):
            return (.recording, [])

        case (.callEnded, .meetingDeleted):
            return (.idle, [.stopRecording, .setMenuBarRecording(false)])

        case (.finalizing, .transcriptionFinalized(let count)):
            return (.readyForAI, [.emitTranscriptReadyNotification(segmentCount: count)])

        case (.readyForAI, .userGenerateReport):
            return (.reporting, [.generateReport])

        case (.readyForAI, .userSkipReport):
            return (.idle, [])

        case (.reporting, .reportSucceeded):
            return (.idle, [])

        case (.reporting, .reportFailed):
            // On ne perd pas la transcription : la réunion reste prête et
            // l'utilisateur peut retenter depuis la fenêtre (spec §10).
            return (.readyForAI, [.notifyReportFailure])

        default:
            return (phase, [])
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsAutoRecordStateTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/TeamsAutoRecordState.swift Tests/TeamsAutoRecordStateTests.swift
git commit -m "feat(teams): machine a etats pure du parcours auto-record"
```

---

### Task 6 : l'état d'enregistrement dans la barre de menus

**Files:**
- Modify: `OneToOne/Services/MenuBarController.swift`
- Test: `Tests/MenuBarRecordingStateTests.swift`

**Interfaces:**
- Consumes: rien de neuf.
- Produces: `MenuBarController.shared` (référence faible partagée, consommée par `TeamsAutoRecordCoordinator.apply(.setMenuBarRecording:)`), `MenuBarController.setRecording(_:)`, et la fonction pure `MenuBarController.statusSymbol(isRecording:pulseOn:)`.

> **Ce qu'on teste d'une icône.** Pas le rendu — le choix du symbole. La règle
> « rouge pendant l'enregistrement, pulse une fois sur deux, icône d'agenda
> sinon » est une fonction pure de deux booléens ; l'animation elle-même relève
> de la vérification à l'écran de `§9`.

- [ ] **Step 1: Write the failing test**

Créer `Tests/MenuBarRecordingStateTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// L'icône de barre de menus est le seul signal permanent qu'un enregistrement
/// tourne. Se tromper de symbole, c'est laisser l'utilisateur enregistrer sans
/// le savoir.
@Suite("MenuBarController — symbole d'état")
struct MenuBarRecordingStateTests {

    @Test("Au repos, l'icône reste celle de l'agenda")
    func idleKeepsCalendarSymbol() {
        #expect(MenuBarController.statusSymbol(isRecording: false, pulseOn: false) == "calendar.badge.clock")
        #expect(MenuBarController.statusSymbol(isRecording: false, pulseOn: true) == "calendar.badge.clock")
    }

    @Test("En enregistrement, le pulse alterne entre disque plein et disque cerclé")
    func recordingPulses() {
        #expect(MenuBarController.statusSymbol(isRecording: true, pulseOn: true) == "record.circle.fill")
        #expect(MenuBarController.statusSymbol(isRecording: true, pulseOn: false) == "record.circle")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuBarRecordingStateTests`
Expected: échec de compilation — « type 'MenuBarController' has no member 'statusSymbol' ».

- [ ] **Step 3: Write minimal implementation**

Dans `OneToOne/Services/MenuBarController.swift`, ajouter la référence partagée et l'état, près des autres propriétés :

```swift
    /// Instance installée, exposée pour que `TeamsAutoRecordCoordinator` puisse
    /// basculer l'état d'enregistrement sans traverser l'AppDelegate.
    private(set) static weak var shared: MenuBarController?

    private var isRecording = false
    private var pulseOn = false
    private var pulseTimer: Timer?
```

Dans `install(container:)`, en première ligne du corps :

```swift
        Self.shared = self
```

Dans `uninstall()`, avant la libération du timer existant :

```swift
        pulseTimer?.invalidate()
        pulseTimer = nil
        isRecording = false
        if Self.shared === self { Self.shared = nil }
```

Ajouter, dans une nouvelle section :

```swift
    // MARK: - État d'enregistrement

    /// Symbole SF à afficher. Fonction pure : c'est la règle, pas le rendu.
    nonisolated static func statusSymbol(isRecording: Bool, pulseOn: Bool) -> String {
        guard isRecording else { return "calendar.badge.clock" }
        return pulseOn ? "record.circle.fill" : "record.circle"
    }

    /// Bascule l'icône en mode enregistrement (rouge, pulse 0,8 Hz) ou la
    /// rend à l'agenda. Idempotent.
    func setRecording(_ on: Bool) {
        guard isRecording != on else { return }
        isRecording = on
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseOn = on
        if on {
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.625, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.pulseOn.toggle()
                    self.applyStatusImage()
                }
            }
        }
        applyStatusImage()
    }

    /// Applique le symbole courant, teinté en rouge pendant l'enregistrement.
    private func applyStatusImage() {
        guard let button = statusItem?.button else { return }
        let name = Self.statusSymbol(isRecording: isRecording, pulseOn: pulseOn)
        let image = NSImage(systemSymbolName: name, accessibilityDescription:
                                isRecording ? "Enregistrement en cours" : "OneToOne agenda")
        image?.isTemplate = !isRecording
        button.image = image
        button.contentTintColor = isRecording ? .systemRed : nil
    }
```

Dans `refresh()`, remplacer les deux affectations directes de `item.button?.image` par un appel à `applyStatusImage()`, pour que le rafraîchissement périodique n'écrase pas l'état d'enregistrement :

```swift
        applyStatusImage()
```

Enfin, dans le gestionnaire de clic de l'item : quand `isRecording` est vrai et qu'une réunion est en cours, ouvrir cette réunion. `openMeeting(_:)` existe déjà ; ajouter en tête de `buildMenu(settings:)` un premier item quand `isRecording` :

```swift
        if isRecording {
            let item = NSMenuItem(title: "Ouvrir la réunion en cours",
                                  action: #selector(openActiveRecording), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
```

et l'action correspondante, près des autres `@objc` :

```swift
    /// Ouvre la réunion dont l'enregistrement est en cours (spec §4, clic sur
    /// l'icône rouge).
    @objc private func openActiveRecording() {
        guard let meetingID = AudioRecorderService.shared.activeMeetingID else { return }
        NSApp.activate(ignoringOtherApps: true)
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: meetingID, autoStartRecording: false)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuBarRecordingStateTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Run the full suite**

Run: `swift test --skip CalendarImportEventTests`
Expected: PASS, hors les échecs préexistants listés dans `STATUS.md`.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/MenuBarController.swift Tests/MenuBarRecordingStateTests.swift
git commit -m "feat(teams): etat RECORDING rouge et pulse dans la barre de menus"
```

---

### Task 7 : le coordinateur et les trois déclencheurs

**Files:**
- Create: `OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift`
- Modify: `OneToOne/Models/AppSettings.swift` (deux clés, section « Calendar & Menubar Integration »)
- Modify: `OneToOne/Services/TeamsLauncher.swift` (déclencheur 2)
- Modify: `OneToOne/Services/MeetingNotificationService.swift` (déclencheur 3)
- Modify: `OneToOne/AppDelegate.swift` (démarrage et observateurs)
- Test: `Tests/TeamsAutoRecordCoordinatorTests.swift`

**Interfaces:**
- Consumes: `TeamsAutoRecordState.reduce(phase:event:)` (Task 5) ; `TeamsCallMatchService.match(events:at:)` (Task 2) ; `TeamsCallMonitor.callStartedNotification` / `.callEndedNotification` (Task 3) ; `MeetingNotificationService.teamsActionNotification`, `.notifyTeamsCallDetected(eventTitle:meetingStableID:)`, `.notifyTeamsCallEnded(meetingStableID:)`, `.notifyTeamsTranscriptReady(segmentCount:meetingStableID:)`, `.TeamsAction` (Task 4).
- Consumes (existant) : `CalendarAgendaService.shared.events(for:)`, `CalendarMeetingImportService.importEvent(_:context:settings:) -> Meeting`, `QuickLaunchRouter.shared.pendingToken`, `OneToOneLaunchToken(meetingID:autoStartRecording:)`, `Meeting.ensuredStableID`, `AIReportService.generate(meeting:in:settings:additionalContext:onProgress:) async throws -> MeetingReportData`, `AudioRecorderService.shared`.
- Produces: `TeamsAutoRecordCoordinator.shared`, `.start(container:)`, `.stop()`, `.handle(_ event: TeamsAutoRecordEvent)`, `AppSettings.teamsAutoRecordEnabled`, `AppSettings.teamsAudioCaptureModeRaw`.

> **Ce qui rend ce coordinateur simple.** Créer la réunion, l'ouvrir et démarrer
> l'enregistrement est **déjà** un chemin existant : `importEvent` construit la
> `Meeting` avec son `kind`, ses participants et son `calendarEventID`, puis
> `QuickLaunchRouter.pendingToken` avec `autoStartRecording: true` ouvre la
> fenêtre et `MeetingView.onAppear` démarre la capture. Le coordinateur
> n'invente aucun de ces mécanismes ; il les enchaîne.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsAutoRecordCoordinatorTests.swift` :

```swift
import XCTest
import SwiftData
@testable import OneToOne

/// Intégration du coordinateur avec SwiftData : la réunion créée depuis un
/// événement d'agenda doit porter le lien vers l'événement, et une seconde
/// détection du même événement ne doit pas créer un doublon.
@MainActor
final class TeamsAutoRecordCoordinatorTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: cfg)
        let settings = AppSettings()
        context.insert(settings)
        try context.save()
    }

    private func makeEvent(id: String) -> CalendarMeetingEvent {
        let start = Date()
        return CalendarMeetingEvent(
            id: id, title: "Comité hebdo",
            startDate: start, endDate: start.addingTimeInterval(3600),
            calendarTitle: "Pro", attendees: [],
            teamsJoinURL: "https://teams.microsoft.com/l/meetup-join/\(id)",
            isCancelled: false, isAllDay: false)
    }

    private var settings: AppSettings {
        (try! context.fetch(FetchDescriptor<AppSettings>())).first!
    }

    func test_createMeeting_carriesCalendarLink() throws {
        let importer = CalendarMeetingImportService()
        let meeting = importer.importEvent(makeEvent(id: "EVT-1"), context: context, settings: settings)
        try context.save()

        XCTAssertEqual(meeting.calendarEventID, "EVT-1")
        XCTAssertEqual(meeting.title, "Comité hebdo")
        XCTAssertNotNil(meeting.scheduledStart)
        XCTAssertNotNil(meeting.teamsJoinURL)
    }

    func test_secondDetectionOfSameEvent_reusesMeeting() throws {
        let importer = CalendarMeetingImportService()
        let first = importer.importEvent(makeEvent(id: "EVT-1"), context: context, settings: settings)
        try context.save()
        let second = importer.importEvent(makeEvent(id: "EVT-1"), context: context, settings: settings)
        try context.save()

        XCTAssertEqual(first.ensuredStableID, second.ensuredStableID)
        let all = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(all.count, 1, "Un même événement ne doit produire qu'une réunion")
    }

    func test_autoRecordDisabled_blocksDetection() {
        settings.teamsAutoRecordEnabled = false
        let coordinator = TeamsAutoRecordCoordinator.shared
        coordinator.start(container: container)
        defer { coordinator.stop() }

        coordinator.handle(.callDetected(eventID: "EVT-1"))
        XCTAssertEqual(coordinator.phase, .idle, "Réglage désactivé → aucun parcours n'est armé")
    }

    func test_detectionThenDismiss_returnsToIdle() {
        settings.teamsAutoRecordEnabled = true
        let coordinator = TeamsAutoRecordCoordinator.shared
        coordinator.start(container: container)
        defer { coordinator.stop() }

        coordinator.handle(.callDetected(eventID: "EVT-1"))
        XCTAssertEqual(coordinator.phase, .detected)
        coordinator.handle(.userDismissed)
        XCTAssertEqual(coordinator.phase, .idle)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsAutoRecordCoordinatorTests`
Expected: échec de compilation — « cannot find 'TeamsAutoRecordCoordinator' in scope » et « value of type 'AppSettings' has no member 'teamsAutoRecordEnabled' ».

- [ ] **Step 3: Write minimal implementation**

Dans `OneToOne/Models/AppSettings.swift`, à la fin de la section « Calendar & Menubar Integration » (juste après `notifMeetingEnd`) :

```swift
    /// Arme le parcours Teams auto-record (spec §7). Pas d'interface en v2 :
    /// la clé existe pour désactiver le système en cas de besoin.
    var teamsAutoRecordEnabled: Bool = true

    /// Mode de capture souhaité pour les réunions Teams. Stocké en `…Raw`
    /// (contournement du bug SwiftData sur les énumérations persistées).
    /// Bascule automatiquement à `.microOnly` si la permission écran est
    /// refusée. Consommé par le plan 2 (double piste).
    var teamsAudioCaptureModeRaw: String = TeamsAudioCaptureMode.microAndSystem.rawValue
    var teamsAudioCaptureMode: TeamsAudioCaptureMode {
        get { TeamsAudioCaptureMode(rawValue: teamsAudioCaptureModeRaw) ?? .microAndSystem }
        set { teamsAudioCaptureModeRaw = newValue.rawValue }
    }
```

Et, à côté des autres énumérations en tête de `AppSettings.swift` :

```swift
/// Sources audio capturées pour une réunion Teams.
enum TeamsAudioCaptureMode: String, Codable, CaseIterable, Sendable {
    /// Micro seul — mode de repli quand la permission écran est refusée.
    case microOnly
    /// Micro + audio système de Teams, mixés (spec §6.1).
    case microAndSystem
}
```

Créer `OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift` :

```swift
import AppKit
import Foundation
import SwiftData
import os

private let coordLog = Logger(subsystem: "com.onetoone.app", category: "teams-autorecord")

/// Orchestre le parcours auto-record : reçoit les trois déclencheurs de §3,
/// avance la machine à états pure de `TeamsAutoRecordState`, applique les
/// effets. Seul fichier du chantier à connaître à la fois SwiftData, les
/// notifications et le routeur de fenêtres.
@MainActor
final class TeamsAutoRecordCoordinator {

    static let shared = TeamsAutoRecordCoordinator()

    /// Phase courante — en mémoire, jamais persistée (spec §5).
    private(set) var phase: TeamsAutoRecordPhase = .idle

    /// Événement d'agenda du parcours en cours, et réunion créée pour lui.
    private var currentEventID: String?
    private var currentMeetingID: UUID?
    /// Empêche de re-proposer le même appel après un refus (spec §3).
    private var lastHandledEventID: String?

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var snoozeTask: Task<Void, Never>?

    private init() {}

    // MARK: - Cycle de vie

    /// Branche les trois déclencheurs et les retours d'action de notification.
    func start(container: ModelContainer) {
        self.container = container
        let nc = NotificationCenter.default

        observers.append(nc.addObserver(
            forName: TeamsCallMonitor.callStartedNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetectionFromClock() }
            })

        observers.append(nc.addObserver(
            forName: TeamsCallMonitor.callEndedNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handle(.callEnded) }
            })

        // Déclencheur 2 : l'utilisateur a explicitement rejoint depuis OneToOne.
        observers.append(nc.addObserver(
            forName: TeamsLauncher.didJoinNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetectionFromClock() }
            })

        observers.append(nc.addObserver(
            forName: MeetingNotificationService.teamsActionNotification, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleAction(note.userInfo) }
            })

        TeamsCallMonitor.shared.start()
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        snoozeTask?.cancel()
        snoozeTask = nil
        TeamsCallMonitor.shared.stop()
        phase = .idle
        currentEventID = nil
        currentMeetingID = nil
        lastHandledEventID = nil
    }

    // MARK: - Entrée des déclencheurs

    /// Apparie l'instant courant à l'agenda du jour, puis arme le parcours.
    /// Les trois déclencheurs passent par ici : c'est le point unique où l'on
    /// décide qu'un appel « compte » (spec §3).
    private func handleDetectionFromClock() {
        guard settings()?.teamsAutoRecordEnabled ?? false else {
            coordLog.debug("auto-record desactive par reglage")
            return
        }
        let events = CalendarAgendaService.shared.events(for: Date())
        switch TeamsCallMatchService.match(events: events, at: Date()) {
        case .none:
            coordLog.debug("appel detecte sans evenement correspondant — aucun popup")
        case .ambiguous(let candidates):
            coordLog.info("appel ambigu (\(candidates.count) evenements) — aucun popup")
        case .matched(let event):
            guard event.id != lastHandledEventID else {
                coordLog.debug("evenement deja traite — pas de re-popup")
                return
            }
            handle(.callDetected(eventID: event.id))
        }
    }

    /// Traduit une action de notification en événement de la machine.
    private func handleAction(_ userInfo: [AnyHashable: Any]?) {
        guard let actionID = userInfo?["actionID"] as? String else { return }
        switch actionID {
        case MeetingNotificationService.TeamsAction.startRecord:      handle(.userStarted)
        case MeetingNotificationService.TeamsAction.snooze5:          handle(.userSnoozed)
        case MeetingNotificationService.TeamsAction.dismiss:          handle(.userDismissed)
        case MeetingNotificationService.TeamsAction.stopAndFinalize:  handle(.userStopAndFinalize)
        case MeetingNotificationService.TeamsAction.continueRecording: handle(.userContinue)
        case MeetingNotificationService.TeamsAction.generateReport:   handle(.userGenerateReport)
        case MeetingNotificationService.TeamsAction.skipReport:       handle(.userSkipReport)
        default: break
        }
    }

    // MARK: - Machine à états

    /// Avance la machine et applique les effets. Point d'entrée unique, exposé
    /// pour les tests.
    func handle(_ event: TeamsAutoRecordEvent) {
        if case .callDetected(let eventID) = event {
            guard settings()?.teamsAutoRecordEnabled ?? false else { return }
            currentEventID = eventID
        }
        if case .userDismissed = event { lastHandledEventID = currentEventID }

        let (next, effects) = TeamsAutoRecordState.reduce(phase: phase, event: event)
        coordLog.debug("\(String(describing: self.phase)) --\(String(describing: event))--> \(String(describing: next))")
        phase = next
        effects.forEach(apply)
    }

    // MARK: - Effets

    private func apply(_ effect: TeamsAutoRecordEffect) {
        switch effect {
        case .emitDetectedNotification(let eventID):
            guard let event = currentEvent(eventID) else { return }
            MeetingNotificationService.shared.notifyTeamsCallDetected(
                eventTitle: event.title, meetingStableID: "")

        case .createAndOpenMeeting:
            createAndOpenMeeting()

        case .scheduleSnooze(let minutes):
            scheduleSnooze(minutes: minutes)

        case .emitEndedNotification:
            MeetingNotificationService.shared.notifyTeamsCallEnded(
                meetingStableID: currentMeetingID?.uuidString ?? "")

        case .stopRecording:
            // `MeetingView` observe le recorder ; l'arrêt s'y répercute.
            _ = AudioRecorderService.shared.stop()

        case .emitTranscriptReadyNotification(let count):
            MeetingNotificationService.shared.notifyTeamsTranscriptReady(
                segmentCount: count, meetingStableID: currentMeetingID?.uuidString ?? "")

        case .generateReport:
            Task { await generateReport() }

        case .notifyReportFailure:
            MeetingNotificationService.shared.notifyRecordingStarted(
                meetingTitle: "Le provider IA n'a pas pu générer le rapport.")

        case .setMenuBarRecording(let on):
            MenuBarController.shared?.setRecording(on)
        }
    }

    /// Crée la réunion depuis l'événement d'agenda et ouvre sa fenêtre avec
    /// démarrage automatique de l'enregistrement. Réutilise intégralement le
    /// chemin existant `importEvent` + `QuickLaunchRouter`.
    private func createAndOpenMeeting() {
        guard let container, let eventID = currentEventID,
              let event = currentEvent(eventID), let settings = settings() else { return }
        let context = container.mainContext
        let meeting = CalendarMeetingImportService().importEvent(event, context: context, settings: settings)
        // Trace visuelle de la provenance (spec §5) — pas un champ SwiftData.
        if meeting.summary.isEmpty {
            meeting.summary = "Source : Outlook Calendar\n"
        }
        do { try context.save() } catch { coordLog.error("save: \(error.localizedDescription)") }

        let stableID = meeting.ensuredStableID
        currentMeetingID = stableID
        lastHandledEventID = eventID
        NSApp.activate(ignoringOtherApps: true)
        QuickLaunchRouter.shared.pendingToken = OneToOneLaunchToken(
            meetingID: stableID, autoStartRecording: true)
    }

    private func scheduleSnooze(minutes: Int) {
        snoozeTask?.cancel()
        let eventID = currentEventID
        snoozeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let eventID else { return }
            await MainActor.run { self?.handle(.snoozeElapsed(eventID: eventID)) }
        }
    }

    /// Génère le rapport par le chemin existant. Aucun prompt propre au
    /// parcours Teams : `AIReportService` choisit le `ReportTemplate` par
    /// défaut du `kind` (spec §6.4).
    private func generateReport() async {
        guard let container, let meetingID = currentMeetingID,
              let settings = settings() else { handle(.reportFailed); return }
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        guard let meeting = all.first(where: { $0.stableID == meetingID }) else {
            handle(.meetingDeleted)
            return
        }
        do {
            _ = try await AIReportService.generate(meeting: meeting, in: context, settings: settings)
            try context.save()
            handle(.reportSucceeded)
        } catch {
            coordLog.error("rapport: \(error.localizedDescription)")
            handle(.reportFailed)
        }
    }

    // MARK: - Accès au contexte

    private func settings() -> AppSettings? {
        guard let context = container?.mainContext else { return nil }
        return (try? context.fetch(FetchDescriptor<AppSettings>()))?.first
    }

    private func currentEvent(_ eventID: String) -> CalendarMeetingEvent? {
        CalendarAgendaService.shared.events(for: Date()).first { $0.id == eventID }
    }
}
```

Dans `OneToOne/Services/TeamsLauncher.swift`, ajouter le déclencheur 2 en tête de l'`enum` et l'émission dans `open` :

```swift
    /// Émise quand l'utilisateur rejoint explicitement un appel Teams depuis
    /// OneToOne — déclencheur 2 de la spec §3. Signal sans faux positif :
    /// contrairement à la surveillance de fenêtres, l'intention est certaine.
    static let didJoinNotification = Notification.Name("OneToOne.TeamsLauncher.didJoin")
```

et, à la fin du corps de `open(_:)`, après l'ouverture effective de l'URL :

```swift
        NotificationCenter.default.post(name: didJoinNotification, object: nil)
```

Dans `OneToOne/Services/MeetingNotificationService.swift`, ajouter le déclencheur 3 dans `userNotificationCenter(_:willPresent:withCompletionHandler:)`, avant l'appel au `completionHandler` :

```swift
        // Déclencheur 3 de la spec §3 : l'heure de début d'une réunion arrive.
        // Le coordinateur décidera s'il existe un événement Teams apparié.
        if notification.request.content.categoryIdentifier == Category.start {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.meetingStartReachedNotification, object: nil)
            }
        }
```

et déclarer le nom à côté des autres :

```swift
    /// Posted quand une notification `MEETING_START` est présentée — sert de
    /// déclencheur 3 au parcours Teams auto-record.
    static let meetingStartReachedNotification = Notification.Name("OneToOne.MeetingNotificationService.meetingStartReached")
```

Enfin, brancher ce nom dans `TeamsAutoRecordCoordinator.start(container:)`, à la suite des autres observateurs :

```swift
        observers.append(nc.addObserver(
            forName: MeetingNotificationService.meetingStartReachedNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleDetectionFromClock() }
            })
```

Dans `OneToOne/AppDelegate.swift`, après `menuBar.install(container: container)` :

```swift
        // Parcours Teams auto-record : trois déclencheurs, une machine à états.
        TeamsAutoRecordCoordinator.shared.start(container: container)
```

et dans la méthode de terminaison qui nettoie déjà `notifObservers` :

```swift
        TeamsAutoRecordCoordinator.shared.stop()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsAutoRecordCoordinatorTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift OneToOne/Models/AppSettings.swift \
        OneToOne/Services/TeamsLauncher.swift OneToOne/Services/MeetingNotificationService.swift \
        OneToOne/AppDelegate.swift Tests/TeamsAutoRecordCoordinatorTests.swift
git commit -m "feat(teams): coordinateur auto-record et branchement des trois declencheurs"
```

---

### Task 8 : concurrence, provider IA absent, échec du STT

**Files:**
- Create: `OneToOne/Services/Teams/TeamsReportAvailability.swift`
- Modify: `OneToOne/Services/Teams/TeamsAutoRecordState.swift`
- Modify: `OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift`
- Modify: `OneToOne/Services/MeetingNotificationService.swift`
- Test: `Tests/TeamsAutoRecordEdgeCasesTests.swift`

**Interfaces:**
- Consumes: `TeamsAutoRecordState.reduce(phase:event:)`, `TeamsAutoRecordEffect` (Task 5) ; `MeetingNotificationService.TeamsCategory.link`, `.TeamsAction.linkToCurrent`, `.TeamsCategory.error` (Task 4) ; `AppSettings.provider`, `AppSettings.cloudToken` (existants).
- Produces: `TeamsReportAvailability.isAvailable(provider:cloudToken:)` ; les cas `TeamsAutoRecordEvent.callDetectedWhileRecording(eventID:)`, `.userLinkedToCurrentMeeting` ; les effets `TeamsAutoRecordEffect.emitLinkProposal(eventID:)`, `.linkEventToCurrentMeeting(eventID:)`, `.emitSTTErrorNotification` ; les émetteurs `MeetingNotificationService.notifyTeamsCallLinkProposal(eventTitle:meetingStableID:)` et `.notifyTeamsSTTUnavailable(meetingStableID:)` ; la surcharge `notifyTeamsTranscriptReady(segmentCount:meetingStableID:reportAvailable:)`.

> **Trois exigences de la spec que le chemin nominal ne couvre pas.** D-10 (un
> second appel pendant un enregistrement), D-9 (aucun provider IA configuré) et
> le cas « STT muet » de `§10` — ce dernier explique pourquoi `§5` déclare une
> catégorie `TEAMS_RECORDING_ERROR` que rien n'émettait jusqu'ici. Les trois
> sont des embranchements, donc exactement le genre de code qui ne s'exécute
> jamais en démonstration et casse en usage réel.

- [ ] **Step 1: Write the failing test**

Créer `Tests/TeamsAutoRecordEdgeCasesTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

/// Les embranchements du parcours : un second appel pendant un enregistrement,
/// un provider IA absent, un STT qui n'a rien produit. Trois chemins qu'aucune
/// démonstration ne traverse et que l'usage réel trouve tout de suite.
@Suite("Teams auto-record — cas limites")
struct TeamsAutoRecordEdgeCasesTests {

    // MARK: - D-9 : disponibilité du rapport

    @Test("Le provider local est toujours disponible, sans jeton")
    func localProvidersNeedNoToken() {
        #expect(TeamsReportAvailability.isAvailable(provider: .direct, cloudToken: ""))
        #expect(TeamsReportAvailability.isAvailable(provider: .ollama, cloudToken: ""))
        #expect(TeamsReportAvailability.isAvailable(provider: .geminiOAuth, cloudToken: ""))
    }

    @Test("Un provider distant sans jeton n'est pas disponible")
    func remoteProviderWithoutTokenIsUnavailable() {
        #expect(!TeamsReportAvailability.isAvailable(provider: .anthropic, cloudToken: ""))
        #expect(!TeamsReportAvailability.isAvailable(provider: .openai, cloudToken: "   "))
        #expect(!TeamsReportAvailability.isAvailable(provider: .gemini, cloudToken: ""))
    }

    @Test("Un provider distant avec jeton est disponible")
    func remoteProviderWithTokenIsAvailable() {
        #expect(TeamsReportAvailability.isAvailable(provider: .anthropic, cloudToken: "sk-xxx"))
    }

    // MARK: - D-10 : concurrence

    @Test("Un appel détecté pendant un enregistrement propose de lier, pas de créer")
    func secondCallProposesLink() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .recording, event: .callDetectedWhileRecording(eventID: "EVT-2"))
        #expect(phase == .recording, "On ne quitte pas l'enregistrement en cours")
        #expect(effects == [.emitLinkProposal(eventID: "EVT-2")])
    }

    @Test("Accepter la liaison rattache l'événement sans toucher à la capture")
    func linkingKeepsRecording() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .recording, event: .userLinkedToCurrentMeeting(eventID: "EVT-2"))
        #expect(phase == .recording)
        #expect(effects == [.linkEventToCurrentMeeting(eventID: "EVT-2")])
    }

    @Test("Refuser la liaison ne modifie rien")
    func decliningLinkChangesNothing() {
        let (phase, effects) = TeamsAutoRecordState.reduce(phase: .recording, event: .userDismissed)
        #expect(phase == .recording)
        #expect(effects.isEmpty)
    }

    // MARK: - §10 : STT muet

    @Test("Une transcription vide déclenche le popup d'erreur, pas celui du rapport")
    func emptyTranscriptRaisesError() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .finalizing, event: .transcriptionFinalized(segmentCount: 0))
        #expect(phase == .idle)
        #expect(effects == [.emitSTTErrorNotification])
    }

    @Test("Une transcription non vide suit le chemin nominal")
    func nonEmptyTranscriptProceeds() {
        let (phase, effects) = TeamsAutoRecordState.reduce(
            phase: .finalizing, event: .transcriptionFinalized(segmentCount: 1))
        #expect(phase == .readyForAI)
        #expect(effects == [.emitTranscriptReadyNotification(segmentCount: 1)])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TeamsAutoRecordEdgeCasesTests`
Expected: échec de compilation — « cannot find 'TeamsReportAvailability' in scope » et « type 'TeamsAutoRecordEvent' has no member 'callDetectedWhileRecording' ».

- [ ] **Step 3: Write minimal implementation**

Créer `OneToOne/Services/Teams/TeamsReportAvailability.swift` :

```swift
import Foundation

/// Le rapport n'est proposé que si un provider IA peut effectivement répondre
/// (spec D-9). Sans cette garde, le popup promet un rapport que la génération
/// ne pourra pas produire.
enum TeamsReportAvailability {

    /// Vrai si `provider` peut générer un rapport en l'état de la configuration.
    ///
    /// Les providers locaux (`.direct` en MLX in-process, `.ollama` en HTTP
    /// local, `.geminiOAuth` qui s'authentifie via la CLI) n'ont pas besoin de
    /// jeton. Les providers distants en exigent un.
    static func isAvailable(provider: AIProvider, cloudToken: String) -> Bool {
        switch provider {
        case .direct, .ollama, .geminiOAuth:
            return true
        case .anthropic, .openai, .gemini:
            return !cloudToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
```

Dans `OneToOne/Services/Teams/TeamsAutoRecordState.swift`, ajouter deux cas à `TeamsAutoRecordEvent`, après `callDetected` :

```swift
    /// Un appel est détecté alors qu'un enregistrement tourne déjà (spec D-10).
    case callDetectedWhileRecording(eventID: String)
    /// L'utilisateur accepte de rattacher ce second appel à la réunion en cours.
    case userLinkedToCurrentMeeting(eventID: String)
```

et trois effets à `TeamsAutoRecordEffect` :

```swift
    case emitLinkProposal(eventID: String)
    case linkEventToCurrentMeeting(eventID: String)
    /// Le STT n'a rien produit : on propose de le retenter plutôt que de
    /// promettre un rapport (spec §10).
    case emitSTTErrorNotification
```

Dans `reduce`, insérer ces trois transitions **avant** le cas
`(.finalizing, .transcriptionFinalized(let count))` existant, l'ordre des `case`
faisant foi en Swift :

```swift
        case (.recording, .callDetectedWhileRecording(let eventID)):
            return (.recording, [.emitLinkProposal(eventID: eventID)])

        case (.recording, .userLinkedToCurrentMeeting(let eventID)):
            return (.recording, [.linkEventToCurrentMeeting(eventID: eventID)])

        case (.finalizing, .transcriptionFinalized(let count)) where count == 0:
            // Rien à résumer : inutile de proposer un rapport.
            return (.idle, [.emitSTTErrorNotification])
```

Dans `OneToOne/Services/MeetingNotificationService.swift`, ajouter deux
émetteurs et une surcharge, à la suite des trois de la Task 4 :

```swift
    /// Popup « un appel Teams a été détecté pendant un enregistrement ».
    func notifyTeamsCallLinkProposal(eventTitle: String, meetingStableID: String) {
        postTeams(category: TeamsCategory.link,
                  title: "Appel Teams détecté : \(eventTitle)",
                  body: "Un enregistrement est déjà en cours. Lier cet appel à la réunion en cours ?",
                  meetingStableID: meetingStableID,
                  suffix: "teams.link")
    }

    /// Popup « le STT n'a rien produit ».
    func notifyTeamsSTTUnavailable(meetingStableID: String) {
        postTeams(category: TeamsCategory.error,
                  title: "STT indisponible",
                  body: "L'enregistrement audio est conservé. Transcription à retenter.",
                  meetingStableID: meetingStableID,
                  suffix: "teams.error")
    }
```

et remplacer `notifyTeamsTranscriptReady` par une version qui sait taire la
promesse de rapport :

```swift
    /// Quand `reportAvailable` est faux, la notification informe que la
    /// transcription est prête mais ne propose pas de rapport : la catégorie
    /// sans action évite un bouton qui échouerait (spec D-9).
    func notifyTeamsTranscriptReady(segmentCount: Int,
                                    meetingStableID: String,
                                    reportAvailable: Bool = true) {
        postTeams(category: reportAvailable ? TeamsCategory.transcriptReady : Category.recording,
                  title: "Transcription prête (\(segmentCount) segments)",
                  body: reportAvailable
                      ? "Générer le rapport avec le provider IA ?"
                      : "Aucun provider IA configuré — rapport indisponible.",
                  meetingStableID: meetingStableID,
                  suffix: "teams.transcript")
    }
```

Dans `OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift`, router l'action
de liaison dans `handleAction` :

```swift
        case MeetingNotificationService.TeamsAction.linkToCurrent:
            if let eventID = currentEventID { handle(.userLinkedToCurrentMeeting(eventID: eventID)) }
```

aiguiller la détection selon qu'un enregistrement tourne, dans
`handleDetectionFromClock`, en remplaçant l'appel `handle(.callDetected(...))` :

```swift
            if AudioRecorderService.shared.isRecording {
                currentEventID = event.id
                handle(.callDetectedWhileRecording(eventID: event.id))
            } else {
                handle(.callDetected(eventID: event.id))
            }
```

et appliquer les trois nouveaux effets dans `apply`, avant le `case
.setMenuBarRecording` :

```swift
        case .emitLinkProposal(let eventID):
            guard let event = currentEvent(eventID) else { return }
            MeetingNotificationService.shared.notifyTeamsCallLinkProposal(
                eventTitle: event.title, meetingStableID: currentMeetingID?.uuidString ?? "")

        case .linkEventToCurrentMeeting(let eventID):
            linkEventToCurrentMeeting(eventID)

        case .emitSTTErrorNotification:
            MeetingNotificationService.shared.notifyTeamsSTTUnavailable(
                meetingStableID: currentMeetingID?.uuidString ?? "")
```

puis ajouter la méthode de liaison et la garde D-9 :

```swift
    /// Rattache un second événement d'agenda à la réunion déjà en cours, sans
    /// toucher à la capture ni aux participants d'origine (spec §9,
    /// « la Meeting reçoit l'event mais conserve ses participants »).
    private func linkEventToCurrentMeeting(_ eventID: String) {
        guard let container, let meetingID = currentMeetingID,
              let event = currentEvent(eventID) else { return }
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        guard let meeting = all.first(where: { $0.stableID == meetingID }) else { return }
        meeting.calendarEventID = event.id
        meeting.calendarEventTitle = event.title
        if meeting.teamsJoinURL?.isEmpty ?? true { meeting.teamsJoinURL = event.teamsJoinURL }
        lastHandledEventID = eventID
        do { try context.save() } catch { coordLog.error("liaison: \(error.localizedDescription)") }
    }
```

et remplacer l'effet `.emitTranscriptReadyNotification` par une version qui
consulte la disponibilité du provider :

```swift
        case .emitTranscriptReadyNotification(let count):
            let available = settings().map {
                TeamsReportAvailability.isAvailable(provider: $0.provider, cloudToken: $0.cloudToken)
            } ?? false
            MeetingNotificationService.shared.notifyTeamsTranscriptReady(
                segmentCount: count,
                meetingStableID: currentMeetingID?.uuidString ?? "",
                reportAvailable: available)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TeamsAutoRecordEdgeCasesTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Vérifier la non-régression de la machine à états**

Run: `swift test --filter TeamsAutoRecordStateTests`
Expected: PASS, 9 tests. Les transitions du chemin nominal ne doivent pas avoir bougé : les nouveaux `case` s'insèrent avant le cas générique sans le masquer.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Services/Teams/TeamsReportAvailability.swift \
        OneToOne/Services/Teams/TeamsAutoRecordState.swift \
        OneToOne/Services/Teams/TeamsAutoRecordCoordinator.swift \
        OneToOne/Services/MeetingNotificationService.swift \
        Tests/TeamsAutoRecordEdgeCasesTests.swift
git commit -m "feat(teams): concurrence, garde provider IA et popup STT indisponible"
```

---

### Task 9 : vérification à l'écran et clôture

**Files:**
- Modify: `STATUS.md`

> Aucun test automatisé ne couvre ce que `§9` appelle « UI (manuel) » et
> « Smoke ». Cette tâche est la vérification à l'écran exigée par `§12`, sans
> laquelle la PR n'est pas proposable.

- [ ] **Step 1: Construire et lancer l'application**

Run: `Scripts/bump-and-build.sh dev`
Expected: l'app se lance depuis `~/Applications`. Le `default.metallib` prébuilt est embarqué par le script — sans lui, MLX plante à la première opération GPU.

- [ ] **Step 2: Scénario 1 — détection et démarrage**

Créer dans le calendrier un événement Teams commençant dans 1 min. Ouvrir Teams et amener au premier plan une fenêtre dont le titre contient « Réunion ». Attendre 5 s.
Attendu : notification « Appel Teams détecté : … » avec trois boutons. « Démarrer » crée la réunion, ouvre sa fenêtre, lance l'enregistrement, et l'icône de barre de menus passe au rouge en pulsant.

- [ ] **Step 3: Scénario 2 — refus**

Rejouer le scénario 1 et cliquer « Ignorer ».
Attendu : aucune réunion créée, icône inchangée, et **aucun** nouveau popup pour le même événement.

- [ ] **Step 4: Scénario 3 — fin d'appel**

Depuis l'état « enregistrement en cours », quitter Teams (`killall Teams`). Attendre 30 s.
Attendu : notification « Appel Teams terminé ». « Arrêter et finaliser » stoppe la capture et l'icône redevient normale.

- [ ] **Step 5: Scénario 4 — rapport**

Attendu : notification « Transcription prête (N segments) ». « Générer le rapport » remplit le rapport de la réunion, éditable comme celui d'une réunion enregistrée à la main.

- [ ] **Step 6: Scénario 5 — sans permission d'enregistrement d'écran**

Retirer OneToOne de Réglages Système → Confidentialité → Enregistrement de l'écran, relancer, et rejoindre un appel via le bouton « Rejoindre Teams » de OneToOne.
Attendu : le déclencheur 2 fonctionne et le popup s'affiche, alors même que la détection par titre de fenêtre est aveugle. C'est la dégradation prévue par D-11.

- [ ] **Step 7: Mettre `STATUS.md` à jour**

Ajouter l'état du chantier, la prochaine action (« plan 2 — double piste audio ») et la date.

- [ ] **Step 8: Commit**

```bash
git add STATUS.md
git commit -m "docs(status): parcours Teams auto-record verifie a l'ecran"
```

---

## Journal d'exécution (2026-08-28)

Le plan a été exécuté tâche par tâche, chacune revue avant la suivante. Ce journal consigne
ce qui a été livré **différemment** du texte des tâches ci-dessus, et pourquoi. Le code fait
foi ; les tâches restent telles qu'écrites pour la traçabilité.

### Écarts par tâche

| Tâche | Écart | Raison |
|---|---|---|
| 1 | `lastEmittedAt` et le cooldown de 30 s supprimés de `TeamsCallObservation` ; test de cycle complet ajouté. | Code mort : avec 30 s d'absence avant `callEnded` et 5 s de stabilité, deux `callStarted` sont structurellement séparés d'au moins 35 s. La fusion « à moins de 30 s » de la spec §3 est honorée par construction. |
| 2 | Test `allDayIsIgnored` ajouté. | La branche `isAllDay` était implémentée sans aucun test qui la traverse. |
| 3 | `teamsBundleIdentifiers` déclaré `nonisolated` ; `tick()` construit son entrée en un seul `let`. | Diagnostic d'isolation d'acteur ; réaffectation redondante. |
| 4 | Cinq catégories Teams au lieu de quatre (`TEAMS_CALL_LINK`) ; le routage de `didReceive` n'envoie que des valeurs `Sendable` dans la closure. | D-10 exige un libellé « Lier à la réunion en cours » que la catégorie de détection ne peut pas porter ; avertissement de capture. |
| 5 | Deux tests ajoutés (`(snoozed, userDismissed)`, `(callEnded, meetingDeleted)`). | Transitions implémentées sans test. |
| 6 | Pas de `isTemplate = false` ; timer de pulse en mode `.common`. | `contentTintColor` ne teinte que les images template ; le timer se figeait pendant qu'un menu était ouvert. |
| 7 | **Refonte** : le coordinateur ne pilote plus `AudioRecorderService` ni `AIReportService`. Il dépose des `MeetingRequest` (`startRecording`, `stopAndFinalize`, `generateReport`, `retryTranscription`) que `MeetingView` consomme une fois, et la fenêtre lui rend compte (`transcriptionDidFinish`, `reportDidFinish`, `meetingWasDeleted`, `recordingDidFail`). Effets externes livrés par une valeur `Outbound` via `deliver`. Horloge de 30 s comme déclencheur 3 robuste. `OneToOneLaunchToken` égal par `meetingID` seul. `MeetingNotificationService.center` optionnel hors bundle `.app`. | Arrêt, transcription et rapport sont un pipeline privé de `MeetingView` (`JobQueue`, révisions, tâches, alertes, RAG) que le plan proposait de dupliquer ; aucun producteur n'existait pour `transcriptionFinalized`. `willPresent` ne tire qu'au premier plan. Un token différent par option ouvrait une seconde fenêtre. `UNUserNotificationCenter.current()` avortait le hôte de test — le `--skip CalendarImportEventTests` historique n'est plus nécessaire. |
| 7b (ajoutée) | Hooks dans `MeetingView` : consommation des demandes à `onAppear` et sur notification ; comptes rendus après `saveContext()` ; hook de suppression placé **après** le teardown recorder/live de la vue. | Sans ces hooks le parcours s'arrête au premier popup. L'ordre du hook de suppression évite qu'un transcript live non drainé se colle à la réunion suivante. |
| 8 | « Retenter le STT » implémenté (`.userRetrySTT` : `.idle → .finalizing`, la fenêtre relance `retranscribe`). `lastHandledEventID` remplacé par `handledEventIDs` et `linkProposedEventIDs`. | Bouton mort sur le popup d'erreur ; slot unique qui confondait deux garanties. |

### Écarts par rapport à la spec v2.1

- **§5, trace « Source : Outlook Calendar » dans `summary`** : non écrite. `summary` est le corps du
  rapport, écrasé par `apply(report:)` ; `calendarEventID` / `calendarEventTitle` portent déjà le lien.
- **§5, quatre catégories Teams** : cinq (voir tâche 4).
- **§3, déclencheur 3** : `willPresent` conservé, doublé d'une horloge de 30 s dans le coordinateur.
- **`swift test --skip CalendarImportEventTests`** : le `--skip` est devenu inutile (voir tâche 7).

### Vague de correction après revue de branche

La revue finale de branche a rendu « No — with fixes » : cinq constats, soldés en une vague
unique (commits `5c999e1` et suivant).

- **C1 — identité d'une occurrence.** EventKit déplie une série récurrente en un `EKEvent` par
  occurrence, mais toutes portent le même `calendarItemIdentifier`. Deux conséquences : le point
  hebdomadaire n'était proposé qu'une seule fois (`handledEventIDs` bloquait toutes les
  occurrences suivantes), et après une relance « Démarrer » → `importEvent` →
  `findExisting(calendarEventID)` rendait la réunion de la semaine précédente, que
  l'enregistrement écrasait (`wavFilePath`, segments, `rawTranscript`, rapport). L'identité
  d'une réunion est désormais le couple (identifiant, date de début) :
  `findExisting(eventID:startDate:)` côté import, `occurrenceKey(_:)` pour `handledEventIDs` et
  `linkProposedEventIDs` côté coordinateur.
- **I1 — un popup sans réponse ne bloque plus la session.** Une bannière laissée expirer
  n'émet aucun `didReceive` : `.detected`, `.snoozed` et `.readyForAI` étaient définitifs.
  Le réducteur accepte maintenant `callDetected` depuis ces trois phases (supersession, même
  identifiant de requête de notification → la bannière précédente disparaît), et `detected(_:)`
  arbitre par un `switch` explicite sur la phase au lieu d'un `reduce` à blanc. `.finalizing`
  et `.reporting` restent inertes : un travail est en cours.
- **I2 — l'horloge est gardée sur Teams.** Le tick de 30 s appariait l'agenda que Teams tourne
  ou non, donc proposait tout événement Teams à T−2 min ; couplé à I1, un seul popup ignoré
  gelait la fonctionnalité. `TeamsCallMonitor.isTeamsRunning()` (registre des applications,
  aucune permission) garde désormais le déclencheur : sans Teams, l'heure de début est un
  simple rappel, que `MEETING_START` couvre déjà. Non testable unitairement (état système).
- **I3 — double démarrage sur la même réunion.** Le `catch` de `MeetingView.startRecording()`
  signalait `recordingDidFail` sur n'importe quelle erreur, `AudioError.alreadyRecording`
  comprise : le perdant de la course ramenait la machine à `.idle` alors que la capture du
  gagnant tournait. Le signal n'est émis que si `recorder.isRecording(for:)` est faux.
- **I4 — plus de balayage à 1 Hz.** `TeamsCallMonitor` échantillonne à 5 s au repos et à 1 s
  seulement pendant la confirmation d'un candidat (`.observing`) ; les notifications
  `NSWorkspace` continuent de déclencher un tick immédiat, donc l'activation de Teams reste
  détectée sur-le-champ. Avec 5 s de stabilité et 30 s d'absence, la latence pire cas ne croît
  que d'un tick lent. Le non-objectif §1 de la spec est amendé en conséquence.
- **Mode dégradé.** Hors bundle `.app`, `MeetingNotificationService` compare désormais
  `pathExtension.lowercased()` et trace une fois en `.warning` que les notifications système
  sont désactivées, au lieu de rester totalement muet.
- **C1, suite — lien manuel au calendrier.** `importCalendarEvent` écrit désormais
  `scheduledStart`/`scheduledEnd` : sans quoi l'identité (id, début) faisait créer un doublon
  d'une réunion liée à la main.

### Reports connus (revues de tâches, non bloquants)

Consignés dans `STATUS.md` : aucun timeout par phase dans le coordinateur ; l'icône de barre de
menus est pilotée par le coordinateur plutôt que par l'état réel du recorder ;
`TeamsCallMonitor.stop()` n'annule pas un tick en vol ; un « Retenter » dont le `.wav` a disparu
échoue silencieusement ; un popup de liaison périmé (3e événement) n'est pas comparé au candidat
courant. Le double démarrage (`recordingDidFail`) et le mode dégradé muet hors `.app` ont été
soldés par la vague de correction ci-dessus.
