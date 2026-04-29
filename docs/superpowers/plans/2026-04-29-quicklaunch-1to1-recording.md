# Quick-launch 1:1 Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre de lancer un enregistrement de 1:1 (Meeting `kind = .oneToOne`) avec un collaborateur depuis Spotlight, Shortcuts.app, raccourcis clavier globaux, et clic droit dans la sidebar — tous les chemins traversant un routeur central.

**Architecture:** `QuickLaunchRouter` (singleton + EnvironmentObject) reçoit `startOneToOne(collaborator:autoStartRecording:in:)` depuis quatre déclencheurs. Crée un `Meeting` avec `kind = .oneToOne`, le persiste, ouvre une fenêtre dédiée `OneToOneMeetingWindow` (paramétrée par token codable `{meetingID, autoStart}`), qui présente `MeetingView` avec auto-start du recorder à `onAppear`. Le menu "Voir derniers 1:1" applique un filtre sur `MeetingsListView`.

**Tech Stack:** Swift 5.9, SwiftUI macOS 14+, SwiftData, Swift Testing (`@Suite`/`@Test`/`#expect`), CoreSpotlight, App Intents (macOS 14+), Carbon HIToolbox (RegisterEventHotKey), AppKit (NSPanel).

---

## File Structure

**New files:**
- `OneToOne/Services/QuickLaunchRouter.swift` — singleton router, `startOneToOne` + `showRecentOneToOnes`
- `OneToOne/Services/QuickLaunchURLHandler.swift` — parse NSUserActivity → router
- `OneToOne/Services/HotkeySpec.swift` — encode/decode `"⌃⌥⌘A"` ↔ `(modifiers, keyCode)`
- `OneToOne/Services/GlobalHotkeyService.swift` — Carbon RegisterEventHotKey wrapper
- `OneToOne/AppIntents/OneToOneLaunchToken.swift` — `Codable, Hashable` token for window value
- `OneToOne/AppIntents/CollaboratorEntity.swift` — `AppEntity` + `EntityQuery`
- `OneToOne/AppIntents/StartOneToOneIntent.swift` — `AppIntent` + `AppShortcutsProvider`
- `OneToOne/Views/OneToOneQuickPickerWindow.swift` — overlay picker (NSPanel + SwiftUI hosted)
- `OneToOne/Views/SettingsHotkeysSection.swift` — UI for per-collab hotkey binds
- `Tests/QuickLaunchRouterTests.swift`
- `Tests/HotkeySpecTests.swift`
- `Tests/QuickLaunchURLHandlerTests.swift`
- `Tests/SpotlightCollaboratorIndexTests.swift`

**Modified files:**
- `OneToOne/Models/AppSettings.swift` — `+ var collaboratorHotkeys: [String: String]`
- `OneToOne/Services/SpotlightIndexService.swift` — index `Collaborator` (domain `collaborators`)
- `OneToOne/OneToOneApp.swift` — `sharedContainer`, `WindowGroup(for: OneToOneLaunchToken.self)`, env injection of router, `onContinueUserActivity`, `GlobalHotkeyService` startup
- `OneToOne/Views/MeetingView.swift` — add `autoStartRecording: Bool` parameter, auto-start logic
- `OneToOne/Views/MeetingsListView.swift` — observe `router.listFilterCollaborator`, banner + filter
- `OneToOne/Views/Sidebar.swift` — extend `.contextMenu` on collaborator
- `OneToOne/Views/SettingsView.swift` — insert `SettingsHotkeysSection`

---

## Task 1: Add `collaboratorHotkeys` to `AppSettings`

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift` (around line 47, inside `final class AppSettings`)
- Test: `Tests/SwiftDataTests.swift` (add new `@Test` to existing suite)

- [ ] **Step 1: Write the failing test**

Add at the end of the existing `SwiftDataTests` suite, before the closing `}`:

```swift
    @Test("AppSettings.collaboratorHotkeys persists round-trip")
    func appSettingsHotkeysPersist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        settings.collaboratorHotkeys = [
            "11111111-1111-1111-1111-111111111111": "⌃⌥⌘A",
            "22222222-2222-2222-2222-222222222222": "⌘F1"
        ]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(fetched.first?.collaboratorHotkeys.count == 2)
        #expect(fetched.first?.collaboratorHotkeys["11111111-1111-1111-1111-111111111111"] == "⌃⌥⌘A")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "SwiftDataTests/appSettingsHotkeysPersist"`
Expected: FAIL — "value of type 'AppSettings' has no member 'collaboratorHotkeys'".

- [ ] **Step 3: Add the field**

In `OneToOne/Models/AppSettings.swift`, after the existing `meetingCollaboratorColorHex` line (~line 47), insert:

```swift
    /// Bindings de raccourcis clavier globaux par collaborateur.
    /// Clé = `Collaborator.stableID.uuidString`, valeur = keyspec lisible
    /// (ex. `"⌃⌥⌘A"`). Cf. `HotkeySpec` pour le format.
    var collaboratorHotkeys: [String: String] = [:]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "SwiftDataTests/appSettingsHotkeysPersist"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Models/AppSettings.swift Tests/SwiftDataTests.swift
git commit -m "feat(settings): add AppSettings.collaboratorHotkeys field"
```

---

## Task 2: `HotkeySpec` value type (encode/decode)

**Files:**
- Create: `OneToOne/Services/HotkeySpec.swift`
- Test: `Tests/HotkeySpecTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HotkeySpecTests.swift`:

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("HotkeySpec encode/decode")
struct HotkeySpecTests {

    @Test("Round-trip ⌃⌥⌘A")
    func roundTripCmdOptCtrlA() throws {
        let spec = HotkeySpec(modifiers: [.command, .option, .control], keyChar: "A")
        let str = spec.serialized
        #expect(str == "⌃⌥⌘A")

        let parsed = try #require(HotkeySpec(serialized: str))
        #expect(parsed.modifiers == [.command, .option, .control])
        #expect(parsed.keyChar == "A")
    }

    @Test("Modifier order is canonical (⌃⌥⇧⌘ regardless of input order)")
    func canonicalModifierOrder() {
        let s1 = HotkeySpec(modifiers: [.command, .control, .shift, .option], keyChar: "K").serialized
        let s2 = HotkeySpec(modifiers: [.shift, .option, .command, .control], keyChar: "K").serialized
        #expect(s1 == s2)
        #expect(s1 == "⌃⌥⇧⌘K")
    }

