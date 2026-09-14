# Sources audio et cas d'erreur de capture — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Choisir un micro préféré, proposer une autre source quand il manque au démarrage, basculer sur le micro du Mac quand l'iPhone se déconnecte en séance, signaler l'absence de Teams, et guider vers Réglages Système quand une autorisation est refusée.

**Architecture:** Une règle métier pure (`AudioInputRouting`) décide ; un service CoreAudio (`AudioInputDeviceService`) énumère et observe les entrées ; le recorder exécute la bascule **par segment** (le WAV courant est clos, un second est ouvert sur la nouvelle entrée, les segments sont concaténés à l'arrêt, le flux live n'est jamais interrompu). Un `MeetingRecordingCoordinator` porte la décision de démarrage et la surveillance en séance, alimenté par des protocoles doublés en test. Les événements de séance partent en notification système, les deux prompts sont des feuilles in-app.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation (`AVAudioEngine`), CoreAudio (`AudioObjectGetPropertyData`, `AudioObjectAddPropertyListenerBlock`), UserNotifications, Swift Testing + XCTest.

**Spec:** `docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`

## Global Constraints

- Branche de travail : `feat/sources-audio-erreurs`, créée depuis `docs/sources-audio-erreurs-design` (qui porte la spec). Pas de commit sur `master`. Commits conventionnels, terminés par `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- **Rien ne s'ajoute dans `MeetingView.swift`** : chaque modification y retire au moins autant de lignes qu'elle en ajoute (la propriété `captureMode` disparaît).
- Aucune couleur hors `One2OneToken`, aucune fonte hors `Font.plexSans` / `.plexMono`.
- Commentaires et libellés UI en **français**, symboles en anglais.
- Énums persistées SwiftData en `…Raw: String` ; ici un seul champ `String` est ajouté, sans énum.
- Tests avant code (TDD). `swift build` puis `swift test --filter <Suite>` à chaque tâche ; `swift test` complet en fin de plan. Compter environ 4 minutes pour un `swift build` incrémental et 10 minutes pour la suite complète.
- Le micro intégré est reconnu par `kAudioDeviceTransportTypeBuiltIn`, jamais par son nom (D7).
- Aucune rebascule automatique au retour d'un périphérique (D6).
- Aucune surveillance de Teams en séance (D3).
- Précisions apportées par ce plan à la spec : (1) la bascule est tracée dans une liste dédiée `AudioRecorderService.inputSwitches` et non dans `provenanceTimeline`, dont la struct `TrackEnergySample` est figée par ses tests ; (2) le coordinateur porte la **décision** de démarrage et la **surveillance**, le câblage recorder / transcription live / playhead reste dans `MeetingView`, qui perd `captureMode` et gagne un appel — déplacer tout `startRecording()` aurait mêlé refactor et fonctionnalité dans une PR ; (3) le repli sans micro intégré ni défaut système prend la première entrée restante avant de s'arrêter.

---

## Carte des fichiers

| Fichier | Rôle | Tâche |
| --- | --- | --- |
| Create `OneToOne/Services/Audio/AudioInputDevice.swift` | Valeur `AudioInputDevice`, événement `AudioInputEvent` | 1 |
| Create `OneToOne/Services/Audio/AudioInputRouting.swift` | Règle métier pure : verdict de démarrage, verdict de repli | 1 |
| Create `Tests/AudioInputRoutingTests.swift` | Tests de la règle | 1 |
| Create `OneToOne/Services/Audio/AudioPermissionKind.swift` | `.microphone` / `.systemAudio`, lien Réglages, texte d'aide | 2 |
| Create `OneToOne/Services/Audio/MicrophoneSettingsLink.swift` | Pendant micro de `ScreenRecordingSettingsLink` | 2 |
| Create `Tests/AudioPermissionHelpTests.swift` | Tests du lien et des textes | 2 |
| Modify `OneToOne/Models/AppSettings.swift:206` | `preferredAudioInputUID` | 3 |
| Create `OneToOne/Services/Audio/AudioInputDeviceService.swift` | Énumération et écoute CoreAudio, protocole `AudioInputDeviceProviding` | 3 |
| Modify `OneToOne/Services/AudioRecorderService.swift` (`TapSink`) | `rotate(file:converter:)` | 4 |
| Create `Tests/TapSinkRotationTests.swift` | Le flux live survit à la rotation | 4 |
| Modify `OneToOne/Services/AudioRecorderService.swift` | `inputUID` au démarrage, `switchInput`, segments, `mergeSegments`, `onInputInterrupted` | 5 |
| Create `Tests/AudioRecorderSegmentsTests.swift` | Concaténation de segments | 5 |
| Modify `OneToOne/Services/MeetingNotificationService.swift:316` | Deux notifications | 6 |
| Create `OneToOne/Views/Meeting/Capture/RecordingPromptState.swift` | État d'écran des deux feuilles | 6 |
| Modify `OneToOne/Views/Meeting/MeetingScreenModel.swift:373` | `var recordingPrompts` | 6 |
| Create `OneToOne/Services/Meeting/MeetingRecordingCoordinator.swift` | Décision de démarrage, surveillance, protocoles | 6 |
| Create `Tests/MeetingRecordingCoordinatorTests.swift` + `Tests/RecordingCoordinatorTestDoubles.swift` | Tests du coordinateur | 6 |
| Create `OneToOne/Views/Meeting/Capture/AudioInputChoiceSheet.swift` | Feuille « choisir une autre source » | 7 |
| Create `OneToOne/Views/Meeting/Capture/AudioPermissionHelpSheet.swift` | Feuille d'aide autorisations | 7 |
| Modify `OneToOne/Views/MeetingView.swift:1042-1160, 1204-1260, 269` | Préflight, feuilles, surveillance | 7 |
| Create `OneToOne/Views/Settings/AudioInputSettingsSection.swift` | `GroupBox("Entrée audio")` | 8 |
| Modify `OneToOne/Views/SettingsView.swift:404` | Insertion de la section | 8 |
| Modify `docs/architecture.md:392`, Create `docs/adr/2026-09-14-sources-audio-fallback-par-segment.md`, Modify `STATUS.md` | Documentation | 9 |

---

### Task 0 : Branche de travail

**Files:** aucun.

- [ ] **Step 1 : Créer la branche depuis la branche de la spec**

```bash
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
git checkout docs/sources-audio-erreurs-design
git checkout -b feat/sources-audio-erreurs
git status --short
```

Attendu : `M Info.plist` seulement (modification antérieure au chantier, à ne jamais inclure dans les commits de ce plan).

- [ ] **Step 2 : Vérifier que la base est verte**

```bash
swift build 2>&1 | tail -3
```

Attendu : `Build complete!`.

---

### Task 1 : Valeurs et règle métier `AudioInputRouting`

**Files:**
- Create: `OneToOne/Services/Audio/AudioInputDevice.swift`
- Create: `OneToOne/Services/Audio/AudioInputRouting.swift`
- Test: `Tests/AudioInputRoutingTests.swift`

**Interfaces:**
- Produces:
  - `struct AudioInputDevice: Identifiable, Hashable, Sendable { let uid: String; let name: String; let isBuiltIn: Bool; let isSystemDefault: Bool }`
  - `enum AudioInputEvent: Equatable, Sendable { case added(uid: String); case removed(uid: String) }`
  - `AudioInputRouting.systemDefaultUID == ""`
  - `AudioInputRouting.StartVerdict`: `.use(uid: String?)` (`nil` = entrée par défaut du système), `.askUser(candidates: [AudioInputDevice], missingPreferredUID: String)`, `.noInput`
  - `AudioInputRouting.resolveStart(preferredUID: String, devices: [AudioInputDevice]) -> StartVerdict`
  - `AudioInputRouting.FallbackVerdict`: `.switchTo(AudioInputDevice)`, `.stopRecording`, `.ignore`
  - `AudioInputRouting.fallback(removedUID: String, currentUID: String?, devices: [AudioInputDevice]) -> FallbackVerdict` — `devices` est la liste **après** retrait.

- [ ] **Step 1 : Écrire les tests**

```swift
// Tests/AudioInputRoutingTests.swift
import Testing
import Foundation
@testable import OneToOne

/// La règle qui choisit l'entrée audio au démarrage et le repli à la
/// déconnexion (spec §4.1, décisions D2, D6, D7). Pure : aucun CoreAudio.
@Suite("AudioInputRouting — choix de l'entrée audio")
struct AudioInputRoutingTests {

    private let macBook = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "Microphone MacBook Pro",
                                           isBuiltIn: true, isSystemDefault: false)
    private let iphone = AudioInputDevice(uid: "iPhone-Continuity-1234", name: "iPhone de Laurent",
                                          isBuiltIn: false, isSystemDefault: true)
    private let usb = AudioInputDevice(uid: "USB-Yeti-0001", name: "Yeti Stereo Microphone",
                                       isBuiltIn: false, isSystemDefault: false)

    // MARK: - Démarrage

    @Test("Réglage « par défaut du système » → on laisse macOS choisir")
    func systemDefaultUsesNil() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: AudioInputRouting.systemDefaultUID,
                                                     devices: [macBook, iphone])
        #expect(verdict == .use(uid: nil))
    }

    @Test("Micro préféré présent → on l'utilise")
    func preferredPresent() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: [macBook, iphone])
        #expect(verdict == .use(uid: iphone.uid))
    }

    @Test("Micro préféré absent et d'autres entrées existent → on demande à l'utilisateur")
    func preferredMissingAsksUser() {
        let verdict = AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: [macBook, usb])
        #expect(verdict == .askUser(candidates: [macBook, usb], missingPreferredUID: iphone.uid))
    }

    @Test("Aucune entrée détectée → noInput, même avec un préféré")
    func noDevices() {
        #expect(AudioInputRouting.resolveStart(preferredUID: iphone.uid, devices: []) == .noInput)
        #expect(AudioInputRouting.resolveStart(preferredUID: "", devices: []) == .noInput)
    }

    // MARK: - Repli

    @Test("Le périphérique retiré n'est pas celui en cours → ignore")
    func unrelatedRemovalIsIgnored() {
        let verdict = AudioInputRouting.fallback(removedUID: usb.uid, currentUID: iphone.uid, devices: [macBook, iphone])
        #expect(verdict == .ignore)
    }

    @Test("Entrée en cours = défaut système (nil) → ignore, macOS reroute lui-même")
    func systemDefaultRemovalIsIgnored() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: nil, devices: [macBook])
        #expect(verdict == .ignore)
    }

    @Test("iPhone retiré → micro intégré, reconnu par son type de transport et non par son nom")
    func fallsBackToBuiltIn() {
        let anglais = AudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
                                       isBuiltIn: true, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [usb, anglais])
        #expect(verdict == .switchTo(anglais))
    }

    @Test("Sans micro intégré → l'entrée par défaut du système")
    func fallsBackToSystemDefault() {
        let defautUSB = AudioInputDevice(uid: usb.uid, name: usb.name, isBuiltIn: false, isSystemDefault: true)
        let autre = AudioInputDevice(uid: "Other", name: "Autre", isBuiltIn: false, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [autre, defautUSB])
        #expect(verdict == .switchTo(defautUSB))
    }

    @Test("Ni intégré ni défaut → la première entrée restante")
    func fallsBackToFirstRemaining() {
        let autre = AudioInputDevice(uid: "Other", name: "Autre", isBuiltIn: false, isSystemDefault: false)
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [autre])
        #expect(verdict == .switchTo(autre))
    }

    @Test("Plus aucune entrée → arrêt")
    func stopsWhenNothingRemains() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [])
        #expect(verdict == .stopRecording)
    }

    @Test("Le périphérique retiré encore listé (liste non rafraîchie) n'est jamais choisi comme repli")
    func removedDeviceIsNeverTheFallback() {
        let verdict = AudioInputRouting.fallback(removedUID: iphone.uid, currentUID: iphone.uid, devices: [iphone, macBook])
        #expect(verdict == .switchTo(macBook))
    }
}
```

- [ ] **Step 2 : Lancer, vérifier l'échec de compilation**

```bash
swift build --build-tests 2>&1 | grep -E "error:" | head -5
```

Attendu : erreurs `cannot find 'AudioInputDevice' in scope` / `cannot find 'AudioInputRouting' in scope`.

- [ ] **Step 3 : Écrire les valeurs**

```swift
// OneToOne/Services/Audio/AudioInputDevice.swift
import Foundation

/// Une entrée audio telle que la règle de routage la voit : une valeur, sans
/// identifiant CoreAudio. L'UID est stable pour un même appareil physique
/// (iPhone en Continuité compris) ; le nom est relu à chaque énumération et
/// jamais persisté.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    var id: String { uid }
    let uid: String
    let name: String
    /// Type de transport `kAudioDeviceTransportTypeBuiltIn` : c'est ainsi que
    /// le micro du Mac est reconnu, jamais par son nom (décision D7).
    let isBuiltIn: Bool
    /// Entrée par défaut du système à l'instant de l'énumération.
    let isSystemDefault: Bool
}

