import XCTest
import AVFoundation
@testable import OneToOne

/// Le fallback par segment (spec D1) remplace le fichier et le convertisseur du
/// `TapSink` **sans** toucher à la continuation du flux live : la transcription
/// en direct doit recevoir tous les blocs, avant et après la rotation, et les
/// deux WAV doivent être relisibles.
final class TapSinkRotationTests: XCTestCase {

    private static let wavSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    private static func makeSine(sampleRate: Double, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let ptr = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = sin(Float(i) * 0.05) * 0.5 }
        return buf
    }

    func testRotationKeepsLiveStreamAndClosesBothFiles() throws {
        let url1 = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        let url2 = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url1); try? FileManager.default.removeItem(at: url2) }

        var received = 0
        var continuation: AsyncStream<[Float]>.Continuation!
        let stream = AsyncStream<[Float]> { continuation = $0 }
        let consumer = Task { for await block in stream { received += block.count } }

        // Premier segment : entrée 48 kHz (un iPhone en Continuité, par exemple).
        let sink: TapSink
        do {
            let file1 = try AVAudioFile(forWriting: url1, settings: Self.wavSettings)
            let target = file1.processingFormat
            let input48 = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let conv1 = AVAudioConverter(from: input48, to: target)!
            sink = TapSink(converter: conv1, targetFormat: target, file: file1, continuation: continuation)
        }
        for _ in 0..<5 { XCTAssertNotNil(sink.process(Self.makeSine(sampleRate: 48_000, frames: 4800))) }

        // Rotation : entrée 44,1 kHz (le micro intégré), nouveau fichier.
        do {
            let file2 = try AVAudioFile(forWriting: url2, settings: Self.wavSettings)
            let input44 = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let conv2 = AVAudioConverter(from: input44, to: sink.targetFormat)!
            sink.rotate(file: file2, converter: conv2)
        }
        for _ in 0..<5 { XCTAssertNotNil(sink.process(Self.makeSine(sampleRate: 44_100, frames: 4410))) }

        sink.finish()
        _ = try? awaitTask(consumer)

        let f1 = try AVAudioFile(forReading: url1)
        let f2 = try AVAudioFile(forReading: url2)
        // 5 × 0,1 s à 16 kHz ≈ 8 000 frames par segment (tolérance resampler).
        XCTAssertGreaterThan(f1.length, 7_000, "le premier segment est clos et relisible")
        XCTAssertGreaterThan(f2.length, 7_000, "le second segment est clos et relisible")
        XCTAssertGreaterThan(received, 14_000, "le flux live a reçu les deux segments sans coupure")
    }

    /// Attend la fin d'une `Task` depuis un test XCTest synchrone.
    private func awaitTask(_ task: Task<Void, Never>) throws {
        let done = expectation(description: "flux live terminé")
        Task { await task.value; done.fulfill() }
        wait(for: [done], timeout: 5)
    }
}