    @Test("Function key F1")
    func functionKey() throws {
        let spec = HotkeySpec(modifiers: [.command], keyChar: "F1")
        #expect(spec.serialized == "⌘F1")
        let parsed = try #require(HotkeySpec(serialized: "⌘F1"))
        #expect(parsed.keyChar == "F1")
    }

    @Test("Empty / malformed string fails to parse")
    func malformedRejected() {
        #expect(HotkeySpec(serialized: "") == nil)
        #expect(HotkeySpec(serialized: "ABC") == nil)  // pas de modifier
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "HotkeySpecTests"`
Expected: FAIL — `HotkeySpec` does not exist.

- [ ] **Step 3: Implement `HotkeySpec`**

Create `OneToOne/Services/HotkeySpec.swift`:

```swift
import Foundation

/// Spécification d'un raccourci clavier global, sérialisable en chaîne
/// lisible humainement (ex. `"⌃⌥⌘A"`, `"⌘F1"`).
///
/// Utilisé pour stocker les bindings dans `AppSettings.collaboratorHotkeys`
/// et pour communiquer avec `GlobalHotkeyService` qui traduit vers Carbon.
struct HotkeySpec: Equatable, Hashable {

    enum Modifier: String, CaseIterable {
        case control = "⌃"
        case option  = "⌥"
        case shift   = "⇧"
        case command = "⌘"

        /// Ordre canonique d'affichage / sérialisation: ⌃⌥⇧⌘
        static let canonicalOrder: [Modifier] = [.control, .option, .shift, .command]
    }

    let modifiers: Set<Modifier>
    /// Touche imprimable normalisée majuscule (`"A"`, `"1"`) ou nom de
    /// touche fonction (`"F1"`...`"F19"`).
    let keyChar: String

    /// Représentation canonique sérialisée.
    var serialized: String {
        let mods = Modifier.canonicalOrder.filter { modifiers.contains($0) }
        return mods.map(\.rawValue).joined() + keyChar
    }

    init(modifiers: Set<Modifier>, keyChar: String) {
        self.modifiers = modifiers
        self.keyChar = keyChar.uppercased()
    }

    init?(serialized: String) {
        guard !serialized.isEmpty else { return nil }
        var mods: Set<Modifier> = []
        var rest = serialized
        for mod in Modifier.canonicalOrder {
            if rest.hasPrefix(mod.rawValue) {
                mods.insert(mod)
                rest.removeFirst(mod.rawValue.count)
            }
        }
        guard !mods.isEmpty, !rest.isEmpty else { return nil }
        self.modifiers = mods
        self.keyChar = rest.uppercased()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "HotkeySpecTests"`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/HotkeySpec.swift Tests/HotkeySpecTests.swift
git commit -m "feat(hotkey): add HotkeySpec encode/decode value type"
```

---

## Task 3: `OneToOneLaunchToken` (window value)

**Files:**
- Create: `OneToOne/AppIntents/OneToOneLaunchToken.swift`
- (No dedicated test — covered indirectly by Task 4 router test which uses it.)

- [ ] **Step 1: Create the file**

Create `OneToOne/AppIntents/OneToOneLaunchToken.swift`:

```swift
import Foundation

/// Token transmis comme valeur de `WindowGroup(for: OneToOneLaunchToken.self)`
/// — `Codable` + `Hashable` requis par SwiftUI WindowGroup.
struct OneToOneLaunchToken: Codable, Hashable {
    /// `Meeting.stableID` du meeting à présenter.
    let meetingID: UUID
    /// Si vrai, démarre l'enregistrement à `onAppear`.
    let autoStartRecording: Bool
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/AppIntents/OneToOneLaunchToken.swift
git commit -m "feat(quicklaunch): add OneToOneLaunchToken window value"
```

---

## Task 4: `QuickLaunchRouter` core — `startOneToOne`

**Files:**
- Create: `OneToOne/Services/QuickLaunchRouter.swift`
- Test: `Tests/QuickLaunchRouterTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuickLaunchRouterTests.swift`:

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@MainActor
@Suite("QuickLaunchRouter")
struct QuickLaunchRouterTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Collaborator.self, Meeting.self, Project.self,
            Interview.self, ActionTask.self, AppSettings.self, Entity.self,
            ProjectAlert.self, ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, MeetingAttachment.self, TranscriptChunk.self,
            SlideCapture.self, InterviewAttachment.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("startOneToOne creates Meeting kind=.oneToOne with collab as sole participant")
    func startOneToOneCreatesTaggedMeeting() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Alice", role: "Dev")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()  // fresh, not the shared one
        let meeting = router.startOneToOne(collaborator: collab,
                                           autoStartRecording: true,
                                           in: context)

        #expect(meeting.kind == .oneToOne)
        #expect(meeting.title == "1:1 — Alice")
        #expect(meeting.participants.count == 1)
        #expect(meeting.participants.first?.stableID == collab.stableID)
    }

    @Test("startOneToOne publishes pendingToken with autoStart flag")
    func startOneToOnePublishesToken() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Bob")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        let meeting = router.startOneToOne(collaborator: collab,
                                           autoStartRecording: true,
                                           in: context)

        let token = try #require(router.pendingToken)
        #expect(token.meetingID == meeting.stableID)
        #expect(token.autoStartRecording == true)
    }

    @Test("startOneToOne with autoStartRecording=false sets flag accordingly")
    func startOneToOneWithoutAutoStart() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Carol")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        _ = router.startOneToOne(collaborator: collab,
                                 autoStartRecording: false,
                                 in: context)

        #expect(router.pendingToken?.autoStartRecording == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "QuickLaunchRouterTests"`
Expected: FAIL — `QuickLaunchRouter` does not exist.

- [ ] **Step 3: Implement the router (initial scope: `startOneToOne` only)**

Create `OneToOne/Services/QuickLaunchRouter.swift`:

