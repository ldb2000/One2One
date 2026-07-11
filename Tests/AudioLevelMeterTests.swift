import Testing
import Foundation
@testable import OneToOne

struct AudioLevelMeterTests {

    @Test func silenceFloorsAtMinus160() {
        let (avg, peak) = AudioLevelMeter.levels(from: [Float](repeating: 0, count: 512))
        #expect(avg == -160)
        #expect(peak == -160)
    }

    @Test func emptyBufferFloorsAtMinus160() {
        let (avg, peak) = AudioLevelMeter.levels(from: [])
        #expect(avg == -160)
        #expect(peak == -160)
    }

    @Test func fullScaleSquareWaveIsNearZeroDB() {
        // Signal à ±1.0 : RMS = 1.0 → 0 dBFS, crête = 1.0 → 0 dBFS.
        let samples = (0..<512).map { $0 % 2 == 0 ? Float(1.0) : Float(-1.0) }
        let (avg, peak) = AudioLevelMeter.levels(from: samples)
        #expect(abs(avg - 0) < 0.01)
        #expect(abs(peak - 0) < 0.01)
    }

    @Test func halfAmplitudePeakIsAboutMinus6dB() {
        let samples = (0..<512).map { $0 % 2 == 0 ? Float(0.5) : Float(-0.5) }
        let (_, peak) = AudioLevelMeter.levels(from: samples)
        #expect(abs(peak - (-6.02)) < 0.1)
    }
}
