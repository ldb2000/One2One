import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import os

private let captureLog = Logger(subsystem: "com.onetoone.app", category: "capture")

/// Coordinateur de la capture automatique de slides : relie la source d'images
/// (`FrameSource`), la zone (`NormalizedRect`), le détecteur (`SlideDetector`) et la
/// persistance (`SlideCapture` + OCR), et publie l'état de la session à l'interface.
///
/// **Invariant** : une session est ouverte (`currentAttachment != nil`) si et seulement
/// si l'état est `running`, `paused` ou `stopped`.
///
/// - `stop()` annule la boucle et publie `stopped` **sans** clore la session : `resume()`
///   reprend le même attachment, le même détecteur, la même numérotation.
/// - `finish()` clôt : attente OCR, sauvegarde, réindexation, puis `idle`.
/// - `abandon()` ferme sans rien sauvegarder ni réindexer (réunion supprimée).
/// - `tick()` est la plus petite unité de travail et est appelable directement : les tests
///   pilotent la capture sans horloge. Après chaque `await`, il revérifie **jeton de session
///   et état** (`sessionIsLive`) : un tick suspendu pendant `stop()` ou `finish()` ne doit ni
///   écrire ni publier — publier `.paused` par-dessus `.stopped` serait irrécupérable
///   (`resume()` exige `.stopped`).
@MainActor
final class ScreenCaptureService: ObservableObject {

    enum State: Equatable {
        case idle
        case running
        case paused(String)
        case stopped

        var isPaused: Bool {
            if case .paused = self { return true }
            return false
        }
    }

    /// Ce qui définit une session : figé pendant la boucle, modifiable en `stopped`
    /// (fenêtre seulement, via `updateSource`).
    struct SessionConfiguration: Equatable {
        var windowID: CGWindowID
        var windowTitle: String
        var crop: NormalizedRect
        var sensitivity: SlideCaptureSettings.Sensitivity
    }

    enum SessionError: Error, Equatable, LocalizedError {
        case sessionAlreadyOpen
        case attachmentBelongsToAnotherMeeting

        var errorDescription: String? {
            switch self {
            case .sessionAlreadyOpen:
                return "Une session de capture est déjà ouverte."
            case .attachmentBelongsToAnotherMeeting:
                return "Ce lot de slides appartient à une autre réunion."
            }
        }
    }

    typealias FrameSourceFactory = @Sendable (CGWindowID) -> any FrameSource
    typealias OCRFunction = @Sendable (CGImage) async throws -> String
    typealias ReindexFunction = @MainActor (MeetingAttachment, ModelContext) async -> Void

    // MARK: - État publié

    @Published private(set) var state: State = .idle
    /// Attachment `kind: "slides"` de la session ouverte. `nil` hors session.
    @Published private(set) var currentAttachment: MeetingAttachment?
    @Published private(set) var configuration: SessionConfiguration?
    @Published var lastError: String?
    @Published private(set) var ocrProgress: (current: Int, total: Int)?

    /// Compatibilité avec les barres : capture « active » = en cours ou en pause.
    var isCapturing: Bool { state == .running || state.isPaused }
    var hasOpenSession: Bool { currentAttachment != nil }
    /// Source de vérité : le nombre d'éléments dans `currentAttachment.slides`.
    var capturedSlidesCount: Int { currentAttachment?.slides.count ?? 0 }

    // MARK: - Dépendances injectables

    private let recordingsRoot: URL
    private let frameSourceFactory: FrameSourceFactory
    private let ocr: OCRFunction
    private let reindex: ReindexFunction

    // MARK: - État interne de session