```swift
import Foundation
import SwiftData
import AppKit

/// Routeur central pour les lancements rapides de 1:1.
/// Tous les déclencheurs (Spotlight handler, AppIntent, hotkey, menu
/// contextuel) appellent `startOneToOne(...)`. SwiftUI observe
/// `pendingToken` pour ouvrir la fenêtre dédiée; `listFilterCollaborator`
/// pour appliquer le filtre dans `MeetingsListView`.
@MainActor
final class QuickLaunchRouter: ObservableObject {

    static let shared = QuickLaunchRouter()

    /// Token consommé par `OneToOneApp` pour ouvrir un `WindowGroup`. Reset
    /// à `nil` après ouverture par `consumePendingToken()`.
    @Published var pendingToken: OneToOneLaunchToken?

    /// Collaborateur cible du filtre "Voir derniers 1:1" dans la liste
    /// des réunions. Reset à `nil` quand l'utilisateur ferme le filtre.
    @Published var listFilterCollaborator: Collaborator?

    /// Init privé pour le singleton; `testInstance()` ouvre une porte pour
    /// les tests qui ne doivent pas piétiner l'état partagé.
    private init() {}

    /// Crée un `Meeting` `kind=.oneToOne`, l'insère dans le contexte,
    /// active l'app, publie le token. Retourne le meeting créé.
    @discardableResult
    func startOneToOne(collaborator: Collaborator,
                       autoStartRecording: Bool,
                       in context: ModelContext) -> Meeting {
        let meeting = Meeting(
            title: "1:1 — \(collaborator.name)",
            date: Date(),
            notes: ""
        )
        meeting.kind = .oneToOne
        context.insert(meeting)
        meeting.participants = [collaborator]

        do {
            try context.save()
        } catch {
            print("[QuickLaunchRouter] save failed: \(error)")
        }

        NSApp.activate(ignoringOtherApps: true)

        pendingToken = OneToOneLaunchToken(
            meetingID: meeting.stableID,
            autoStartRecording: autoStartRecording
        )
        return meeting
    }

    /// Consommé par la vue qui ouvre la fenêtre — reset le token pour ne
    /// pas re-tirer.
    func consumePendingToken() -> OneToOneLaunchToken? {
        let t = pendingToken
        pendingToken = nil
        return t
    }
}

// MARK: - Test helpers

#if DEBUG
extension QuickLaunchRouter {
    /// Crée une instance dédiée aux tests, isolée du singleton partagé.
    static func testInstance() -> QuickLaunchRouter {
        QuickLaunchRouter()
    }
}
#endif
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "QuickLaunchRouterTests"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/QuickLaunchRouter.swift Tests/QuickLaunchRouterTests.swift
git commit -m "feat(quicklaunch): add QuickLaunchRouter with startOneToOne"
```

---

## Task 5: Router `showRecentOneToOnes`

