import Foundation
import AVFoundation

/// Reads a WAV, returns `count` decimated peak magnitudes in `[0.0, 1.0]`.
/// Each bucket = max absolute sample over its frame range.
struct AudioWaveform {

    static func peaks(url: URL, count: Int) async throws -> [Float] {
        let safeCount = max(1, min(count, 2_000))
        return try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let total = file.length
            guard total > 0 else { return [Float](repeating: 0, count: safeCount) }
            let bucketSize = max(AVAudioFrameCount(1), AVAudioFrameCount(total / Int64(safeCount)))
            var result: [Float] = []
            result.reserveCapacity(safeCount)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bucketSize)!
            file.framePosition = 0
            while file.framePosition < total, result.count < safeCount {
                buf.frameLength = 0
                try file.read(into: buf, frameCount: bucketSize)
                let n = Int(buf.frameLength)
                if n == 0 { break }
                var peak: Float = 0
                if let p = buf.floatChannelData?[0] {
                    for i in 0..<n { peak = max(peak, abs(p[i])) }
                } else if let p = buf.int16ChannelData?[0] {
                    for i in 0..<n {
                        let v = Float(abs(p[i])) / 32_767.0
                        if v > peak { peak = v }
                    }
                }
                result.append(min(peak, 1.0))
            }
            while result.count < safeCount { result.append(0) }
            return result
        }.value
    }
}
