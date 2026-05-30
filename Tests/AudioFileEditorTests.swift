import XCTest
import AVFoundation
@testable import OneToOne

final class AudioFileEditorTests: XCTestCase {

    /// Génère un WAV 16-bit PCM mono 16 kHz, sinus 440 Hz, durée `seconds`.
    /// Approach : buffer interne Float32 → AVAudioFile écrit en .pcmFormatInt16
    /// (AVAudioFile gère la conversion automatiquement).
    func makeSyntheticWAV(seconds: Double) throws -> URL {
        let sr: Double = 16_000
        let totalFrames = Int(sr * seconds)
        let chunk = 4096

        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        // Settings pour fichier WAV PCM 16-bit (sortie disque).
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("synth-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)

        var framesWritten = 0
        let buf = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(chunk))!
        while framesWritten < totalFrames {
            let toWrite = min(chunk, totalFrames - framesWritten)
            buf.frameLength = AVAudioFrameCount(toWrite)
            if let ptr = buf.floatChannelData?[0] {
                for i in 0..<toWrite {
                    let global = framesWritten + i
                    let s = sin(2.0 * .pi * 440.0 * Double(global) / sr)
                    ptr[i] = Float(s) * 0.5
                }
            }
            try file.write(from: buf)
            framesWritten += toWrite
        }
        return url
    }

    func test_duration_returnsExpectedSeconds() throws {
        let url = try makeSyntheticWAV(seconds: 5.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 5.0, accuracy: 0.05)
    }

    func test_trim_dropsLeadingSeconds() async throws {
        let url = try makeSyntheticWAV(seconds: 6.0)
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioFileEditor.trim(url: url, from: 2.0)
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 4.0, accuracy: 0.05)
    }

    func test_trim_throws_whenFromSecExceedsDuration() async throws {
        let url = try makeSyntheticWAV(seconds: 3.0)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await AudioFileEditor.trim(url: url, from: 5.0)
            XCTFail("trim should throw when fromSec >= duration")
        } catch { /* expected */ }
    }

    func test_split_producesTwoFilesOfExpectedLengths() async throws {
        let url = try makeSyntheticWAV(seconds: 10.0)
        let (a, b) = try await AudioFileEditor.split(url: url, at: 4.0)
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        XCTAssertEqual(AudioFileEditor.duration(url: a), 4.0, accuracy: 0.05)
        XCTAssertEqual(AudioFileEditor.duration(url: b), 6.0, accuracy: 0.05)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "Original file must be removed after split")
    }

    func test_split_throws_whenCutTooCloseToEdge() async throws {
        let url = try makeSyntheticWAV(seconds: 5.0)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await AudioFileEditor.split(url: url, at: 0.5)
            XCTFail("split should refuse cuts < 1s from start")
        } catch { /* expected */ }
    }

    func test_trim_dropsTrailingSeconds() async throws {
        let url = try makeSyntheticWAV(seconds: 6.0)
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioFileEditor.trim(url: url, from: nil, to: 2.5)
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 2.5, accuracy: 0.05)
    }

    func test_trim_acceptsBothBounds() async throws {
        let url = try makeSyntheticWAV(seconds: 10.0)
        defer { try? FileManager.default.removeItem(at: url) }
        try await AudioFileEditor.trim(url: url, from: 2.0, to: 7.0)
        let d = AudioFileEditor.duration(url: url)
        XCTAssertEqual(d, 5.0, accuracy: 0.05)
    }
}