**Files:**
- Modify: `OneToOne/Services/QuickLaunchRouter.swift`
- Test: `Tests/QuickLaunchRouterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `QuickLaunchRouterTests`, before the closing `}`:

```swift
    @Test("showRecentOneToOnes sets listFilterCollaborator and does not touch pendingToken")
    func showRecent() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Dora")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        router.pendingToken = OneToOneLaunchToken(meetingID: UUID(), autoStartRecording: false)

        router.showRecentOneToOnes(for: collab)

        #expect(router.listFilterCollaborator?.stableID == collab.stableID)
        #expect(router.pendingToken != nil)  // not cleared
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "QuickLaunchRouterTests/showRecent"`
Expected: FAIL — `showRecentOneToOnes` does not exist.

- [ ] **Step 3: Implement**

In `OneToOne/Services/QuickLaunchRouter.swift`, after `consumePendingToken()`:

```swift
    /// Active le filtre "1:1 avec X" dans `MeetingsListView`. Ne touche pas
    /// au token de lancement (les deux flux peuvent coexister).
    func showRecentOneToOnes(for collaborator: Collaborator) {
        listFilterCollaborator = collaborator
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "QuickLaunchRouterTests/showRecent"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/QuickLaunchRouter.swift Tests/QuickLaunchRouterTests.swift
git commit -m "feat(quicklaunch): router showRecentOneToOnes(for:)"
```

---

## Task 6: `MeetingView` accepts `autoStartRecording` parameter

**Files:**
- Modify: `OneToOne/Views/MeetingView.swift` (struct decl, add `@State` flag, `.onAppear`)

> Note: this is a SwiftUI behavior best validated via runtime smoke test (Task 18). No unit test here.

- [ ] **Step 1: Add parameter and state**

In `OneToOne/Views/MeetingView.swift`, change the struct decl + state at top of struct:

```swift
struct MeetingView: View {
    @Bindable var meeting: Meeting
    /// Démarre automatiquement le recorder à `onAppear` (déclenché par
    /// quick-launch 1:1). Consommé une seule fois grâce à `didAutoStart`.
    var autoStartRecording: Bool = false

    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    // ... existing services ...

    @State private var didAutoStart = false   // <-- ajouter
```

(Add `@State private var didAutoStart = false` somewhere among the other `@State` declarations.)

- [ ] **Step 2: Hook auto-start in body**

Find the `var body: some View {` block. After the existing `VStack(spacing: 0) { ... }` content (at the end of the body, just before closing brace), add an `.onAppear`:

```swift
        .onAppear {
            guard autoStartRecording, !didAutoStart, !recorder.isRecording else { return }
            didAutoStart = true
            Task { await startRecording() }
        }
```

> If `MeetingView.body` already has a `.onAppear`, merge the guard into it instead of adding a second.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds. Existing call sites (`MeetingView(meeting: meeting)` with default `autoStartRecording=false`) still compile.

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingView.swift
git commit -m "feat(meeting): MeetingView autoStartRecording parameter"
```

---

## Task 7: `OneToOneApp.sharedContainer` + dedicated `WindowGroup`

**Files:**
- Modify: `OneToOne/OneToOneApp.swift`

- [ ] **Step 1: Expose the container as a static**

In `OneToOne/OneToOneApp.swift`, change the struct so `container` is exposed:

```swift
@main
struct OneToOneApp: App {
    /// Container partagé pour les déclencheurs hors hiérarchie SwiftUI
    /// (AppIntent perform, Carbon hotkey callback). Initialisé dans `init()`.
    static var sharedContainer: ModelContainer!

    let container: ModelContainer

    init() {
        // ... existing init body unchanged ...
        // At the very end, after `container = try ModelContainer(...)` succeeds:
        Self.sharedContainer = container
    }
```

Concretely: in the existing `init()`, after each successful `container = try ModelContainer(...)` assignment (the happy-path one and the post-recovery one), add `Self.sharedContainer = container` immediately before exiting the do/catch.

- [ ] **Step 2: Inject router into env + add 1:1 window group**

Replace the `var body: some Scene { ... }` of `OneToOneApp` with:

```swift
    @StateObject private var router = QuickLaunchRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(router)
        }
        .modelContainer(container)

        WindowGroup(id: "1to1-meeting", for: OneToOneLaunchToken.self) { $token in
            OneToOneMeetingWindowContent(token: token)
                .environmentObject(router)
        }
        .modelContainer(container)
    }
```

- [ ] **Step 3: Add `OneToOneMeetingWindowContent`**

At the bottom of `OneToOne/OneToOneApp.swift`, add:

```swift
/// Contenu de la fenêtre `1to1-meeting`. Résout le token vers un `Meeting`
/// via `stableID`, présente `MeetingView` avec `autoStartRecording`.
struct OneToOneMeetingWindowContent: View {
    let token: OneToOneLaunchToken?
    @Environment(\.modelContext) private var context
    @State private var resolved: Meeting?

    var body: some View {
        Group {
            if let resolved {
                MeetingView(meeting: resolved, autoStartRecording: token?.autoStartRecording ?? false)
            } else {
                ProgressView()
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .onAppear { resolveIfNeeded() }
        .onChange(of: token) { _, _ in resolveIfNeeded() }
    }

    private func resolveIfNeeded() {
        guard resolved == nil, let token else { return }
        let target = token.meetingID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == target }
        )
        resolved = try? context.fetch(descriptor).first
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: succeeds. App launches; the new window group is registered but inert until something opens it.

- [ ] **Step 5: Commit**

```bash
git add OneToOne/OneToOneApp.swift
git commit -m "feat(app): expose sharedContainer + 1to1 meeting window group"
```

---

## Task 8: `ContentView` opens window when `pendingToken` set

**Files:**
- Modify: `OneToOne/OneToOneApp.swift` (`ContentView`)

- [ ] **Step 1: Inject `openWindow` and observe router**

In `OneToOne/OneToOneApp.swift`, change `ContentView`:

```swift
struct ContentView: View {
    @State private var selectedTab: String? = "Dashboard"
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: QuickLaunchRouter
    @State private var didRunDataRepair = false

    var body: some View {
        NavigationSplitView {
            MainSidebarView()
                .focusSection()
        } detail: {
            DashboardView()
                .focusSection()
        }
        .onAppear {
            // ... existing code unchanged ...
        }
        .onReceive(router.$pendingToken.compactMap { $0 }) { token in
            openWindow(id: "1to1-meeting", value: token)
            // Drain so the same token doesn't fire twice on view remount.
            _ = router.consumePendingToken()
        }
    }
    // ... rest unchanged ...
}
```

> If `Combine` is not yet imported in this file, add `import Combine` at the top.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/OneToOneApp.swift
git commit -m "feat(app): ContentView opens 1to1 window on router token"
```

---

## Task 9: Sidebar `.contextMenu` on collaborator

**Files:**
- Modify: `OneToOne/Views/Sidebar.swift` (around line 132 for active, ~line 169 for archived — apply only to active here; archived collabs don't make sense for new 1:1)

- [ ] **Step 1: Add router env + extend menu**

In `OneToOne/Views/Sidebar.swift`, in `MainSidebarView` struct:

1. Add the env object near the top of the struct, alongside existing `@Query` and `@Environment`:

```swift
    @EnvironmentObject private var router: QuickLaunchRouter
```

2. Find the `.contextMenu { ... }` attached to the active-collaborator NavigationLink (around line 132). Extend it from:

```swift
                        .contextMenu {
                            Button("Renommer") {
                                renamingName = collaborator.name
                                renamingCollaborator = collaborator
                            }
                            Button(collaborator.isArchived ? "Désarchiver" : "Archiver") {
                                collaborator.isArchived.toggle()
                                saveContext()
                            }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                context.delete(collaborator)
                                saveContext()
                            }
                        }
```

to:

```swift
                        .contextMenu {
                            Button {
                                router.startOneToOne(collaborator: collaborator,
                                                     autoStartRecording: true,
                                                     in: context)
                            } label: {
                                Label("Démarrer 1:1 maintenant", systemImage: "mic.circle.fill")
                            }
                            Button {
                                router.startOneToOne(collaborator: collaborator,
                                                     autoStartRecording: false,
                                                     in: context)
                            } label: {
                                Label("Nouveau 1:1 (sans enregistrer)", systemImage: "doc.badge.plus")
                            }
                            Button {
                                router.showRecentOneToOnes(for: collaborator)
                            } label: {
                                Label("Voir les derniers 1:1", systemImage: "clock.arrow.circlepath")
                            }

                            Divider()

                            Button("Renommer") {
                                renamingName = collaborator.name
                                renamingCollaborator = collaborator
                            }
                            Button(collaborator.isArchived ? "Désarchiver" : "Archiver") {
                                collaborator.isArchived.toggle()
                                saveContext()
                            }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                context.delete(collaborator)
                                saveContext()
                            }
                        }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Sidebar.swift
git commit -m "feat(sidebar): collaborator context menu with 1:1 quick-launch"
```

---

## Task 10: `MeetingsListView` honors `router.listFilterCollaborator`

**Files:**
- Modify: `OneToOne/Views/MeetingsListView.swift`

- [ ] **Step 1: Add router env + extend filter**

Near the top of `MeetingsListView`:

```swift
    @EnvironmentObject private var router: QuickLaunchRouter
```

In `filteredMeetings`, after the existing `if let kind = filterKind { ... }` block, add:

```swift
        if let collab = router.listFilterCollaborator {
            result = result.filter { meeting in
                meeting.kind == .oneToOne &&
                meeting.participants.contains(where: { $0.stableID == collab.stableID })
            }
        }
```

- [ ] **Step 2: Add filter banner**

Just below the existing toolbar `HStack` (around line 167, where `.padding()` and `.background(Color(nsColor: .controlBackgroundColor))` close it), inject a banner conditional:

```swift
            if let collab = router.listFilterCollaborator {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill").foregroundColor(.accentColor)
                    Text("1:1 avec \(collab.name)")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        router.listFilterCollaborator = nil
                    } label: {
                        Label("Retirer le filtre", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.10))
            }
```

- [ ] **Step 3: Build + manual quick check**

Run: `swift build`
Expected: succeeds. (Manual run validation deferred to Task 18.)

- [ ] **Step 4: Commit**

```bash
git add OneToOne/Views/MeetingsListView.swift
git commit -m "feat(meetings): filter list by 1:1 collaborator from router"
```

---

## Task 11: Spotlight indexing for `Collaborator`

**Files:**
- Modify: `OneToOne/Services/SpotlightIndexService.swift`
- Test: `Tests/SpotlightCollaboratorIndexTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SpotlightCollaboratorIndexTests.swift`:

```swift
import Testing
import CoreSpotlight
import Foundation
@testable import OneToOne

@Suite("Spotlight collaborator indexing")
struct SpotlightCollaboratorIndexTests {

    @Test("makeCollaboratorItem yields stable identifier prefixed with 'collaborator-'")
    func itemIdentifierFormat() {
        let collab = Collaborator(name: "Alice", role: "Architecte")
        let item = SpotlightIndexService.shared.makeCollaboratorItemForTesting(collab)
        #expect(item.uniqueIdentifier == "collaborator-\(collab.stableID.uuidString)")
        #expect(item.domainIdentifier == "collaborators")
    }

    @Test("makeCollaboratorItem populates display name and OneToOne keyword")
    func itemAttributes() {
        let collab = Collaborator(name: "Alice", role: "Architecte")
        let item = SpotlightIndexService.shared.makeCollaboratorItemForTesting(collab)
        let attrs = item.attributeSet
        #expect(attrs.displayName == "Alice")
        #expect(attrs.title?.contains("1:1") == true)
        #expect(attrs.keywords?.contains("OneToOne") == true)
        #expect(attrs.keywords?.contains("Alice") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "SpotlightCollaboratorIndexTests"`
Expected: FAIL — `makeCollaboratorItemForTesting` does not exist.

- [ ] **Step 3: Implement indexing**

In `OneToOne/Services/SpotlightIndexService.swift`:

1. Extend `indexAll(projects:)` (around line 9) to accept and index collaborators. Change signature and body:

```swift
    /// Re-index all projects + collaborators at once (call on app startup).
    func indexAll(projects: [Project], collaborators: [Collaborator]) {
        var items: [CSSearchableItem] = []
        for project in projects {
            items.append(makeProjectItem(project))
            items.append(contentsOf: project.infoEntries.map { makeInfoItem($0, project: project) })
            items.append(contentsOf: project.collaboratorEntries.map { makeCollaboratorEntryItem($0, project: project) })
        }
        for collab in collaborators where !collab.isArchived {
            items.append(makeCollaboratorItem(collab))
        }
        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[Spotlight] Bulk indexing failed: \(error)")
            } else {
                print("[Spotlight] Indexed \(items.count) items (\(projects.count) projects, \(collaborators.count) collaborators)")
            }
        }
    }
```

2. Update the `fetchIndexedItemCount` query string (~line 31) to include the new domain:

```swift
        let query = CSSearchQuery(queryString: "domainIdentifier == 'projects' || domainIdentifier == 'project-info' || domainIdentifier == 'project-collaborator-info' || domainIdentifier == 'collaborators'", queryContext: queryContext)
```

3. Add private factory + identifier + test hook at the bottom (before final `}`):

```swift
    private func makeCollaboratorItem(_ collab: Collaborator) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .contact)
        attributes.title = "OneToOne — 1:1 avec \(collab.name)"
        attributes.displayName = collab.name
        attributes.contentDescription = collab.role
        var keywords = ["OneToOne", "1:1", "entretien", collab.name]
        if !collab.role.isEmpty { keywords.append(collab.role) }
        attributes.keywords = keywords
        return CSSearchableItem(
            uniqueIdentifier: collaboratorIdentifier(collab),
            domainIdentifier: "collaborators",
            attributeSet: attributes
        )
    }

    private func collaboratorIdentifier(_ collab: Collaborator) -> String {
        "collaborator-\(collab.stableID.uuidString)"
    }

    /// Test hook only.
    func makeCollaboratorItemForTesting(_ collab: Collaborator) -> CSSearchableItem {
        makeCollaboratorItem(collab)
    }
```

4. Update the existing `index(project:)` call sites by also exposing a `index(collaborator:)`:

```swift
    func index(collaborator: Collaborator) {
        let item = makeCollaboratorItem(collaborator)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error { print("[Spotlight] Indexing collaborator failed: \(error)") }
        }
    }

    func remove(collaborator: Collaborator) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [collaboratorIdentifier(collaborator)]) { error in
            if let error { print("[Spotlight] Delete collaborator failed: \(error)") }
        }
    }
```

5. Update the call site in `OneToOne/OneToOneApp.swift` `reindexSpotlight()`:

```swift
    private func reindexSpotlight() {
        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            SpotlightIndexService.shared.indexAll(projects: allProjects, collaborators: allCollabs)
        } catch {
            print("[Spotlight] Failed to fetch for indexing: \(error)")
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "SpotlightCollaboratorIndexTests"`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/SpotlightIndexService.swift OneToOne/OneToOneApp.swift Tests/SpotlightCollaboratorIndexTests.swift
git commit -m "feat(spotlight): index Collaborator under 'collaborators' domain"
```

---

## Task 12: `QuickLaunchURLHandler` — parse `NSUserActivity`

**Files:**
- Create: `OneToOne/Services/QuickLaunchURLHandler.swift`
- Test: `Tests/QuickLaunchURLHandlerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuickLaunchURLHandlerTests.swift`:

```swift
import Testing
import SwiftData
import CoreSpotlight
import Foundation
@testable import OneToOne

@MainActor
@Suite("QuickLaunchURLHandler")
struct QuickLaunchURLHandlerTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Collaborator.self, Meeting.self, Project.self,
            Interview.self, ActionTask.self, AppSettings.self, Entity.self,
            ProjectAlert.self, ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, MeetingAttachment.self, TranscriptChunk.self,
            SlideCapture.self, InterviewAttachment.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("Activity with collaborator-<uuid> id triggers router.startOneToOne")
    func activityRoutes() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Eve")
        context.insert(collab)
        try context.save()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "collaborator-\(collab.stableID.uuidString)"
        ]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken != nil)
        #expect(router.pendingToken?.autoStartRecording == true)
    }

    @Test("Unknown identifier is a no-op")
    func unknownIdentifierNoOp() throws {
        let context = try makeContext()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "collaborator-deadbeef-dead-dead-dead-deaddeaddead"]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken == nil)
    }

    @Test("Identifier without 'collaborator-' prefix is ignored")
    func wrongPrefixIgnored() throws {
        let context = try makeContext()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "project-something"]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "QuickLaunchURLHandlerTests"`
Expected: FAIL — `QuickLaunchURLHandler` does not exist.

- [ ] **Step 3: Implement**

Create `OneToOne/Services/QuickLaunchURLHandler.swift`:

```swift
import Foundation
import CoreSpotlight
import SwiftData

