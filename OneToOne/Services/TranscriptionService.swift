import Foundation
@preconcurrency import AVFoundation
import Combine
import AppKit
import os

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

private let sttLog = Logger(subsystem: "com.onetoone.app", category: "stt")

// MARK: - STT result

struct STTResult {
    let text: String
    let language: String
    let durationSeconds: TimeInterval
}

// MARK: - Errors

enum STTError: LocalizedError {
    case modelMissing(searched: [URL])
    case mlxNotLinked
    case loadFailed(String)
    case transcribeFailed(String)
    case audioReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let searched):
            let paths = searched.map { $0.path }.joined(separator: "\n• ")
            return "Modèle Cohere introuvable. Chemins testés :\n• \(paths)"
        case .mlxNotLinked:
            return "MLX non linké : la dépendance mlx-audio-swift n'est pas disponible dans ce build."
        case .loadFailed(let detail):
            return "Échec chargement modèle Cohere : \(detail)"
        case .transcribeFailed(let detail):
            return "Échec transcription : \(detail)"
        case .audioReadFailed(let detail):
            return "Lecture audio impossible : \(detail)"
        }
    }
}

// MARK: - TranscriptionService (Cohere MLX local)

/// Transcription locale via modèle Cohere MLX 8-bit (même moteur que Mickey).
///
/// Résolution du modèle — ordre de priorité :
///   1. HuggingFace cache partagé : `~/.cache/huggingface/hub/models--beshkenadze--cohere-transcribe-03-2026-mlx-8bit/snapshots/<commit>/`
///   2. Dossier géré par OneToOne : `~/Library/Application Support/OneToOne/models/…/`
///   3. Chemin manuel (UserDefaults, NSOpenPanel)
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    static let defaultRepoId = "beshkenadze/cohere-transcribe-03-2026-mlx-8bit"

    // MARK: - Published state

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadingProgress: String = ""
    @Published private(set) var isTranscribing: Bool = false
    /// Progression de la transcription (0.0…1.0). Mis à jour en cours
    /// d'exécution segment par segment.
    @Published private(set) var progressFraction: Double = 0
    /// Libellé court à afficher à côté de la barre (ex. "3 / 45 chunks").
    @Published private(set) var progressLabel: String = ""
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Self.languageKey) }
    }
    @Published var lastError: String?

    // MARK: - UserDefaults keys

    private static let manualPathKey = "onetoone_cohere_manual_model_path"
    private static let languageKey = "onetoone_cohere_language"

    #if canImport(MLXAudioSTT)
    private var asr: CohereTranscribeModel?
    #endif

    private init() {
        self.language = UserDefaults.standard.string(forKey: Self.languageKey) ?? "fr"
    }

    // MARK: - Paths

    static var managedModelDirectory: URL {
        let fm = FileManager.default
        let base = URL.applicationSupportDirectory
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(defaultRepoId.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// Cache HuggingFace partagé avec Mickey et la CLI `huggingface-cli`.
    static var huggingFaceSnapshotsDir: URL {
        let safeRepo = "models--" + defaultRepoId.replacingOccurrences(of: "/", with: "--")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            .appendingPathComponent(safeRepo, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
    }

    func resolveExistingModelDirectory() -> URL? {
        let candidates: [URL?] = [
            firstSnapshotInside(Self.huggingFaceSnapshotsDir),
            Self.managedModelDirectory,
            UserDefaults.standard.string(forKey: Self.manualPathKey).map { URL(fileURLWithPath: $0) }
        ]
        for case let url? in candidates where containsModel(url) {
            return url
        }
        return nil
    }

    func candidateDirectories() -> [URL] {
        var out: [URL] = []
        if let snap = firstSnapshotInside(Self.huggingFaceSnapshotsDir) { out.append(snap) }
        out.append(Self.managedModelDirectory)
        if let manual = UserDefaults.standard.string(forKey: Self.manualPathKey) {
            out.append(URL(fileURLWithPath: manual))
        }
        return out
    }

    func setManualModelDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.manualPathKey)
    }

    private func firstSnapshotInside(_ snapshotsRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: snapshotsRoot, includingPropertiesForKeys: nil) else {
            return nil
        }
        return entries.first(where: { containsModel($0) })
    }

    private func containsModel(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("config.json").path)
            && fm.fileExists(atPath: url.appendingPathComponent("model.safetensors").path)
    }

    // MARK: - Load model

    func loadModel() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        loadingProgress = "Recherche du modèle Cohere…"
        guard let dir = resolveExistingModelDirectory() else {
            sttLog.error("loadModel: model not found")
            throw STTError.modelMissing(searched: candidateDirectories())
        }

        loadingProgress = "Chargement du modèle (\(dir.lastPathComponent))…"
        sttLog.info("loadModel: dir=\(dir.path, privacy: .public)")

        #if canImport(MLXAudioSTT)
        do {
            let model = try CohereTranscribeModel.fromDirectory(dir)
            self.asr = model
            self.isModelLoaded = true
            self.loadingProgress = "Modèle chargé"
            self.lastError = nil
            sttLog.info("loadModel: OK")
        } catch {
            sttLog.error("loadModel: failed \(error.localizedDescription, privacy: .public)")
            self.lastError = error.localizedDescription
            throw STTError.loadFailed(error.localizedDescription)
        }
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    // MARK: - Transcribe

    /// Transcrit un WAV 16 kHz mono. Charge le modèle si nécessaire.
    ///
    /// Le travail MLX (lourd) est effectué sur un thread d'arrière-plan dédié,
    /// segment par segment (60 s). Entre chaque segment, `progressFraction`
    /// et `progressLabel` sont publiés sur le main actor — l'UI reste fluide
    /// et peut afficher une barre de progression en temps réel.
    func transcribe(audioURL: URL) async throws -> STTResult {
        #if canImport(MLXAudioSTT)
        if asr == nil {
            try await loadModel()
        }
        guard let asr else { throw STTError.loadFailed("model non disponible après loadModel()") }

        isTranscribing = true
        progressFraction = 0
        progressLabel = "Préparation…"
        defer {
            isTranscribing = false
            progressFraction = 0
            progressLabel = ""
        }

        let t0 = Date()
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
        let sampleCount = audio.shape.last ?? 0
        let durationSec = Double(sampleCount) / 16_000.0
        sttLog.info("transcribe: samples=\(sampleCount) (=\(durationSec, format: .fixed(precision: 1))s)")

        let segmentDurationSec = 60
        let segmentSamples = segmentDurationSec * 16_000
        let segmentCount = max(1, Int(ceil(Double(sampleCount) / Double(segmentSamples))))
        // Budget tokens par segment : 60s × ~30 tok/s + marge → 2400, plancher 1024.
        let perSegmentMaxTokens = max(1024, Int(Double(segmentDurationSec) * 30.0 * 1.5))
        let lang = self.language

        progressLabel = "0 / \(segmentCount) segments"

        let params = STTGenerateParameters(
            maxTokens: perSegmentMaxTokens,
            temperature: 0.0,
            topP: 1.0,
            topK: 0,
            verbose: false,
            language: lang,
            chunkDuration: Float(segmentDurationSec),
            minChunkDuration: 1.0
        )

        // Boucle off-main : chaque segment est traité dans une `Task.detached`,
        // ce qui libère le main actor et permet au thread UI de re-rendre
        // entre deux segments. La progression est publiée via `MainActor.run`
        // après chaque segment.
        var pieces: [String] = []
        pieces.reserveCapacity(segmentCount)
        for i in 0..<segmentCount {
            let start = i * segmentSamples
            let end = min(start + segmentSamples, sampleCount)
            let segment = audio[start..<end]
            let progressBefore = Double(i) / Double(segmentCount)
            self.progressFraction = progressBefore
            self.progressLabel = "Segment \(i + 1) / \(segmentCount)"

            let segText: String = await Task.detached(priority: .userInitiated) { [params] in
                let out = asr.generate(audio: segment, generationParameters: params)
                return String(out.text).trimmingCharacters(in: .whitespacesAndNewlines)
            }.value

            pieces.append(segText)
            self.progressFraction = Double(i + 1) / Double(segmentCount)
        }

        let combined = pieces.filter { !$0.isEmpty }.joined(separator: "\n")
        let deduped = Self.collapseRepetitions(combined)
        let cleaned = Self.stripWrappingQuotes(deduped)
        let elapsed = Date().timeIntervalSince(t0)
        sttLog.info("transcribe: done in \(elapsed, format: .fixed(precision: 1))s, \(cleaned.count) chars over \(segmentCount) segments")
        return STTResult(
            text: cleaned,
            language: lang,
            durationSeconds: durationSec
        )
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    // MARK: - Audio loader

    /// Lit un WAV quelconque et produit un `[Float]` mono 16 kHz normalisé -1…1.
    /// Utilise AVAudioConverter pour resample + downmix si nécessaire.
    static func loadMonoFloat32(from url: URL, targetSampleRate: Double = 16_000) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw STTError.audioReadFailed(error.localizedDescription)
        }

        let srcFormat = file.processingFormat
        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw STTError.audioReadFailed("format cible invalide")
        }

        guard let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw STTError.audioReadFailed("AVAudioConverter indisponible")
        }

        let frameCapacity = AVAudioFrameCount(file.length)
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCapacity) else {
            throw STTError.audioReadFailed("buffer source alloc échoué")
        }
        do {
            try file.read(into: srcBuffer)
        } catch {
            throw STTError.audioReadFailed(error.localizedDescription)
        }

        // Ratio sample-rate → taille cible
        let ratio = targetSampleRate / srcFormat.sampleRate
        let dstFrameCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio + 1024)
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstFrameCapacity) else {
            throw STTError.audioReadFailed("buffer dst alloc échoué")
        }

        var error: NSError?
        var pushed = false
        let status = converter.convert(to: dstBuffer, error: &error) { _, inputStatus in
            if pushed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            pushed = true
            inputStatus.pointee = .haveData
            return srcBuffer
        }

        if status == .error {
            throw STTError.audioReadFailed(error?.localizedDescription ?? "convert error")
        }

        guard let ptr = dstBuffer.floatChannelData?[0] else {
            throw STTError.audioReadFailed("floatChannelData nil")
        }
        let count = Int(dstBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    /// Détecte et collapse les répétitions pathologiques (boucle ASR) :
    /// - Phrases identiques qui se répètent ≥ 3 fois d'affilée → 1 occurrence + suffixe
    ///   "(×N)" pour rendre la boucle explicite.
    /// - Même logique sur les groupes de 2-5 mots consécutifs.
    static func collapseRepetitions(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // 1. Collapse de phrases entières séparées par `. `, `! `, `? ` ou newline.
        let sentenceRegex = try? NSRegularExpression(
            pattern: "([^.!?\\n]+[.!?])(?:\\s+\\1)+",
            options: [.caseInsensitive]
        )
        var out = text
        if let rx = sentenceRegex {
            let ns = out as NSString
            let range = NSRange(location: 0, length: ns.length)
            rx.enumerateMatches(in: out, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1 else { return }
                let fullRange = match.range
                let phraseRange = match.range(at: 1)
                let phrase = ns.substring(with: phraseRange)
                let full = ns.substring(with: fullRange)
                let count = full.components(separatedBy: phrase).count - 1
                if count >= 3 {
                    out = out.replacingOccurrences(of: full, with: "\(phrase) (×\(count) — boucle détectée)")
                }
            }
        }

        // 2. Collapse de groupes de mots (2-5 tokens) répétés immédiatement.
        let words = out.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 10 {
            var cleaned: [String] = []
            var i = 0
            while i < words.count {
                var replaced = false
                for n in stride(from: 5, through: 2, by: -1) where i + n * 3 <= words.count {
                    let pattern = Array(words[i..<i + n])
                    var repeats = 1
                    var j = i + n
                    while j + n <= words.count && Array(words[j..<j + n]) == pattern {
                        repeats += 1
                        j += n
                    }
                    if repeats >= 3 {
                        cleaned.append(contentsOf: pattern)
                        cleaned.append("(×\(repeats) — boucle)")
                        i = j
                        replaced = true
                        break
                    }
                }
                if !replaced {
                    cleaned.append(words[i])
                    i += 1
                }
            }
            out = cleaned.joined(separator: " ")
        }

        return out
    }

    /// Retire les guillemets parasites qui entourent parfois la sortie du STT.
    static func stripWrappingQuotes(_ s: String) -> String {
        var t = s
        while t.count >= 2,
              let first = t.first,
              let last = t.last,
              ["\"", "'", "“", "”", "«", "»"].contains(String(first)),
              ["\"", "'", "“", "”", "«", "»"].contains(String(last)) {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return t
    }
}
