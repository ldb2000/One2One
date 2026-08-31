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

    /// Configuration du flux : audio seul, aligné sur la piste micro.
    ///
    /// `width`/`height` sont posés au minimum légal parce que `SCStream` exige
    /// une taille de sortie même quand seule l'audio nous intéresse ; on ne
    /// consomme jamais les échantillons vidéo.
    nonisolated static func makeConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(AudioRecorderService.sampleRate)
        config.channelCount = Int(AudioRecorderService.channels)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        return config
    }

    /// Vrai si la permission d'enregistrement d'écran est **déjà** accordée.
    /// Ne déclenche aucune demande — et comme l'armement de la seconde piste
    /// est gardé par ce préflight, l'app ne provoque jamais le prompt système
    /// elle-même : l'octroi passe par Réglages Système → Confidentialité →
    /// Enregistrement de l'écran (le bandeau de repli l'indique).
    nonisolated static func isPermissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Démarre la capture. Lance une erreur si la permission manque ou si
    /// aucun écran n'est partageable — à l'appelant de retomber sur micro seul.
    func start(onSamples: @escaping ([Float]) -> Void) async throws {
        // Jamais deux flux : un second démarrage orphelinerait le premier
        // SCStream (session d'enregistrement d'écran jamais arrêtée, audio
        // livré deux fois au même callback). Même garde que le micro.
        guard stream == nil else { throw AudioError.alreadyRecording }
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
