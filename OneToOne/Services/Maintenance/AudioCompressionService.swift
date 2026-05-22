import Foundation
import AVFoundation
import os

private let compLog = Logger(subsystem: "com.onetoone.app", category: "audio-compress")

/// Compresses a WAV into AAC LC mono 32 kbps `.m4a`. Atomic via `.compressing.m4a`
/// temp file + duration check. The original `.wav` is removed on success.
enum AudioCompressionService {

    static func compress(url: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "AudioCompressionService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Source introuvable"])
        }
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent("\(base).compressing.m4a")
        let final = dir.appendingPathComponent("\(base).m4a")
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.removeItem(at: final)

        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(domain: "AudioCompressionService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "AVAssetExportSession indisponible"])
        }
        export.outputURL = tmp
        export.outputFileType = .m4a
        export.audioMix = nil

        await export.export()
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: tmp)
            throw export.error ?? NSError(
                domain: "AudioCompressionService", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Export AVAssetExportSession incomplet"])
        }

        let origDuration = AudioFileEditor.duration(url: url)
        let newDuration = AudioFileEditor.duration(url: tmp)
        guard abs(newDuration - origDuration) <= 0.5 else {
            try? FileManager.default.removeItem(at: tmp)
            throw NSError(domain: "AudioCompressionService", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Durée incohérente après compression (\(newDuration)s vs \(origDuration)s)"])
        }

        try FileManager.default.moveItem(at: tmp, to: final)
        try FileManager.default.removeItem(at: url)
        compLog.info("compress done from=\(url.lastPathComponent, privacy: .public) to=\(final.lastPathComponent, privacy: .public) duration=\(newDuration)s")
        return final
    }
}
