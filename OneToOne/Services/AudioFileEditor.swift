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