    /// Régénéré à chaque `beginSession`, remis à `nil` par `finish()` et `abandon()`
    /// **avant** toute attente. Toute étape de capture après un `await` compare son jeton
    /// local à celui-ci — et vérifie l'état, cf. `sessionIsLive(_:)`. La tâche OCR, elle,
    /// ne le consulte pas : elle doit pouvoir écrire son texte pendant la clôture.
    private var sessionToken: UUID?
    private var source: (any FrameSource)?
    private var detector = SlideDetector(settings: SlideCaptureSettings())
    private var settings = SlideCaptureSettings()
    private var slidesDirectory: URL?
    private var modelContext: ModelContext?
    /// Prochain index de slide, réservé **avant** tout `await` d'écriture : deux écritures
    /// en vol (tick + snapshot) ne peuvent pas se partager un numéro.
    private var nextIndex = 1
    private var loop: Task<Void, Never>?
    /// L'OCR d'un slide est détaché de `tick()` (ne doit pas le bloquer) mais reste
    /// associé à son slide : `deleteSlide` peut ainsi annuler la tâche encore en vol
    /// avant de supprimer le modèle qu'elle vise, plutôt que de la laisser écrire dans
    /// le vide.
    private var ocrTasks: [(slideID: PersistentIdentifier, task: Task<Void, Never>)] = []

    init(
        recordingsRoot: URL? = nil,
        frameSourceFactory: @escaping FrameSourceFactory = { WindowFrameSource(windowID: $0) },
        ocr: @escaping OCRFunction = { try await OCRService.recognize(cgImage: $0) },
        reindex: @escaping ReindexFunction = { attachment, context in
            try? await MeetingAttachmentService.reindexAttachment(attachment, context: context)
        }
    ) {
        self.recordingsRoot = recordingsRoot ?? ScreenCaptureService.defaultRecordingsRoot()
        self.frameSourceFactory = frameSourceFactory
        self.ocr = ocr
        self.reindex = reindex
    }

    // MARK: - Cycle de vie de la session

