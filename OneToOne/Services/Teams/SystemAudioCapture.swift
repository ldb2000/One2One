import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

private let sysAudioLog = Logger(subsystem: "com.onetoone.app", category: "system-audio")

/// Capture l'audio système via `ScreenCaptureKit`, sans vidéo. C'est la seconde
/// piste d'une réunion Teams : ce que disent les participants distants.
///
/// La permission d'enregistrement d'écran est requise. Si elle manque, `start`
/// échoue proprement et l'appelant continue en micro seul (spec D-6) : cette
/// classe ne notifie pas l'utilisateur elle-même.
@MainActor
final class SystemAudioCapture: NSObject, SCStreamOutput {

    /// Appelée à chaque bloc capturé, en 16 kHz mono.
    private var onSamples: (([Float]) -> Void)?
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.onetoone.system-audio", qos: .userInitiated)

    /// Miroirs de `AudioRecorderService.sampleRate`/`.channels` (16 kHz mono).
    ///
    /// `AudioRecorderService` est `@MainActor` : ses constantes le sont donc
    /// aussi, et `makeConfiguration()` doit rester `nonisolated` (appelée
    /// telle quelle, hors acteur, par `SystemAudioCaptureTests` et par le
    /// futur appelant synchrone de Task 3). Une lecture directe de
    /// `AudioRecorderService.sampleRate` depuis ce contexte `nonisolated`
    /// compile mais avertit (« main actor-isolated static property … can not
    /// be referenced from a nonisolated context ; this is an error in the
    /// Swift 6 language mode ») — `MainActor.assumeIsolated` a été essayé et
    /// **plante** ici (signal 5) : Swift Testing exécute les suites en
    /// parallèle sur le pool coopératif, pas garanti sur le fil principal.
    /// Dupliquer est donc le choix le plus sûr ; `SystemAudioCaptureTests.
    /// sampleRateMatchesRecorder`/`monoChannel` comparent les deux sources et
    /// échoueraient si elles divergeaient.
    private nonisolated static let recorderSampleRate = 16_000
    private nonisolated static let recorderChannelCount = 1

    /// Configuration du flux : audio seul, aligné sur la piste micro.
    ///
    /// `width`/`height` sont posés au minimum légal parce que `SCStream` exige
    /// une taille de sortie même quand seule l'audio nous intéresse ; on ne
    /// consomme jamais les échantillons vidéo.
    nonisolated static func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = recorderSampleRate
        config.channelCount = recorderChannelCount
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return config
    }

    /// Vrai si la permission d'enregistrement d'écran est **déjà** accordée.
    /// Ne déclenche aucune demande : c'est `start` qui provoquera le prompt
    /// système, au moment où l'utilisateur a demandé un enregistrement.
    nonisolated static func isPermissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Démarre la capture. Lance une erreur si la permission manque ou si
    /// aucun écran n'est partageable — à l'appelant de retomber sur micro seul.
    func start(onSamples: @escaping ([Float]) -> Void) async throws {
        self.onSamples = onSamples
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw AudioError.startFailed
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: Self.makeConfiguration(), delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
        sysAudioLog.info("capture audio systeme demarree")
    }

    /// Arrête la capture. Idempotent.
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        self.onSamples = nil
        do { try await stream.stopCapture() } catch {
            sysAudioLog.warning("arret capture: \(error.localizedDescription)")
        }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let samples = Self.floatSamples(from: sampleBuffer) else { return }
        Task { @MainActor in self.onSamples?(samples) }
    }

    /// Extrait les échantillons `Float32` mono d'un `CMSampleBuffer` audio.
    nonisolated static func floatSamples(from buffer: CMSampleBuffer) -> [Float]? {
        guard let description = buffer.formatDescription,
              let asbd = description.audioStreamBasicDescription,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer)
        guard status == noErr,
              let data = audioBufferList.mBuffers.mData else { return nil }
        let count = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
    }
}
