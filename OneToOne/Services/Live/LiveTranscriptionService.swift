import Foundation
import Combine
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXAudioCore)
import MLXAudioCore
#endif

/// Un segment de transcription live horodaté (secondes depuis le début).
struct LiveSegment: Sendable {
    let start: Double
    let end: Double
    let text: String
}

/// Orchestre la transcription en direct : flux audio → VAD → fenêtres → Voxtral
/// (séquentiel) → fusion. Éphémère en mémoire ; le texte final est produit à la
/// fin via `end()` puis nettoyé/diarisé par le pipeline batch.
@MainActor
final class LiveTranscriptionService: ObservableObject {

    static let shared = LiveTranscriptionService()

    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var isLive: Bool = false
    @Published private(set) var statusMessage: String?

    private let sampleRate: Double = 16_000
    private let overlapSeconds: Double = 1.5
    private var engine: STTEngine?
    private var segmenter: LiveVADSegmenter?
    private var merger = LiveTranscriptMerger()
    private var ring: [Float] = []
    private var segments: [LiveSegment] = []
    private var consumeTask: Task<Void, Never>?
    private var generation = 0

    private init() {}

    func begin(audioStream: AsyncStream<[Float]>, language: String,
               engineKind: STTEngineKind, variant: VoxtralVariant) async {
        guard !isLive else { return }
        generation += 1
        let gen = generation
        isLive = true
        liveTranscript = ""
        statusMessage = "Chargement du modèle…"
        merger = LiveTranscriptMerger()
        ring = []
        segments = []

        // Même moteur que le batch (Réglages) : Qwen3-ASR force la langue en live
        // aussi ; Voxtral/Cohere auto-détectent. `variant` ne sert qu'à Voxtral.
        let eng: STTEngine
        switch engineKind {
        case .cohere:  eng = CohereEngine()
        case .voxtral: eng = VoxtralEngine(variant: variant)
        case .qwen3:   eng = Qwen3ASREngine()
        }
        do {
            try await eng.load()
        } catch {
            // N'écrase l'état que si la session n'a pas été arrêtée entre-temps.
            if gen == generation {
                statusMessage = "Transcription en direct indisponible (modèle STT manquant)."
                isLive = false
            }
            return
        }
        // Session arrêtée pendant le chargement du modèle ?
        guard gen == generation else { return }
        engine = eng

        let seg = LiveVADSegmenter()
        let sileroOK = await seg.loadSilero()
        // Session arrêtée pendant le chargement du VAD ?
        guard gen == generation else { return }
        segmenter = seg
        statusMessage = sileroOK ? nil : "Découpe par énergie (VAD indisponible)."

        consumeTask = Task { [weak self] in
            await self?.consume(audioStream, language: language)
        }
    }

    private func consume(_ stream: AsyncStream<[Float]>, language: String) async {
        guard let segmenter else { return }
        for await samples in stream {
            ring.append(contentsOf: samples)
            let closed = await segmenter.feed(samples, sampleRate: sampleRate)
            for range in closed {
                await transcribeWindow(range, language: language)
            }
        }
        // Fin de flux : clore le dernier segment.
        let tail = await segmenter.flush()
        for range in tail { await transcribeWindow(range, language: language) }
    }

    private func transcribeWindow(_ range: ClosedRange<Double>, language: String) async {
        guard let engine else { return }
        let from = max(0, range.lowerBound - overlapSeconds)
        let startIdx = Int(from * sampleRate)
        let endIdx = min(ring.count, Int(range.upperBound * sampleRate))
        guard endIdx > startIdx else { return }
        let clipSamples = Array(ring[startIdx..<endIdx])
        #if canImport(MLX) && canImport(MLXAudioCore)
        let clip = MLXArray(clipSamples)
        let durationSec = Double(clipSamples.count) / sampleRate
        let maxTokens = max(64, Int(durationSec * 13) + 64)
        let text = await engine.transcribe(clip: clip, language: language, maxTokens: maxTokens)
        guard !text.isEmpty else { return }
        let merged = merger.append(text)
        liveTranscript = merged
        segments.append(LiveSegment(start: range.lowerBound, end: range.upperBound, text: text))
        #endif
    }

    /// Arrête le live et renvoie les segments horodatés accumulés.
    /// PRÉCONDITION : l'enregistreur doit déjà avoir été arrêté/annulé
    /// (le flux audio est terminé) avant d'appeler `end()`, afin que le drainage
    /// de la tâche de consommation soit borné.
    @discardableResult
    func end() async -> [LiveSegment] {
        generation += 1                 // invalide toute begin() en cours de chargement
        // Draine le travail en vol : le flux étant terminé par AudioRecorderService
        // (stop/cancel → continuation.finish()), la boucle se vide (VAD + flush +
        // dernière fenêtre transcrite) puis se termine.
        await consumeTask?.value
        consumeTask = nil
        isLive = false
        statusMessage = nil
        engine = nil
        segmenter = nil
        let result = segments
        ring = []
        return result
    }

    /// Arrête immédiatement le live SANS drainer (flux éventuellement non
    /// terminé). À utiliser quand la transcription n'est pas récupérée : échec
    /// de démarrage de l'enregistrement, annulation. Annule la tâche de
    /// consommation (ce qui termine sa boucle `for await` même si le flux n'est
    /// pas fini) et remet l'état à zéro.
    func abort() {
        generation += 1
        consumeTask?.cancel()
        consumeTask = nil
        isLive = false
        statusMessage = nil
        engine = nil
        segmenter = nil
        segments = []
        ring = []
    }
}