/// Ce que le service CoreAudio publie quand la liste des entrées change.
enum AudioInputEvent: Equatable, Sendable {
    case added(uid: String)
    case removed(uid: String)
}
```

- [ ] **Step 4 : Écrire la règle**

```swift
// OneToOne/Services/Audio/AudioInputRouting.swift
import Foundation

/// Décide quelle entrée audio utiliser — au démarrage d'un enregistrement et
/// quand l'entrée en cours disparaît (spec §4.1). Fonctions pures : l'appelant
/// fournit la liste des entrées, la règle ne touche jamais CoreAudio.
enum AudioInputRouting {

    /// Valeur du réglage « par défaut du système » : chaîne vide, stockée telle
    /// quelle dans `AppSettings.preferredAudioInputUID`.
    static let systemDefaultUID = ""

    enum StartVerdict: Equatable, Sendable {
        /// `nil` : on laisse macOS choisir l'entrée par défaut.
        case use(uid: String?)
        /// Le préféré manque, d'autres entrées existent : la feuille de choix.
        case askUser(candidates: [AudioInputDevice], missingPreferredUID: String)
        /// Aucune entrée : l'enregistrement ne peut pas démarrer.
        case noInput
    }

    static func resolveStart(preferredUID: String, devices: [AudioInputDevice]) -> StartVerdict {
        guard !devices.isEmpty else { return .noInput }
        guard preferredUID != systemDefaultUID else { return .use(uid: nil) }
        if devices.contains(where: { $0.uid == preferredUID }) { return .use(uid: preferredUID) }
        return .askUser(candidates: devices, missingPreferredUID: preferredUID)
    }

    enum FallbackVerdict: Equatable, Sendable {
        case switchTo(AudioInputDevice)
        case stopRecording
        case ignore
    }

    /// Repli quand `removedUID` disparaît. `devices` est la liste courante ;
    /// le périphérique retiré en est exclu par sécurité, qu'elle soit
    /// rafraîchie ou non. Ordre : micro intégré (D7), puis défaut système,
    /// puis la première entrée restante, sinon l'arrêt.
    static func fallback(removedUID: String, currentUID: String?, devices: [AudioInputDevice]) -> FallbackVerdict {
        guard let currentUID, currentUID == removedUID else { return .ignore }
        let restantes = devices.filter { $0.uid != removedUID }
        if let integre = restantes.first(where: \.isBuiltIn) { return .switchTo(integre) }
        if let defaut = restantes.first(where: \.isSystemDefault) { return .switchTo(defaut) }
        if let premiere = restantes.first { return .switchTo(premiere) }
        return .stopRecording
    }
}
```

- [ ] **Step 5 : Lancer les tests**

```bash
swift test --filter AudioInputRoutingTests 2>&1 | tail -5
```

Attendu : `✔ Suite "AudioInputRouting — choix de l'entrée audio" passed`, 11 tests.

- [ ] **Step 6 : Commit**

```bash
git add OneToOne/Services/Audio/AudioInputDevice.swift OneToOne/Services/Audio/AudioInputRouting.swift Tests/AudioInputRoutingTests.swift
git commit -m "feat(audio): règle de routage des entrées audio

Verdict de démarrage (préféré présent, absent, aucune entrée) et verdict de
repli à la déconnexion (micro intégré par type de transport, défaut système,
première restante, arrêt). Fonctions pures, spec §4.1.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2 : Autorisations — `AudioPermissionKind` et `MicrophoneSettingsLink`

**Files:**
- Create: `OneToOne/Services/Audio/AudioPermissionKind.swift`
- Create: `OneToOne/Services/Audio/MicrophoneSettingsLink.swift`
- Test: `Tests/AudioPermissionHelpTests.swift`

**Interfaces:**
- Consumes: `ScreenRecordingSettingsLink.candidateURLs`, `.manualPath`, `.open(using:)` (`Services/SlideCapture/ScreenRecordingSettingsLink.swift`).
- Produces:
  - `enum MicrophoneSettingsLink { static let candidateURLs: [URL]; static let manualPath: String; @MainActor static func open(using:) -> Bool }`
  - `enum AudioPermissionKind: String, Identifiable, Sendable { case microphone, systemAudio; var title: String; var explanation: String; var manualPath: String; var candidateURLs: [URL]; @MainActor func openSettings() -> Bool }`

- [ ] **Step 1 : Écrire les tests**

```swift
// Tests/AudioPermissionHelpTests.swift
import Testing
import Foundation
@testable import OneToOne

/// La feuille d'aide autorisations doit envoyer au **bon** volet des Réglages
/// Système selon ce qui a été refusé (spec §1, ligne 4).
@Suite("AudioPermissionKind — aide autorisations")
struct AudioPermissionHelpTests {

    @Test("Le micro pointe sur l'ancre Privacy_Microphone, moderne puis historique")
    func microphoneAnchors() {
        let urls = AudioPermissionKind.microphone.candidateURLs.map(\.absoluteString)
        #expect(urls.count == 2)
        #expect(urls.allSatisfy { $0.hasSuffix("?Privacy_Microphone") })
        #expect(urls[0].contains("com.apple.settings.PrivacySecurity.extension"))
        #expect(urls[1].contains("com.apple.preference.security"))
    }

    @Test("L'audio système réutilise le lien d'enregistrement de l'écran")
    func systemAudioReusesScreenRecordingLink() {
        #expect(AudioPermissionKind.systemAudio.candidateURLs == ScreenRecordingSettingsLink.candidateURLs)
        #expect(AudioPermissionKind.systemAudio.manualPath == ScreenRecordingSettingsLink.manualPath)
    }

    @Test("Le chemin manuel du micro nomme le volet Microphone")
    func microphoneManualPath() {
        #expect(AudioPermissionKind.microphone.manualPath.hasSuffix("→ Microphone"))
    }

    @Test("Les textes distinguent les deux cas")
    func textsDiffer() {
        #expect(AudioPermissionKind.microphone.title != AudioPermissionKind.systemAudio.title)
        #expect(AudioPermissionKind.microphone.explanation.contains("micro"))
        #expect(AudioPermissionKind.systemAudio.explanation.contains("écran"))
    }

    @Test("open s'arrête à la première URL acceptée")
    @MainActor
    func openStopsAtFirstSuccess() {
        var tentatives: [URL] = []
        let ok = MicrophoneSettingsLink.open { url in tentatives.append(url); return true }
        #expect(ok)
        #expect(tentatives.count == 1)
    }

    @Test("open rend faux quand aucune URL n'est acceptée")
    @MainActor
    func openReportsFailure() {
        var tentatives: [URL] = []
        let ok = MicrophoneSettingsLink.open { url in tentatives.append(url); return false }
        #expect(!ok)
        #expect(tentatives.count == 2)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

```bash
swift build --build-tests 2>&1 | grep -E "error:" | head -3
```

Attendu : `cannot find 'AudioPermissionKind' in scope`.

- [ ] **Step 3 : Écrire le lien micro**

```swift
// OneToOne/Services/Audio/MicrophoneSettingsLink.swift
import AppKit
import Foundation

/// Ouvre la section « Microphone » des Réglages Système. Même mécanisme que
/// `ScreenRecordingSettingsLink` : identifiant moderne puis historique, et un
/// chemin manuel si les deux échouent.
enum MicrophoneSettingsLink {

    static let candidateURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone")!,
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!,
    ]

    static let manualPath = "Réglages Système → Confidentialité et sécurité → Microphone"

    @MainActor
    static func open(using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        for url in candidateURLs where opener(url) {
            return true
        }
        return false
    }
}
```

- [ ] **Step 4 : Écrire le type d'autorisation**

```swift
// OneToOne/Services/Audio/AudioPermissionKind.swift
import Foundation

/// Ce qui a été refusé, et donc quel volet des Réglages Système ouvrir. Porte
/// aussi les textes de la feuille d'aide : ils dépendent du cas, pas de l'écran.
enum AudioPermissionKind: String, Identifiable, Sendable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Accès au micro refusé"
        case .systemAudio: return "Audio système non autorisé"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            return "OneToOne n'est pas autorisé à utiliser le micro. Sans cette autorisation, aucun enregistrement ne peut démarrer."
        case .systemAudio:
            return "Capter les participants distants passe par l'enregistrement de l'écran (audio seul, aucune image n'est conservée). L'enregistrement continue avec le micro seul tant que l'autorisation manque."
        }
    }

    var manualPath: String {
        switch self {
        case .microphone: return MicrophoneSettingsLink.manualPath
        case .systemAudio: return ScreenRecordingSettingsLink.manualPath
        }
    }

    var candidateURLs: [URL] {
        switch self {
        case .microphone: return MicrophoneSettingsLink.candidateURLs
        case .systemAudio: return ScreenRecordingSettingsLink.candidateURLs
        }
    }

    @MainActor
    func openSettings() -> Bool {
        switch self {
        case .microphone: return MicrophoneSettingsLink.open()
        case .systemAudio: return ScreenRecordingSettingsLink.open()
        }
    }
}
```

- [ ] **Step 5 : Lancer les tests**

```bash
swift test --filter AudioPermissionHelpTests 2>&1 | tail -4
```

Attendu : 6 tests verts.

- [ ] **Step 6 : Commit**

```bash
git add OneToOne/Services/Audio/AudioPermissionKind.swift OneToOne/Services/Audio/MicrophoneSettingsLink.swift Tests/AudioPermissionHelpTests.swift
git commit -m "feat(audio): lien Réglages Système pour le micro et type d'autorisation

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3 : Réglage persisté et service CoreAudio

**Files:**
- Modify: `OneToOne/Models/AppSettings.swift:206` (après `teamsAudioCaptureMode`)
- Create: `OneToOne/Services/Audio/AudioInputDeviceService.swift`

**Interfaces:**
- Consumes: `AudioInputDevice`, `AudioInputEvent` (Task 1).
- Produces:
  - `AppSettings.preferredAudioInputUID: String = ""`
  - `protocol AudioInputDeviceProviding: AnyObject { var devices: [AudioInputDevice] { get }; func refresh(); func events() -> AsyncStream<AudioInputEvent> }`
  - `@MainActor @Observable final class AudioInputDeviceService: AudioInputDeviceProviding { static let shared; private(set) var devices; func refresh(); func events(); func startObserving() }`
  - `nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID?`
  - `nonisolated static func defaultInputDeviceID() -> AudioDeviceID?`

Pas de test unitaire sur ce service (CoreAudio, matériel) : il est vérifié par la recette manuelle de la Task 9. Son contenu métier est nul par construction : il énumère, il n'interprète pas.

- [ ] **Step 1 : Ajouter le réglage**

Dans `OneToOne/Models/AppSettings.swift`, juste après le bloc `teamsAudioCaptureMode` (ligne 210) :

```swift
    /// UID CoreAudio du micro préféré (spec §5). Chaîne vide =
    /// `AudioInputRouting.systemDefaultUID`, « par défaut du système ». Le nom
    /// du périphérique n'est jamais stocké : il est relu depuis
    /// `AudioInputDeviceService` à chaque affichage. Ajout à valeur par défaut →
    /// migration légère automatique dans `SchemaV3`.
    var preferredAudioInputUID: String = ""
```

- [ ] **Step 2 : Écrire le service**

```swift
// OneToOne/Services/Audio/AudioInputDeviceService.swift
import CoreAudio
import Foundation
import Observation
import os

private let inputLog = Logger(subsystem: "com.onetoone.app", category: "audio-input")

/// Ce que le coordinateur d'enregistrement attend d'un fournisseur d'entrées
/// audio. Doublé en test ; en production, `AudioInputDeviceService.shared`.
protocol AudioInputDeviceProviding: AnyObject {
    var devices: [AudioInputDevice] { get }
    /// Relit la liste maintenant. Idempotent.
    func refresh()
    /// Un flux par abonné ; se termine quand l'abonné lâche le flux.
    func events() -> AsyncStream<AudioInputEvent>
}

/// Énumère les entrées audio du Mac et observe leurs branchements. Il **ne
/// décide rien** : la règle est dans `AudioInputRouting`, l'exécution dans
/// `AudioRecorderService`.
@MainActor
@Observable
final class AudioInputDeviceService: AudioInputDeviceProviding {

    static let shared = AudioInputDeviceService()

    private(set) var devices: [AudioInputDevice] = []

    @ObservationIgnored private var continuations: [UUID: AsyncStream<AudioInputEvent>.Continuation] = [:]
    @ObservationIgnored private var isObserving = false

    init() {
        refresh()
    }

    // MARK: - AudioInputDeviceProviding

    func refresh() {
        let nouvelles = Self.enumerateInputDevices()
        let anciens = Set(devices.map(\.uid))
        let recents = Set(nouvelles.map(\.uid))
        devices = nouvelles
        for uid in anciens.subtracting(recents) { broadcast(.removed(uid: uid)) }
        for uid in recents.subtracting(anciens) { broadcast(.added(uid: uid)) }
    }

    func events() -> AsyncStream<AudioInputEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Pose les écouteurs CoreAudio. À appeler une fois, au lancement de l'app
    /// (`AppDelegate`) ; un second appel est sans effet.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultAddress, DispatchQueue.main, block)
    }

    private func broadcast(_ event: AudioInputEvent) {
        inputLog.info("AudioInput: \(String(describing: event), privacy: .public)")
        for continuation in continuations.values { continuation.yield(event) }
    }

    // MARK: - CoreAudio (nonisolated, sans état)

    nonisolated static func enumerateInputDevices() -> [AudioInputDevice] {
        let defaut = defaultInputDeviceID()
        return allDeviceIDs()
            .filter { inputStreamCount($0) > 0 }
            .compactMap { id -> AudioInputDevice? in
                guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                      let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
                return AudioInputDevice(uid: uid,
                                        name: name,
                                        isBuiltIn: transportType(id) == kAudioDeviceTransportTypeBuiltIn,
                                        isSystemDefault: id == defaut)
            }
    }

    nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private nonisolated static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func inputStreamCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private nonisolated static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else { return 0 }
        return type
    }

    private nonisolated static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
```

