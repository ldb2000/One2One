import XCTest
import AVFoundation
@testable import OneToOne

final class AudioImportServiceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// WAV PCM 16 kHz mono synthétique (sinusoïde), comme produit par le recorder.
    private func makeSyntheticWAV(seconds: Double, sampleRate: Double = 16_000, channels: UInt32 = 1) throws -> URL {
        let totalFrames = Int(sampleRate * seconds)
        let chunk = 4096

        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let url = tmpDir.appendingPathComponent("src-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        let buf = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                   frameCapacity: AVAudioFrameCount(chunk))!
        var written = 0
        while written < totalFrames {
            let toWrite = min(chunk, totalFrames - written)
            buf.frameLength = AVAudioFrameCount(toWrite)
            for c in 0..<Int(channels) {
                if let ptr = buf.floatChannelData?[c] {
                    for i in 0..<toWrite {
                        let g = written + i
                        ptr[i] = Float(sin(2.0 * .pi * 440.0 * Double(g) / sampleRate) * 0.4)
                    }
                }
            }
            try file.write(from: buf)
            written += toWrite
        }
        return url
    }

    /// .m4a AAC valide produit depuis un WAV synthétique.
    private func makeAAC(seconds: Double) async throws -> URL {
        let wav = try makeSyntheticWAV(seconds: seconds, sampleRate: 48_000, channels: 2)
        let m4a = tmpDir.appendingPathComponent("aac-\(UUID().uuidString).m4a")
        try await AudioImportService.extractAudioTrack(from: wav, to: m4a)
        return m4a
    }

    /// Conteneur .m4a AAC valide mais SANS aucun packet audio : `AVAudioFile`
    /// l'ouvre sans erreur avec `length == 0` — même symptôme qu'un codec non
    /// décodable (ex. Opus dans .mp4), qui provoque l'erreur CoreAudio -50 à
    /// la lecture.
    private func makeEmptyAAC() throws -> URL {
        let url = tmpDir.appendingPathComponent("empty-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1
        ]
        _ = try AVAudioFile(forWriting: url, settings: settings)  // header seul, 0 packet
        return url
    }

    // MARK: - isDirectlyReadable

    func test_wavIsDirectlyReadable() throws {
        let wav = try makeSyntheticWAV(seconds: 2.0)
        XCTAssertTrue(AudioImportService.isDirectlyReadable(wav))
    }

    func test_emptyAacIsNotDirectlyReadable() throws {
        let empty = try makeEmptyAAC()
        // Le piège exact du bug -50 : l'ouverture réussit, length == 0.
        XCTAssertNotNil(try? AVAudioFile(forReading: empty))
        XCTAssertFalse(AudioImportService.isDirectlyReadable(empty))
    }

    func test_missingFileIsNotDirectlyReadable() {
        let missing = tmpDir.appendingPathComponent("missing.wav")
        XCTAssertFalse(AudioImportService.isDirectlyReadable(missing))
    }

    // MARK: - prepareForPipeline

    func test_readableWavPassesThrough() async throws {
        let wav = try makeSyntheticWAV(seconds: 2.0)
        let (out, transcoded) = try await AudioImportService.prepareForPipeline(wav, outputDir: tmpDir)
        XCTAssertEqual(out, wav, "Un WAV lisible doit passer tel quel, sans transcodage")
        XCTAssertFalse(transcoded)
    }

    func test_aacIsTranscodedToWav16kMono() async throws {
        let m4a = try await makeAAC(seconds: 3.0)
        let (out, transcoded) = try await AudioImportService.prepareForPipeline(m4a, outputDir: tmpDir)
        XCTAssertTrue(transcoded)
        XCTAssertEqual(out.pathExtension, "wav")

        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertEqual(duration, 3.0, accuracy: 0.2, "La durée doit être préservée par le transcodage")
        // Le WAV produit doit être lisible d'un bloc (chemin du pipeline STT).
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        XCTAssertNoThrow(try file.read(into: buf))
    }

    func test_emptyAacThrowsClearError() async throws {
        let empty = try makeEmptyAAC()
        do {
            _ = try await AudioImportService.prepareForPipeline(empty, outputDir: tmpDir)
            XCTFail("prepareForPipeline doit échouer sur un conteneur sans audio décodable")
        } catch {
            let msg = (error as NSError).localizedDescription
            XCTAssertFalse(msg.contains("-50"), "L'erreur doit être explicite, pas un -50 CoreAudio")
        }
        // Pas de fichier extrait/transcodé orphelin laissé derrière. Comparaison
        // par nom : contentsOfDirectory résout /var → /private/var.
        let leftovers = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != empty.lastPathComponent }
        XCTAssertTrue(leftovers.isEmpty, "Les sorties invalides doivent être nettoyées : \(leftovers)")
    }

    // MARK: - resilientTranscodeToWAV16kMono

    func test_resilientTranscodeHealthyFileSkipsNothing() async throws {
        let m4a = try await makeAAC(seconds: 4.0)
        let out = tmpDir.appendingPathComponent("out-\(UUID().uuidString).wav")
        let stats = try AudioImportService.resilientTranscodeToWAV16kMono(from: m4a, to: out)
        XCTAssertEqual(stats.skippedSeconds, 0)
        XCTAssertEqual(stats.corruptChunkCount, 0)
        XCTAssertEqual(stats.decodedSeconds, 4.0, accuracy: 0.2)
    }

    func test_resilientTranscodeResamples48kStereoTo16kMono() throws {
        let wav48 = try makeSyntheticWAV(seconds: 2.0, sampleRate: 48_000, channels: 2)
        let out = tmpDir.appendingPathComponent("out-\(UUID().uuidString).wav")
        let stats = try AudioImportService.resilientTranscodeToWAV16kMono(from: wav48, to: out)
        XCTAssertEqual(stats.decodedSeconds, 2.0, accuracy: 0.1)

        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000.0, 2.0, accuracy: 0.1)
    }

    // MARK: - En-tête WAV jamais finalisé (2026-09-08)

    /// Casse les tailles de chunk d'un WAV comme le fait un écrivain dont le
    /// processus s'arrête sans fermer le fichier : `AVAudioFile` finalise
    /// l'en-tête RIFF dans son `deinit`, donc un processus tué laisse un
    /// fichier plein d'échantillons qui **annonce** zéro octet de données.
    /// C'est exactement l'état du WAV de la réunion 227 le 2026-09-08
    /// (3 062 526 octets sur le disque, `RIFF` = 4 088, `data` = 0).
    private func breakWavSizes(_ url: URL) throws {
        var octets = [UInt8](try Data(contentsOf: url))
        // `RIFF` annonce l'en-tête aligné seul (4 096 − 8).
        octets[4] = 0xF8; octets[5] = 0x0F; octets[6] = 0; octets[7] = 0
        for i in 0..<(octets.count - 8)
        where octets[i] == 0x64 && octets[i + 1] == 0x61
            && octets[i + 2] == 0x74 && octets[i + 3] == 0x61 {
            octets[i + 4] = 0; octets[i + 5] = 0; octets[i + 6] = 0; octets[i + 7] = 0
            break
        }
        try Data(octets).write(to: url)
    }

    func test_unfinalizedWavIsSeenAsEmptyByAVAudioFile() throws {
        let wav = try makeSyntheticWAV(seconds: 3.0)
        try breakWavSizes(wav)
        // Le piège : l'ouverture réussit, la durée est nulle. C'est ce couple
        // qui a fait persister `durationSeconds = 0` sur une réunion dont le
        // WAV portait 96 s d'audio.
        XCTAssertEqual(try AVAudioFile(forReading: wav).length, 0)
        XCTAssertFalse(AudioImportService.isDirectlyReadable(wav))
    }

    func test_wavLayoutReadsDataChunkAndBlockAlign() throws {
        let wav = try makeSyntheticWAV(seconds: 1.0)
        let entete = [UInt8](try Data(contentsOf: wav).prefix(64 * 1024))
        let plan = try XCTUnwrap(AudioImportService.wavLayout(header: entete))
        XCTAssertEqual(plan.blockAlign, 2, "16 bits mono → 2 octets par trame")
        XCTAssertEqual(plan.declaredDataSize, 16_000 * 2)
        let taille = try FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int
        XCTAssertEqual(plan.dataOffset + plan.declaredDataSize, taille)
    }

    func test_wavLayoutRejectsNonRiff() {
        XCTAssertNil(AudioImportService.wavLayout(header: [UInt8]("pas du tout un WAV".utf8)))
    }

    /// Le correctif : un WAV à en-tête non finalisé est **récupéré**, pas
    /// envoyé à `AVAssetExportSession`.
    func test_unfinalizedWavIsRecoveredByPrepareForPipeline() async throws {
        let wav = try makeSyntheticWAV(seconds: 3.0)
        try breakWavSizes(wav)

        let (out, transcoded) = try await AudioImportService.prepareForPipeline(wav, outputDir: tmpDir)
        XCTAssertTrue(transcoded, "La réunion doit être repointée sur la copie réparée")
        XCTAssertNotEqual(out, wav, "La source n'est jamais modifiée en place")
        let file = try AVAudioFile(forReading: out)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 3.0, accuracy: 0.01)
        // Et le fichier réparé se relit d'un bloc — le chemin du STT.
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        XCTAssertNoThrow(try file.read(into: buf))
    }

    func test_repairedWavCopyReturnsNilOnHealthyWav() throws {
        let wav = try makeSyntheticWAV(seconds: 1.0)
        XCTAssertNil(try AudioImportService.repairedWavCopy(of: wav, in: tmpDir),
                     "Un en-tête sain n'a rien à réparer")
    }

    // MARK: - Durée persistée

    func test_pipelineDurationSecondsOnWav() throws {
        let wav = try makeSyntheticWAV(seconds: 4.0)
        XCTAssertEqual(try AudioImportService.pipelineDurationSeconds(of: wav), 4)
    }

    func test_pipelineDurationSecondsRefusesAnEmptyFile() throws {
        let wav = try makeSyntheticWAV(seconds: 3.0)
        try breakWavSizes(wav)
        // Plutôt que de persister 0 en silence : une erreur en français.
        XCTAssertThrowsError(try AudioImportService.pipelineDurationSeconds(of: wav)) { erreur in
            let msg = (erreur as NSError).localizedDescription
            XCTAssertTrue(msg.contains("aucun audio"), msg)
            XCTAssertFalse(msg.lowercased().contains("operation"), msg)
        }
    }

    func test_pipelineDurationSecondsNeverReturnsZeroOnAudibleFile() throws {
        let court = try makeSyntheticWAV(seconds: 0.3)
        XCTAssertGreaterThan(try AudioImportService.pipelineDurationSeconds(of: court), 0,
                             "Un fichier audible ne doit jamais valoir 0 s en base")
    }

    /// Le geste du 2026-09-08 : import d'un `.mp4` AAC produit par `afconvert`.
    /// La durée persistée doit être celle du fichier.
    func test_importedMp4YieldsAPositiveDuration() async throws {
        let mp4 = try await makeMp4WithAfconvertIfAvailable(seconds: 3.0)
        let (out, transcoded) = try await AudioImportService.prepareForPipeline(mp4, outputDir: tmpDir)
        XCTAssertTrue(transcoded)
        XCTAssertGreaterThan(try AudioImportService.pipelineDurationSeconds(of: out), 0)
    }

    /// `.mp4` réel via `afconvert` si l'outil est là, sinon repli sur un
    /// conteneur AAC équivalent produit par AVFoundation — le test garde son
    /// sens sur une machine sans `/usr/bin/afconvert`.
    private func makeMp4WithAfconvertIfAvailable(seconds: Double) async throws -> URL {
        let afconvert = URL(fileURLWithPath: "/usr/bin/afconvert")
        guard FileManager.default.isExecutableFile(atPath: afconvert.path) else {
            return try await makeAAC(seconds: seconds)
        }
        let source = try makeSyntheticWAV(seconds: seconds, sampleRate: 44_100, channels: 1)
        let mp4 = tmpDir.appendingPathComponent("voix-\(UUID().uuidString).mp4")
        let process = Process()
        process.executableURL = afconvert
        process.arguments = ["-f", "mp4f", "-d", "aac", source.path, mp4.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: mp4.path) else {
            return try await makeAAC(seconds: seconds)
        }
        return mp4
    }

    // MARK: - Messages d'erreur

    /// Aucun message d'AVFoundation ne doit remonter tel quel à l'utilisateur :
    /// « The operation could not be completed » (`AVFoundationErrorDomain`
    /// −11800) est ce que l'alerte affichait, et il ne dit ni quel fichier ni
    /// ce qui a manqué.
    func test_undecodableContainerErrorIsInFrenchAndNamesTheFile() async throws {
        let bidon = tmpDir.appendingPathComponent("piege.m4a")
        try Data(repeating: 0x2A, count: 4_096).write(to: bidon)
        do {
            _ = try await AudioImportService.prepareForPipeline(bidon, outputDir: tmpDir)
            XCTFail("Un conteneur illisible doit échouer")
        } catch {
            let ns = error as NSError
            XCTAssertEqual(ns.domain, "AudioImportService",
                           "L'erreur d'AVFoundation ne doit pas remonter nue : \(ns)")
            XCTAssertTrue(ns.localizedDescription.contains("piege.m4a"),
                          ns.localizedDescription)
            XCTAssertFalse(ns.localizedDescription.lowercased().contains("operation"),
                           ns.localizedDescription)
        }
    }

    // MARK: - Smoke test optionnel sur fichier réel

    /// Exporter ONETOONE_SMOKE_AUDIO=/chemin/vers/fichier pour valider le
    /// transcodage résilient sur un fichier problématique réel (ex. mp4 avec
    /// paquets AAC corrompus). Ignoré sinon.
    func test_smokeRealFile_ifConfigured() async throws {
        guard let path = ProcessInfo.processInfo.environment["ONETOONE_SMOKE_AUDIO"] else {
            throw XCTSkip("ONETOONE_SMOKE_AUDIO non défini")
        }
        let src = URL(fileURLWithPath: path)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: src.path))

        let (out, transcoded) = try await AudioImportService.prepareForPipeline(src, outputDir: tmpDir)
        XCTAssertTrue(transcoded)
        let file = try AVAudioFile(forReading: out)
        XCTAssertGreaterThan(file.length, 0)
        // Lecture intégrale d'un bloc — le chemin exact qui échouait en -50.
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                   frameCapacity: AVAudioFrameCount(file.length))!
        XCTAssertNoThrow(try file.read(into: buf))
        print("[smoke] \(src.lastPathComponent) → \(out.lastPathComponent) duration=\(Double(file.length) / file.processingFormat.sampleRate)s")
    }
}
