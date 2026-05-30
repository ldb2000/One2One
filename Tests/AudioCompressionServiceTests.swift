import XCTest
import AVFoundation
@testable import OneToOne

final class AudioCompressionServiceTests: XCTestCase {

    private func makeSyntheticWAV(seconds: Double) throws -> URL {
        let sr: Double = 16_000
        let totalFrames = Int(sr * seconds)
        let chunk = 4096

        let processingFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
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
            .appendingPathComponent("compress-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        let buf = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                   frameCapacity: AVAudioFrameCount(chunk))!
        var written = 0
        while written < totalFrames {
            let toWrite = min(chunk, totalFrames - written)
            buf.frameLength = AVAudioFrameCount(toWrite)
            if let ptr = buf.floatChannelData?[0] {
                for i in 0..<toWrite {
                    let g = written + i
                    let s = sin(2.0 * .pi * 440.0 * Double(g) / sr) * 0.4
                    ptr[i] = Float(s)
                }
            }
            try file.write(from: buf)
            written += toWrite
        }
        return url
    }

    func test_compressProducesM4AAndRemovesOriginal() async throws {
        let wav = try makeSyntheticWAV(seconds: 4.0)
        let m4a = try await AudioCompressionService.compress(url: wav)
        defer { try? FileManager.default.removeItem(at: m4a) }
        XCTAssertEqual(m4a.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: m4a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: wav.path),
                       "Original .wav doit être supprimé après compression réussie")
        let asset = AVURLAsset(url: m4a)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration), 4.0, accuracy: 0.5)
    }

    func test_compressLeavesOriginalIfMissing() async throws {
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).wav")
        do {
            _ = try await AudioCompressionService.compress(url: badURL)
            XCTFail("Compression devrait échouer pour un fichier source absent")
        } catch {
            // expected
        }
    }
}