/// Décode un `NSUserActivity` Spotlight (clic sur résultat collaborateur)
/// vers un appel `QuickLaunchRouter.startOneToOne`.
enum QuickLaunchURLHandler {

    @MainActor
    static func handle(activity: NSUserActivity,
                       router: QuickLaunchRouter,
                       context: ModelContext) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return }

        guard identifier.hasPrefix("collaborator-") else { return }
        let uuidString = String(identifier.dropFirst("collaborator-".count))
        guard let uuid = UUID(uuidString: uuidString) else { return }

        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == uuid }
        )
        guard let collab = try? context.fetch(descriptor).first else {
            print("[QuickLaunchURLHandler] no Collaborator for stableID \(uuid)")
            return
        }

        router.startOneToOne(collaborator: collab,
                             autoStartRecording: true,
                             in: context)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "QuickLaunchURLHandlerTests"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Services/QuickLaunchURLHandler.swift Tests/QuickLaunchURLHandlerTests.swift
git commit -m "feat(quicklaunch): NSUserActivity handler routes Spotlight clicks"
```

---

## Task 13: Wire `onContinueUserActivity` in `ContentView`

**Files:**
- Modify: `OneToOne/OneToOneApp.swift` (`ContentView`)

- [ ] **Step 1: Attach the modifier**

In `OneToOne/OneToOneApp.swift`, on `ContentView`'s `NavigationSplitView`, after the existing `.onAppear { ... }` and `.onReceive` chain, add:

```swift
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            QuickLaunchURLHandler.handle(activity: activity,
                                         router: router,
                                         context: context)
        }
