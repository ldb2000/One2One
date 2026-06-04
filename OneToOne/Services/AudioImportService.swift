import Foundation
import AVFoundation
import os

private let importLog = Logger(subsystem: "com.onetoone.app", category: "audio-import")

/// Garantit qu'un fichier audio attaché à une réunion est lisible par tout le
/// pipeline aval (waveform, STT, diarisation, éditeur), qui passe par `AVAudioFile`.
///
/// Deux pièges constatés sur des fichiers réels :
/// 1. Certains conteneurs (Opus dans `.mp4` par ex.) s'OUVRENT via
///    `AVAudioFile(forReading:)` sans erreur mais avec `length == 0` → toute
///    lecture échoue ensuite en erreur CoreAudio -50.
/// 2. Des flux AAC annoncés sains (`length > 0`, métadonnées valides) peuvent
///    contenir des paquets corrompus en plein milieu : `ExtAudioFileRead`
///    échoue alors en -50 — y compris dans `afconvert` d'Apple — alors que
///    ffmpeg les décode en les ignorant.
///
/// La parade : tout fichier compressé est transcodé en **WAV PCM 16 kHz mono**
/// (le format natif du recorder) via une lecture *résiliente* qui saute les
/// zones illisibles en les remplaçant par du silence — la timeline est
/// préservée pour la diarisation. Un WAV PCM ne déclenche aucun de ces pièges.
enum AudioImportService {

    /// `true` si `AVAudioFile` sait ouvrir le fichier et y voit au moins une
    /// frame décodable. Nécessaire mais PAS suffisant : des paquets corrompus
    /// au milieu du flux ne sont détectés qu'à la lecture (cf. doc du type).
    static func isDirectlyReadable(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }

    /// Statistiques d'un transcodage résilient.
    struct TranscodeStats: Sendable {
        let decodedSeconds: Double
        let skippedSeconds: Double
        let corruptChunkCount: Int
    }

    /// Prépare un fichier pour le pipeline :
    /// - WAV lisible → renvoyé tel quel (`transcoded == false`) ;
    /// - tout le reste (m4a, mp3, mp4/mov vidéo…) → transcodage résilient en
    ///   WAV 16 kHz mono sous `outputDir` (nom `<UUID>.wav`). Si `AVAudioFile`
    ///   ne sait pas ouvrir le conteneur, la piste audio est d'abord extraite
    ///   en `.m4a` temporaire via `AVAssetExportSession` (qui accepte plus de
    ///   codecs), puis transcodée.
    /// Le fichier source n'est jamais supprimé — au choix de l'appelant.
    static func prepareForPipeline(_ url: URL, outputDir: URL) async throws -> (url: URL, transcoded: Bool) {
        if url.pathExtension.lowercased() == "wav", isDirectlyReadable(url) {
            return (url, false)
        }

        // Source décodable pour AVAudioFile : le fichier lui-même, ou la piste
        // audio extraite si le conteneur n'est pas ouvrable (Opus, etc.).
        var decodeSource = url
        var tempExtract: URL?
        if !isDirectlyReadable(url) {
            let tmp = outputDir.appending(path: "\(UUID().uuidString).extracting.m4a")
            do {
                try await extractAudioTrack(from: url, to: tmp)
            } catch {
                try? FileManager.default.removeItem(at: tmp)  // sortie partielle éventuelle
                throw error
            }
            guard isDirectlyReadable(tmp) else {
                try? FileManager.default.removeItem(at: tmp)
                importLog.error("prepareForPipeline: extraction unreadable src=\(url.lastPathComponent, privacy: .public)")
                throw NSError(domain: "AudioImportService", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Le fichier audio extrait est vide ou son codec n'est pas pris en charge."
                ])
            }
            tempExtract = tmp
            decodeSource = tmp
        }
        defer { if let tempExtract { try? FileManager.default.removeItem(at: tempExtract) } }