- [ ] **Step 3 : Démarrer l'observation au lancement**

Dans `OneToOne/AppDelegate.swift`, dans `applicationDidFinishLaunching` (chercher la ligne qui démarre `TeamsCallMonitor` ou, à défaut, la fin de la méthode), ajouter :

```swift
        // Écoute des branchements de micros (spec sources audio §4.2) : le
        // service doit connaître la liste avant le premier enregistrement.
        AudioInputDeviceService.shared.startObserving()
```

- [ ] **Step 4 : Compiler**

```bash
swift build 2>&1 | grep -E "error|warning: var|Build complete" | head -5
```

Attendu : `Build complete!`. Si `AudioObjectPropertyListenerBlock` provoque une erreur de concurrence Swift 6 (`sending`), remplacer `[weak self]` par une capture forte de `AudioInputDeviceService.shared` dans le bloc : le singleton vit toute la session.

- [ ] **Step 5 : Vérifier le schéma**

```bash
swift test --filter "SchemaVersionsTests|MigrationTests|AppSettingsTests" 2>&1 | tail -3
```

Attendu : les suites existantes qui touchent le schéma restent vertes (aucune ne devrait citer le nouveau champ).

- [ ] **Step 6 : Commit**

```bash
git add OneToOne/Models/AppSettings.swift OneToOne/Services/Audio/AudioInputDeviceService.swift OneToOne/AppDelegate.swift
git commit -m "feat(audio): service CoreAudio des entrées et micro préféré persisté

Énumération des périphériques à flux d'entrée, écoute des branchements,
flux d'événements added/removed. AppSettings.preferredAudioInputUID,
chaîne vide = défaut système.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4 : `TapSink.rotate` — le flux live survit au changement de fichier

**Files:**
- Modify: `OneToOne/Services/AudioRecorderService.swift:476-500` (déclarations de `TapSink`) et `:540-560` (`process`)
- Test: `Tests/TapSinkRotationTests.swift`

**Interfaces:**
- Produces: `TapSink.rotate(file: AVAudioFile, converter: AVAudioConverter)`, `TapSink.targetFormat` lisible (`let` interne, plus `private`).

- [ ] **Step 1 : Écrire le test**

```swift
// Tests/TapSinkRotationTests.swift
import XCTest
import AVFoundation
@testable import OneToOne

/// Le fallback par segment (spec D1) remplace le fichier et le convertisseur du
/// `TapSink` **sans** toucher à la continuation du flux live : la transcription
/// en direct doit recevoir tous les blocs, avant et après la rotation, et les
/// deux WAV doivent être relisibles.
final class TapSinkRotationTests: XCTestCase {

    private static let wavSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    private static func makeSine(sampleRate: Double, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let ptr = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = sin(Float(i) * 0.05) * 0.5 }
        return buf
    }

    func testRotationKeepsLiveStreamAndClosesBothFiles() throws {
        let url1 = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let url2 = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url1); try? FileManager.default.removeItem(at: url2) }

        var received = 0
        var continuation: AsyncStream<[Float]>.Continuation!
        let stream = AsyncStream<[Float]> { continuation = $0 }
        let consumer = Task { for await block in stream { received += block.count } }

        // Premier segment : entrée 48 kHz (un iPhone en Continuité, par exemple).
        let sink: TapSink
        do {
            let file1 = try AVAudioFile(forWriting: url1, settings: Self.wavSettings)
            let target = file1.processingFormat
            let input48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let conv1 = AVAudioConverter(from: input48, to: target)!
            sink = TapSink(converter: conv1, targetFormat: target, file: file1, continuation: continuation)
        }
        for _ in 0..<5 { XCTAssertNotNil(sink.process(Self.makeSine(sampleRate: 48_000, frames: 4800))) }

        // Rotation : entrée 44,1 kHz (le micro intégré), nouveau fichier.
        do {
            let file2 = try AVAudioFile(forWriting: url2, settings: Self.wavSettings)
            let input44 = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let conv2 = AVAudioConverter(from: input44, to: sink.targetFormat)!
            sink.rotate(file: file2, converter: conv2)
        }
        for _ in 0..<5 { XCTAssertNotNil(sink.process(Self.makeSine(sampleRate: 44_100, frames: 4410))) }

        sink.finish()
        _ = try? awaitTask(consumer)

        let f1 = try AVAudioFile(forReading: url1)
        let f2 = try AVAudioFile(forReading: url2)
        // 5 × 0,1 s à 16 kHz ≈ 8 000 frames par segment (tolérance resampler).
        XCTAssertGreaterThan(f1.length, 7_000, "le premier segment est clos et relisible")
        XCTAssertGreaterThan(f2.length, 7_000, "le second segment est clos et relisible")
        XCTAssertGreaterThan(received, 14_000, "le flux live a reçu les deux segments sans coupure")
    }

    /// Attend la fin d'une `Task` depuis un test XCTest synchrone.
    private func awaitTask(_ task: Task<Void, Never>) throws {
        let done = expectation(description: "flux live terminé")
        Task { await task.value; done.fulfill() }
        wait(for: [done], timeout: 5)
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

```bash
swift build --build-tests 2>&1 | grep -E "error:" | head -3
```

Attendu : `value of type 'TapSink' has no member 'rotate'` et `'targetFormat' is inaccessible due to 'private' protection level`.

- [ ] **Step 3 : Modifier `TapSink`**

Dans `OneToOne/Services/AudioRecorderService.swift`, classe `TapSink` :

Remplacer

```swift
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
```

par

```swift
    /// `var` : remplacé à chaque rotation de segment, sous `queue`.
    private var converter: AVAudioConverter
    let targetFormat: AVAudioFormat
```

Après `func engageSystemTrack(startedAt:)`, ajouter :

```swift
    /// Change de fichier et de convertisseur **sans** toucher à la continuation
    /// ni à l'horloge du flux : c'est le cœur du fallback par segment (spec D1).
    /// L'ancien `AVAudioFile` est relâché ici, ce qui finalise son en-tête WAV ;
    /// `publishedSampleCount` continue de courir, le flux live ne voit rien.
    func rotate(file: AVAudioFile, converter: AVAudioConverter) {
        queue.sync {
            self.file = file
            self.converter = converter
        }
    }
```

- [ ] **Step 4 : Lancer le test**

```bash
swift test --filter TapSinkRotationTests 2>&1 | tail -4
```

Attendu : `Executed 1 test, with 0 failures`.

- [ ] **Step 5 : Non-régression du sink**

```bash
swift test --filter "AudioRecorderConverterTests|AudioTrackMixerTests" 2>&1 | tail -3
```

Attendu : vert.

- [ ] **Step 6 : Commit**

```bash
git add OneToOne/Services/AudioRecorderService.swift Tests/TapSinkRotationTests.swift
git commit -m "feat(audio): TapSink.rotate — changer de fichier sans couper le flux live

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5 : Recorder — entrée forcée, `switchInput`, segments

**Files:**
- Modify: `OneToOne/Services/AudioRecorderService.swift` (`start`, nouvelles méthodes, `stop`, `handleConfigurationChange`, `resetState`, `concatenateWAVs`)
- Test: `Tests/AudioRecorderSegmentsTests.swift`

**Interfaces:**
- Consumes: `AudioInputDevice` (Task 1), `AudioInputDeviceService.deviceID(forUID:)`, `.defaultInputDeviceID()` (Task 3), `TapSink.rotate` (Task 4).
- Produces:
  - `struct InputSwitchMark: Equatable, Sendable { let time: TimeInterval; let deviceName: String }`
  - `AudioRecorderService.start(meetingID:captureMode:inputUID: String? = nil)`
  - `AudioRecorderService.currentInputUID: String?` (`private(set)`)
  - `AudioRecorderService.inputSwitches: [InputSwitchMark]` (`private(set)`)
  - `AudioRecorderService.switchInput(to device: AudioInputDevice?) throws`
  - `AudioRecorderService.stopForInputLoss()`
  - `AudioRecorderService.onInputInterrupted: (@MainActor () -> Void)?`
  - `static func concatenateWAVs(_ urls: [URL], output: URL) throws` (l'ancienne signature à deux fichiers reste, elle délègue)
  - `static func mergeSegments(_ urls: [URL]) throws -> URL`
  - `static let wavSettings: [String: Any]`

- [ ] **Step 1 : Écrire les tests de concaténation**

```swift
// Tests/AudioRecorderSegmentsTests.swift
import XCTest
import AVFoundation
@testable import OneToOne

/// Le fallback par segment (spec D1) produit N fichiers WAV qu'`AudioRecorderService.stop()`
/// recolle en un seul. Ces tests fixent le contrat de `mergeSegments`.
final class AudioRecorderSegmentsTests: XCTestCase {

    /// Écrit un WAV 16 kHz mono de `seconds` secondes de sinusoïde.
    private func writeWav(seconds: Double) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorderService.wavSettings)
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = sin(Float(i) * 0.05) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    func testSingleSegmentIsReturnedUntouched() throws {
        let seul = try writeWav(seconds: 1)
        defer { try? FileManager.default.removeItem(at: seul) }
        let result = try AudioRecorderService.mergeSegments([seul])
        XCTAssertEqual(result, seul)
        XCTAssertTrue(FileManager.default.fileExists(atPath: seul.path))
    }

    func testTwoSegmentsAreConcatenatedAndDeleted() throws {
        let a = try writeWav(seconds: 1)
        let b = try writeWav(seconds: 2)
        let result = try AudioRecorderService.mergeSegments([a, b])
        defer { try? FileManager.default.removeItem(at: result) }

        XCTAssertNotEqual(result, a)
        XCTAssertNotEqual(result, b)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "les segments sont supprimés")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        let merged = try AVAudioFile(forReading: result)
        XCTAssertEqual(Double(merged.length) / merged.processingFormat.sampleRate, 3, accuracy: 0.01)
        XCTAssertEqual(result.deletingLastPathComponent(), AudioRecorderService.recordingsDirectory)
    }

    func testThreeSegmentsKeepOrderAndTotalDuration() throws {
        let urls = try [0.5, 1.0, 1.5].map { try writeWav(seconds: $0) }
        let result = try AudioRecorderService.mergeSegments(urls)
        defer { try? FileManager.default.removeItem(at: result) }
        let merged = try AVAudioFile(forReading: result)
        XCTAssertEqual(Double(merged.length) / merged.processingFormat.sampleRate, 3, accuracy: 0.01)
    }

    func testMissingSegmentFailsWithoutDeletingOthers() throws {
        let a = try writeWav(seconds: 1)
        defer { try? FileManager.default.removeItem(at: a) }
        let absent = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        XCTAssertThrowsError(try AudioRecorderService.mergeSegments([a, absent]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "rien n'est supprimé si la fusion échoue")
    }

    func testEmptyListThrows() {
        XCTAssertThrowsError(try AudioRecorderService.mergeSegments([]))
    }
}
```

- [ ] **Step 2 : Vérifier l'échec**

```bash
swift build --build-tests 2>&1 | grep -E "error:" | head -3
```

Attendu : `type 'AudioRecorderService' has no member 'wavSettings'` / `'mergeSegments'`.

- [ ] **Step 3 : Ajouter les réglages WAV et la fusion**

Dans `AudioRecorderService`, section `// MARK: - Storage (inchangé)`, ajouter **avant** `concatenateWAVs(first:second:output:)` :

