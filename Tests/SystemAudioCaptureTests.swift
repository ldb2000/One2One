import Testing
import Foundation
import ScreenCaptureKit
@testable import OneToOne

/// La configuration du flux est une valeur, donc testable — et c'est elle qui
/// décide si le STT recevra quelque chose d'exploitable. Un `sampleRate` qui ne
/// correspond pas à celui du micro rendrait le mixage incohérent.
@Suite("SystemAudioCapture — configuration du flux")
struct SystemAudioCaptureTests {

    @Test("Le flux capture l'audio et rien d'autre")
    func capturesAudioOnly() {
        let config = SystemAudioCapture.makeConfiguration()
        #expect(config.capturesAudio)
        // Vidéo réduite au minimum légal : on ne veut pas d'image (spec §1).
        #expect(config.width == 2)
        #expect(config.height == 2)
    }

    @Test("Le taux d'échantillonnage suit celui du micro")
    func sampleRateMatchesRecorder() {
        #expect(SystemAudioCapture.makeConfiguration().sampleRate == Int(AudioRecorderService.sampleRate))
    }

    @Test("Le flux est mono, comme la piste micro")
    func monoChannel() {
        #expect(SystemAudioCapture.makeConfiguration().channelCount == Int(AudioRecorderService.channels))
    }

    @Test("L'audio de OneToOne lui-même est exclu, pour ne pas s'enregistrer en boucle")
    func excludesOwnAudio() {
        #expect(SystemAudioCapture.makeConfiguration().excludesCurrentProcessAudio)
    }
}
