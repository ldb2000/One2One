import Foundation
import SwiftData
import os

private let pillLog = Logger(subsystem: "com.onetoone.app", category: "session-pill")

/// La pastille branchée sur une vraie réunion.
///
/// C'est le seul endroit du lot qui touche à SwiftData, au coordinateur de capture et
/// aux notes : `SessionPillModel` ne connaît que le protocole, et la vue ne connaît que
/// le modèle.
///
/// Aucune méthode de ce type n'active l'application ni ne change d'espace, sauf
/// `openSourceSelector()` — qui est là pour ça, et que le modèle n'appelle qu'en
/// l'absence de source (critère n° 2 du chantier 4).
@MainActor
final class MeetingPillTarget: SessionPillTarget {

    private let handle: ActiveMeetingHandle
    private let onOpenSourceSelector: @MainActor (ActiveMeetingHandle) -> Void
    private let recordingCheck: @MainActor (UUID) -> Bool

    init(handle: ActiveMeetingHandle,
         isRecording: @escaping @MainActor (UUID) -> Bool = { AudioRecorderService.shared.isRecording(for: $0) },
         onOpenSourceSelector: @escaping @MainActor (ActiveMeetingHandle) -> Void) {
        self.handle = handle
        self.recordingCheck = isRecording
        self.onOpenSourceSelector = onOpenSourceSelector
    }

    var meetingStableID: UUID { handle.meetingStableID }

    // MARK: - Lecture

    /// Le `t` de la réunion, depuis l'axe **audio** — jamais l'horloge de la capture
    /// (même règle que le lot 7 : une note et une capture prises au même moment doivent
    /// porter le même instant).
    /// `elapsedIfAny` et non `refresh()` : ce chrono est lu **depuis un corps de
    /// vue** (le `TimelineView` de `FloatingPill`), et `refresh()` écrit `t` et
    /// `duration`. Une écriture pendant un rendu invalide ce rendu, qui relit,
    /// qui réécrit : c'est le gel du 2026-09-08 au démarrage de
    /// l'enregistrement. Le temps est publié par le battement de la tête de
    /// lecture, pas par la vue qui l'affiche.
    var elapsed: Double? {
        handle.screen.playhead.elapsedIfAny
    }

    var captureCount: Int { handle.capture.captureCount }

    var isRecording: Bool { recordingCheck(handle.meetingStableID) }

    func firstOCRLine(forCaptureID id: UUID) -> String? {
        guard let capture = slide(id) else { return nil }
        return CaptureStripModel.firstOCRLine(of: capture)
    }

    // MARK: - Capturer

    /// La chaîne complète du critère n° 2 : `captureNow` → `SlideCapture(t)` →
    /// `CaptureNoteInsertion` → confirmation, sans un seul aller-retour dans la fenêtre.
    func captureNow() async -> SessionPillCaptureResult {
        let coordinateur = handle.capture
        guard coordinateur.pillHasSource else { return .needsSource }

        let avant = Set(coordinateur.captures.map(\.id))
        let ecrit = await coordinateur.captureNow()
        guard ecrit else {
            return .failed(coordinateur.service.lastError ?? "Capture impossible.")
        }
        // La capture neuve par différence, et non « la dernière » : la bande trie par
        // timecode, et une capture prise hors enregistrement (`t == nil`) part en fin de
        // liste, où elle n'est pas la plus récente.
        guard let capture = coordinateur.captures.first(where: { !avant.contains($0.id) }) else {
            return .failed(coordinateur.service.lastError ?? "Capture écrite, mais introuvable.")
        }

        // La vignette « glisse dans les notes au timecode courant » (légende de la
        // maquette 4b) : l'insertion du lot 7, idempotente, porte un `sourceRef` et non
        // une copie de l'image.
        CaptureNoteInsertion.insert(capture, in: handle.meeting, context: handle.context)
        pillLog.info("capture depuis la pastille : t=\(capture.t ?? -1)")

        return .captured(SessionPillCapture(id: capture.id,
                                            t: capture.t,
                                            thumbnailPath: capture.imagePath))
    }

    // MARK: - Écrire

    @discardableResult
    func createNote(_ text: String) -> Bool {
        // Le même analyseur que le composeur de notes : `/décision` frappé dans la
        // pastille doit créer une décision, pas une note qui commence par un slash.
        let analyse = NoteCommandParser.parse(text)
        let note = MeetingNoteStore.append(analyse,
                                           at: elapsed ?? 0,
                                           to: handle.meeting,
                                           in: handle.context)
        return note != nil
    }

    @discardableResult
    func createAction(fromCaptureID id: UUID) -> Bool {
        guard let capture = slide(id) else { return false }
        let brouillon = CaptureNoteInsertion.actionDraft(for: capture)
        let action = ActionComposerService.creerDepuisCapture(brouillon,
                                                              screen: handle.screen,
                                                              meeting: handle.meeting,
                                                              in: handle.context)
        return action != nil
    }

    /// Le seul chemin qui ramène l'utilisateur dans l'application.
    func openSourceSelector() {
        handle.screen.capture.showPopover = true
        onOpenSourceSelector(handle)
    }

    // MARK: - Zone à la souris

    /// Ouvre une session sur une zone tracée (spec §5.1, `⌥⌘⇧S`).
    func useRegion(_ region: NormalizedRect) async {
        await handle.capture.startRegionSession(region)
    }

    private func slide(_ id: UUID) -> SlideCapture? {
        handle.meeting.attachments.flatMap(\.slides).first { $0.id == id }
    }
}