```swift
    /// Format du fichier : PCM 16 bits, 16 kHz, mono. Partagé par le démarrage
    /// et par chaque rotation de segment — deux segments de formats différents
    /// ne se concatèneraient pas.
    nonisolated static let wavSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    /// Recolle les segments d'un enregistrement à bascules (spec D1). Un seul
    /// segment : rendu tel quel. Plusieurs : concaténés dans un nouveau fichier
    /// de `recordingsDirectory`, puis les segments sont supprimés — seulement
    /// si la fusion a réussi, pour qu'un échec ne perde jamais d'audio.
    static func mergeSegments(_ urls: [URL]) throws -> URL {
        guard let premier = urls.first else { throw AudioError.startFailed }
        guard urls.count > 1 else { return premier }
        let output = recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
        try concatenateWAVs(urls, output: output)
        for url in urls { try? FileManager.default.removeItem(at: url) }
        return output
    }

    /// Concaténation de N fichiers de même format dans `output`.
    static func concatenateWAVs(_ urls: [URL], output: URL) throws {
        guard let premier = urls.first else { throw AudioError.startFailed }
        let modele = try AVAudioFile(forReading: premier)
        let outFile = try AVAudioFile(
            forWriting: output,
            settings: modele.fileFormat.settings,
            commonFormat: modele.processingFormat.commonFormat,
            interleaved: modele.processingFormat.isInterleaved)
        for url in urls {
            let input = try AVAudioFile(forReading: url)
            try copyAudio(from: input, to: outFile)
        }
    }
```

Remplacer le corps de l'ancienne `concatenateWAVs(first:second:output:)` par :

```swift
    static func concatenateWAVs(first: URL, second: URL, output: URL) throws {
        try concatenateWAVs([first, second], output: output)
    }
```

Dans `start`, remplacer la variable locale `settings` (les six clés) par `let settings = Self.wavSettings`.

- [ ] **Step 4 : Lancer les tests de fusion**

```bash
swift test --filter AudioRecorderSegmentsTests 2>&1 | tail -4
```

Attendu : 5 tests verts.

- [ ] **Step 5 : Ajouter l'état et la liaison d'entrée**

Après `@Published private(set) var systemAudioUnavailable = false`, ajouter :

```swift
    /// UID de l'entrée forcée sur l'engine, `nil` = défaut système. Sert au
    /// coordinateur pour savoir si un périphérique retiré était le nôtre.
    private(set) var currentInputUID: String?

    /// URLs des segments **clos** de l'enregistrement en cours (fallback par
    /// segment, spec D1). Le segment courant est `currentFileURL`.
    private var segmentURLs: [URL] = []

    /// Bascules d'entrée survenues pendant l'enregistrement, pour le rapport.
    /// Vidée au prochain `start()`, comme `provenanceTimeline`.
    private(set) var inputSwitches: [InputSwitchMark] = []

    /// Posé par `MeetingRecordingCoordinator` pendant qu'il surveille : la
    /// notification `AVAudioEngineConfigurationChange` lui est alors remise au
    /// lieu de stopper l'enregistrement. `nil` = comportement historique.
    var onInputInterrupted: (@MainActor () -> Void)?
```

Après `// MARK: - Errors`, avant `enum AudioError`, ajouter :

```swift
/// Une bascule d'entrée, datée sur l'horloge de l'enregistrement.
struct InputSwitchMark: Equatable, Sendable {
    let time: TimeInterval
    let deviceName: String
}
```

Dans la section `// MARK: - Lifecycle`, ajouter avant `start` :

```swift
    /// Force l'entrée de l'engine sur `uid` (`nil` = l'entrée par défaut du
    /// système). Doit être appelée engine **arrêté**, avant de lire
    /// `inputNode.outputFormat(forBus:)` : le format dépend du périphérique.
    private func bindInput(uid: String?) throws {
        let deviceID: AudioDeviceID?
        if let uid { deviceID = AudioInputDeviceService.deviceID(forUID: uid) }
        else { deviceID = AudioInputDeviceService.defaultInputDeviceID() }
        guard var id = deviceID, let unit = engine.inputNode.audioUnit else {
            throw AudioError.inputUnavailable
        }
        let status = AudioUnitSetProperty(unit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            audioLog.error("AudioRecorder: bind input \(uid ?? "default", privacy: .public) failed \(status)")
            throw AudioError.inputUnavailable
        }
        currentInputUID = uid
    }
```

Ajouter le cas dans `AudioError` :

```swift
    case inputUnavailable
```

et sa description :

```swift
        case .inputUnavailable:
            return "L'entrée audio choisie n'est pas disponible."
```

- [ ] **Step 6 : Étendre `start`**

Signature :

```swift
    func start(meetingID: UUID? = nil,
               captureMode: TeamsAudioCaptureMode = .microOnly,
               inputUID: String? = nil) async throws -> URL {
```

Après `systemAudioUnavailable = false`, ajouter :

```swift
        segmentURLs = []
        inputSwitches = []
```

Dans le `do`, remplacer

```swift
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
```

par

```swift
            // L'entrée est liée avant de lire le format : un iPhone en
            // Continuité tourne à 48 kHz, le micro intégré à 44,1 ou 48 kHz.
            try bindInput(uid: inputUID)
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
```

Dans le `catch` de `start`, remplacer `throw AudioError.startFailed` par :

```swift
            throw (error as? AudioError) ?? AudioError.startFailed
```

- [ ] **Step 7 : Ajouter `switchInput` et `stopForInputLoss`**

Après `resume()` :

```swift
    // MARK: - Bascule d'entrée (fallback par segment, spec D1)

    /// Ferme le segment courant, en ouvre un nouveau sur `device` (`nil` =
    /// défaut système) et rouvre le tap sur le **même** `TapSink` : le flux live
    /// ne voit aucune coupure, seul le fichier est découpé. Une pause en cours
    /// est conservée (`setCapturing` reste faux).
    func switchInput(to device: AudioInputDevice?) throws {
        guard isRecording, let sink else { return }
        let node = engine.inputNode
        node.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        try bindInput(uid: device?.uid)
        let inputFormat = node.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inputFormat, to: sink.targetFormat) else {
            throw AudioError.startFailed
        }
        let url = Self.recordingsDirectory.appending(path: "\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: Self.wavSettings)
        if let clos = currentFileURL { segmentURLs.append(clos) }
        sink.rotate(file: file, converter: conv)
        currentFileURL = url
        node.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let samples = sink.process(buffer) else { return }
            Task { @MainActor [weak self] in self?.publishMetersThrottled(from: samples) }
        }
        engine.prepare()
        try engine.start()
        inputSwitches.append(InputSwitchMark(time: elapsedSeconds,
                                             deviceName: device?.name ?? "Entrée par défaut"))
        audioLog.info("AudioRecorder(engine): switch input → \(device?.name ?? "default", privacy: .public) segment=\(url.lastPathComponent, privacy: .public)")
    }

    /// Arrêt quand plus aucune entrée n'existe : le message historique, et le
    /// nettoyage de la session live que `MeetingView` ne fera pas (ce chemin ne
    /// passe pas par elle).
    func stopForInputLoss() {
        guard isRecording else { return }
        lastError = "Périphérique audio modifié — enregistrement interrompu. Vérifie l'entrée micro."
        audioLog.error("AudioRecorder(engine): input lost → stop")
        _ = stop()
        LiveTranscriptionService.shared.abort()
    }
```

- [ ] **Step 8 : Faire fusionner les segments dans `stop`**

Remplacer le corps de `stop()` :

```swift
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let url = currentFileURL else { return nil }
        let duration = elapsedSeconds
        let segments = segmentURLs + [url]
        finalizeAndTeardown()
        // `finalizeAndTeardown` a clos le dernier fichier (`sink.finish()`), les
        // précédents l'ont été à chaque `rotate` : tout est relisible ici.
        let finalURL: URL
        do { finalURL = try Self.mergeSegments(segments) }
        catch {
            audioLog.error("AudioRecorder(engine): merge segments failed \(error.localizedDescription, privacy: .public) — dernier segment conservé")
            finalURL = url
        }
        audioLog.info("AudioRecorder(engine): stop duration=\(duration, format: .fixed(precision: 1), privacy: .public)s segments=\(segments.count, privacy: .public)")
        return (finalURL, duration)
    }
```

Dans `cancel()`, après `finalizeAndTeardown()`, remplacer `if let url { try? FileManager.default.removeItem(at: url) }` par :

```swift
        for segment in segmentURLs + [url].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: segment)
        }
        segmentURLs = []
```

Attention : `segmentURLs` doit être lu **avant** `resetState()` ; déplacer la ligne `let segments = segmentURLs` au début de `cancel()` si `resetState` le vide. Dans `resetState()`, ajouter :

```swift
        segmentURLs = []
        currentInputUID = nil
```

- [ ] **Step 9 : Déléguer le changement de configuration**

Remplacer le corps de `handleConfigurationChange` :

```swift
    @objc private nonisolated func handleConfigurationChange(_ note: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            if let onInputInterrupted {
                // Le coordinateur surveille : c'est lui qui rebranche ou arrête.
                audioLog.info("AudioRecorder(engine): configuration change → coordinateur")
                onInputInterrupted()
                return
            }
            // Comportement historique, sans coordinateur.
            self.stopForInputLoss()
        }
    }
```

- [ ] **Step 10 : Compiler et rejouer les suites audio**

```bash
swift build 2>&1 | grep -E "error:|Build complete" | head -5
swift test --filter "AudioRecorder|TapSink|AudioTrackMixer" 2>&1 | tail -4
```

Attendu : `Build complete!`, toutes les suites vertes. Si `AudioUnitSetProperty` n'est pas résolu, ajouter `import AudioToolbox` en tête du fichier.

- [ ] **Step 11 : Commit**

```bash
git add OneToOne/Services/AudioRecorderService.swift Tests/AudioRecorderSegmentsTests.swift
git commit -m "feat(audio): entrée forcée, bascule par segment et fusion à l'arrêt

start(inputUID:) lie l'entrée sur l'AUHAL ; switchInput ferme le segment,
en ouvre un sur la nouvelle entrée et garde le TapSink ; stop() fusionne
les segments. Le changement de configuration est remis au coordinateur
quand il surveille, sinon comportement historique.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6 : Notifications, état des feuilles et `MeetingRecordingCoordinator`

**Files:**
- Modify: `OneToOne/Services/MeetingNotificationService.swift:316` (avant `notifyRecordingStarted`)
- Create: `OneToOne/Views/Meeting/Capture/RecordingPromptState.swift`
- Modify: `OneToOne/Views/Meeting/MeetingScreenModel.swift:373` (après `var capture = CaptureState()`)
- Create: `OneToOne/Services/Meeting/MeetingRecordingCoordinator.swift`
- Create: `Tests/RecordingCoordinatorTestDoubles.swift`
- Test: `Tests/MeetingRecordingCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AudioInputRouting`, `AudioInputDevice`, `AudioInputEvent` (Task 1), `AudioPermissionKind` (Task 2), `AudioInputDeviceProviding` (Task 3), `AudioRecorderService.switchInput / stopForInputLoss / currentInputUID / isRecording / onInputInterrupted` (Task 5), `TeamsAudioCaptureMode`, `SystemAudioCapture.isPermissionGranted()`, `TeamsCallMonitor.isTeamsRunning()`.
- Produces:
  - `MeetingNotificationService.notifyAudioInputFallback(deviceName: String)`, `.notifyTeamsFlowMissing()`
  - `struct AudioInputChoiceRequest: Identifiable, Equatable { let id: UUID; let missingPreferredUID: String; let candidates: [AudioInputDevice] }`
  - `struct RecordingPromptState: Equatable { var audioInputChoice: AudioInputChoiceRequest?; var permissionHelp: AudioPermissionKind? }`
  - `MeetingScreenModel.recordingPrompts: RecordingPromptState`
  - `protocol RecordingInputSwitching: AnyObject { var isRecording: Bool { get }; var currentInputUID: String? { get }; var onInputInterrupted: (@MainActor () -> Void)? { get set }; func switchInput(to device: AudioInputDevice?) throws; func stopForInputLoss() }`
  - `protocol RecordingNotifying: AnyObject { func notifyAudioInputFallback(deviceName: String); func notifyTeamsFlowMissing() }`
  - `enum MicrophonePermissionStatus: Sendable { case granted, denied, undetermined }`
  - `struct RecordingStartPlan: Equatable { let inputUID: String?; let captureMode: TeamsAudioCaptureMode }`
  - `enum RecordingStartOutcome: Equatable { case proceed(RecordingStartPlan); case awaitingUserChoice; case blocked }`
  - `@MainActor final class MeetingRecordingCoordinator { init(devices:recorder:notifier:isTeamsRunning:hasScreenPermission:microphonePermission:); static func makeLive() -> MeetingRecordingCoordinator; func prepareStart(preferredUID:chosenUID:hasTeamsLink:requestedMode:screen:) async -> RecordingStartOutcome; func beginMonitoring(); func endMonitoring(); func handleRemoval(uid:); func handleInterruption(); var teamsFlowMissing: Bool }`

- [ ] **Step 1 : Ajouter les deux notifications**

Dans `MeetingNotificationService`, avant `func notifyRecordingStarted` :

```swift
    /// « Bascule sur le micro MacBook » (spec §4.6) : l'entrée en cours a
    /// disparu, l'enregistrement continue sur `deviceName`. Notification
    /// système et non bandeau : décision D4.
    func notifyAudioInputFallback(deviceName: String) {
        postSimple(title: "Bascule sur le micro \(deviceName)",
                   body: "L'entrée audio précédente a été déconnectée. L'enregistrement continue.",
                   suffix: "audio.input-fallback")
    }

    /// « Aucun flux Teams détecté » : la réunion porte un lien Teams mais Teams
    /// n'est pas lancé au démarrage. L'enregistrement part en micro seul (D3).
    func notifyTeamsFlowMissing() {
        postSimple(title: "Aucun flux Teams détecté",
                   body: "Capture micro globale activée.",
                   suffix: "audio.teams-missing")
    }

    /// Bannière immédiate sans action, catégorie `recording`.
    private func postSimple(title: String, body: String, suffix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Category.recording
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(identifier: "\(suffix).\(UUID().uuidString)", content: content, trigger: trigger)
        center?.add(request) { error in
            if let error { print("[MeetingNotificationService] \(suffix): \(error)") }
        }
    }