```

Add `import CoreSpotlight` at the top of the file.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/OneToOneApp.swift
git commit -m "feat(app): handle Spotlight CSSearchableItemActionType activity"
```

---

## Task 14: `CollaboratorEntity` (App Intents)

**Files:**
- Create: `OneToOne/AppIntents/CollaboratorEntity.swift`

- [ ] **Step 1: Implement entity + query**

Create `OneToOne/AppIntents/CollaboratorEntity.swift`:

```swift
import AppIntents
import SwiftData
import Foundation

/// Représentation d'un `Collaborator` exposée à App Intents / Shortcuts.
/// Identifiée par `Collaborator.stableID` (UUID stable, sûr à exposer).
struct CollaboratorEntity: AppEntity, Identifiable {
    var id: UUID
    var name: String
    var role: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: role.isEmpty ? nil : "\(role)"
        )
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Collaborateur")
    }

    static var defaultQuery = CollaboratorEntityQuery()
}

struct CollaboratorEntityQuery: EntityQuery, EntityStringQuery {

    @MainActor
    func entities(for ids: [CollaboratorEntity.ID]) async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { ids.contains($0.stableID) }
        )
        let collabs = (try? context.fetch(descriptor)) ?? []
        return collabs.map(Self.toEntity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? context.fetch(descriptor)) ?? []
        let q = string.lowercased()
        return all
            .filter { !$0.isArchived }
            .filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) }
            .map(Self.toEntity)
    }

    @MainActor
    func suggestedEntities() async throws -> [CollaboratorEntity] {
        let context = OneToOneApp.sharedContainer.mainContext
        let descriptor = FetchDescriptor<Collaborator>(
            sortBy: [SortDescriptor(\.pinLevel, order: .reverse), SortDescriptor(\.name)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !$0.isArchived }.prefix(20).map(Self.toEntity)
    }

    private static func toEntity(_ c: Collaborator) -> CollaboratorEntity {
        CollaboratorEntity(id: c.stableID, name: c.name, role: c.role)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/AppIntents/CollaboratorEntity.swift
git commit -m "feat(intents): CollaboratorEntity + EntityQuery for Shortcuts"
```

---

## Task 15: `StartOneToOneIntent` + `AppShortcutsProvider`

**Files:**
- Create: `OneToOne/AppIntents/StartOneToOneIntent.swift`

- [ ] **Step 1: Implement**

Create `OneToOne/AppIntents/StartOneToOneIntent.swift`:

```swift
import AppIntents
import SwiftData
import Foundation

/// App Intent exposé dans Shortcuts.app + Spotlight (action) pour démarrer
/// un 1:1 avec enregistrement automatique. `openAppWhenRun = true` pour
/// que `perform()` tourne dans le process de l'app et écrive dans le store
/// SwiftData partagé.
struct StartOneToOneIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer un 1:1"
    static var description = IntentDescription(
        "Crée un nouveau 1:1 avec le collaborateur sélectionné et démarre l'enregistrement."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Collaborateur")
    var collaborator: CollaboratorEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = OneToOneApp.sharedContainer.mainContext
        let target = collaborator.id
        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate { $0.stableID == target }
        )
        guard let model = try context.fetch(descriptor).first else {
            throw $collaborator.needsValueError("Collaborateur introuvable.")
        }
        QuickLaunchRouter.shared.startOneToOne(
            collaborator: model,
            autoStartRecording: true,
            in: context
        )
        return .result()
    }
}

struct OneToOneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOneToOneIntent(),
            phrases: [
                "Démarrer un 1:1 dans \(.applicationName)",
                "Lancer un 1:1 \(.applicationName)"
            ],
            shortTitle: "Démarrer un 1:1",
            systemImageName: "mic.circle.fill"
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/AppIntents/StartOneToOneIntent.swift
git commit -m "feat(intents): StartOneToOneIntent + AppShortcutsProvider"
```

---

## Task 16: `GlobalHotkeyService` (Carbon wrapper)

**Files:**
- Create: `OneToOne/Services/GlobalHotkeyService.swift`

> Note: Carbon hotkey registration cannot be unit-tested without registering against the real OS. Validation is manual (Task 18).

- [ ] **Step 1: Implement**

Create `OneToOne/Services/GlobalHotkeyService.swift`:

