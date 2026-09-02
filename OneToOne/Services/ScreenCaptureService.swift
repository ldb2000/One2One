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
/// - `tick()` est la plus petite unité de travail et est appelable directement : les tests
///   pilotent la capture sans horloge. Après chaque `await`, il revérifie le **jeton de
///   session** : un tick suspendu pendant `finish()` ne doit ni écrire ni publier.
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
        case noOpenSession

        var errorDescription: String? {
            switch self {
            case .sessionAlreadyOpen: return "Une session de capture est déjà ouverte."
            case .noOpenSession: return "Aucune session de capture n'est ouverte."
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

    /// Régénéré à chaque `beginSession`, remis à `nil` par `finish()` **avant** la
    /// première attente. Toute étape après un `await` compare son jeton local à celui-ci.
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
    private var ocrTasks: [Task<Void, Never>] = []

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
        self.nextIndex = attachment.slides.count + 1
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
    func resume() {
        guard state == .stopped, currentAttachment != nil else { return }
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
            for (index, task) in tasks.enumerated() {
                await task.value
                ocrProgress = (index + 1, tasks.count)
            }
        }
        ocrProgress = nil

        try? context.save()
        currentAttachment = nil
        configuration = nil
        slidesDirectory = nil
        state = .idle
        clearError()
        captureLog.info("Session de capture terminée : \(attachment.slides.count) slides")
        await reindex(attachment, context)
    }

    /// Change de fenêtre source sans toucher à la zone. Autorisé en `stopped` seulement.
    func updateSource(windowID: CGWindowID, title: String) {
        guard state == .stopped, var configuration else { return }
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
            guard sessionToken == token else { return }
            lastError = error.localizedDescription
            state = .paused("Capture impossible : \(error.localizedDescription)")
            return
        }

        guard sessionToken == token else { return }

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
    func snapshotForTesting() async {
        guard state == .running, let token = sessionToken, let source, let crop = configuration?.crop else { return }
        guard let frame = try? await source.captureFrame(), sessionToken == token,
              let cropped = crop.apply(to: frame) else { return }
        if let fingerprint = SlideFingerprint(image: cropped) {
            detector.seed([fingerprint])
        }
        await writeSlide(cropped, token: token)
    }

    /// Annule la boucle sans changer l'état (tests : piloter les ticks à la main).
    func cancelLoopForTesting() {
        loop?.cancel()
        loop = nil
    }

    /// Attend la fin de tous les OCR en vol, sans clore la session (tests uniquement).
    ///
    /// `writeSlide` détache l'OCR pour ne pas bloquer `tick()` ; seul `finish()` les
    /// attend en production. Un test qui écrit un slide puis rend la main sans passer
    /// par `finish()` laisse cette tâche détachée continuer après son propre retour :
    /// dans le harnais de tests (`ModelContainer` en mémoire, un par test), le
    /// `ModelContainer` du test peut alors être libéré pendant que la tâche OCR est
    /// encore en train d'écrire sur le `SlideCapture` qu'il possédait, ce qui plante
    /// (« this model instance was destroyed by calling ModelContext.reset »). Ce point
    /// d'entrée donne aux tests un moyen d'attendre cette fin avant de rendre la main.
    func drainOCRTasksForTesting() async {
        for task in ocrTasks { await task.value }
    }

    func deleteSlide(_ slide: SlideCapture) {
        guard let context = modelContext ?? slide.modelContext else { return }
        let path = slide.imagePath
        context.delete(slide)
        try? FileManager.default.removeItem(atPath: path)
        rebuildAttachmentText()
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

    private func writeSlide(_ image: CGImage, token: UUID) async {
        guard sessionToken == token,
              let attachment = currentAttachment,
              let context = modelContext,
              let directory = slidesDirectory else { return }

        let index = nextIndex
        nextIndex += 1
        let date = Date()
        let fileURL = directory.appendingPathComponent(ScreenCaptureService.fileName(index: index, date: date))

        do {
            try await ScreenCaptureService.encodePNG(image, to: fileURL)
        } catch {
            guard sessionToken == token else { return }
            lastError = "Écriture du slide \(index) impossible : \(error.localizedDescription)"
            return
        }

        guard sessionToken == token else {
            // La session a été close pendant l'encodage : ce slide ne lui appartient plus.
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let slide = SlideCapture(index: index, capturedAt: date, imagePath: fileURL.path)
        slide.attachment = attachment
        context.insert(slide)
        // La vue observe `capturedSlidesCount`, calculé depuis `attachment.slides`.
        objectWillChange.send()
        captureLog.info("Slide \(index) écrit")

        let ocr = self.ocr
        let task = Task { [weak self] in
            do {
                let text = try await ocr(image)
                await MainActor.run {
                    slide.ocrText = text
                    self?.rebuildAttachmentText()
                }
            } catch {
                captureLog.error("OCR du slide \(index) échoué : \(error.localizedDescription)")
            }
        }
        ocrTasks.append(task)
    }

    private func rebuildAttachmentText() {
        guard let attachment = currentAttachment else { return }
        let slides = attachment.slides.sorted(by: { $0.index < $1.index })
        var fullText = ""
        for slide in slides {
            let timestamp = slide.capturedAt.formatted(date: .omitted, time: .standard)
            fullText += "--- Slide \(slide.index) [\(timestamp)] ---\n"
            fullText += slide.ocrText + "\n\n"
        }
        attachment.extractedText = fullText
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