```

- [ ] **Step 2 : Écrire l'état des feuilles**

```swift
// OneToOne/Views/Meeting/Capture/RecordingPromptState.swift
import Foundation

/// Le pop-up de pré-réunion : le micro préféré manque, voici les sources
/// détectées (spec §1, ligne 1). `Identifiable` pour `.sheet(item:)`.
struct AudioInputChoiceRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let missingPreferredUID: String
    let candidates: [AudioInputDevice]

    init(id: UUID = UUID(), missingPreferredUID: String, candidates: [AudioInputDevice]) {
        self.id = id
        self.missingPreferredUID = missingPreferredUID
        self.candidates = candidates
    }
}

/// Les deux feuilles que le démarrage d'enregistrement peut demander. Une
/// ligne dans `MeetingScreenModel`, tout le reste ici (même règle que
/// `CaptureState`).
struct RecordingPromptState: Equatable, Sendable {
    var audioInputChoice: AudioInputChoiceRequest?
    var permissionHelp: AudioPermissionKind?
}
```

Dans `MeetingScreenModel`, après `var capture = CaptureState()` :

```swift
    // MARK: - Sources audio et cas d'erreur (2026-09-14)

    /// Les feuilles du démarrage d'enregistrement : choix d'un autre micro,
    /// aide autorisations (`Views/Meeting/Capture/RecordingPromptState.swift`).
    var recordingPrompts = RecordingPromptState()
```

- [ ] **Step 3 : Écrire les doubles de test**

```swift
// Tests/RecordingCoordinatorTestDoubles.swift
import Foundation
@testable import OneToOne

/// Fournisseur d'entrées scripté : la liste est posée par le test, les
/// événements sont injectés à la main.
@MainActor
final class FakeAudioInputDevices: AudioInputDeviceProviding {
    var devices: [AudioInputDevice]
    var refreshCount = 0
    private var continuations: [AsyncStream<AudioInputEvent>.Continuation] = []

    init(devices: [AudioInputDevice]) { self.devices = devices }

    func refresh() { refreshCount += 1 }

    func events() -> AsyncStream<AudioInputEvent> {
        AsyncStream { self.continuations.append($0) }
    }

    func emit(_ event: AudioInputEvent) { continuations.forEach { $0.yield(event) } }
}

/// Recorder scripté : enregistre les appels, peut échouer à la bascule.
@MainActor
final class FakeRecorder: RecordingInputSwitching {
    var isRecording = true
    var currentInputUID: String?
    var onInputInterrupted: (@MainActor () -> Void)?
    var switchedTo: [AudioInputDevice?] = []
    var stopCount = 0
    var switchShouldFail = false

    struct SwitchFailed: Error {}

    func switchInput(to device: AudioInputDevice?) throws {
        if switchShouldFail { throw SwitchFailed() }
        switchedTo.append(device)
        currentInputUID = device?.uid
    }

    func stopForInputLoss() { stopCount += 1; isRecording = false }
}

@MainActor
final class FakeNotifier: RecordingNotifying {
    var fallbackNames: [String] = []
    var teamsMissingCount = 0
    func notifyAudioInputFallback(deviceName: String) { fallbackNames.append(deviceName) }
    func notifyTeamsFlowMissing() { teamsMissingCount += 1 }
}
```

- [ ] **Step 4 : Écrire les tests du coordinateur**

```swift
// Tests/MeetingRecordingCoordinatorTests.swift
import Testing
import Foundation
@testable import OneToOne

/// Le coordinateur applique `AudioInputRouting` au démarrage et en séance
/// (spec §4.4) : feuilles demandées à `MeetingScreenModel`, notifications,
/// rétrogradation Teams. Tout est doublé : aucun micro, aucun Teams.
@Suite("MeetingRecordingCoordinator — démarrage et surveillance")
@MainActor
struct MeetingRecordingCoordinatorTests {

    private let macBook = AudioInputDevice(uid: "BuiltIn", name: "Microphone MacBook Pro", isBuiltIn: true, isSystemDefault: false)
    private let iphone = AudioInputDevice(uid: "iPhone", name: "iPhone de Laurent", isBuiltIn: false, isSystemDefault: true)

    private struct Harness {
        let devices: FakeAudioInputDevices
        let recorder: FakeRecorder
        let notifier: FakeNotifier
        let screen: MeetingScreenModel
        let coordinator: MeetingRecordingCoordinator
    }

    private func makeHarness(devices: [AudioInputDevice],
                             teamsRunning: Bool = true,
                             screenPermission: Bool = true,
                             micro: MicrophonePermissionStatus = .granted) -> Harness {
        let fakeDevices = FakeAudioInputDevices(devices: devices)
        let recorder = FakeRecorder()
        let notifier = FakeNotifier()
        let suite = "MeetingRecordingCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let screen = MeetingScreenModel(defaults: defaults)
        let coordinator = MeetingRecordingCoordinator(
            devices: fakeDevices, recorder: recorder, notifier: notifier,
            isTeamsRunning: { teamsRunning },
            hasScreenPermission: { screenPermission },
            microphonePermission: { micro })
        return Harness(devices: fakeDevices, recorder: recorder, notifier: notifier, screen: screen, coordinator: coordinator)
    }

    // MARK: - Démarrage

    @Test("Micro préféré présent → proceed avec son UID, aucune feuille")
    func preferredPresentProceeds() async {
        let h = makeHarness(devices: [macBook, iphone])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: iphone.uid, captureMode: .microOnly)))
        #expect(h.screen.recordingPrompts == RecordingPromptState())
    }

    @Test("Réunion sans lien Teams → micro seul même si le mode demande la seconde piste")
    func noTeamsLinkIsMicOnly() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microOnly)))
        #expect(h.notifier.teamsMissingCount == 0)
    }

    @Test("Micro préféré absent → feuille de choix, awaitingUserChoice")
    func preferredMissingAsks() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .awaitingUserChoice)
        #expect(h.screen.recordingPrompts.audioInputChoice?.candidates == [macBook])
        #expect(h.screen.recordingPrompts.audioInputChoice?.missingPreferredUID == iphone.uid)
    }

    @Test("Le choix de l'utilisateur court-circuite la règle et ne touche pas au préféré")
    func chosenUIDWins() async {
        let h = makeHarness(devices: [macBook])
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: macBook.uid,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: macBook.uid, captureMode: .microOnly)))
        #expect(h.screen.recordingPrompts.audioInputChoice == nil)
    }

    @Test("Aucune entrée → blocked, aucune feuille")
    func noInputBlocks() async {
        let h = makeHarness(devices: [])
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .blocked)
        #expect(h.screen.recordingPrompts == RecordingPromptState())
    }

    @Test("Permission micro refusée → feuille d'aide micro, blocked, la règle n'est pas consultée")
    func deniedMicrophoneShowsHelp() async {
        let h = makeHarness(devices: [macBook], micro: .denied)
        let outcome = await h.coordinator.prepareStart(preferredUID: iphone.uid, chosenUID: nil,
                                                       hasTeamsLink: false, requestedMode: .microOnly, screen: h.screen)
        #expect(outcome == .blocked)
        #expect(h.screen.recordingPrompts.permissionHelp == .microphone)
        #expect(h.screen.recordingPrompts.audioInputChoice == nil)
    }

    @Test("Lien Teams, Teams lancé, permission écran → micro + système, aucune notification")
    func teamsRunningKeepsSystemTrack() async {
        let h = makeHarness(devices: [macBook], teamsRunning: true, screenPermission: true)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microAndSystem)))
        #expect(h.notifier.teamsMissingCount == 0)
        #expect(h.coordinator.teamsFlowMissing == false)
    }

    @Test("Lien Teams mais Teams fermé → notification « aucun flux », micro seul, drapeau posé")
    func teamsClosedDowngrades() async {
        let h = makeHarness(devices: [macBook], teamsRunning: false, screenPermission: true)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microOnly)))
        #expect(h.notifier.teamsMissingCount == 1)
        #expect(h.coordinator.teamsFlowMissing == true)
    }

    @Test("Permission écran absente → le mode demandé est transmis tel quel (le recorder dégrade et lève le bandeau)")
    func screenPermissionMissingLeavesModeToRecorder() async {
        let h = makeHarness(devices: [macBook], teamsRunning: true, screenPermission: false)
        let outcome = await h.coordinator.prepareStart(preferredUID: "", chosenUID: nil,
                                                       hasTeamsLink: true, requestedMode: .microAndSystem, screen: h.screen)
        #expect(outcome == .proceed(RecordingStartPlan(inputUID: nil, captureMode: .microAndSystem)))
        #expect(h.notifier.teamsMissingCount == 0)
    }

    // MARK: - Surveillance

    @Test("Retrait de l'entrée en cours → bascule sur le micro intégré et notification avec son nom")
    func removalSwitchesAndNotifies() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.switchedTo == [macBook])
        #expect(h.notifier.fallbackNames == [macBook.name])
    }

    @Test("Retrait d'une autre entrée → rien")
    func unrelatedRemovalDoesNothing() {
        let h = makeHarness(devices: [macBook, iphone])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: "USB")
        #expect(h.recorder.switchedTo.isEmpty)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Plus aucune entrée → arrêt, aucune notification de bascule")
    func nothingLeftStops() {
        let h = makeHarness(devices: [])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.stopCount == 1)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("La bascule échoue → arrêt propre plutôt qu'un engine mort")
    func failedSwitchStops() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.recorder.switchShouldFail = true
        h.coordinator.beginMonitoring()
        h.coordinator.handleRemoval(uid: iphone.uid)
        #expect(h.recorder.stopCount == 1)
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Interruption de l'engine, entrée encore présente → rebranchement silencieux sur la même entrée")
    func interruptionRebindsSameDevice() {
        let h = makeHarness(devices: [macBook, iphone])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.devices.refreshCount == 1)
        #expect(h.recorder.switchedTo == [iphone])
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("Interruption de l'engine, entrée disparue de la liste → même chemin que le retrait")
    func interruptionDetectsRemoval() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.recorder.switchedTo == [macBook])
        #expect(h.notifier.fallbackNames == [macBook.name])
    }

    @Test("Interruption en défaut système (nil) → rebranchement sur le défaut, sans notification")
    func interruptionOnSystemDefaultRebinds() {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = nil
        h.coordinator.beginMonitoring()
        h.coordinator.handleInterruption()
        #expect(h.recorder.switchedTo == [nil])
        #expect(h.notifier.fallbackNames.isEmpty)
    }

    @Test("beginMonitoring pose le crochet du recorder, endMonitoring le retire")
    func monitoringHooksRecorder() {
        let h = makeHarness(devices: [macBook])
        #expect(h.recorder.onInputInterrupted == nil)
        h.coordinator.beginMonitoring()
        #expect(h.recorder.onInputInterrupted != nil)
        h.coordinator.endMonitoring()
        #expect(h.recorder.onInputInterrupted == nil)
    }

    @Test("Un événement removed du fournisseur déclenche la bascule")
    func providerEventTriggersFallback() async throws {
        let h = makeHarness(devices: [macBook])
        h.recorder.currentInputUID = iphone.uid
        h.coordinator.beginMonitoring()
        h.devices.emit(.removed(uid: iphone.uid))
        // Le flux est consommé par une Task du coordinateur : on lui laisse un tour.
        for _ in 0..<50 where h.recorder.switchedTo.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(h.recorder.switchedTo == [macBook])
        h.coordinator.endMonitoring()
    }
}
```

- [ ] **Step 5 : Vérifier l'échec**

```bash
swift build --build-tests 2>&1 | grep -E "error:" | head -3
```

Attendu : `cannot find 'MeetingRecordingCoordinator' in scope`.

- [ ] **Step 6 : Écrire le coordinateur**

```swift
// OneToOne/Services/Meeting/MeetingRecordingCoordinator.swift
import AVFoundation
import Foundation
import os

private let coordLog = Logger(subsystem: "com.onetoone.app", category: "recording-coordinator")

/// Ce que le coordinateur demande au recorder. `AudioRecorderService` s'y
/// conforme ; les tests passent un double.
@MainActor
protocol RecordingInputSwitching: AnyObject {
    var isRecording: Bool { get }
    var currentInputUID: String? { get }
    var onInputInterrupted: (@MainActor () -> Void)? { get set }
    func switchInput(to device: AudioInputDevice?) throws
    func stopForInputLoss()
}