```swift
import Foundation
import AppKit
import Carbon.HIToolbox

/// Wrapper Carbon `RegisterEventHotKey` pour des raccourcis globaux qui
/// fonctionnent même quand l'app n'a pas le focus, sans demander la
/// permission Accessibility (contrairement à `CGEventTap`).
@MainActor
final class GlobalHotkeyService {

    static let shared = GlobalHotkeyService()

    private struct Binding {
        let id: UInt32
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var bindings: [String: Binding] = [:]   // serialized HotkeySpec → binding
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Enregistre un raccourci. Si un binding existait déjà pour ce `spec`,
    /// remplace son handler. Retourne `true` si l'enregistrement a réussi.
    @discardableResult
    func register(spec: HotkeySpec, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        unregister(spec: spec)

        guard let keyCode = Self.keyCode(forKeyChar: spec.keyChar) else {
            print("[GlobalHotkey] unknown keyChar: \(spec.keyChar)")
            return false
        }
        var modifiers: UInt32 = 0
        if spec.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.option)  { modifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.shift)   { modifiers |= UInt32(shiftKey) }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4E4554), id: id)  // 'ONET'

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            print("[GlobalHotkey] register failed for \(spec.serialized): status=\(status)")
            return false
        }

        bindings[spec.serialized] = Binding(id: id, ref: ref, handler: handler)
        return true
    }

    func unregister(spec: HotkeySpec) {
        guard let binding = bindings.removeValue(forKey: spec.serialized) else { return }
        UnregisterEventHotKey(binding.ref)
    }

    func unregisterAll() {
        for (_, binding) in bindings {
            UnregisterEventHotKey(binding.ref)
        }
        bindings.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, theEvent, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            DispatchQueue.main.async {
                GlobalHotkeyService.shared.dispatch(id: hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func dispatch(id: UInt32) {
        guard let binding = bindings.values.first(where: { $0.id == id }) else { return }
        binding.handler()
    }

    /// Mapping des chars vers virtual key codes (Carbon).
    private static func keyCode(forKeyChar char: String) -> UInt32? {
        switch char.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "F1": return UInt32(kVK_F1)
        case "F2": return UInt32(kVK_F2)
        case "F3": return UInt32(kVK_F3)
        case "F4": return UInt32(kVK_F4)
        case "F5": return UInt32(kVK_F5)
        case "F6": return UInt32(kVK_F6)
        case "F7": return UInt32(kVK_F7)
        case "F8": return UInt32(kVK_F8)
        case "F9": return UInt32(kVK_F9)
        case "F10": return UInt32(kVK_F10)
        case "F11": return UInt32(kVK_F11)
        case "F12": return UInt32(kVK_F12)
        default: return nil
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Services/GlobalHotkeyService.swift
git commit -m "feat(hotkey): Carbon-based GlobalHotkeyService wrapper"
```

---

## Task 17: `OneToOneQuickPickerWindow` (overlay collab picker)

**Files:**
- Create: `OneToOne/Views/OneToOneQuickPickerWindow.swift`

- [ ] **Step 1: Implement window controller + SwiftUI content**

Create `OneToOne/Views/OneToOneQuickPickerWindow.swift`:

```swift
import AppKit
import SwiftUI
import SwiftData

/// Fenêtre flottante pour choisir un collaborateur et lancer un 1:1.
/// Présentée par `GlobalHotkeyService` au déclenchement du raccourci
/// d'overlay (`⌃⌥⌘1` par défaut).
@MainActor
final class OneToOneQuickPickerWindow: NSPanel {

    static let shared = OneToOneQuickPickerWindow()

    private convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        animationBehavior = .utilityWindow
    }

    /// Présente la fenêtre centrée à l'écran principal et donne le focus
    /// au champ de recherche.
    func present() {
        let host = NSHostingController(rootView: OneToOneQuickPickerView(onClose: { [weak self] in
            self?.orderOut(nil)
        }))
        contentViewController = host
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

struct OneToOneQuickPickerView: View {
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived },
           sort: [SortDescriptor(\.pinLevel, order: .reverse), SortDescriptor(\.name)])
    private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: QuickLaunchRouter

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    let onClose: () -> Void

    private var filtered: [Collaborator] {
        guard !query.isEmpty else { return Array(collaborators.prefix(20)) }
        let q = query.lowercased()
        return collaborators
            .filter { $0.name.lowercased().contains(q) || $0.role.lowercased().contains(q) }
            .prefix(20)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Rechercher un collaborateur...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { commit() }
                    .onChange(of: query) { _, _ in highlightedIndex = 0 }
            }
            .padding(12)
            Divider()

            List(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, collab in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collab.name).font(.body)
                        if !collab.role.isEmpty {
                            Text(collab.role).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if index == highlightedIndex {
                        Image(systemName: "return").foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .background(index == highlightedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    highlightedIndex = index
                    commit()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 480, height: 360)
        .onAppear { searchFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.downArrow) {
            highlightedIndex = min(highlightedIndex + 1, max(filtered.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlightedIndex = max(highlightedIndex - 1, 0)
            return .handled
        }
    }

    private func commit() {
        guard !filtered.isEmpty else { return }
        let target = filtered[min(highlightedIndex, filtered.count - 1)]
        router.startOneToOne(collaborator: target, autoStartRecording: true, in: context)
        onClose()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/OneToOneQuickPickerWindow.swift
git commit -m "feat(picker): floating quick-launch picker for 1:1 collaborator"
```

---

## Task 18: Settings UI for hotkeys + app startup wiring + smoke test

**Files:**
- Create: `OneToOne/Views/SettingsHotkeysSection.swift`
- Modify: `OneToOne/Views/SettingsView.swift` (insert section)
- Modify: `OneToOne/OneToOneApp.swift` (register overlay hotkey + per-collab binds at startup)

- [ ] **Step 1: Implement `SettingsHotkeysSection`**

Create `OneToOne/Views/SettingsHotkeysSection.swift`:

```swift
import SwiftUI
import SwiftData
import AppKit

/// Section de la fenêtre Settings pour configurer:
/// 1. Le raccourci d'ouverture du picker overlay (`⌃⌥⌘1` par défaut).
/// 2. Un raccourci individuel par collaborateur épinglé (pinLevel ≥ 1).
struct SettingsHotkeysSection: View {
    @Query(filter: #Predicate<Collaborator> { $0.pinLevel >= 1 && !$0.isArchived },
           sort: \Collaborator.name) private var pinnedCollabs: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    private var settings: AppSettings? { settingsList.canonicalSettings }

    var body: some View {
        Section("Raccourcis 1:1") {
            HStack {
                Label("Ouvrir le sélecteur 1:1", systemImage: "magnifyingglass")
                Spacer()
                HotkeyCaptureField(
                    keyspec: Binding(
                        get: { settings?.collaboratorHotkeys["__overlay__"] ?? "⌃⌥⌘1" },
                        set: { newValue in setHotkey("__overlay__", to: newValue) }
                    )
                )
            }

            if pinnedCollabs.isEmpty {
                Text("Épingle un collaborateur dans la sidebar pour lui assigner un raccourci.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(pinnedCollabs) { collab in
                    HStack {
                        Image(systemName: "person.crop.circle").foregroundColor(.accentColor)
                        Text(collab.name)
                        Spacer()
                        HotkeyCaptureField(
                            keyspec: Binding(
                                get: { settings?.collaboratorHotkeys[collab.stableID.uuidString] ?? "" },
                                set: { newValue in setHotkey(collab.stableID.uuidString, to: newValue) }
                            )
                        )
                    }
                }
            }
        }
    }

    private func setHotkey(_ key: String, to newValue: String) {
        guard let settings else { return }
        var map = settings.collaboratorHotkeys
        if newValue.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = newValue
        }
        settings.collaboratorHotkeys = map
        try? context.save()
        NotificationCenter.default.post(name: .collaboratorHotkeysChanged, object: nil)
    }
}

extension Notification.Name {
    static let collaboratorHotkeysChanged = Notification.Name("collaboratorHotkeysChanged")
}

/// Champ qui capture la prochaine combinaison de touches et la sérialise via
/// `HotkeySpec`. Clic = mode capture; Échap pendant capture = clear.
struct HotkeyCaptureField: View {
    @Binding var keyspec: String
    @State private var capturing = false

    var body: some View {
        Button {
            capturing.toggle()
            if capturing { startMonitoring() }
        } label: {
            Text(capturing ? "Tape la combinaison..." : (keyspec.isEmpty ? "—" : keyspec))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 140, alignment: .center)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(capturing ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Clic pour modifier; Échap pour effacer")
    }

    private func startMonitoring() {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            defer { if !capturing, let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }

            if event.keyCode == 0x35 {  // Esc
                keyspec = ""
                capturing = false
                return nil
            }

            var mods: Set<HotkeySpec.Modifier> = []
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            if event.modifierFlags.contains(.option)  { mods.insert(.option) }
            if event.modifierFlags.contains(.control) { mods.insert(.control) }
            if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }

            guard !mods.isEmpty, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
                return event
            }
            let spec = HotkeySpec(modifiers: mods, keyChar: chars)
            keyspec = spec.serialized
            capturing = false
            return nil
        }
    }
}
```

