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

    /// Rewrite `url` keeping samples in [`fromSec`, `toSec`). Either bound
    /// can be nil → unbounded. Atomic via `.tmp.wav` + `replaceItemAt`.
    /// Throws if the resulting range is empty or invalid.
    static func trim(url: URL, from fromSec: Double? = nil, to toSec: Double? = nil) async throws {
        let total = duration(url: url)
        let lo = max(0, fromSec ?? 0)
        let hi = min(total, toSec ?? total)
        guard hi - lo >= 0.5 else {
            throw NSError(domain: "AudioFileEditor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Plage à conserver trop courte"])
        }
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".tmp.wav")
        try? FileManager.default.removeItem(at: tmp)

        try await Task.detached(priority: .userInitiated) {
            let src = try AVAudioFile(forReading: url)
            let format = src.processingFormat
            let dst = try AVAudioFile(forWriting: tmp, settings: src.fileFormat.settings)
            let startFrame = AVAudioFramePosition(lo * format.sampleRate)
            let endFrame = AVAudioFramePosition(hi * format.sampleRate)
            src.framePosition = startFrame
            let chunk: AVAudioFrameCount = 8192
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!
            while src.framePosition < endFrame {
                try Task.checkCancellation()
                let remaining = AVAudioFrameCount(endFrame - src.framePosition)
                let toRead = min(chunk, remaining)
                buf.frameLength = 0
                try src.read(into: buf, frameCount: toRead)
                if buf.frameLength == 0 { break }
                try dst.write(from: buf)
            }
        }.value

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        editorLog.info("trim done from=\(lo)s to=\(hi)s total=\(total)s")
    }

}

extension AudioFileEditor {

    /// Split `url` at `cutSec` into two WAVs. Returns `(urlA, urlB)`. The
    /// original is removed after both new files are written successfully.
    /// Throws if `cutSec < 1s` or `cutSec > duration - 1s`.
    static func split(url: URL, at cutSec: Double) async throws -> (URL, URL) {
        let total = duration(url: url)
        guard cutSec >= 1.0, cutSec <= total - 1.0 else {
            throw NSError(domain: "AudioFileEditor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Position de coupe trop proche d'un bord"])
        }
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let urlA = dir.appendingPathComponent("\(base)_A.wav")
        let urlB = dir.appendingPathComponent("\(base)_B.wav")
        try? FileManager.default.removeItem(at: urlA)
        try? FileManager.default.removeItem(at: urlB)

        do {
            try await Task.detached(priority: .userInitiated) {
                let src = try AVAudioFile(forReading: url)
                let format = src.processingFormat
                let cutFrame = AVAudioFramePosition(cutSec * format.sampleRate)
                let chunk: AVAudioFrameCount = 8192
                let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)!

                // Part A: 0 ..< cutFrame
                let dstA = try AVAudioFile(forWriting: urlA, settings: src.fileFormat.settings)
                src.framePosition = 0
                while src.framePosition < cutFrame {
                    try Task.checkCancellation()
                    let remaining = AVAudioFrameCount(cutFrame - src.framePosition)
                    buf.frameLength = min(chunk, remaining)
                    try src.read(into: buf, frameCount: buf.frameLength)
                    if buf.frameLength == 0 { break }
                    try dstA.write(from: buf)
                }

                // Part B: cutFrame ..< end
                let dstB = try AVAudioFile(forWriting: urlB, settings: src.fileFormat.settings)
                src.framePosition = cutFrame
                while src.framePosition < src.length {
                    try Task.checkCancellation()
                    try src.read(into: buf)
                    if buf.frameLength == 0 { break }
                    try dstB.write(from: buf)
                }
            }.value
        } catch {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
            throw error
        }

        try FileManager.default.removeItem(at: url)
        editorLog.info("split done at=\(cutSec)s")
        return (urlA, urlB)
    }
}
