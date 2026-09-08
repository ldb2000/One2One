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
        if url.pathExtension.lowercased() == "wav" {
            if isDirectlyReadable(url) { return (url, false) }
            // En-tête jamais finalisé : les échantillons sont là, seules les
            // tailles de chunk mentent (cf. `repairedWavCopy`). Ce cas passait
            // par `AVAssetExportSession` ci-dessous, qui échoue en
            // `AVFoundationErrorDomain −11800` — l'alerte opaque du 2026-09-08.
            if let repaired = try repairedWavCopy(of: url, in: outputDir) {
                return (repaired, true)
            }
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
                throw undecodableError(error, source: url)
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

    // MARK: - Messages d'erreur

    /// Traduit en français une erreur de décodage venue d'AVFoundation.
    ///
    /// `AVAssetExportSession` échoue en `AVFoundationErrorDomain −11800`, dont
    /// la description localisée — « The operation could not be completed » —
    /// ne dit ni quel fichier ni ce qui a manqué. C'est ce message que
    /// l'alerte de « Transcrire + Rapport » a affiché le 2026-09-08 : le
    /// pipeline avait pris un WAV à en-tête non finalisé pour un conteneur
    /// exotique et l'avait envoyé à l'export. Nos propres erreurs, déjà
    /// rédigées, passent inchangées.
    static func undecodableError(_ underlying: Error, source: URL) -> NSError {
        let ns = underlying as NSError
        guard ns.domain != "AudioImportService" else { return ns }
        importLog.error("prepareForPipeline: décodage impossible src=\(source.lastPathComponent, privacy: .public) — \(ns.domain, privacy: .public) \(ns.code)")
        return NSError(domain: "AudioImportService", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Le fichier « \(source.lastPathComponent) » n'a pas pu être décodé : "
                + "son conteneur ou son codec n'est pas pris en charge.",
            NSLocalizedFailureReasonErrorKey: "\(ns.domain) \(ns.code)",
            NSUnderlyingErrorKey: underlying
        ])
    }

    // MARK: - Durée persistée

    /// La durée à inscrire dans `Meeting.durationSeconds`, en secondes entières.
    ///
    /// Lève plutôt que de rendre zéro : une réunion qui retient un chemin audio
    /// **et** une durée nulle est le couple exact qui a produit le défaut du
    /// 2026-09-08 (frise sans échelle, notes horodatées à zéro, et un
    /// `Transcrire + Rapport` qui repartait dans l'export AVFoundation). Un
    /// fichier audible mais plus court qu'une demi-seconde vaut 1 s, jamais 0.
    static func pipelineDurationSeconds(of url: URL) throws -> Int {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              file.processingFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioImportService", code: 9, userInfo: [
                NSLocalizedDescriptionKey: "Le fichier « \(url.lastPathComponent) » ne contient aucun audio "
                    + "lisible : sa durée est nulle."
            ])
        }
        let secondes = Double(file.length) / file.processingFormat.sampleRate
        return max(1, Int(secondes.rounded()))
    }

    // MARK: - En-tête RIFF/WAVE non finalisé

    /// La position du chunk `data` d'un fichier RIFF/WAVE et l'alignement d'une
    /// trame, lus dans la table des chunks.
    struct WavLayout: Equatable, Sendable {
        /// Décalage, en octets, du premier échantillon.
        let dataOffset: Int
        /// Taille du chunk `data` telle que l'en-tête l'annonce.
        let declaredDataSize: Int
        /// Taille d'une trame, tous canaux confondus (`nBlockAlign` du chunk
        /// `fmt ` — 2 octets pour du 16 bits mono).
        let blockAlign: Int
    }

    /// Combien d'octets de préfixe suffisent à contenir la table des chunks.
    /// CoreAudio aligne le début des données sur 4 096 octets (chunk `FLLR`) ;
    /// 64 Kio couvrent large sans charger un fichier de 300 Mo en mémoire.
    static let wavHeaderScanLimit = 64 * 1024

    /// Lit la table des chunks d'un en-tête RIFF/WAVE. Fonction pure sur un
    /// préfixe d'octets — aucune E/S, donc testable octet par octet.
    static func wavLayout(header: [UInt8]) -> WavLayout? {
        func mot32(_ i: Int) -> Int? {
            guard i + 4 <= header.count else { return nil }
            return Int(header[i]) | Int(header[i + 1]) << 8
                 | Int(header[i + 2]) << 16 | Int(header[i + 3]) << 24
        }
        func mot16(_ i: Int) -> Int? {
            guard i + 2 <= header.count else { return nil }
            return Int(header[i]) | Int(header[i + 1]) << 8
        }
        func identifiant(_ i: Int) -> String? {
            guard i + 4 <= header.count else { return nil }
            return String(decoding: header[i..<(i + 4)], as: UTF8.self)
        }

        guard identifiant(0) == "RIFF", identifiant(8) == "WAVE" else { return nil }

        var blockAlign: Int?
        var curseur = 12
        while curseur + 8 <= header.count {
            guard let id = identifiant(curseur), let taille = mot32(curseur + 4), taille >= 0
            else { return nil }
            let charge = curseur + 8
            if id == "fmt " {
                // WAVEFORMATEX : nBlockAlign est au 12ᵉ octet de la charge.
                blockAlign = mot16(charge + 12)
            }
            if id == "data" {
                guard let blockAlign, blockAlign > 0 else { return nil }
                return WavLayout(dataOffset: charge, declaredDataSize: taille, blockAlign: blockAlign)
            }
            // Les chunks RIFF sont alignés sur un nombre pair d'octets.
            curseur = charge + taille + (taille % 2)
        }
        return nil
    }

    /// Écrit sous `outputDir` une copie d'un WAV dont les tailles de chunk
    /// n'ont jamais été finalisées, ou `nil` s'il n'y a rien à réparer.
    ///
    /// `AVAudioFile(forWriting:)` inscrit les tailles réelles dans l'en-tête
    /// **à sa fermeture** (son `deinit`). Un processus qui s'arrête pendant
    /// l'écriture — enregistrement en cours, instance tuée — laisse donc sur
    /// le disque un fichier plein d'échantillons qui annonce `data = 0` :
    /// `AVAudioFile(forReading:)` l'ouvre sans erreur, avec `length == 0`.
    /// Rien n'est perdu, seul l'en-tête ment ; on le recalcule depuis la
    /// taille du fichier. La source n'est jamais modifiée en place — elle peut
    /// appartenir à l'utilisateur.
    static func repairedWavCopy(of url: URL, in outputDir: URL) throws -> URL? {
        let fm = FileManager.default
        guard let taille = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int,
              taille > 0,
              let lecture = try? FileHandle(forReadingFrom: url) else { return nil }
        let prefixe = (try? lecture.read(upToCount: wavHeaderScanLimit)) ?? Data()
        try? lecture.close()
        guard let plan = wavLayout(header: [UInt8](prefixe)) else { return nil }

        let reelle = taille - plan.dataOffset
        // Rien à faire si l'en-tête dit déjà la vérité (ou davantage).
        guard reelle > 0, plan.declaredDataSize < reelle else { return nil }
        // Une trame partielle en fin de fichier reste hors de la taille annoncée.
        let corrigee = (reelle / plan.blockAlign) * plan.blockAlign
        guard corrigee > 0 else { return nil }

        let output = outputDir.appending(path: "\(UUID().uuidString).wav")
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        try fm.copyItem(at: url, to: output)
        do {
            let ecriture = try FileHandle(forUpdating: output)
            try ecriture.seek(toOffset: 4)
            try ecriture.write(contentsOf: octets32(plan.dataOffset - 8 + corrigee))
            try ecriture.seek(toOffset: UInt64(plan.dataOffset - 4))
            try ecriture.write(contentsOf: octets32(corrigee))
            try ecriture.close()
        } catch {
            try? fm.removeItem(at: output)
            throw error
        }
        guard isDirectlyReadable(output) else {
            try? fm.removeItem(at: output)
            return nil
        }
        importLog.warning("repairedWavCopy: \(url.lastPathComponent, privacy: .public) — en-tête non finalisé (data annoncé \(plan.declaredDataSize), réel \(corrigee)) → \(output.lastPathComponent, privacy: .public)")
        return output
    }

    /// Un entier 32 bits en petit-boutien, comme l'exige RIFF.
    private static func octets32(_ valeur: Int) -> Data {
        let v = UInt32(clamping: valeur)
        return Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                     UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
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
