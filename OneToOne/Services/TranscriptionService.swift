import Foundation
@preconcurrency import AVFoundation
import Combine
import AppKit
import os
import SwiftData

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

private let sttLog = Logger(subsystem: "com.onetoone.app", category: "stt")

// MARK: - STT result

struct STTSegment {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}

struct STTResult {
    let text: String
    let language: String
    let durationSeconds: TimeInterval
    /// Segments timestampés (1 par chunk de 60s par défaut). Vide pour
    /// les chemins legacy qui n'auraient pas conservé les segments.
    let segments: [STTSegment]
    /// Embeddings 256-dim par cluster issus de la diarisation (vide si pas
    /// de diarisation ou si SpeechVAD indisponible). Indexé par identifiant de
    /// cluster. Utilisé par MeetingView pour déclencher l'EMA voiceprint update
    /// lors d'un labeling manuel.
    var clusterEmbeddings: [Int: [Float]] = [:]
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
            return "Modèle STT introuvable. Chemins testés :\n• \(paths)"
        case .mlxNotLinked:
            return "MLX non linké : la dépendance mlx-audio-swift n'est pas disponible dans ce build."
        case .loadFailed(let detail):
            return "Échec chargement modèle STT : \(detail)"
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

    // MARK: - Published state

    @Published private(set) var isTranscribing: Bool = false
    /// Progression de la transcription (0.0…1.0). Mis à jour en cours
    /// d'exécution segment par segment.
    @Published private(set) var progressFraction: Double = 0
    /// Libellé court à afficher à côté de la barre (ex. "3 / 45 chunks").
    @Published private(set) var progressLabel: String = ""
    /// Langue cible de la transcription (code ISO, ex. "fr"). Persistée dans
    /// UserDefaults à chaque modification.
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Self.languageKey) }
    }
    @Published var lastError: String?

    // MARK: - UserDefaults keys

    private static let languageKey = "onetoone_cohere_language"

    private init() {
        self.language = UserDefaults.standard.string(forKey: Self.languageKey) ?? "fr"
    }

    // MARK: - Transcribe

    /// Point d'entrée unique. Branche sur `settings.transcriptionMode`. Appelé
    /// par les call sites DANS un `JobQueue.start(kind: .transcription)`.
    /// `@MainActor` (classe entière) : mute l'état publié et le `ModelContext`
    /// sur le main thread ; le travail lourd est délégué aux moteurs/transcribers.
    func runTranscription(audioURL: URL,
                          meeting: Meeting,
                          settings: AppSettings,
                          in context: ModelContext,
                          onPhase: ((TranscriptionPhase) -> Void)? = nil,
                          onProgress: ((Double, String) -> Void)? = nil) async throws -> STTResult {
        isTranscribing = true
        progressFraction = 0
        progressLabel = ""
        defer {
            isTranscribing = false
            progressFraction = 0
            progressLabel = ""
        }
        let progress: (Double, String) -> Void = { [weak self] fraction, status in
            self?.progressFraction = fraction
            self?.progressLabel = status
            onProgress?(fraction, status)
        }
        switch settings.transcriptionMode {
        case .transcriptionOnly:
            let engine = makeEngine(kind: settings.transcriptionEngine, settings: settings)
            let result = try await transcribeChunks(
                audioURL: audioURL, engine: engine, settings: settings,
                onPhase: onPhase, onProgress: progress)
            persistAnonymousSegments(sttResult: result, meeting: meeting, in: context)
            return result

        case .diarizeFirst:
            let engine: STTEngine = VoxtralEngine(variant: settings.voxtralVariant)
            onPhase?(.loadingModel)
            try await engine.load()
            let diar: (blocks: [TurnMerger.Block], embeddings: [Int: [Float]], duration: Double)
            do {
                diar = try await DiarizeFirstTranscriber.run(
                    audioURL: audioURL, engine: engine, language: self.language,
                    clusterThreshold: Float(settings.diarizationClusterThreshold),
                    onPhase: onPhase, onProgress: progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                print("[TranscriptionService] diarize-first failed: \(error). Fallback anonymous.")
                let result = try await transcribeChunks(
                    audioURL: audioURL, engine: engine, settings: settings,
                    onPhase: onPhase, onProgress: progress)
                persistAnonymousSegments(sttResult: result, meeting: meeting, in: context)
                return result
            }

            if diar.blocks.isEmpty {
                print("[TranscriptionService] diarize-first produced no blocks. Fallback anonymous.")
                let result = try await transcribeChunks(
                    audioURL: audioURL, engine: engine, settings: settings,
                    onPhase: onPhase, onProgress: progress)
                persistAnonymousSegments(sttResult: result, meeting: meeting, in: context)
                return result
            }

            onPhase?(.matching)
            let assignments = SpeakerMatcher.match(
                clusterEmbeddings: diar.embeddings, meeting: meeting,
                in: context, settings: settings)
            let canonical = canonicalizeBlocks(diar.blocks, assignments: assignments)
            persistBlocks(canonical, assignments: assignments, meeting: meeting, in: context)

            let text = canonical.map { $0.text }.joined(separator: "\n")
            var result = STTResult(text: text, language: self.language,
                                   durationSeconds: diar.duration, segments: [])
            result.clusterEmbeddings = diar.embeddings
            return result
        }
    }

    private func makeEngine(kind: STTEngineKind, settings: AppSettings) -> STTEngine {
        switch kind {
        case .cohere:  return CohereEngine()
        case .voxtral: return VoxtralEngine(variant: settings.voxtralVariant)
        }
    }

    /// Transcription seule par chunks 60s, moteur pluggable.
    private func transcribeChunks(audioURL: URL,
                                  engine: STTEngine,
                                  settings: AppSettings,
                                  onPhase: ((TranscriptionPhase) -> Void)?,
                                  onProgress: ((Double, String) -> Void)?) async throws -> STTResult {
        #if canImport(MLXAudioSTT)
        if !engine.isLoaded {
            onPhase?(.loadingModel)
            try await engine.load()
        }
        onPhase?(.transcribing)
        let t0 = Date()
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)
        let sampleCount = audio.shape.last ?? 0
        let durationSec = Double(sampleCount) / 16_000.0
        let segmentSamples = 60 * 16_000
        let segmentCount = max(1, Int(ceil(Double(sampleCount) / Double(segmentSamples))))
        let perSegmentMaxTokens = max(1024, Int(60.0 * 30.0 * 1.5))
        var pieces: [String] = []
        var sttSegments: [STTSegment] = []
        for i in 0..<segmentCount {
            try Task.checkCancellation()
            let start = i * segmentSamples
            let end = min(start + segmentSamples, sampleCount)
            onProgress?(Double(i) / Double(segmentCount), "Segment \(i + 1) / \(segmentCount)")
            let clip = audio[start..<end]
            let segText = await engine.transcribe(clip: clip, language: self.language, maxTokens: perSegmentMaxTokens)
            let segClean = Self.collapseRepetitions(segText)
            pieces.append(segClean)
            if !segClean.isEmpty {
                sttSegments.append(STTSegment(
                    startSeconds: Double(start) / 16_000.0,
                    endSeconds: Double(end) / 16_000.0,
                    text: segClean))
            }
        }
        onProgress?(1.0, "Terminé")
        let combined = pieces.filter { !$0.isEmpty }.joined(separator: "\n")
        let cleaned = Self.stripWrappingQuotes(Self.collapseRepetitions(combined))
        sttLog.info("transcribeChunks done in \(Date().timeIntervalSince(t0), format: .fixed(precision: 1))s")
        return STTResult(text: cleaned, language: self.language,
                         durationSeconds: durationSec, segments: sttSegments)
        #else
        throw STTError.mlxNotLinked
        #endif
    }

    /// Purge atomique des segments existants juste avant insertion des
    /// nouveaux. Si on arrive ici, c'est que STT + diarisation ont réussi
    /// — sûr d'écraser. Annulation antérieure préserve les anciens.
    private func deleteExistingSegments(from meeting: Meeting, in context: ModelContext) {
        for old in meeting.transcriptSegments { context.delete(old) }
    }

    private func persistAnonymousSegments(sttResult: STTResult,
                                           meeting: Meeting,
                                           in context: ModelContext) {
        deleteExistingSegments(from: meeting, in: context)
        var idx = 0
        for chunk in sttResult.segments {
            let s = TranscriptSegment(
                orderIndex: idx,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                text: chunk.text,
                speakerID: 1
            )
            s.meeting = meeting
            context.insert(s)
            idx += 1
        }
    }

    // MARK: - Canonicalisation des clusters

    /// Unifie les clusters mappés au même collaborateur vers un cluster canonique,
    /// puis re-merge les blocs adjacents. Réduit la sur-segmentation Pyannote.
    func canonicalizeBlocks(_ blocks: [TurnMerger.Block],
                            assignments: [Int: SpeakerMatcher.Assignment]) -> [TurnMerger.Block] {
        var canonicalByCollab: [PersistentIdentifier: Int] = [:]
        for cid in assignments.keys.sorted() {
            guard let collab = assignments[cid]?.collaborator else { continue }
            let pid = collab.persistentModelID
            if canonicalByCollab[pid] == nil { canonicalByCollab[pid] = cid }
        }
        guard !canonicalByCollab.isEmpty else { return blocks }
        let rewritten: [TurnMerger.Block] = blocks.map { b in
            guard let collab = assignments[b.speaker]?.collaborator,
                  let canonical = canonicalByCollab[collab.persistentModelID],
                  canonical != b.speaker else { return b }
            var nb = b; nb.speaker = canonical; return nb
        }
        return TurnMerger.mergeConsecutiveBlocks(rewritten)
    }

    #if DEBUG
    func canonicalizeBlocksForTest(_ blocks: [TurnMerger.Block],
                                   assignments: [Int: SpeakerMatcher.Assignment]) -> [TurnMerger.Block] {
        canonicalizeBlocks(blocks, assignments: assignments)
    }
    #endif

    private func persistBlocks(_ blocks: [TurnMerger.Block],
                               assignments: [Int: SpeakerMatcher.Assignment],
                               meeting: Meeting,
                               in context: ModelContext) {
        deleteExistingSegments(from: meeting, in: context)
        var idx = 0
        var assignmentsDict: [String: Any] = [:]
        var metaDict: [String: [String: Any]] = [:]
        for b in blocks {
            let s = TranscriptSegment(
                orderIndex: idx, startSeconds: b.start, endSeconds: b.end,
                text: b.text, speakerID: b.speaker + 1)
            s.meeting = meeting
            if let a = assignments[b.speaker], let collab = a.collaborator, a.auto {
                s.speaker = collab
            }
            context.insert(s)
            idx += 1
        }
        for (cid, a) in assignments {
            assignmentsDict[String(cid)] = a.collaborator?.ensuredStableID.uuidString ?? NSNull()
            metaDict[String(cid)] = [
                "confidence": a.confidence, "auto": a.auto, "ambiguous": a.ambiguous,
                "candidates": a.candidates.map { $0.0.ensuredStableID.uuidString }
            ]
        }
        if let d = try? JSONSerialization.data(withJSONObject: assignmentsDict),
           let s = String(data: d, encoding: .utf8) { meeting.speakerAssignmentsJSON = s }
        if let d = try? JSONSerialization.data(withJSONObject: metaDict),
           let s = String(data: d, encoding: .utf8) { meeting.speakerMatchMetaJSON = s }
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

        // 2. Collapse de groupes de mots (1-5 tokens) répétés immédiatement.
        // n=1 attrape les boucles mono-token type "Je. Je. Je. …" qu'on voit
        // sur des fins de chunk silencieuses.
        let words = out.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if words.count > 4 {
            var cleaned: [String] = []
            var i = 0
            while i < words.count {
                var replaced = false
                for n in stride(from: 5, through: 1, by: -1) where i + n * 3 <= words.count {
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