    /// Ouvre la session : attachment (nouveau ou `appendTo`), dossier créé **tout de
    /// suite** (une racine non inscriptible échoue avant toute capture), détecteur neuf
    /// (réamorcé depuis les PNG du lot repris), état `running`. Ne lance pas la boucle.
    func beginSession(
        configuration: SessionConfiguration,
        meeting: Meeting,
        context: ModelContext,
        appendTo existing: MeetingAttachment? = nil
    ) throws {
        guard state == .idle, currentAttachment == nil else { throw SessionError.sessionAlreadyOpen }
        if let existing, existing.meeting !== meeting {
            throw SessionError.attachmentBelongsToAnotherMeeting
        }

        let directory = recordingsRoot
            .appendingPathComponent(meeting.ensuredStableID.uuidString, isDirectory: true)
            .appendingPathComponent("slides", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let attachment: MeetingAttachment
        if let existing {
            attachment = existing
        } else {
            attachment = MeetingAttachment(
                url: URL(fileURLWithPath: "slides-\(Date().timeIntervalSince1970).slides"),
                kind: "slides"
            )
            attachment.fileName = "Slides capture - \(Date().formatted(date: .abbreviated, time: .shortened))"
            attachment.meeting = meeting
            context.insert(attachment)
        }

        let settings = SlideCaptureSettings(sensitivity: configuration.sensitivity)
        self.settings = settings
        var detector = SlideDetector(settings: settings)
        if let existing {
            let known = existing.slides.compactMap { SlideFingerprint(contentsOf: URL(fileURLWithPath: $0.imagePath)) }
            detector.seed(known)
        }
        self.detector = detector

        self.configuration = configuration
        self.source = frameSourceFactory(configuration.windowID)
        self.slidesDirectory = directory
        self.modelContext = context
        // Maximum + 1, et non `count + 1` : une suppression laisse un trou et
        // `count + 1` redonnerait un index déjà pris.
        self.nextIndex = (attachment.slides.map(\.index).max() ?? 0) + 1
        self.currentAttachment = attachment
        self.sessionToken = UUID()
        clearError()
        self.state = .running
        captureLog.info("Session de capture ouverte (append=\(existing != nil)) fenêtre=\(configuration.windowID)")
    }

    /// Ouvre la session et lance la boucle périodique.
    func start(
        configuration: SessionConfiguration,
        meeting: Meeting,
        context: ModelContext,
        appendTo existing: MeetingAttachment? = nil
    ) throws {
        try beginSession(configuration: configuration, meeting: meeting, context: context, appendTo: existing)
        launchLoop()
    }

    /// Reprend une session arrêtée : même attachment, même détecteur, même numérotation.
    ///
    /// Le jeton est exigé en plus de l'état : `finish()` publie `stopped` puis **attend**
    /// les OCR, et pendant cette attente la session est déjà invalidée (jeton `nil`).
    /// Reprendre là relancerait une boucle que `finish()` ne connaît pas — boucle fantôme
    /// qui bloquerait ensuite `launchLoop()` de la session suivante.
    func resume() {
        guard state == .stopped, sessionToken != nil, currentAttachment != nil else { return }
        clearError()
        state = .running
        launchLoop()
        captureLog.info("Capture reprise")
    }

    /// Arrête la boucle. La session reste ouverte, les slides restent visibles.
    func stop() {
        loop?.cancel()
        loop = nil
        switch state {
        case .running, .paused:
            state = .stopped
            captureLog.info("Capture arrêtée (session conservée)")
        case .idle, .stopped:
            break
        }
    }

    /// Clôt la session : le jeton est invalidé **avant** la première attente, si bien
    /// qu'un tick en vol ne peut plus rien écrire ni publier. Attend les OCR, sauvegarde,
    /// réindexe, puis repasse `idle`.
    func finish() async {
        stop()
        guard let attachment = currentAttachment, let context = modelContext else { return }
        sessionToken = nil
        source = nil

        let tasks = ocrTasks
        ocrTasks = []
        if !tasks.isEmpty {
            ocrProgress = (0, tasks.count)
            for (index, entry) in tasks.enumerated() {
                await entry.task.value
                ocrProgress = (index + 1, tasks.count)
            }
        }
        ocrProgress = nil

        try? context.save()
        // Après les attentes seulement : une boucle a pu être relancée entre-temps
        // (bouton Reprendre, notification…). Aucune ne doit survivre à la clôture,
        // sinon `launchLoop()` refuserait celle de la session suivante.
        loop?.cancel()
        loop = nil
        currentAttachment = nil
        configuration = nil
        slidesDirectory = nil
        state = .idle
        clearError()
        captureLog.info("Session de capture terminée : \(attachment.slides.count) slides")
        await reindex(attachment, context)
    }

    /// Abandonne la session : boucle et OCR annulés, tout est relâché, **rien** n'est
    /// sauvegardé ni réindexé.
    ///
    /// C'est le chemin de la réunion supprimée : la cascade emporte l'attachment de
    /// capture, sauvegarder ou réindexer pendant sa suppression n'aurait pas de sens.
    func abandon() {
        loop?.cancel()
        loop = nil
        for entry in ocrTasks { entry.task.cancel() }
        ocrTasks = []
        sessionToken = nil
        source = nil
        currentAttachment = nil
        configuration = nil
        slidesDirectory = nil
        modelContext = nil
        ocrProgress = nil
        state = .idle
        clearError()
        captureLog.info("Session de capture abandonnée (rien sauvegardé, rien réindexé)")
    }

    /// Change de fenêtre source sans toucher à la zone. Autorisé en `stopped` seulement.
    func updateSource(windowID: CGWindowID, title: String) {
        guard state == .stopped, sessionToken != nil, var configuration else { return }
        configuration.windowID = windowID
        configuration.windowTitle = title
        self.configuration = configuration
        source = frameSourceFactory(windowID)
    }

    // MARK: - Capture

    /// Un cycle : capture, crop, empreinte, décision, écriture éventuelle.
    func tick() async {
        guard let token = sessionToken, let source, isCapturing else { return }

        let frame: CGImage?
        do {
            frame = try await source.captureFrame()
        } catch {
            guard sessionIsLive(token) else { return }
            lastError = error.localizedDescription
            state = .paused("Capture impossible : \(error.localizedDescription)")
            return
        }

        guard sessionIsLive(token) else { return }

        guard let frame else {
            state = .paused("Fenêtre source introuvable. La capture reprendra si elle réapparaît.")
            return
        }

        if state.isPaused {
            state = .running
            clearError()
        }

        guard let crop = configuration?.crop,
              let cropped = crop.apply(to: frame),
              let fingerprint = SlideFingerprint(image: cropped) else {
            lastError = "La zone de capture est vide ou invalide."
            return
        }

        guard detector.consume(fingerprint) == .newSlide else { return }
        await writeSlide(cropped, token: token)
    }

    /// Force l'écriture de l'image courante, sans attendre la stabilisation.
    func snapshot() {
        Task { await snapshotForTesting() }
    }

    /// Corps attendable de `snapshot()` (visible des tests).
    ///
    /// N'amorce le détecteur avec cette empreinte qu'**après** confirmation de
    /// l'écriture (`writeSlide` réussi) : si l'écriture échoue (jeton périmé, panne
    /// d'encodage…), le détecteur ne doit pas croire connaître un slide qui n'existe
    /// pas sur disque.
    func snapshotForTesting() async {
        guard state == .running, let token = sessionToken, let source, let crop = configuration?.crop else { return }
        guard let frame = try? await source.captureFrame(), sessionIsLive(token),
              let cropped = crop.apply(to: frame) else { return }
        let fingerprint = SlideFingerprint(image: cropped)
        let wrote = await writeSlide(cropped, token: token)
        if wrote, let fingerprint {
            detector.seed([fingerprint])
        }
    }

    /// Vrai si une boucle périodique est armée (tests : détecter une boucle fantôme).
    var hasLoopForTesting: Bool { loop != nil }

    /// Annule la boucle sans changer l'état (tests : piloter les ticks à la main).
    func cancelLoopForTesting() {
        loop?.cancel()
        loop = nil
    }

    /// Attend la fin de tous les OCR en vol, sans clore la session (tests uniquement).
    ///
    /// `writeSlide` détache l'OCR pour ne pas bloquer `tick()` ; seul `finish()` les
    /// attend en production. La tâche OCR revérifie elle-même la vivacité de ses modèles
    /// (`slide.modelContext != nil`, `attachment.modelContext != nil`) avant d'écrire
    /// quoi que ce soit, donc un test qui ne l'attend pas ne risque plus de crash — ce point
    /// d'entrée reste une simple commodité pour un test qui veut observer l'OCR terminé
    /// (texte reconnu, `ocrProgress`) sans passer par `finish()`.
    func drainOCRTasksForTesting() async {
        for entry in ocrTasks { await entry.task.value }
    }

    func deleteSlide(_ slide: SlideCapture) {
        guard let context = modelContext ?? slide.modelContext else { return }
        // L'OCR de ce slide peut encore être en vol : l'annuler et l'oublier avant de
        // supprimer le modèle qu'il vise, plutôt que de le laisser toucher un
        // `SlideCapture` supprimé (crash SwiftData).
        let slideID = slide.persistentModelID
        for entry in ocrTasks where entry.slideID == slideID {
            entry.task.cancel()
        }
        ocrTasks.removeAll { $0.slideID == slideID }
        let path = slide.imagePath
        // `slide.attachment` et non `currentAttachment` : la galerie permet de supprimer
        // un slide hors session, quand aucun attachment n'est courant. Lu **avant** la
        // suppression, qui casse la relation.
        let attachment = slide.attachment
        context.delete(slide)
        try? FileManager.default.removeItem(atPath: path)
        if let attachment { rebuildAttachmentText(for: attachment) }
        objectWillChange.send()
        try? context.save()
    }

    // MARK: - Boucle

    private func launchLoop() {
        guard loop == nil else { return }
        let interval = settings.tickInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // Le propriétaire a disparu : sortir, pas de tâche fantôme.
                guard let self else { break }
                await self.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: - Écriture

    /// Renvoie `true` si le `SlideCapture` a bien été inséré (utilisé par
    /// `snapshotForTesting` pour n'amorcer le détecteur qu'en cas de succès réel).
    @discardableResult
    private func writeSlide(_ image: CGImage, token: UUID) async -> Bool {
        guard sessionIsLive(token),
              let attachment = currentAttachment,
              let context = modelContext,
              let directory = slidesDirectory else { return false }

        let index = nextIndex
        nextIndex += 1
        let date = Date()
        let fileURL = directory.appendingPathComponent(ScreenCaptureService.fileName(index: index, date: date))

        do {
            try await ScreenCaptureService.encodePNG(image, to: fileURL)
        } catch {
            guard sessionIsLive(token) else { return false }
            lastError = "Écriture du slide \(index) impossible : \(error.localizedDescription)"
            return false
        }

        guard sessionIsLive(token) else {
            // La session a été close ou arrêtée pendant l'encodage : ce slide ne lui
            // appartient plus.
            try? FileManager.default.removeItem(at: fileURL)
            return false
        }

        let slide = SlideCapture(index: index, capturedAt: date, imagePath: fileURL.path)
        slide.attachment = attachment
        context.insert(slide)
        // La vue observe `capturedSlidesCount`, calculé depuis `attachment.slides`.
        objectWillChange.send()
        captureLog.info("Slide \(index) écrit")

        // OCR détaché de `tick()` (ne doit pas le bloquer). Il écrit dans **son** slide et
        // **son** attachment, capturés ici : surtout pas dans `currentAttachment`, qui peut
        // déjà être celui d'une autre session. Le jeton de session n'est délibérément
        // **pas** consulté : `finish()` l'invalide avant d'attendre les OCR, et un OCR
        // attendu par la clôture doit justement pouvoir écrire son texte. Seule la
        // vivacité est vérifiée : (1) `Task.isCancelled` — `deleteSlide` et `abandon()`
        // annulent les tâches en vol ; (2) `slide.modelContext != nil` et
        // (3) `attachment.modelContext != nil` — un modèle supprimé n'a plus de contexte
        // utilisable et toucher à ses propriétés planterait (« this model instance was
        // destroyed »).
        let ocr = self.ocr
        let task = Task { [weak self] in
            do {
                let text = try await ocr(image)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled,
                          slide.modelContext != nil,
                          attachment.modelContext != nil else { return }
                    slide.ocrText = text
                    self?.rebuildAttachmentText(for: attachment)
                }
            } catch {
                captureLog.error("OCR du slide \(index) échoué : \(error.localizedDescription)")
            }
        }
        ocrTasks.append((slideID: slide.persistentModelID, task: task))
        return true
    }

    /// Texte agrégé du lot **courant** (chemin du tick et de `deleteSlide`).
    private func rebuildAttachmentText() {
        guard let attachment = currentAttachment else { return }
        rebuildAttachmentText(for: attachment)
    }

    /// Texte agrégé d'un lot désigné : ne dépend pas de `currentAttachment`, donc reste
    /// valable pour un OCR qui se termine pendant ou après la clôture de la session.
    private func rebuildAttachmentText(for attachment: MeetingAttachment) {
        let slides = attachment.slides.sorted(by: { $0.index < $1.index })
        var fullText = ""
        for slide in slides {
            let timestamp = slide.capturedAt.formatted(date: .omitted, time: .standard)
            fullText += "--- Slide \(slide.index) [\(timestamp)] ---\n"
            fullText += slide.ocrText + "\n\n"
        }
        attachment.extractedText = fullText
    }

    /// Vrai si le tick appartient toujours à la session courante **et** que la capture
    /// est encore active. Les deux conditions comptent : le jeton écarte un tick d'une
    /// session close, l'état écarte un tick suspendu pendant `stop()` — qui publierait
    /// sinon `.paused` par-dessus `.stopped`, état dont `resume()` ne sait pas repartir.
    private func sessionIsLive(_ token: UUID) -> Bool {
        sessionToken == token && isCapturing
    }

    /// Seul endroit qui remet le message de panne à zéro : appelé sur **tous** les
    /// chemins de succès (ouverture, reprise, tick réussi après pause, clôture).
    private func clearError() {
        lastError = nil
    }

    // MARK: - Helpers statiques

    static func fileName(index: Int, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HHmmss"
        return "slide-\(String(format: "%04d", index))-\(formatter.string(from: date)).png"
    }

    /// Encodage PNG hors thread principal : quelques dizaines de millisecondes.
    nonisolated static func encodePNG(_ image: CGImage, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            ) else { throw SlideCaptureError.captureFailed("destination PNG non créable") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw SlideCaptureError.captureFailed("encodage PNG échoué")
            }
        }.value
    }

    private static func defaultRecordingsRoot() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0]
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
    }
}
