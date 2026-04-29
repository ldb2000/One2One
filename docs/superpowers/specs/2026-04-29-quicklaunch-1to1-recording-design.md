# Quick-launch 1:1 recording

Date: 2026-04-29
Status: Design — awaiting implementation plan

## Goal

Permettre de lancer un enregistrement de 1:1 avec un collaborateur depuis quatre points d'entrée externes ou périphériques à l'app:

1. Recherche Spotlight macOS (résultat "Collaborateur" → app + record).
2. App Shortcuts macOS (App Intent "Démarrer un 1:1").
3. Raccourcis clavier globaux (combo: hotkey unique d'overlay picker + binds par collaborateur configurables).
4. Menu contextuel (clic droit) sur un collaborateur dans la sidebar.

Tous les chemins convergent sur la même action: création d'un `Meeting` taggé 1:1, navigation vers `MeetingView`, démarrage automatique du recorder.

## Non-goals

- Pas de redesign de `Interview` (l'objet reste tel quel pour les imports PPTX/PDF/job).
- Pas de partage de session/recording entre Meeting et Interview.
- Pas de modification du stack transcription/rapport IA.
- Pas de hotkey iOS/iPadOS (macOS uniquement).

## Architecture

### Composant central: `QuickLaunchRouter`

Objet observable, `@MainActor`, **singleton** (`QuickLaunchRouter.shared`) ET injecté dans l'environnement SwiftUI au niveau de `OneToOneApp`. Le singleton sert pour les déclencheurs hors hiérarchie SwiftUI (AppIntent, Carbon hotkey callback, NSUserActivity); l'`@EnvironmentObject` sert aux vues SwiftUI (sidebar contextMenu, MeetingsListView, ContentView). Les deux pointent vers la même instance — l'init de `OneToOneApp` injecte `QuickLaunchRouter.shared` comme `.environmentObject(...)`.

```swift
@MainActor
final class QuickLaunchRouter: ObservableObject {
    static let shared = QuickLaunchRouter()
    private init() {}

    @Published var pendingMeeting: Meeting?
    @Published var autoStartRecording: Bool = false
    @Published var listFilterCollaborator: Collaborator?  // pour "Voir les derniers 1:1"

    func startOneToOne(collaborator: Collaborator,
                       autoStartRecording: Bool,
                       in context: ModelContext) -> Meeting

    func showRecentOneToOnes(for collaborator: Collaborator)
}
```

Tous les déclencheurs externes (Spotlight handler, AppIntent perform, hotkey callback, menu contextuel) appellent `startOneToOne(...)`. Le routeur:

1. Crée `Meeting` (cf. tag ci-dessous) et l'insère dans le contexte.
2. Active la fenêtre principale (`NSApp.activate(ignoringOtherApps: true)`).
3. Publie `pendingMeeting` + `autoStartRecording`.

`ContentView` observe `pendingMeeting` → sélectionne le meeting dans la nav → ouvre `MeetingView` avec `autoStartRecording`. Une fois ouverte, la vue consomme le flag (le routeur reset à nil).

### Modèle: tag 1:1 sur Meeting

`Meeting` possède déjà `kind: MeetingKind` (raw stocké dans `kindRaw`) avec un cas `.oneToOne` pré-existant. **On réutilise** — pas de nouveau champ.

Le routeur crée:

```swift
let meeting = Meeting(
    title: "1:1 — \(collaborator.name)",
    date: .now,
    notes: ""
)
meeting.participants = [collaborator]
meeting.kind = .oneToOne
```

### `MeetingView` reçoit `autoStartRecording`

Nouveau paramètre optionnel:

```swift
struct MeetingView: View {
    @Bindable var meeting: Meeting
    let autoStartRecording: Bool   // default false
    ...
    .onAppear {
        if autoStartRecording && !recorder.isRecording {
            Task { await startRecording() }
        }
    }
}
```

Le flag n'est consommé qu'une fois (`@State private var didAutoStart = false`).

## Points d'entrée

### 1. Spotlight macOS

**Indexation.** `SpotlightIndexService` étendu pour indexer chaque `Collaborator` non archivé:

- `domainIdentifier = "collaborators"`
- `uniqueIdentifier = "collaborator-\(stableID)"` (UUID stable du modèle)
- `attributeSet.contentType = .contact`
- `displayName = collaborator.name`
- `title = "OneToOne — 1:1 avec \(name)"`
- `keywords = ["OneToOne", "1:1", "entretien", name, role]`
- `relatedUniqueIdentifier` → liens vers projets où le collab a des entrées (utile pour ranking)

Re-indexation: appelée dans `reindexSpotlight()` existant + à chaque `addCollaborator`/rename/archive.

**Routage du clic.** Spotlight envoie `NSUserActivity` avec type `CSSearchableItemActionType` et `userInfo[CSSearchableItemActivityIdentifier] = uniqueIdentifier`. Capté via:

```swift
.onContinueUserActivity(CSSearchableItemActionType) { activity in
    QuickLaunchURLHandler.handle(activity, router: router, context: context)
}
```

`QuickLaunchURLHandler.handle`:

1. Extrait l'identifiant.
2. Si préfixe `collaborator-`, fetch `Collaborator` par `stableID`.
3. Appelle `router.startOneToOne(collaborator:autoStartRecording: true, in: context)`.

### 2. App Intent (Shortcuts.app)

Nouveau fichier `OneToOne/AppIntents/StartOneToOneIntent.swift`:

```swift
struct StartOneToOneIntent: AppIntent {
    static var title: LocalizedStringResource = "Démarrer un 1:1"
    static var description = IntentDescription("Crée un nouveau 1:1 avec enregistrement.")
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
            throw $collaborator.needsValueError()
        }
        QuickLaunchRouter.shared.startOneToOne(
            collaborator: model,
            autoStartRecording: true,
            in: context
        )
        return .result()
    }
}

struct CollaboratorEntity: AppEntity {
    var id: UUID                      // stableID
    var displayRepresentation: DisplayRepresentation
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Collaborateur")
    static var defaultQuery = CollaboratorEntityQuery()
}

struct CollaboratorEntityQuery: EntityQuery {
    func entities(for ids: [UUID]) async throws -> [CollaboratorEntity]
    func suggestedEntities() async throws -> [CollaboratorEntity]
    // implémente String search via `EntityStringQuery`
}
```

`AppShortcutsProvider` enregistre l'intent pour qu'il apparaisse dans Spotlight comme action et dans Shortcuts.app:

```swift
struct OneToOneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOneToOneIntent(),
            phrases: ["Démarrer un 1:1 dans \(.applicationName)"],
            shortTitle: "Démarrer un 1:1",
            systemImageName: "mic.circle.fill"
        )
    }
}
```

Container partagé: `OneToOneApp.sharedContainer` (static, exposé par `OneToOneApp.init()` après création du `ModelContainer` existant). L'AppIntent tourne dans le process de l'app grâce à `openAppWhenRun = true` et lit/écrit via `mainContext` du container partagé.

### 3. Hotkeys globaux (combo D)

Deux niveaux:

**3a. Hotkey unique d'overlay** — `⌃⌥⌘1` (configurable en Settings).
Action: ouvre une fenêtre flottante `OneToOneQuickPickerWindow` (NSPanel `.floating` level, non-activating, taille ~480×320). Contenu SwiftUI:

- Champ texte focused (recherche fuzzy par `name`/`role`).
- Liste filtrée des collaborateurs non archivés, triée par pinLevel desc puis nom.
- Enter → `router.startOneToOne(...)`, ferme la fenêtre.
- Échap → ferme.

**3b. Hotkey par collaborateur** — bindable individuellement.
Persistance: nouveau champ sur `AppSettings`:

```swift
var collaboratorHotkeys: [String: String] = [:]   // stableID UUID string → keyspec
```

`keyspec` format: `"⌃⌥⌘A"` (string lisible; modifiers + key char). Encode/decode via helper `Hotkey.keyspec(from: NSEvent)` / `Hotkey.eventSpec(from: String)`.

UI Settings: nouvelle section "Raccourcis 1:1" listant les collabs pinnés (`pinLevel >= 1`). Chaque ligne: avatar, nom, capteur de raccourci (clic → record next key combo, échap = clear).

**Implémentation Carbon HotKey** (sans dépendance externe):

Service `GlobalHotkeyService` (singleton, @MainActor):

- Wrappe `RegisterEventHotKey` / `UnregisterEventHotKey` (Carbon, importé via `Carbon.HIToolbox`).
- API: `register(keyspec: String, identifier: UInt32, handler: @escaping () -> Void) throws`.
- Gère `EventHotKeyID` mapping vers handler.
- Au `applicationDidBecomeActive` / au démarrage: souscrit aux hotkeys overlay + tous les binds dans `AppSettings.collaboratorHotkeys`.
- Sur changement de bind: déréférencer ancien, enregistrer nouveau.

**Permissions / Accessibility**: les hotkeys globaux Carbon ne nécessitent pas Accessibility (contrairement à `CGEventTap`), donc pas de prompt utilisateur.

### 4. Clic droit Sidebar collaborateur

Dans `Sidebar.swift`, le `NavigationLink` collab est wrappé dans `.contextMenu`:

```swift
.contextMenu {
    Button {
        router.startOneToOne(collaborator: collab, autoStartRecording: true, in: context)
    } label: {
        Label("Démarrer 1:1 maintenant", systemImage: "mic.circle.fill")
    }

    Button {
        router.startOneToOne(collaborator: collab, autoStartRecording: false, in: context)
    } label: {
        Label("Nouveau 1:1 (sans enregistrer)", systemImage: "doc.badge.plus")
    }

    Divider()

    Button {
        router.showRecentOneToOnes(for: collab)
    } label: {
        Label("Voir les derniers 1:1", systemImage: "clock.arrow.circlepath")
    }
}
```

### "Voir les derniers 1:1" — comportement

Le routeur publie `listFilterCollaborator`. La nav route vers `MeetingsListView`. Cette vue observe le routeur et:

1. Définit son filtre actif: `meetings.filter { $0.kind == .oneToOne && $0.participants.contains(where: { $0.stableID == collab.stableID }) }`.
2. Tri date desc.
3. Banner discret en haut: "1:1 avec \(name) — [×] retirer le filtre".
4. Le clear bouton remet `listFilterCollaborator = nil`.

Pas de fenêtre dédiée, pas de nouvelle vue.

## Data flow

```
[Spotlight result clic]   ─┐
[Shortcuts.app run]       ─┤
[Global hotkey overlay]   ─┼──▶  QuickLaunchRouter.startOneToOne(collab, autoStart, ctx)
[Per-collab hotkey]       ─┤         │
[Right-click menu]        ─┘         ▼
                                 - Crée Meeting (kind = .oneToOne, participants=[collab])
                                 - Active app, makeKeyAndOrderFront
                                 - Publish pendingMeeting + autoStartRecording
                                       │
                                       ▼
                          ContentView observe pendingMeeting
                                       │
                                       ▼
                          Navigue vers MeetingView(meeting, autoStartRecording: flag)
                                       │
                                       ▼
                          .onAppear → recorder.start() si flag && !didAutoStart
```

## Erreurs

- **Spotlight: collab introuvable** (UUID périmé après suppression) → log + fallback: ouvrir l'app sans navigation. Ne jamais crash.
- **AppIntent: pas de collab matché** → `$collaborator.needsValueError()`.
- **Hotkey enregistrement échoue** (conflit OS) → message visible dans la ligne Settings concernée + log; ne pas crash; ne pas bloquer save.
- **Recorder.start() échoue** au auto-start → utilise mécanisme d'erreur existant `recorder.lastError` (déjà affiché par `MeetingContextualRecorderBar`); ne pas supprimer le Meeting créé (l'utilisateur peut juste ne pas enregistrer).
- **Fenêtre principale pas encore prête** au démarrage à froid déclenché par Spotlight: le routeur queue le `pendingMeeting`; `ContentView.onAppear` consomme le pending au premier rendu.

## Tests

Cibles `OneToOneTests`:

1. `QuickLaunchRouterTests`
   - `startOneToOne` crée Meeting avec `kind == .oneToOne`, participants contient le collab unique, title = "1:1 — Name".
   - `autoStartRecording` propagé correctement (publié true puis flushé).
   - `showRecentOneToOnes` set le filtre, n'efface pas pendingMeeting.

2. `SpotlightIndexServiceTests`
   - Index collab non-archivé → CSSearchableItem généré avec bon domain/ID.
   - Collab archivé exclu.
   - Update collab → re-indexation passe par même uniqueIdentifier.

3. `QuickLaunchURLHandlerTests`
   - `NSUserActivity` avec `CSSearchableItemActivityIdentifier = "collaborator-<uuid>"` → router appelé avec bon collab + autoStart=true.
   - Identifiant invalide → no-op + log.

4. `HotkeySpecTests`
   - Encode/decode round-trip (`⌃⌥⌘A`, `⌘F1`, etc.).
   - Modifier ordre canonique.

5. `StartOneToOneIntentTests` (instanciation programmatique, sans UI)
   - `perform()` route vers le router.
   - Param manquant → `needsValueError`.

Pas de test UI automatisé pour overlay picker / contextMenu (test manuel suffit dans cette release).

## Migration / Compat

- Schéma SwiftData: ajout d'un champ `AppSettings.collaboratorHotkeys: [String: String]` (default `[:]`). Default value sur Optional/typed-default → lightweight migration automatique, pas besoin de bump V2. Pas de modif sur `Meeting` (réutilisation `kind`).
- `MeetingView` initializer rétrocompatible: `autoStartRecording` a une default value `false`. Tous les call-sites existants continuent de fonctionner.
- `MeetingsListView` ajoute le filtre observé; sans filtre actif, comportement inchangé.

## Permissions / Info.plist

- Aucun nouvel entitlement requis (Carbon hotkeys ne demandent pas Accessibility).
- Spotlight: `CoreSpotlight` déjà utilisé.
- App Intents: ajouter `NSAppleEventsUsageDescription` n'est pas nécessaire (App Intents != AppleScript).

## Fichiers touchés (estimation)

**Nouveaux**:
- `OneToOne/Services/QuickLaunchRouter.swift`
- `OneToOne/Services/QuickLaunchURLHandler.swift`
- `OneToOne/Services/GlobalHotkeyService.swift`
- `OneToOne/Services/HotkeySpec.swift`
- `OneToOne/AppIntents/StartOneToOneIntent.swift`
- `OneToOne/AppIntents/CollaboratorEntity.swift`
- `OneToOne/AppIntents/OneToOneShortcuts.swift`
- `OneToOne/Views/OneToOneQuickPickerWindow.swift` (+ contenu SwiftUI)
- `OneToOne/Views/SettingsHotkeysSection.swift`
- `Tests/QuickLaunchRouterTests.swift`
- `Tests/SpotlightIndexServiceCollaboratorTests.swift`
- `Tests/QuickLaunchURLHandlerTests.swift`
- `Tests/HotkeySpecTests.swift`
- `Tests/StartOneToOneIntentTests.swift`

**Modifiés**:
- `OneToOne/Models/AppSettings.swift` (+ `collaboratorHotkeys`)
- `OneToOne/Services/SpotlightIndexService.swift` (indexation Collaborator)
- `OneToOne/OneToOneApp.swift` (router env, `onContinueUserActivity`, init `GlobalHotkeyService`, `SharedModelContainer`)
- `OneToOne/Views/MeetingView.swift` (param `autoStartRecording`)
- `OneToOne/Views/MeetingsListView.swift` (filtre 1:1 + banner)
- `OneToOne/Views/Sidebar.swift` (`.contextMenu` collab)
- `OneToOne/Views/SettingsView.swift` (insérer section raccourcis)

## Open questions

Aucune — toutes les décisions clés sont fixées:
- Cible = Meeting avec `kind = .oneToOne` (enum existant, pas de nouveau champ).
- Routeur central unique pour tous les déclencheurs.
- Hotkey combo D (overlay + binds par collab).
- Carbon, pas de dep externe.
- Liste 1:1 = filtre dans `MeetingsListView`, pas nouvelle vue.