/// Les deux notifications de séance (spec §4.6, décision D4).
@MainActor
protocol RecordingNotifying: AnyObject {
    func notifyAudioInputFallback(deviceName: String)
    func notifyTeamsFlowMissing()
}

enum MicrophonePermissionStatus: Sendable {
    case granted
    case denied
    case undetermined
}

/// Ce que `MeetingView` passe à `AudioRecorderService.start`.
struct RecordingStartPlan: Equatable, Sendable {
    let inputUID: String?
    let captureMode: TeamsAudioCaptureMode
}

enum RecordingStartOutcome: Equatable, Sendable {
    case proceed(RecordingStartPlan)
    /// Une feuille est affichée ; `MeetingView` rappellera `prepareStart` avec
    /// `chosenUID` au choix de l'utilisateur.
    case awaitingUserChoice
    /// Rien ne démarre : autorisation refusée (la feuille d'aide est posée) ou
    /// aucune entrée (l'appelant affiche `AudioError.inputUnavailable`).
    case blocked
}

/// Porte la **décision** de démarrage d'un enregistrement (quelle entrée, quel
/// mode, quelle feuille) et la **surveillance** des entrées en séance (spec
/// §4.4). Le câblage recorder / transcription live / playhead reste dans
/// `MeetingView`. Un coordinateur par fenêtre de réunion.
@MainActor
final class MeetingRecordingCoordinator {

    private let devices: any AudioInputDeviceProviding
    private let recorder: any RecordingInputSwitching
    private let notifier: any RecordingNotifying
    private let isTeamsRunning: @MainActor () -> Bool
    private let hasScreenPermission: @MainActor () -> Bool
    private let microphonePermission: @MainActor () async -> MicrophonePermissionStatus

    /// Vrai depuis le dernier démarrage où Teams était fermé : `MeetingView`
    /// s'en sert pour **ne pas** afficher le bandeau « permission écran », qui
    /// parlerait d'autre chose (spec §4.4, point 3).
    private(set) var teamsFlowMissing = false

    private var monitoringTask: Task<Void, Never>?

    init(devices: any AudioInputDeviceProviding,
         recorder: any RecordingInputSwitching,
         notifier: any RecordingNotifying,
         isTeamsRunning: @escaping @MainActor () -> Bool,
         hasScreenPermission: @escaping @MainActor () -> Bool,
         microphonePermission: @escaping @MainActor () async -> MicrophonePermissionStatus) {
        self.devices = devices
        self.recorder = recorder
        self.notifier = notifier
        self.isTeamsRunning = isTeamsRunning
        self.hasScreenPermission = hasScreenPermission
        self.microphonePermission = microphonePermission
    }

    /// Le coordinateur de production, sur les singletons.
    static func makeLive() -> MeetingRecordingCoordinator {
        MeetingRecordingCoordinator(
            devices: AudioInputDeviceService.shared,
            recorder: AudioRecorderService.shared,
            notifier: MeetingNotificationService.shared,
            isTeamsRunning: { TeamsCallMonitor.isTeamsRunning() },
            hasScreenPermission: { SystemAudioCapture.isPermissionGranted() },
            microphonePermission: {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized: return .granted
                case .notDetermined: return .undetermined
                case .denied, .restricted: return .denied
                @unknown default: return .denied
                }
            })
    }

    // MARK: - Démarrage

    /// Applique dans l'ordre : permission micro, choix de l'entrée, mode de
    /// capture. `chosenUID` est le choix fait dans la feuille : il court-
    /// circuite la règle sans modifier le réglage préféré (D2).
    func prepareStart(preferredUID: String,
                      chosenUID: String?,
                      hasTeamsLink: Bool,
                      requestedMode: TeamsAudioCaptureMode,
                      screen: MeetingScreenModel) async -> RecordingStartOutcome {
        teamsFlowMissing = false

        // 1. Permission micro. `.undetermined` laisse `AudioRecorderService.start`
        //    déclencher la demande système, comme aujourd'hui.
        if await microphonePermission() == .denied {
            screen.recordingPrompts.permissionHelp = .microphone
            return .blocked
        }

        // 2. Entrée audio.
        devices.refresh()
        let inputUID: String?
        if let chosenUID {
            inputUID = chosenUID
        } else {
            switch AudioInputRouting.resolveStart(preferredUID: preferredUID, devices: devices.devices) {
            case .use(let uid):
                inputUID = uid
            case .askUser(let candidates, let missing):
                screen.recordingPrompts.audioInputChoice = AudioInputChoiceRequest(
                    missingPreferredUID: missing, candidates: candidates)
                return .awaitingUserChoice
            case .noInput:
                return .blocked
            }
        }

        // 3. Mode de capture. Une permission écran absente est laissée au
        //    recorder (bandeau jaune, spec D-6) ; Teams fermé est tranché ici (D3).
        var captureMode: TeamsAudioCaptureMode = hasTeamsLink ? requestedMode : .microOnly
        if captureMode == .microAndSystem, hasScreenPermission(), !isTeamsRunning() {
            teamsFlowMissing = true
            notifier.notifyTeamsFlowMissing()
            captureMode = .microOnly
        }

        return .proceed(RecordingStartPlan(inputUID: inputUID, captureMode: captureMode))
    }

    // MARK: - Surveillance

    /// À appeler dès que `AudioRecorderService.start` a réussi. Pose le crochet
    /// d'interruption du recorder et consomme les événements du fournisseur.
    func beginMonitoring() {
        endMonitoring()
        recorder.onInputInterrupted = { [weak self] in self?.handleInterruption() }
        let stream = devices.events()
        monitoringTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .removed(let uid) = event { self.handleRemoval(uid: uid) }
            }
        }
    }

    func endMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        recorder.onInputInterrupted = nil
    }

    /// Un périphérique a disparu. Interne (pas `private`) pour être appelée
    /// directement par les tests, sans passer par le flux.
    func handleRemoval(uid: String) {
        guard recorder.isRecording else { return }
        let verdict = AudioInputRouting.fallback(removedUID: uid,
                                                 currentUID: recorder.currentInputUID,
                                                 devices: devices.devices)
        switch verdict {
        case .ignore:
            return
        case .stopRecording:
            coordLog.error("Entrée \(uid, privacy: .public) retirée, aucune autre entrée → arrêt")
            recorder.stopForInputLoss()
        case .switchTo(let device):
            do {
                try recorder.switchInput(to: device)
                notifier.notifyAudioInputFallback(deviceName: device.name)
                coordLog.info("Bascule sur \(device.name, privacy: .public)")
            } catch {
                coordLog.error("Bascule échouée \(error.localizedDescription, privacy: .public) → arrêt")
                recorder.stopForInputLoss()
            }
        }
    }

    /// L'engine signale un changement de configuration. Deux cas : l'entrée en
    /// cours a disparu (la liste ne la contient plus) → même chemin que le
    /// retrait ; elle est toujours là (changement de fréquence, reroutage du
    /// défaut) → on la rebranche en silence, nouveau segment, aucune notification.
    func handleInterruption() {
        guard recorder.isRecording else { return }
        devices.refresh()
        if let current = recorder.currentInputUID,
           !devices.devices.contains(where: { $0.uid == current }) {
            handleRemoval(uid: current)
            return
        }
        let same = recorder.currentInputUID.flatMap { uid in devices.devices.first { $0.uid == uid } }
        do {
            try recorder.switchInput(to: same)
            coordLog.info("Interruption engine, rebranchement sur \(same?.name ?? "défaut système", privacy: .public)")
        } catch {
            coordLog.error("Rebranchement échoué \(error.localizedDescription, privacy: .public) → arrêt")
            recorder.stopForInputLoss()
        }
    }
}

// MARK: - Conformances de production

extension AudioRecorderService: RecordingInputSwitching {}
extension MeetingNotificationService: RecordingNotifying {}
```

Note : `AudioRecorderService.isRecording` est `@Published private(set)`, ce qui satisfait `{ get }` ; `onInputInterrupted` est `var` (Task 5). Si le compilateur refuse la conformance à cause de `nonisolated`/`@MainActor`, les deux classes sont déjà `@MainActor` : la conformance vide suffit.

- [ ] **Step 7 : Lancer les tests**

```bash
swift test --filter MeetingRecordingCoordinatorTests 2>&1 | tail -6
```

Attendu : 18 tests verts. Si `providerEventTriggersFallback` est instable, vérifier que `FakeAudioInputDevices.events()` enregistre la continuation **de façon synchrone** (le `AsyncStream` init l'appelle immédiatement).

- [ ] **Step 8 : Non-régression du modèle d'écran**

```bash
swift test --filter MeetingScreenModelTests 2>&1 | tail -3
```

- [ ] **Step 9 : Commit**

```bash
git add OneToOne/Services/MeetingNotificationService.swift OneToOne/Views/Meeting/Capture/RecordingPromptState.swift OneToOne/Views/Meeting/MeetingScreenModel.swift OneToOne/Services/Meeting/MeetingRecordingCoordinator.swift Tests/RecordingCoordinatorTestDoubles.swift Tests/MeetingRecordingCoordinatorTests.swift
git commit -m "feat(meeting): coordinateur d'enregistrement — décision de démarrage et surveillance des entrées

Permission micro → feuille d'aide ; préféré absent → feuille de choix ;
Teams fermé → notification et micro seul ; en séance, retrait ou
interruption → bascule par segment et notification, arrêt si plus rien.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7 : Feuilles et câblage dans `MeetingView`

**Files:**
- Create: `OneToOne/Views/Meeting/Capture/AudioInputChoiceSheet.swift`
- Create: `OneToOne/Views/Meeting/Capture/AudioPermissionHelpSheet.swift`
- Modify: `OneToOne/Views/MeetingView.swift` — lignes 78 (`screen`), 251 (bandeau), 269 (feuilles), 1042-1044 (`captureMode`), 1046-1100 (`startRecording`), 1104-1145 (`startAppendRecording`), 1204-1212 (`stopRecordingAndTranscribe`)

**Interfaces:**
- Consumes: `RecordingPromptState`, `AudioInputChoiceRequest`, `MeetingRecordingCoordinator`, `RecordingStartOutcome` (Task 6), `AudioPermissionKind` (Task 2), `AudioRecorderService.start(meetingID:captureMode:inputUID:)` (Task 5).
- Produces: `AudioInputChoiceSheet(request:onUse:onCancel:)`, `AudioPermissionHelpSheet(kind:onClose:)`.

Aucun test unitaire de vue (la convention du dépôt teste les règles, pas les vues) ; `RefonteTypographieTests` vérifie l'absence de fonte système sous `Views/Meeting/`.

- [ ] **Step 1 : Feuille de choix**

```swift
// OneToOne/Views/Meeting/Capture/AudioInputChoiceSheet.swift
import SwiftUI

/// « Micro de pré-réunion indisponible » (spec §1, ligne 1) : le micro préféré
/// n'est pas branché, voici les sources détectées. Le choix vaut pour cette
/// réunion seulement (D2). Mise en page reprise du sélecteur de capture :
/// lignes à sous-titre, bouton primaire plein, jetons `One2OneToken`.
struct AudioInputChoiceSheet: View {

    let request: AudioInputChoiceRequest
    let onUse: (AudioInputDevice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Micro indisponible")
                .font(.plexSans(17, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("Le micro préféré n'est pas branché. Choisissez une autre source pour cette réunion ; le réglage n'est pas modifié.")
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(request.candidates) { device in
                    ligne(device)
                }
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.plexSans(12.5, .medium))
                    .foregroundStyle(One2OneToken.ink3)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420)
        .background(One2OneToken.surface)
    }

    private func ligne(_ device: AudioInputDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isBuiltIn ? "laptopcomputer" : "mic")
                .font(.plexSans(13))
                .foregroundStyle(One2OneToken.ink3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.plexSans(13, .medium))
                    .foregroundStyle(One2OneToken.ink1)
                Text(sousTitre(device))
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
            }
            Spacer()
            Button("Utiliser") { onUse(device) }
                .buttonStyle(CapturePrimaryButtonStyle())
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.surfaceAlt))
        .overlay(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).stroke(One2OneToken.cardBorder))
    }

    private func sousTitre(_ device: AudioInputDevice) -> String {
        switch (device.isBuiltIn, device.isSystemDefault) {
        case (true, true): return "Micro intégré · entrée par défaut du système"
        case (true, false): return "Micro intégré"
        case (false, true): return "Entrée par défaut du système"
        case (false, false): return "Entrée externe"
        }
    }
}
```

- [ ] **Step 2 : Feuille d'aide autorisations**

