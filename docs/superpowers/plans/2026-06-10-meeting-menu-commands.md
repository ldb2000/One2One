# Meeting Menu Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sortir les actions secondaires de la réunion du menu « ⋯ » fourre-tout vers des menus natifs macOS (`Réunion` + export sous `Fichier`) avec raccourcis clavier, en gardant un « ⋯ » in-window allégé qui partage la même source d'actions.

**Architecture:** Une struct valeur `MeetingMenuActions` (closures + drapeaux d'état + `isEnabled(_:)`) construite par `MeetingView`, publiée via `.focusedValue(\.meetingMenu, …)`. Un `Commands` (`MeetingCommands`) la lit via `@FocusedValue` pour bâtir les menus natifs ; il est branché dans `OneToOneApp`. `MeetingTopChromeBar` consomme la même struct, ce qui simplifie son init et permet d'alléger le « ⋯ ». Items grisés quand aucune réunion n'a le focus.

**Tech Stack:** Swift, SwiftUI (`Commands`, `CommandMenu`, `CommandGroup(after: .importExport)`, `FocusedValueKey`/`@FocusedValue`, `keyboardShortcut`), SwiftPM, Swift Testing/XCTest.

---

## File Structure

| Fichier | Responsabilité |
|---|---|
| `OneToOne/Views/Menus/MeetingMenuActions.swift` | **Nouveau.** Struct `MeetingMenuActions` (closures + état + `isEnabled`), enum `MeetingMenuItem`, plomberie `FocusedValueKey`/`FocusedValues.meetingMenu`. Logique pure d'activation testable. |
| `OneToOne/Views/Menus/MeetingCommands.swift` | **Nouveau.** `struct MeetingCommands: Commands` — menu `Réunion` + groupe Exporter dans `Fichier`. Lit `@FocusedValue(\.meetingMenu)`. |
| `OneToOne/OneToOneApp.swift` | **Modifié.** `.commands { MeetingCommands() }` sur la `WindowGroup` principale. |
| `OneToOne/Views/MeetingView.swift` | **Modifié.** Méthode `makeMenuActions()` ; `.focusedValue(\.meetingMenu, …)` ; appel du chrome bar via `actions:`. |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | **Modifié.** Init simplifié (`actions:` + 3 closures bar-only) ; `moreMenu` allégé en sous-menus. |
| `Tests/MeetingMenuActionsTests.swift` | **Nouveau.** Tests unitaires de `isEnabled(_:)`. |

Convention projet : commentaires & libellés UI en **français**, symboles en anglais. Commits en **Conventional Commits** français (`feat(menus): …`).

---

## Task 1: `MeetingMenuActions` + activation (TDD)

**Files:**
- Create: `OneToOne/Views/Menus/MeetingMenuActions.swift`
- Test: `Tests/MeetingMenuActionsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MeetingMenuActionsTests.swift`:

```swift
import XCTest
@testable import OneToOne

/// Logique d'activation des items de menu réunion selon l'état courant.
final class MeetingMenuActionsTests: XCTestCase {

    private func make(isRecording: Bool = false, isPaused: Bool = false,
                      isTranscribing: Bool = false, isGeneratingReport: Bool = false,
                      hasWav: Bool = false, hasPlayableAudio: Bool = false,
                      hasReport: Bool = false, hasTranscript: Bool = false) -> MeetingMenuActions {
        MeetingMenuActions(
            meetingTitle: "T",
            isRecording: isRecording, isPaused: isPaused, isTranscribing: isTranscribing,
            isGeneratingReport: isGeneratingReport, hasWav: hasWav,
            hasPlayableAudio: hasPlayableAudio, hasReport: hasReport, hasTranscript: hasTranscript,
            startRecording: {}, stopRecording: {}, appendRecording: {}, togglePause: {},
            retranscribe: {}, generateReport: {}, toggleCustomPrompt: {},
            importCalendar: {}, importExistingWAV: {}, editAudio: {}, revealWAV: {}, deleteMeeting: {},
            exportMarkdown: {}, exportPDF: {}, exportMail: { _ in }, exportOutlook: { _ in },
            exportAppleNotes: { _ in })
    }

    func testExportsRequireReport() {
        let no = make(hasReport: false)
        let yes = make(hasReport: true)
        for item in [MeetingMenuItem.exportMarkdown, .exportPDF, .exportMail, .exportOutlook, .exportNotes] {
            XCTAssertFalse(no.isEnabled(item), "\(item) devrait être grisé sans rapport")
            XCTAssertTrue(yes.isEnabled(item), "\(item) devrait être actif avec rapport")
        }
    }

    func testAudioItemsRequirePlayableAudio() {
        XCTAssertFalse(make(hasPlayableAudio: false).isEnabled(.editAudio))
        XCTAssertFalse(make(hasPlayableAudio: false).isEnabled(.revealWAV))
        XCTAssertTrue(make(hasPlayableAudio: true).isEnabled(.editAudio))
        XCTAssertTrue(make(hasPlayableAudio: true).isEnabled(.revealWAV))
    }

    func testGenerateReportRequiresTranscriptAndNotBusy() {
        XCTAssertFalse(make(hasTranscript: false).isEnabled(.generateReport))
        XCTAssertTrue(make(hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isRecording: true, hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isTranscribing: true, hasTranscript: true).isEnabled(.generateReport))
        XCTAssertFalse(make(isGeneratingReport: true, hasTranscript: true).isEnabled(.generateReport))
    }

    func testRetranscribeRequiresWavAndNotTranscribing() {
        XCTAssertFalse(make(hasWav: false).isEnabled(.retranscribe))
        XCTAssertTrue(make(hasWav: true).isEnabled(.retranscribe))
        XCTAssertFalse(make(hasWav: true, isTranscribing: true).isEnabled(.retranscribe))
    }

    func testAppendRequiresWavAndNotBusy() {
        XCTAssertFalse(make(hasWav: false).isEnabled(.appendRecording))
        XCTAssertTrue(make(hasWav: true).isEnabled(.appendRecording))
        XCTAssertFalse(make(hasWav: true, isGeneratingReport: true).isEnabled(.appendRecording))
    }

    func testPauseOnlyWhileRecording() {
        XCTAssertFalse(make(isRecording: false).isEnabled(.pause))
        XCTAssertTrue(make(isRecording: true).isEnabled(.pause))
    }

    func testStartStopBlockedWhileTranscribingOrGenerating() {
        XCTAssertTrue(make().isEnabled(.startStopRecording))
        XCTAssertFalse(make(isTranscribing: true).isEnabled(.startStopRecording))
        XCTAssertFalse(make(isGeneratingReport: true).isEnabled(.startStopRecording))
    }

    func testAlwaysEnabled() {
        let a = make()
        XCTAssertTrue(a.isEnabled(.customPrompt))
        XCTAssertTrue(a.isEnabled(.importCalendar))
        XCTAssertTrue(a.isEnabled(.delete))
    }
}
```

- [ ] **Step 2: Run test to verify it fails (compile error)**

Run: `swift test --filter MeetingMenuActionsTests 2>&1 | tail -20`
Expected: FAIL — compile error « cannot find 'MeetingMenuActions' / 'MeetingMenuItem' in scope ».

- [ ] **Step 3: Write the implementation**

Create `OneToOne/Views/Menus/MeetingMenuActions.swift`:

```swift
import SwiftUI

/// Identifiants des items de menu réunion, pour piloter leur activation.
enum MeetingMenuItem {
    case startStopRecording, appendRecording, pause, generateReport, retranscribe,
         customPrompt, importCalendar, importWAV, editAudio, revealWAV, delete,
         exportMarkdown, exportPDF, exportMail, exportOutlook, exportNotes
}

/// Source de vérité unique des actions « secondaires » d'une réunion, partagée
/// entre le menu « ⋯ » in-window (`MeetingTopChromeBar`) et les menus natifs
/// macOS (`MeetingCommands` via `FocusedValue`).
///
/// Valeur reconstruite à chaque rendu de `MeetingView` : les closures capturent
/// l'état courant de la vue ; les drapeaux pilotent `isEnabled(_:)`.
struct MeetingMenuActions {
    var meetingTitle: String

    // État courant (pour l'activation des items)
    var isRecording: Bool
    var isPaused: Bool
    var isTranscribing: Bool
    var isGeneratingReport: Bool
    var hasWav: Bool
    var hasPlayableAudio: Bool
    var hasReport: Bool
    var hasTranscript: Bool

    // Actions — enregistrement / rapport
    var startRecording: () -> Void
    var stopRecording: () -> Void
    var appendRecording: () -> Void
    var togglePause: () -> Void
    var retranscribe: () -> Void
    var generateReport: () -> Void
    var toggleCustomPrompt: () -> Void

    // Actions — import / audio / suppression
    var importCalendar: () -> Void
    var importExistingWAV: () -> Void
    var editAudio: () -> Void
    var revealWAV: () -> Void
    var deleteMeeting: () -> Void

    // Actions — export
    var exportMarkdown: () -> Void
    var exportPDF: () -> Void
    var exportMail: (MeetingMailExportOptions) -> Void
    var exportOutlook: (MeetingMailExportOptions) -> Void
    var exportAppleNotes: (MeetingMailExportOptions) -> Void

    /// Occupé par une opération longue (enreg./transcription/rapport).
    var busy: Bool { isRecording || isTranscribing || isGeneratingReport }

    /// Item activable dans l'état courant.
    func isEnabled(_ item: MeetingMenuItem) -> Bool {
        switch item {
        case .startStopRecording: return !isTranscribing && !isGeneratingReport
        case .appendRecording:    return hasWav && !busy
        case .pause:              return isRecording
        case .generateReport:     return hasTranscript && !busy
        case .retranscribe:       return hasWav && !isTranscribing
        case .customPrompt:       return true
        case .importCalendar:     return true
        case .importWAV:          return !busy
        case .editAudio:          return hasPlayableAudio && !busy
        case .revealWAV:          return hasPlayableAudio
        case .delete:             return true
        case .exportMarkdown, .exportPDF, .exportMail, .exportOutlook, .exportNotes:
            return hasReport
        }
    }
}

// MARK: - FocusedValue plumbing

struct MeetingMenuActionsKey: FocusedValueKey {
    typealias Value = MeetingMenuActions
}

extension FocusedValues {
    /// Actions de la réunion ayant le focus (nil si aucune).
    var meetingMenu: MeetingMenuActions? {
        get { self[MeetingMenuActionsKey.self] }
        set { self[MeetingMenuActionsKey.self] = newValue }
    }
}
```

> ⚠️ Corriger la coquille du commentaire ci-dessus : remplacer la ligne
> `    /: occupé …` par `    /// Occupé par une opération longue (enreg./transcription/rapport).`
> (le `///` est requis, `/:` ne compile pas).

> Note : `MeetingMailExportOptions` est déjà défini dans `Services/ExportService.swift`
> (même module) — ne pas le redéfinir, juste l'utiliser.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MeetingMenuActionsTests 2>&1 | tail -20`
Expected: PASS — « Executed 8 tests, with 0 failures ».

- [ ] **Step 5: Commit**

```bash
git add OneToOne/Views/Menus/MeetingMenuActions.swift Tests/MeetingMenuActionsTests.swift
git commit -m "feat(menus): MeetingMenuActions + logique d'activation (FocusedValue)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `MeetingCommands` (menus natifs)

**Files:**
- Create: `OneToOne/Views/Menus/MeetingCommands.swift`

Pas de test unitaire (UI/Commands non testables en unité) — vérification par compilation ici, manuelle en Task 4.

- [ ] **Step 1: Write the implementation**

Create `OneToOne/Views/Menus/MeetingCommands.swift`:

```swift
import SwiftUI

/// Menus natifs macOS pour la réunion ayant le focus. Lit `MeetingMenuActions`
/// via `FocusedValue` : tout est grisé si aucune réunion n'a le focus
/// (`menu == nil`). Export rangé sous « Fichier » (`.importExport`) ; le reste
/// dans un nouveau menu « Réunion ».
struct MeetingCommands: Commands {
    @FocusedValue(\.meetingMenu) private var menu

    var body: some Commands {
        // Export → menu « Fichier », emplacement conventionnel.
        CommandGroup(after: .importExport) {
            Button("Copier le rapport en Markdown") { menu?.exportMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!isEnabled(.exportMarkdown))
            Button("Exporter en PDF…") { menu?.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!isEnabled(.exportPDF))
            Menu("Envoyer via Apple Mail") { mailItems(menu?.exportMail) }
                .disabled(!isEnabled(.exportMail))
            Menu("Envoyer via Microsoft Outlook") { mailItems(menu?.exportOutlook) }
                .disabled(!isEnabled(.exportOutlook))
            Menu("Exporter vers Apple Notes") { mailItems(menu?.exportAppleNotes) }
                .disabled(!isEnabled(.exportNotes))
        }

        // Tout le reste → nouveau menu « Réunion ».
        CommandMenu("Réunion") {
            Button(menu?.isRecording == true ? "Arrêter et transcrire" : "Démarrer l'enregistrement") {
                if menu?.isRecording == true { menu?.stopRecording() } else { menu?.startRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isEnabled(.startStopRecording))
            Button("Reprendre l'enregistrement") { menu?.appendRecording() }
                .disabled(!isEnabled(.appendRecording))
            Button(menu?.isPaused == true ? "Reprendre" : "Mettre en pause") { menu?.togglePause() }
                .disabled(!isEnabled(.pause))

            Divider()
            Button("Générer le rapport") { menu?.generateReport() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isEnabled(.generateReport))
            Button("Relancer la transcription") { menu?.retranscribe() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!isEnabled(.retranscribe))
            Button("Prompt spécifique…") { menu?.toggleCustomPrompt() }
                .disabled(!isEnabled(.customPrompt))

            Divider()
            Button("Importer depuis le calendrier…") { menu?.importCalendar() }
                .disabled(!isEnabled(.importCalendar))
            Button("Importer un fichier WAV…") { menu?.importExistingWAV() }
                .disabled(!isEnabled(.importWAV))

            Divider()
            Button("Éditer l'audio…") { menu?.editAudio() }
                .disabled(!isEnabled(.editAudio))
            Button("Révéler le WAV dans le Finder") { menu?.revealWAV() }
                .disabled(!isEnabled(.revealWAV))

            Divider()
            Button("Supprimer la réunion…", role: .destructive) { menu?.deleteMeeting() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!isEnabled(.delete))
        }
    }

    private func isEnabled(_ item: MeetingMenuItem) -> Bool {
        menu?.isEnabled(item) ?? false
    }

    /// Les 4 variantes d'export e-mail/notes (mêmes options que l'ancien « ⋯ »).
    @ViewBuilder
    private func mailItems(_ action: ((MeetingMailExportOptions) -> Void)?) -> some View {
        Button("Rapport seul") { action?([]) }
        Button("Rapport + slides (PDF)") { action?(.includeSlidesPDF) }
        Button("Rapport + transcript") { action?([.includeTranscript]) }
        Button("Rapport + transcript + slides") { action?([.includeTranscript, .includeSlidesPDF]) }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -15`
Expected: « Build complete! ». (Le `Commands` n'est pas encore branché — il doit juste compiler.)

> Si erreur sur `keyboardShortcut(.return, …)` ou `.delete` : ce sont des
> `KeyEquivalent` standard (Return, ⌫). Ne pas substituer.

- [ ] **Step 3: Commit**

```bash
git add OneToOne/Views/Menus/MeetingCommands.swift
git commit -m "feat(menus): MeetingCommands — menu Réunion + export sous Fichier

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Brancher les menus (app + `MeetingView.focusedValue`)

À l'issue de cette tâche, **les menus natifs sont fonctionnels** (le « ⋯ » reste l'ancien, allégé en Task 4).

**Files:**
- Modify: `OneToOne/OneToOneApp.swift:70-75` (WindowGroup principale)
- Modify: `OneToOne/Views/MeetingView.swift` (ajout `makeMenuActions()` + `.focusedValue`)

- [ ] **Step 1: Brancher `.commands` dans l'app**

Dans `OneToOne/OneToOneApp.swift`, la `WindowGroup` principale est :

```swift
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(router)
        }
        .modelContainer(container)
```

La remplacer par (ajout de `.commands` après `.modelContainer`) :

```swift
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(router)
        }
        .modelContainer(container)
        .commands { MeetingCommands() }
```

- [ ] **Step 2: Ajouter `makeMenuActions()` à `MeetingView`**

Dans `OneToOne/Views/MeetingView.swift`, le `body` se termine ligne 351 par `}` (après le bloc `.onAppear { … }`). Insérer **juste après** cette accolade fermante du `body`, comme nouvelle méthode :

```swift
    /// Construit la source d'actions partagée par le « ⋯ » et les menus natifs
    /// (réutilise les mêmes closures que l'ancien call-site du chrome bar).
    private func makeMenuActions() -> MeetingMenuActions {
        MeetingMenuActions(
            meetingTitle: meeting.title,
            isRecording: recorder.isRecording,
            isPaused: recorder.isPaused,
            isTranscribing: stt.isTranscribing,
            isGeneratingReport: isGeneratingReport,
            hasWav: meeting.wavFileURL != nil && fileExists(meeting.wavFileURL!),
            hasPlayableAudio: meeting.hasPlayableAudio,
            hasReport: !meeting.summary.isEmpty,
            hasTranscript: !meeting.rawTranscript.isEmpty,
            startRecording: { Task { await startRecording() } },
            stopRecording: { Task { await stopRecordingAndTranscribe() } },
            appendRecording: { Task { await startAppendRecording() } },
            togglePause: { if recorder.isPaused { recorder.resume() } else { recorder.pause() } },
            retranscribe: { if let wav = meeting.wavFileURL { Task { await retranscribe(wavURL: wav) } } },
            generateReport: { Task { await generateReport() } },
            toggleCustomPrompt: { showCustomPrompt.toggle() },
            importCalendar: { showCalendarImporter = true },
            importExistingWAV: { showWavImporter = true },
            editAudio: { audioEditMode = .trimStart },
            revealWAV: {
                if let url = meeting.wavFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            deleteMeeting: { showDeleteConfirm = true },
            exportMarkdown: {
                let md = ExportService().exportMeetingMarkdown(meeting: meeting)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(md, forType: .string)
            },
            exportPDF: {
                let name = "Reunion_\(meeting.date.formatted(.iso8601.year().month().day()))_\(meeting.title).pdf"
                ExportService().exportMeetingPDF(meeting: meeting, fileName: name)
            },
            exportMail: { opts in ExportService().exportMeetingMail(meeting: meeting, options: opts) },
            exportOutlook: { opts in ExportService().exportMeetingOutlook(meeting: meeting, options: opts) },
            exportAppleNotes: { opts in ExportService().exportMeetingToAppleNotes(meeting: meeting, options: opts) }
        )
    }
```

- [ ] **Step 3: Publier la valeur focus**

Toujours dans `MeetingView.swift`, le `body` finit par ce bloc (lignes ~346-350) :

```swift
        .onAppear {
            guard autoStartRecording, !didAutoStart, !recorder.isRecording else { return }
            didAutoStart = true
            Task { await startRecording() }
        }
```

Ajouter **immédiatement après** (toujours sur le `VStack` racine, avant le `}` du body ligne 351) :

```swift
        .focusedValue(\.meetingMenu, makeMenuActions())
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -15`
Expected: « Build complete! ».

- [ ] **Step 5: Vérification manuelle (menus fonctionnels)**

Run: `Scripts/bump-and-build.sh dev`
Vérifier dans l'app :
1. Ouvrir une réunion → menus **`Réunion`** et **`Fichier`** (section export) présents.
2. Aller sur le **Dashboard** (aucune réunion focus) → tous les items réunion/export **grisés**.
3. Sans rapport généré → exports grisés ; sans audio → « Éditer l'audio »/« Révéler » grisés.
4. Tester un raccourci (ex. ⇧⌘C copie le Markdown ; ⌘⌫ ouvre la confirmation de suppression).

> **Point de vigilance (risque connu)** : si les menus restent grisés alors
> qu'une réunion est ouverte **dans la fenêtre principale** (navigation depuis
> la sidebar/dashboard), la `focusedValue` ne se propage pas. Correctif :
> remplacer `.focusedValue(\.meetingMenu, …)` par
> `.focusedSceneValue(\.meetingMenu, …)` (lecture inchangée via `@FocusedValue`).
> Re-build et re-vérifier. La fenêtre dédiée `1to1-meeting` doit fonctionner
> dans les deux cas.

- [ ] **Step 6: Commit**

```bash
git add OneToOne/OneToOneApp.swift OneToOne/Views/MeetingView.swift
git commit -m "feat(menus): branche les menus natifs réunion via FocusedValue

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `MeetingTopChromeBar` — source unique + « ⋯ » allégé

Simplifie l'init du chrome bar pour consommer `MeetingMenuActions` (supprime ~17 closures redondantes) et réorganise le « ⋯ » en sous-menus, en miroir des menus natifs.

**Files:**
- Modify: `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (props + pills + reportButton + moreMenu)
- Modify: `OneToOne/Views/MeetingView.swift:165-210` (call-site du chrome bar)

- [ ] **Step 1: Remplacer les propriétés stockées du chrome bar**

Dans `MeetingTopChromeBar.swift`, remplacer **tout le bloc** des propriétés stockées (de `let isGeneratingReport: Bool` jusqu'à `let onDeleteMeeting: () -> Void` inclus, lignes 16-61) par :

```swift
    let isGeneratingReport: Bool
    let reportProgressChars: Int
    let reportElapsedSeconds: Int
    let capturedSlidesCount: Int

    /// Source d'actions partagée avec les menus natifs (cf. MeetingMenuActions).
    let actions: MeetingMenuActions

    // Closures propres à la barre (non présentes dans les menus natifs) :
    /// Bascule lecture/pause de l'audio enregistré.
    let onTogglePlay: () -> Void
    /// Ouvre la configuration de la source de capture d'écran.
    let onShowCaptureSetup: () -> Void
    /// Ouvre la galerie des slides capturées.
    let onShowSlides: () -> Void
```

(Conserver intacts au-dessus : `@Bindable var meeting`, `@Environment modelContext`, `@Query allTemplates`, et les `@ObservedObject recorder/stt/player/captureService`. Le paramètre `hasWav` disparaît — remplacé par `actions.hasWav`.)

- [ ] **Step 2: Adapter les pills d'enregistrement**

Dans `idlePill` : `Button(action: onStartRecording)` → `Button(action: actions.startRecording)`.

Dans `recordingPill` : `Button(action: onTogglePause)` → `Button(action: actions.togglePause)` ; `Button(action: onStopRecording)` → `Button(action: actions.stopRecording)`.

Dans `playbackPill` : laisser `Button(action: onTogglePlay)` ; `Button(action: onAppendRecording)` → `Button(action: actions.appendRecording)` ; `Button(action: onRetranscribe)` → `Button(action: actions.retranscribe)`.

Dans `recorderPill` : la branche `} else if hasWav {` → `} else if actions.hasWav {`.

- [ ] **Step 3: Adapter le bouton rapport et la capture**

Dans `reportButton` : `Button(action: onGenerateReport)` → `Button(action: actions.generateReport)`. (Le calcul `disabled` reste inchangé : il référence `meeting`, `recorder`, `stt`, `isGeneratingReport`.)

Dans `captureButton` : inchangé (utilise `onShowSlides`, `onShowCaptureSetup`, `captureService`).

- [ ] **Step 4: Réécrire `moreMenu` (allégé, en miroir)**

Remplacer **entièrement** la propriété `moreMenu` (lignes 373-448) par :

```swift
    private var moreMenu: some View {
        Menu {
            Menu {
                Button(action: actions.exportMarkdown) { Label("Copier Markdown", systemImage: "doc.text") }
                Button(action: actions.exportPDF) { Label("Exporter PDF", systemImage: "doc.richtext") }
                Menu {
                    Button { actions.exportMail([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportMail(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportMail([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportMail([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Apple Mail", systemImage: "envelope") }
                Menu {
                    Button { actions.exportOutlook([]) } label: { Label("Rapport seul", systemImage: "envelope") }
                    Button { actions.exportOutlook(.includeSlidesPDF) } label: { Label("Rapport + slides (PDF)", systemImage: "envelope.badge") }
                    Button { actions.exportOutlook([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "envelope") }
                    Button { actions.exportOutlook([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "envelope.badge") }
                } label: { Label("Envoyer via Microsoft Outlook", systemImage: "paperplane") }
                Menu {
                    Button { actions.exportAppleNotes([]) } label: { Label("Rapport seul", systemImage: "note.text") }
                    Button { actions.exportAppleNotes(.includeSlidesPDF) } label: { Label("Rapport + slides", systemImage: "note.text.badge.plus") }
                    Button { actions.exportAppleNotes([.includeTranscript]) } label: { Label("Rapport + transcript", systemImage: "note.text") }
                    Button { actions.exportAppleNotes([.includeTranscript, .includeSlidesPDF]) } label: { Label("Rapport + transcript + slides", systemImage: "note.text.badge.plus") }
                } label: { Label("Exporter vers Apple Notes", systemImage: "note.text") }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .disabled(!actions.hasReport)

            Divider()
            Button(action: actions.toggleCustomPrompt) { Label("Prompt spécifique", systemImage: "text.bubble") }
            Menu {
                Button(action: actions.importCalendar) { Label("Importer Calendrier", systemImage: "calendar.badge.plus") }
                Button(action: actions.importExistingWAV) { Label("Importer un WAV existant", systemImage: "waveform.badge.plus") }
            } label: { Label("Importer", systemImage: "square.and.arrow.down") }
            Menu {
                Button(action: actions.editAudio) { Label("Éditer l'audio…", systemImage: "scissors") }
                    .disabled(!actions.hasPlayableAudio)
                Button(action: actions.revealWAV) { Label("Révéler le WAV dans Finder", systemImage: "folder") }
                    .disabled(!actions.hasPlayableAudio)
            } label: { Label("Audio", systemImage: "waveform") }

            Divider()
            Button(role: .destructive, action: actions.deleteMeeting) {
                Label("Supprimer la réunion…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
```

- [ ] **Step 5: Mettre à jour le call-site dans `MeetingView`**

Dans `OneToOne/Views/MeetingView.swift`, remplacer l'appel `MeetingTopChromeBar( … )` (lignes 165-210, du `MeetingTopChromeBar(` jusqu'au `)` fermant ligne 210) par :

```swift
            MeetingTopChromeBar(
                meeting: meeting,
                recorder: recorder,
                stt: stt,
                player: player,
                captureService: captureService,
                isGeneratingReport: isGeneratingReport,
                reportProgressChars: reportProgressChars,
                reportElapsedSeconds: reportElapsedSeconds,
                capturedSlidesCount: currentSlides.count,
                actions: makeMenuActions(),
                onTogglePlay: { if let wav = meeting.wavFileURL { togglePlay(url: wav); showPlayback = true } },
                onShowCaptureSetup: { showCaptureSetup = true },
                onShowSlides: { showSlidesList = true }
            )
```

(Le `.confirmationDialog(…)` chaîné juste après, lignes 211-216, reste inchangé.)

- [ ] **Step 6: Build**

Run: `swift build 2>&1 | tail -20`
Expected: « Build complete! ». Si erreur « extra argument » / « missing argument » au call-site : vérifier que la liste des paramètres correspond exactement à la nouvelle init (Step 1).

- [ ] **Step 7: Run unit tests (non-régression)**

Run: `swift test --filter MeetingMenuActionsTests 2>&1 | tail -10`
Expected: PASS (8 tests).

- [ ] **Step 8: Vérification manuelle (parité « ⋯ » + menus)**

Run: `Scripts/bump-and-build.sh dev`
Vérifier :
1. Le « ⋯ » est allégé : `Exporter ▸`, `Prompt spécifique`, `Importer ▸`, `Audio ▸`, `Supprimer`.
2. Chaque action du « ⋯ » fait la même chose qu'avant (export Markdown/PDF/Mail/Outlook/Notes, prompt, imports, éditer/révéler audio, suppression).
3. Les pills enregistrement/lecture, Capture, Auto, Rapport fonctionnent comme avant.
4. `Exporter ▸` grisé tant qu'il n'y a pas de rapport ; sous-items Audio grisés sans audio.

- [ ] **Step 9: Commit**

```bash
git add OneToOne/Views/Meeting/MeetingTopChromeBar.swift OneToOne/Views/MeetingView.swift
git commit -m "feat(menus): chrome bar via MeetingMenuActions + « ⋯ » allégé

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Vérification finale & doc

- [ ] **Step 1: Build complet + tests complets**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -15`
Expected: « Build complete! » puis suite de tests verte (au moins `MeetingMenuActionsTests` + non-régression du reste).

- [ ] **Step 2: Revue manuelle finale**

Run: `Scripts/bump-and-build.sh dev`
Repasser la checklist Task 3 Step 5 + Task 4 Step 8 d'un seul tenant (focus réunion vs dashboard, raccourcis, parité « ⋯ »).

- [ ] **Step 3: (option) Mettre à jour la doc d'architecture**

Si `docs/architecture.md` liste les composants de l'écran réunion, y ajouter une ligne : « Menus natifs réunion : `MeetingCommands` lit `MeetingMenuActions` via `FocusedValue` ; source partagée avec le « ⋯ » de `MeetingTopChromeBar`. » Sinon, ignorer ce step.

```bash
git add docs/architecture.md
git commit -m "docs: menus natifs réunion dans l'architecture

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage :**
- §3 export sous Fichier + menu Réunion → Task 2 (`CommandGroup(after: .importExport)` + `CommandMenu("Réunion")`). ✓
- §3 « ⋯ » gardé/allégé → Task 4 Step 4. ✓
- §3 raccourcis enregistrement/rapport → Task 2 (⇧⌘R, ⌘↩, ⇧⌘T) + Task 1 activation. ✓
- §4.1 source unique `MeetingMenuActions` → Task 1 ; partagée → Task 3 (focusedValue) + Task 4 (chrome bar). ✓
- §4.2 FocusedValue + fallback focusedSceneValue → Task 1 plumbing + Task 3 Step 5 note. ✓
- §4.3 MeetingCommands branché une fois → Task 2 + Task 3 Step 1. ✓
- §4.4 init simplifié → Task 4 Steps 1-3,5. ✓
- §5/§6 contenu exact des menus → Task 2. ✓
- §7 « ⋯ » allégé en sous-menus → Task 4 Step 4. ✓
- §8 raccourcis sans conflit → Task 2 (⇧⌘C, ⇧⌘E, ⌘⌫). ✓
- §9 test unitaire isEnabled + vérif manuelle → Task 1 + Tasks 3/4 manual. ✓
- §10 fichiers touchés → couverts. ✓
- §11 risques (propagation focus, libellé dynamique start/stop) → Task 3 Step 5 note + Task 2 libellés conditionnels. ✓

**Placeholders :** un seul step « option » (Task 5 Step 3, doc) explicitement conditionnel ; pas de TODO/TBD ni de coquille dans le code des steps. ✓

**Cohérence des types :** `MeetingMenuActions` (mêmes champs en Task 1 / test / makeMenuActions Task 3 / chrome bar Task 4) ; `MeetingMenuItem` cases identiques entre Task 1, test, et `MeetingCommands` Task 2 ; `MeetingMailExportOptions` (`.includeTranscript`, `.includeSlidesPDF`, `[]`) cohérent partout. ✓
