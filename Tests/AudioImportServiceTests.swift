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
