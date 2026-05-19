import XCTest
import AVFoundation
@testable import OneToOne

final class AudioWaveformTests: XCTestCase {

    /// Synth WAV via AVAudioFile en pcm16 (settings) + buffer Float32 standard.
    func makeSyntheticWAV(seconds: Double, amplitude: Double = 0.5) throws -> URL {
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
            .appendingPathComponent("wf-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)

        var written = 0
        let buf = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(chunk))!
        while written < totalFrames {
            let toWrite = min(chunk, totalFrames - written)
            buf.frameLength = AVAudioFrameCount(toWrite)
            if let ptr = buf.floatChannelData?[0] {
                for i in 0..<toWrite {
                    let g = written + i
                    let s = sin(2.0 * .pi * 440.0 * Double(g) / sr) * amplitude
                    ptr[i] = Float(s)
                }
            }
            try file.write(from: buf)
            written += toWrite
        }
        return url
    }

    func test_peaks_returnsRequestedCountInUnitInterval() async throws {
        let url = try makeSyntheticWAV(seconds: 4.0, amplitude: 0.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = try await AudioWaveform.peaks(url: url, count: 100)
        XCTAssertEqual(p.count, 100)
        for v in p {
            XCTAssertGreaterThanOrEqual(v, 0.0)
            XCTAssertLessThanOrEqual(v, 1.0)
        }
        let maxP = p.max() ?? 0
        XCTAssertGreaterThan(maxP, 0.3, "Peak should reflect the 0.5 amplitude")
    }
}