```swift
// OneToOne/Views/Meeting/Capture/AudioPermissionHelpSheet.swift
import SwiftUI

/// « Refus d'autorisation microphone / audio système » (spec §1, ligne 4) :
/// explique, ouvre le bon volet des Réglages Système, donne le chemin manuel
/// si l'ouverture échoue. Même patron que `refusDAutorisation` du sélecteur
/// de capture.
struct AudioPermissionHelpSheet: View {

    let kind: AudioPermissionKind
    let onClose: () -> Void

    @State private var ouvertureEchouee = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title)
                .font(.plexSans(17, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text(kind.explanation)
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pour autoriser OneToOne :")
                    .font(.plexSans(12, .medium))
                    .foregroundStyle(One2OneToken.warnInk)
                Text(kind.manualPath)
                    .font(.plexMono(11.5))
                    .foregroundStyle(One2OneToken.ink2)
                Text("Cochez OneToOne dans la liste, puis relancez l'enregistrement.")
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                if ouvertureEchouee {
                    Text("Les Réglages Système n'ont pas pu être ouverts automatiquement : suivez le chemin ci-dessus.")
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.warnInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: One2OneToken.radiusCard).fill(One2OneToken.warnBg))

            HStack {
                Button("Fermer", action: onClose)
                    .buttonStyle(.plain)
                    .font(.plexSans(12.5, .medium))
                    .foregroundStyle(One2OneToken.ink3)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Ouvrir les Réglages Système…") {
                    ouvertureEchouee = !kind.openSettings()
                }
                .buttonStyle(CapturePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(One2OneToken.surface)
    }
}
```

- [ ] **Step 3 : Retirer `captureMode` de `MeetingView` et ajouter le coordinateur**

Supprimer les lignes 1038-1044 (le commentaire et la propriété `captureMode`). À la ligne 78, juste après `@State private var screen = MeetingScreenModel()`, ajouter :

```swift
    @State private var recordingCoordinator = MeetingRecordingCoordinator.makeLive()
```

- [ ] **Step 4 : Réécrire le début de `startRecording`**

