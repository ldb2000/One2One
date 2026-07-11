import XCTest
import AVFoundation
@testable import OneToOne

/// Non-régression du `TapSink` : le converter `AVAudioConverter` est réutilisé
/// buffer après buffer sur toute la session d'enregistrement. Signaler
/// `.endOfStream` dans le bloc d'entrée le finalise après le 1er buffer → tous
/// les suivants produisent 0 frame → le WAV reste figé à ~0,1 s (bug a8fcf99).
/// La correction (`.noDataNow`) doit garder le converter vivant.
final class AudioRecorderConverterTests: XCTestCase {

    /// Génère un buffer mono Float32 rempli d'une sinusoïde (signal non nul).
    private static func makeSine(sampleRate: Double, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
        buf.frameLength = frames
        let ptr = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ptr[i] = sin(Float(i) * 0.05) * 0.5 }
        return buf
    }

    func testConverterKeepsProcessingAcrossBuffers() throws {
        let tmp = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        // Le `TapSink` doit détenir l'UNIQUE référence forte au fichier : `finish()`
        // le libère (file = nil) → l'`AVAudioFile` est désalloué → header WAV finalisé
        // et fermé, sinon la relecture voit une longueur nulle. On confine donc la
        // création du fichier à ce bloc.
        let sink: TapSink
        do {
            let file = try AVAudioFile(forWriting: tmp, settings: settings)
            let target = file.processingFormat
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let converter = try XCTUnwrap(AVAudioConverter(from: inputFormat, to: target))
            sink = TapSink(converter: converter, targetFormat: target, file: file, continuation: nil)
        }

        // 5 buffers de 4800 frames @48k = 0,5 s d'audio en entrée.
        let bufferCount = 5
        var successes = 0
        for _ in 0..<bufferCount where sink.process(Self.makeSine(sampleRate: 48_000, frames: 4800)) != nil {
            successes += 1
        }
        sink.finish()

        // Avec `.endOfStream`, seul le 1er buffer réussit (successes == 1).
        XCTAssertEqual(successes, bufferCount,
                       "process() doit réussir sur TOUS les buffers, pas seulement le premier")

        // Le WAV doit contenir ~0,5 s, pas un unique buffer (~0,1 s).
        let read = try AVAudioFile(forReading: tmp)
        let duration = Double(read.length) / read.fileFormat.sampleRate
        XCTAssertGreaterThan(duration, 0.4,
                             "le WAV doit contenir ~0,5 s d'audio, or il est figé à \(duration) s")
    }
}
