import Foundation
import AVFoundation
import os

private let editorLog = Logger(subsystem: "com.onetoone.app", category: "audio-editor")

/// Stateless WAV editor. All operations rewrite files on disk atomically and
/// run off-main via `Task.detached` for large files.
struct AudioFileEditor {

    /// Total duration via AVAudioFile.length / sampleRate. Returns 0 on error.
    static func duration(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sr = file.processingFormat.sampleRate
        guard sr > 0 else { return 0 }
        return Double(file.length) / sr
    }
}

extension AudioFileEditor {

    /// Rewrite `url` keeping only samples from `fromSec` onward. Atomic:
    /// writes a `.tmp.wav` sibling then replaces the original.
    /// Throws if `fromSec` >= total duration.
    static func trim(url: URL, from fromSec: Double) async throws {
        let total = duration(url: url)
        guard fromSec > 0, fromSec < total else {
            throw NSError(domain: "AudioFileEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Position invalide"])
        }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
        try? FileManager.default.removeItem(at: tmp)

        try await Task.detached(priority: .userInitiated) {
            let src = try AVAudioFile(forReading: url)
            let format = src.processingFormat
            let dst = try AVAudioFile(forWriting: tmp, settings: src.fileFormat.settings)
            let startFrame = AVAudioFramePosition(fromSec * format.sampleRate)
            src.framePosition = startFrame
            let chunk: AVAudioFrameCount = 8192
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
            while src.framePosition < src.length {
                try Task.checkCancellation()
                try src.read(into: buf)
                if buf.frameLength == 0 { break }
                try dst.write(from: buf)
            }
        }.value

        // Atomic replace.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        editorLog.info("trim done from=\(fromSec)s")
    }
}