- [ ] **Step 2: Insert section into `SettingsView`**

In `OneToOne/Views/SettingsView.swift`, find the top-level `Form { ... }` (or wrapping container) and insert `SettingsHotkeysSection()` near the top. Concretely, locate where existing sections are declared and add:

```swift
            SettingsHotkeysSection()
```

> If `SettingsView`'s body is split across helper computed properties, drop it into the same one that hosts other `Section(...)` calls.

- [ ] **Step 3: Register overlay + per-collab hotkeys at app startup**

In `OneToOne/OneToOneApp.swift`, in `ContentView.body`'s outer `.onAppear`, after the existing `reindexSpotlight()` call, append:

```swift
            registerHotkeys()

            NotificationCenter.default.addObserver(
                forName: .collaboratorHotkeysChanged,
                object: nil,
                queue: .main
            ) { _ in
                registerHotkeys()
            }
```

Then add `registerHotkeys()` as a private func of `ContentView`:

```swift
    private func registerHotkeys() {
        GlobalHotkeyService.shared.unregisterAll()

        let settings: AppSettings? = (try? context.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings
        let map = settings?.collaboratorHotkeys ?? [:]

        // Overlay (default ⌃⌥⌘1 if absent)
        let overlaySpec = HotkeySpec(serialized: map["__overlay__"] ?? "⌃⌥⌘1")
            ?? HotkeySpec(modifiers: [.control, .option, .command], keyChar: "1")
        _ = GlobalHotkeyService.shared.register(spec: overlaySpec) {
            OneToOneQuickPickerWindow.shared.present()
        }

        // Per-collab
        for (key, serialized) in map where key != "__overlay__" {
            guard let spec = HotkeySpec(serialized: serialized),
                  let uuid = UUID(uuidString: key) else { continue }
            _ = GlobalHotkeyService.shared.register(spec: spec) {
                Task { @MainActor in
                    let descriptor = FetchDescriptor<Collaborator>(
                        predicate: #Predicate { $0.stableID == uuid }
                    )
                    guard let collab = try? context.fetch(descriptor).first else { return }
                    QuickLaunchRouter.shared.startOneToOne(
                        collaborator: collab,
                        autoStartRecording: true,
                        in: context
                    )
                }
            }
        }
    }
```

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: all suites pass (Hotkey, QuickLaunchRouter, QuickLaunchURLHandler, SpotlightCollaboratorIndex, existing SwiftDataTests).

- [ ] **Step 5: Manual smoke test checklist**

Run the app:

```bash
./run.sh
```

(Or `swift run OneToOne` if `run.sh` is unavailable.) Then verify each entry point manually:

- [ ] **Right-click sidebar collaborator → "Démarrer 1:1 maintenant"**
   - New window opens with title "1:1 — \(name)".
   - Recorder starts within ~1s (red recording indicator).
   - Stop recorder, close window. New meeting visible in `MeetingsListView` with kind icon `person.2.fill`.

- [ ] **Right-click sidebar collaborator → "Nouveau 1:1 (sans enregistrer)"**
   - New window opens, recorder NOT started.

- [ ] **Right-click sidebar collaborator → "Voir les derniers 1:1"**
   - Navigate to `MeetingsListView`, banner shows "1:1 avec \(name)", list shows only matching meetings.
   - Click "×" on banner → filter clears.

- [ ] **Spotlight (`⌘+space`) → type collaborator name**
   - Result with "OneToOne — 1:1 avec \(name)" appears.
   - Click → app activates, new 1:1 window opens, recorder starts.

- [ ] **Shortcuts.app → search "Démarrer un 1:1"**
   - App Shortcut "Démarrer un 1:1 dans OneToOne" is suggested.
   - Run with a collaborator → app activates, 1:1 window opens, recorder starts.

- [ ] **Global hotkey `⌃⌥⌘1`**
   - Overlay picker appears centered, search field focused.
   - Type partial name, ↓/↑ navigate, Enter starts 1:1.
   - Esc closes without action.

- [ ] **Settings → "Raccourcis 1:1" section**
   - Pinned collab listed. Click capture field, press `⌃⌥⌘A` → field shows `⌃⌥⌘A`, persists across app restart.
   - Trigger `⌃⌥⌘A` globally → 1:1 with that collab starts directly.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/Views/SettingsHotkeysSection.swift OneToOne/Views/SettingsView.swift OneToOne/OneToOneApp.swift
git commit -m "feat(hotkey): settings section + startup registration of 1:1 hotkeys"
```

---

## Final Self-Review Checklist (run after all tasks)

- [ ] All tests green: `swift test`
- [ ] Build clean: `swift build`
- [ ] All 18 tasks committed
- [ ] Manual smoke checklist (Task 18 Step 5) all green
- [ ] No leftover `print` statements beyond the existing `[Spotlight]` / `[QuickLaunchURLHandler]` diagnostic ones
- [ ] No `TODO`/`FIXME` left in plan-introduced code