        let output = outputDir.appending(path: "\(UUID().uuidString).wav")
        let src = decodeSource
        do {
            // CPU-bound (décodage complet) → hors main actor.
            let stats = try await Task.detached(priority: .userInitiated) {
                try resilientTranscodeToWAV16kMono(from: src, to: output)
            }.value
            guard stats.decodedSeconds > 0.1 else {
                try? FileManager.default.removeItem(at: output)
                throw NSError(domain: "AudioImportService", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Aucun audio décodable dans le fichier."
                ])
            }
            if stats.skippedSeconds > 0 {
                importLog.warning("prepareForPipeline: \(url.lastPathComponent, privacy: .public) → \(stats.skippedSeconds, format: .fixed(precision: 1))s corrompues remplacées par du silence (\(stats.corruptChunkCount) zones)")
            }
            importLog.info("prepareForPipeline: \(url.lastPathComponent, privacy: .public) → \(output.lastPathComponent, privacy: .public) (\(stats.decodedSeconds, format: .fixed(precision: 1))s)")
            return (output, true)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// Extrait la piste audio d'un conteneur audiovisuel (.mp4, .mov…) vers un
    /// `.m4a` AAC via `AVAssetExportSession` (preset `AppleM4A`).
    static func extractAudioTrack(from source: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw NSError(domain: "AudioImportService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Aucune piste audio trouvée dans le fichier."
            ])
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioImportService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Impossible de préparer l'extraction de la piste audio."
            ])
        }
        try await export.export(to: output, as: .m4a)
    }

    /// Transcode `source` en WAV PCM Int16 16 kHz mono, par chunks, en survivant
    /// aux paquets corrompus : chaque zone illisible est sautée (~1 s) et
    /// remplacée par du silence de même durée afin de préserver la timeline
    /// (essentiel pour aligner diarisation et transcription sur l'original).
    nonisolated static func resilientTranscodeToWAV16kMono(from source: URL, to output: URL) throws -> TranscodeStats {
        let file = try AVAudioFile(forReading: source)
        let inFormat = file.processingFormat
        let srIn = inFormat.sampleRate
        let total = file.length
        guard total > 0, srIn > 0 else {
            throw NSError(domain: "AudioImportService", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Audio illisible (0 échantillon décodable) — codec non pris en charge."
            ])
        }

        let outSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "AudioImportService", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Conversion audio impossible depuis ce format."
            ])
        }
        let outFile = try AVAudioFile(forWriting: output, settings: outSettings)

        let chunkFrames: AVAudioFrameCount = 65_536
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: chunkFrames),
              let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: chunkFrames) else {
            throw NSError(domain: "AudioImportService", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Allocation du tampon audio impossible."
            ])
        }

        var decodedFrames: Int64 = 0
        var skippedFrames: Int64 = 0
        var corruptChunks = 0
        var endOfInput = false

        readLoop: while true {
            // 1. Chunk suivant : lecture réelle, ou silence en cas de zone corrompue.
            var pending: AVAudioPCMBuffer?
            if !endOfInput {
                let pos = file.framePosition
                if pos >= total {
                    endOfInput = true
                } else {
                    do {
                        try file.read(into: inBuf, frameCount: min(chunkFrames, AVAudioFrameCount(total - pos)))
                        if inBuf.frameLength == 0 {
                            endOfInput = true
                        } else {
                            decodedFrames += Int64(inBuf.frameLength)
                            pending = inBuf
                        }
                    } catch {
                        // Paquet corrompu : on saute ~1 s (bornée par la capacité du
                        // buffer) et on écrit un silence équivalent.
                        corruptChunks += 1
                        guard corruptChunks <= 2_000 else {
                            throw NSError(domain: "AudioImportService", code: 8, userInfo: [
                                NSLocalizedDescriptionKey: "Fichier audio trop corrompu pour être récupéré."
                            ])
                        }
                        let skip = min(Int64(srIn), Int64(chunkFrames), total - pos)
                        file.framePosition = pos + skip
                        inBuf.frameLength = AVAudioFrameCount(skip)
                        if let chans = inBuf.floatChannelData {
                            for c in 0..<Int(inFormat.channelCount) {
                                memset(chans[c], 0, Int(inBuf.frameLength) * MemoryLayout<Float>.size)
                            }
                        }
                        skippedFrames += skip
                        pending = inBuf
                    }
                }
            }

            // 2. Pousse le chunk dans le converter et draine sa sortie.
            // Box `@unchecked Sendable` : le block est typé @Sendable mais
            // appelé de façon synchrone dans convert(), sur ce thread.
            final class PendingBox: @unchecked Sendable {
                var buf: AVAudioPCMBuffer?
                init(_ buf: AVAudioPCMBuffer?) { self.buf = buf }
            }
            let box = PendingBox(pending)
            let isEnd = endOfInput
            let inputBlock: AVAudioConverterInputBlock = { _, status in
                if let buf = box.buf {
                    box.buf = nil
                    status.pointee = .haveData
                    return buf
                }
                status.pointee = isEnd ? .endOfStream : .noDataNow
                return nil
            }
            drainLoop: while true {
                outBuf.frameLength = 0
                var convError: NSError?
                let st = converter.convert(to: outBuf, error: &convError, withInputFrom: inputBlock)
                if let convError { throw convError }
                if outBuf.frameLength > 0 { try outFile.write(from: outBuf) }
                switch st {
                case .endOfStream: break readLoop
                case .inputRanDry: break drainLoop
                default: continue  // .haveData → continue à drainer
                }
            }
        }

        return TranscodeStats(decodedSeconds: Double(decodedFrames) / srIn,
                              skippedSeconds: Double(skippedFrames) / srIn,
                              corruptChunkCount: corruptChunks)
    }
}
