// Tests/AudioRecorderSegmentsTests.swift
import XCTest
import AVFoundation
@testable import OneToOne

/// Le fallback par segment (spec D1) produit N fichiers WAV qu'`AudioRecorderService.stop()`
/// recolle en un seul. Ces tests fixent le contrat de `mergeSegments`.
final class AudioRecorderSegmentsTests: XCTestCase {

    /// Écrit un WAV 16 kHz mono de `seconds` secondes de sinusoïde.
    private func writeWav(seconds: Double) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorderService.wavSettings)
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = sin(Float(i) * 0.05) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    func testSingleSegmentIsReturnedUntouched() throws {
        let seul = try writeWav(seconds: 1)
        defer { try? FileManager.default.removeItem(at: seul) }
        let result = try AudioRecorderService.mergeSegments([seul])
        XCTAssertEqual(result, seul)
        XCTAssertTrue(FileManager.default.fileExists(atPath: seul.path))
    }

    func testTwoSegmentsAreConcatenatedAndDeleted() throws {
        let a = try writeWav(seconds: 1)
        let b = try writeWav(seconds: 2)
        let result = try AudioRecorderService.mergeSegments([a, b])
        defer { try? FileManager.default.removeItem(at: result) }

        XCTAssertNotEqual(result, a)
        XCTAssertNotEqual(result, b)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path), "les segments sont supprimés")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
        let merged = try AVAudioFile(forReading: result)
        XCTAssertEqual(Double(merged.length) / merged.processingFormat.sampleRate, 3, accuracy: 0.01)
        XCTAssertEqual(result.deletingLastPathComponent(), AudioRecorderService.recordingsDirectory)
    }

    func testThreeSegmentsKeepOrderAndTotalDuration() throws {
        let urls = try [0.5, 1.0, 1.5].map { try writeWav(seconds: $0) }
        let result = try AudioRecorderService.mergeSegments(urls)
        defer { try? FileManager.default.removeItem(at: result) }
        let merged = try AVAudioFile(forReading: result)
        XCTAssertEqual(Double(merged.length) / merged.processingFormat.sampleRate, 3, accuracy: 0.01)
    }

    /// Nombre de `.wav` dans `recordingsDirectory`, pour vérifier qu'une fusion
    /// ratée n'y laisse aucun fichier de sortie orphelin.
    private func wavCountInRecordingsDirectory() throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: AudioRecorderService.recordingsDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }.count
    }

    func testMissingSegmentFailsWithoutDeletingOthers() throws {
        let a = try writeWav(seconds: 1)
        defer { try? FileManager.default.removeItem(at: a) }
        let absent = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let before = try wavCountInRecordingsDirectory()
        XCTAssertThrowsError(try AudioRecorderService.mergeSegments([a, absent]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "rien n'est supprimé si la fusion échoue")
        XCTAssertEqual(try wavCountInRecordingsDirectory(), before, "aucun fichier de sortie orphelin dans recordingsDirectory")
    }

    func testEmptyListThrows() {
        XCTAssertThrowsError(try AudioRecorderService.mergeSegments([]))
    }
}