Remplacer la signature et le début de `startRecording()` (jusqu'à `let liveStream` inclus) par :

```swift
    /// `chosenInputUID` : le choix fait dans `AudioInputChoiceSheet`, `nil` au
    /// premier passage. Le préflight (permission, entrée, Teams) est dans
    /// `MeetingRecordingCoordinator` ; ici, le câblage recorder / live / playhead.
    private func startRecording(chosenInputUID: String? = nil) async {
        if recorder.isRecording && recorder.activeMeetingID != meeting.stableID {
            recorder.lastError = "Un enregistrement est déjà en cours pour une autre réunion."
            TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
            return
        }
        let outcome = await recordingCoordinator.prepareStart(
            preferredUID: settings.preferredAudioInputUID,
            chosenUID: chosenInputUID,
            hasTeamsLink: meeting.teamsJoinURL?.isEmpty == false,
            requestedMode: settings.teamsAudioCaptureMode,
            screen: screen)
        guard case .proceed(let plan) = outcome else {
            if outcome == .blocked, screen.recordingPrompts.permissionHelp == nil {
                recorder.lastError = AudioError.inputUnavailable.errorDescription
            }
            // Le coordinateur Teams attend un enregistrement : sans feuille en
            // attente, on lui dit qu'il n'aura pas lieu.
            if outcome == .blocked, !recorder.isRecording(for: meeting.ensuredStableID) {
                TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
            }
            return
        }
        let liveStream: AsyncStream<[Float]>? = settings.liveTranscriptionEnabled
            ? recorder.makeAudioStream() : nil
```

Dans le `do` qui suit, remplacer

```swift
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: captureMode)
```

par

```swift
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: plan.captureMode,
                                               inputUID: plan.inputUID)
            recordingCoordinator.beginMonitoring()
```

- [ ] **Step 5 : Même préflight pour `startAppendRecording`**

Dans `startAppendRecording()`, remplacer

```swift
        pendingAppendBaseURL = existing
```

par

```swift
        let outcome = await recordingCoordinator.prepareStart(
            preferredUID: settings.preferredAudioInputUID,
            chosenUID: nil,
            hasTeamsLink: meeting.teamsJoinURL?.isEmpty == false,
            requestedMode: settings.teamsAudioCaptureMode,
            screen: screen)
        guard case .proceed(let plan) = outcome else {
            if outcome == .blocked, screen.recordingPrompts.permissionHelp == nil {
                recorder.lastError = AudioError.inputUnavailable.errorDescription
            }
            return
        }
        pendingAppendBaseURL = existing
```

et

```swift
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: captureMode)
```

par

```swift
            let url = try await recorder.start(meetingID: meeting.ensuredStableID,
                                               captureMode: plan.captureMode,
                                               inputUID: plan.inputUID)
            recordingCoordinator.beginMonitoring()
```

Note : en mode « ajout », la feuille de choix rappelle `startRecording(chosenInputUID:)` et non `startAppendRecording` ; c'est acceptable pour ce lot (l'ajout avec micro préféré absent démarre alors un enregistrement qui **remplace** au lieu d'ajouter). Le noter dans STATUS.md (Task 9).

- [ ] **Step 6 : Arrêter la surveillance à l'arrêt**

Dans `stopRecordingAndTranscribe()`, juste après `guard let stopped = recorder.stop() else { return }`, ajouter :

```swift
        recordingCoordinator.endMonitoring()
```

- [ ] **Step 7 : Bandeau et feuilles**

Ligne 251, remplacer la condition du bandeau jaune :

```swift
            if isRecordingThisMeeting, recorder.systemAudioUnavailable, !recordingCoordinator.teamsFlowMissing {
```

Après le `.sheet(isPresented: $showCalendarImporter) { … }` (ligne 269-273), ajouter :

```swift
        .sheet(item: Binding(
            get: { screen.recordingPrompts.audioInputChoice },
            set: { screen.recordingPrompts.audioInputChoice = $0 }
        )) { request in
            AudioInputChoiceSheet(
                request: request,
                onUse: { device in
                    screen.recordingPrompts.audioInputChoice = nil
                    Task { await startRecording(chosenInputUID: device.uid) }
                },
                onCancel: {
                    screen.recordingPrompts.audioInputChoice = nil
                    if !recorder.isRecording(for: meeting.ensuredStableID) {
                        TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
                    }
                })
        }
        .sheet(item: Binding(
            get: { screen.recordingPrompts.permissionHelp },
            set: { screen.recordingPrompts.permissionHelp = $0 }
        )) { kind in
            AudioPermissionHelpSheet(kind: kind) {
                screen.recordingPrompts.permissionHelp = nil
            }
        }
```

- [ ] **Step 8 : Compter les lignes de `MeetingView`**

```bash
git diff --stat OneToOne/Views/MeetingView.swift
```

Attendu : le nombre de lignes retirées est supérieur ou égal au nombre ajouté **hors** les deux blocs `.sheet` (qui remplacent une décision inline par une délégation). Si ce n'est pas le cas, déplacer les deux blocs `.sheet` dans un `ViewModifier` `RecordingPromptSheets` dans `Views/Meeting/Capture/RecordingPromptSheets.swift` :

```swift
// OneToOne/Views/Meeting/Capture/RecordingPromptSheets.swift
import SwiftUI

/// Les deux feuilles du démarrage d'enregistrement, en un modificateur : la
/// vue de réunion reste un routeur.
struct RecordingPromptSheets: ViewModifier {
    let screen: MeetingScreenModel
    let onUseDevice: (AudioInputDevice) -> Void
    let onCancelChoice: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { screen.recordingPrompts.audioInputChoice },
                set: { screen.recordingPrompts.audioInputChoice = $0 }
            )) { request in
                AudioInputChoiceSheet(request: request,
                                      onUse: { screen.recordingPrompts.audioInputChoice = nil; onUseDevice($0) },
                                      onCancel: { screen.recordingPrompts.audioInputChoice = nil; onCancelChoice() })
            }
            .sheet(item: Binding(
                get: { screen.recordingPrompts.permissionHelp },
                set: { screen.recordingPrompts.permissionHelp = $0 }
            )) { kind in
                AudioPermissionHelpSheet(kind: kind) { screen.recordingPrompts.permissionHelp = nil }
            }
    }
}
```

et dans `MeetingView` :

```swift
        .modifier(RecordingPromptSheets(
            screen: screen,
            onUseDevice: { device in Task { await startRecording(chosenInputUID: device.uid) } },
            onCancelChoice: {
                if !recorder.isRecording(for: meeting.ensuredStableID) {
                    TeamsAutoRecordCoordinator.shared.recordingDidFail(meetingID: meeting.ensuredStableID)
                }
            }))
```

- [ ] **Step 9 : Compiler et rejouer les suites qui touchent la vue**

```bash
swift build 2>&1 | grep -E "error:|Build complete" | head -5
swift test --filter "RefonteTypographieTests|AppShortcutsTests|MeetingScreenModelTests|MeetingRecordingCoordinatorTests" 2>&1 | tail -4
```

Attendu : `Build complete!`, suites vertes.

- [ ] **Step 10 : Recette manuelle rapide**

```bash
Scripts/bump-and-build.sh dev
```

Puis, dans l'app installée : Réglages → rien encore (Task 8) ; ouvrir une réunion, démarrer l'enregistrement : il démarre comme avant (préféré = défaut système). Vérifier dans Console.app (`category: audio`) la ligne `bind input default`.

- [ ] **Step 11 : Commit**

```bash
git add OneToOne/Views/Meeting/Capture/AudioInputChoiceSheet.swift OneToOne/Views/Meeting/Capture/AudioPermissionHelpSheet.swift OneToOne/Views/MeetingView.swift
git add OneToOne/Views/Meeting/Capture/RecordingPromptSheets.swift 2>/dev/null || true
git commit -m "feat(meeting): feuilles de choix de micro et d'aide autorisations, préflight du démarrage

MeetingView perd captureMode et délègue la décision au coordinateur ;
la surveillance des entrées commence au succès de start et cesse au stop.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8 : Réglage « Entrée audio »

**Files:**
- Create: `OneToOne/Views/Settings/AudioInputSettingsSection.swift`
- Modify: `OneToOne/Views/SettingsView.swift:404` (avant `GroupBox("Reconnaissance vocale")`)

**Interfaces:**
- Consumes: `AppSettings.preferredAudioInputUID` (Task 3), `AudioInputDeviceService.shared` (Task 3), `AudioInputRouting.systemDefaultUID` (Task 1).
- Produces: `AudioInputSettingsSection(settings: AppSettings, onSave: () -> Void)`.

- [ ] **Step 1 : Écrire la section**

```swift
// OneToOne/Views/Settings/AudioInputSettingsSection.swift
import SwiftUI

/// `GroupBox("Entrée audio")` des Réglages (spec §4.5) : le micro préféré,
/// global (D2). La liste vient du service CoreAudio et se met à jour au
/// branchement ; un préféré débranché reste sélectionnable pour ne pas
/// effacer le réglage à son insu.
struct AudioInputSettingsSection: View {

    let settings: AppSettings
    let onSave: () -> Void

    private var service: AudioInputDeviceService { AudioInputDeviceService.shared }

    var body: some View {
        GroupBox("Entrée audio") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Micro préféré", selection: Binding(
                    get: { settings.preferredAudioInputUID },
                    set: { settings.preferredAudioInputUID = $0; onSave() }
                )) {
                    Text("Par défaut du système").tag(AudioInputRouting.systemDefaultUID)
                    ForEach(service.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if prefereAbsent {
                        Text("Micro débranché (\(settings.preferredAudioInputUID))")
                            .tag(settings.preferredAudioInputUID)
                    }
                }
                Text("Utilisé au démarrage de chaque enregistrement. S'il est débranché, l'application propose une autre source ; s'il se déconnecte en cours de réunion, elle bascule sur le micro du Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
        .onAppear { service.refresh() }
    }

    private var prefereAbsent: Bool {
        let uid = settings.preferredAudioInputUID
        return uid != AudioInputRouting.systemDefaultUID && !service.devices.contains { $0.uid == uid }
    }
}
```

Note : `SettingsView` utilise la fonte système (`.caption`) partout ; cette section suit le fichier hôte, qui est hors du périmètre typographique de la refonte (`Views/Settings/` n'est pas dans `RefonteTypographieTests`). Vérifier :

```bash
grep -n "Settings" Tests/RefonteTypographieTests.swift | head -3
```

Si `Views/Settings/` y figure, remplacer `.font(.caption)` par `.font(.plexSans(11.5))` et `.foregroundColor(.secondary)` par `.foregroundStyle(One2OneToken.inkMuted)`.

- [ ] **Step 2 : Insérer dans `SettingsView`**

Ligne 404, juste avant `GroupBox("Reconnaissance vocale") {` :

```swift
                AudioInputSettingsSection(settings: settings, onSave: saveSettings)

```

- [ ] **Step 3 : Compiler**

```bash
swift build 2>&1 | grep -E "error:|Build complete" | head -5
```

- [ ] **Step 4 : Recette manuelle**

```bash
Scripts/bump-and-build.sh dev
```

Dans Réglages : la section « Entrée audio » liste « Par défaut du système » et les micros détectés. Choisir le micro intégré, fermer, rouvrir : le choix est conservé. Brancher un iPhone en Continuité (ou un micro USB) : il apparaît dans la liste sans relancer.

- [ ] **Step 5 : Commit**

```bash
git add OneToOne/Views/Settings/AudioInputSettingsSection.swift OneToOne/Views/SettingsView.swift
git commit -m "feat(settings): section Entrée audio — micro préféré global

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9 : Documentation, recette de bout en bout, suite complète

**Files:**
- Modify: `docs/architecture.md:392-399` (§6.4 Audio)
- Create: `docs/adr/2026-09-14-sources-audio-fallback-par-segment.md`
- Modify: `docs/adr/README.md` (ajouter la ligne de l'ADR, même format que les précédentes)
- Modify: `STATUS.md`

- [ ] **Step 1 : Architecture §6.4**

Dans `docs/architecture.md`, §6.4 Audio, après la puce `AudioRecorderService`, ajouter :

```markdown
- **`AudioInputDeviceService`** (singleton `@MainActor`, `@Observable`) — énumère les entrées
  audio CoreAudio (UID, nom, transport, défaut système), observe les branchements et publie un
  flux `AudioInputEvent`. Il ne décide rien.
- **`AudioInputRouting`** (enum pure) — verdict de démarrage (préféré présent / absent / aucune
  entrée) et verdict de repli à la déconnexion (micro intégré par type de transport, défaut
  système, première restante, arrêt). Spec `docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`.
- **`AudioPermissionKind` / `MicrophoneSettingsLink`** — quel volet des Réglages Système ouvrir
  quand le micro ou l'audio système est refusé ; pendant micro de `ScreenRecordingSettingsLink`.
- **Fallback par segment** : `AudioRecorderService.switchInput(to:)` clôt le WAV courant, en
  ouvre un second sur la nouvelle entrée et garde le même `TapSink` (le flux live ne voit rien) ;
  `stop()` fusionne les segments (`mergeSegments`). ADR
  `docs/adr/2026-09-14-sources-audio-fallback-par-segment.md`.
```

Dans §6.5, après la puce `MeetingNotificationService`, ajouter :

```markdown
- **`MeetingRecordingCoordinator`** (`Services/Meeting/`, un par fenêtre de réunion) — préflight
  du démarrage d'enregistrement (permission micro → feuille d'aide, entrée → feuille de choix,
  Teams fermé → notification et micro seul) et surveillance des entrées en séance (retrait ou
  interruption de l'engine → bascule par segment et notification, arrêt s'il ne reste rien).
  `MeetingView` garde le câblage recorder / live / playhead.
```

- [ ] **Step 2 : ADR**

```markdown
# ADR 2026-09-14 — Sources audio : fallback par segment et notifications système

## Contexte

Le tableau des cas d'erreur de capture (spec
`docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`, §1) demande qu'un iPhone
déconnecté en cours de réunion provoque une bascule immédiate sur le micro du Mac. Jusqu'ici,
tout changement de périphérique **arrêtait** l'enregistrement et tuait la transcription live
(`AudioRecorderService.handleConfigurationChange`). L'application ne savait pas non plus
choisir un micro : l'engine lisait l'entrée par défaut du système.

## Décisions

**D1 — Fallback par segment.** À la déconnexion, le WAV courant est clos, un second est ouvert
sur l'entrée de repli, et les segments sont concaténés à l'arrêt (`mergeSegments`, sur la
primitive `concatenateWAVs` déjà présente). Le `TapSink` est conservé : seuls son fichier et son
convertisseur changent (`rotate`), la continuation du flux live et l'horloge d'échantillons
publiés ne bougent pas. Alternative écartée : rebrancher l'engine dans le même fichier, qui
impose de réinstaller tap et convertisseur sur un `AVAudioFile` ouvert et risque de corrompre le
WAV en cours.

**D2 — Micro préféré global** (`AppSettings.preferredAudioInputUID`), le choix fait dans la
feuille de pré-réunion vaut pour cette réunion seulement.

**D3 — Contrôle Teams au démarrage seulement.** Une piste système laissée ouverte après la
fermeture de Teams capte du silence, sans dommage.

**D4 — Notifications système pour les événements de séance** (bascule, flux Teams absent) via
`MeetingNotificationService`, **feuilles in-app** pour le choix de micro et l'aide autorisations.
Aucun composant toast n'est créé. Alternative écartée : un toast in-app, toujours visible en
plein écran mais un composant de plus.

**D5 — Trois couches** : `AudioInputRouting` décide (pur, testé), `AudioInputDeviceService`
observe (CoreAudio, recette manuelle), `AudioRecorderService` exécute ; `MeetingRecordingCoordinator`
les relie et porte la surveillance.

**D6 — Pas de rebascule automatique** au retour du périphérique.

**D7 — Le micro intégré est reconnu par `kAudioDeviceTransportTypeBuiltIn`**, jamais par son nom.

## Conséquences

- `AVAudioEngineConfigurationChange` ne stoppe plus l'enregistrement quand un coordinateur
  surveille : il lui est remis, et c'est lui qui rebranche (même entrée, nouveau segment) ou
  bascule. Sans coordinateur, comportement historique.
- Un enregistrement peut désormais produire plusieurs fichiers intermédiaires ; `stop()` rend
  toujours **une** URL. Si la fusion échoue, le dernier segment est rendu et les autres restent
  sur disque, dans `recordings/`.
- Les bascules sont tracées dans `AudioRecorderService.inputSwitches`, pas dans
  `provenanceTimeline` dont la struct est figée par ses tests.
- Hors périmètre : choix par réunion, rebascule au retour, surveillance de Teams en séance,
  toast in-app, périphériques de sortie, sélection du micro depuis la palette ⌘K.
```

- [ ] **Step 3 : STATUS.md**

En tête de `STATUS.md`, remplacer la date et ajouter une section avant « Refonte de la gestion des projets » :

```markdown
Dernière mise à jour : <date du jour> CEST

## Sources audio et cas d'erreur de capture (2026-09-14)

Spec `docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`, plan
`docs/superpowers/plans/2026-09-14-sources-audio-erreurs.md`, ADR
`docs/adr/2026-09-14-sources-audio-fallback-par-segment.md`. Branche `feat/sources-audio-erreurs`.

**Livré.** Micro préféré global (Réglages → Entrée audio) ; feuille de choix quand il manque au
démarrage ; feuille d'aide quand le micro est refusé ; Teams fermé → notification et micro seul ;
iPhone déconnecté en séance → bascule par segment sur le micro intégré, notification système,
fusion des segments à l'arrêt, flux live ininterrompu. `MeetingView` a perdu `captureMode` et
délègue le préflight à `MeetingRecordingCoordinator`.

**Tests.** `swift test` complet vert : <compter> Swift Testing + <compter> XCTest. Nouvelles
suites : `AudioInputRoutingTests`, `AudioPermissionHelpTests`, `TapSinkRotationTests`,
`AudioRecorderSegmentsTests`, `MeetingRecordingCoordinatorTests`.

**Recette manuelle** (<date>) : <résultat des cinq scénarios de la Task 9, un par ligne>.

**Dettes.** En mode « ajouter un enregistrement », si le micro préféré manque, la feuille de choix
relance `startRecording` et non `startAppendRecording` : l'enregistrement remplace au lieu
d'ajouter. `AudioInputDeviceService` n'est pas testé unitairement. Le retour de l'iPhone ne
rebascule pas (D6).

**Prochaine action.** PR `feat/sources-audio-erreurs` → `master`, puis décider du choix de micro
par réunion (D2, alternative) selon l'usage.
```

- [ ] **Step 4 : Tests de documentation**

```bash
swift test --filter DocumentationTests 2>&1 | tail -6
```

Attendu : vert. Si un symbole cité dans l'ADR ou l'architecture n'est pas trouvé, corriger la citation (les noms doivent exister dans les sources : `AudioInputDeviceService`, `AudioInputRouting`, `AudioPermissionKind`, `MicrophoneSettingsLink`, `MeetingRecordingCoordinator`, `mergeSegments`, `switchInput`, `rotate`, `inputSwitches`, `preferredAudioInputUID`).

- [ ] **Step 5 : Suite complète**

```bash
swift test 2>&1 | tail -8
```

Attendu : exit 0, aucun test retiré par rapport à la base (3 599 avant ce chantier), toutes les nouvelles suites listées. Reporter les compteurs dans `STATUS.md`.

- [ ] **Step 6 : Recette manuelle de bout en bout**

```bash
Scripts/bump-and-build.sh dev
```

Cinq scénarios, un iPhone en Continuité ou un micro USB branché :

1. Réglages → Entrée audio → choisir l'iPhone. Débrancher. Ouvrir une réunion, démarrer : la feuille « Micro indisponible » liste le micro intégré ; « Utiliser » démarre ; le réglage reste sur l'iPhone.
2. Rebrancher l'iPhone, démarrer une réunion (préféré présent) : pas de feuille. Débrancher en cours : notification « Bascule sur le micro Microphone MacBook Pro », le vumètre continue, la transcription live continue. Arrêter : un seul WAV, durée cumulée, `recordings/` ne garde pas les segments.
3. Réunion avec lien Teams, Teams fermé, permission écran accordée : notification « Aucun flux Teams détecté », pas de bandeau jaune, enregistrement micro seul.
4. Réglages Système → Confidentialité → Microphone : décocher OneToOne. Démarrer : feuille d'aide micro, bouton « Ouvrir les Réglages Système… » ouvre le volet Microphone.
5. Débrancher **toutes** les entrées externes puis, en séance sur l'iPhone, débrancher l'iPhone sur un Mac de bureau sans micro intégré (ou simuler en posant `devices: []` dans un test) : arrêt propre avec le message « Périphérique audio modifié ».

Reporter chaque résultat dans `STATUS.md`.

- [ ] **Step 7 : Commit et PR**

```bash
git add docs/architecture.md docs/adr/2026-09-14-sources-audio-fallback-par-segment.md docs/adr/README.md STATUS.md
git commit -m "docs: sources audio — architecture §6.4/§6.5, ADR fallback par segment, STATUS

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/sources-audio-erreurs
gh pr create --base master --title "feat: sources audio et cas d'erreur de capture" --body "$(cat <<'EOF'
## Intention

Une seule : honorer les quatre cas d'erreur de capture de la spec
`docs/superpowers/specs/2026-09-14-sources-audio-erreurs-design.md`.

- Micro préféré global (Réglages → Entrée audio) ; feuille de choix quand il manque au démarrage.
- iPhone déconnecté en séance → bascule **par segment** sur le micro intégré, notification système, fusion à l'arrêt, flux live ininterrompu.
- Teams fermé au démarrage → notification « Aucun flux Teams détecté », micro seul.
- Micro refusé → feuille d'aide vers Réglages Système → Microphone.

## Décisions

ADR `docs/adr/2026-09-14-sources-audio-fallback-par-segment.md` (D1–D7).

## Tests

`swift test` complet vert. Nouvelles suites : `AudioInputRoutingTests`, `AudioPermissionHelpTests`,
`TapSinkRotationTests`, `AudioRecorderSegmentsTests`, `MeetingRecordingCoordinatorTests`.
Recette manuelle des cinq scénarios dans `STATUS.md`.

## Dépendances

Aucune nouvelle. CoreAudio et AudioToolbox sont des frameworks système.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Auto-revue du plan

**Couverture de la spec.** §1 ligne 1 → Tasks 1, 6, 7 (feuille de choix) ; ligne 2 → Tasks 4, 5, 6 (bascule, notification) ; ligne 3 → Task 6 (`teamsFlowMissing`, notification) et Task 7 (bandeau conditionné) ; ligne 4 → Tasks 2, 6, 7 (feuille d'aide). §4.1 → Task 1 ; §4.2 → Task 3 ; §4.3 → Tasks 4, 5 ; §4.4 → Task 6 (décision et surveillance ; le déplacement complet de `startRecording` est explicitement laissé, cf. contraintes) ; §4.5 → Tasks 7, 8 ; §4.6 → Task 6 ; §5 → Task 3 ; §6 → chaque tâche porte ses tests, `AudioRecorderSegmentsTests` et `TapSinkRotationTests` couvrent ensemble ce que la spec nommait `AudioRecorderSegmentsTests` ; §7 → rien n'est construit hors périmètre ; §8 → Task 9.

**Cohérence des types.** `AudioInputDevice(uid:name:isBuiltIn:isSystemDefault:)` partout ; `AudioInputRouting.StartVerdict.use(uid:)` (Task 1) consommé tel quel en Task 6 ; `RecordingStartPlan(inputUID:captureMode:)` produit en Task 6, consommé en Task 7 ; `recorder.start(meetingID:captureMode:inputUID:)` défini en Task 5, appelé en Task 7 ; `switchInput(to: AudioInputDevice?)` défini en Task 5, exigé par `RecordingInputSwitching` en Task 6 ; `onInputInterrupted: (@MainActor () -> Void)?` identique en Tasks 5 et 6 ; `TapSink.targetFormat` rendu lisible en Task 4, lu en Task 5 ; `AudioError.inputUnavailable` ajouté en Task 5, utilisé en Task 7 ; `MeetingScreenModel.recordingPrompts` ajouté en Task 6, lu en Task 7.
