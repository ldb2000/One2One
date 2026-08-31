import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

private let sysAudioLog = Logger(subsystem: "com.onetoone.app", category: "system-audio")

/// Boîte verrouillée autour du callback d'échantillons.
///
/// Les blocs capturés sont livrés **directement depuis la file `SCStream`**.
/// Le détour par le main actor (un `Task { @MainActor in … }` par bloc) coûtait
/// un saut de contexte par bloc et, si le main thread bouchonnait, les blocs
/// système arrivaient en rafale une fois le bouchon résorbé : le débit entrant
/// redevenant égal au débit sortant, le retard ne se résorbait plus jamais et
/// la voix distante restait décalée (jusqu'au plafond de 2 s du reliquat) pour
/// tout le reste de l'enregistrement.
///
/// Le callback, lui, est posé par `start` et retiré par `stop`, tous deux sur
/// le main actor : c'est cette seule référence qui a besoin d'un verrou.
/// `deliver` appelle **sous verrou**, ce qui préserve la garantie de `stop()` :
/// aucun callback ne s'exécute après son retour. En contrepartie le callback
/// doit rester non bloquant — le nôtre se contente d'un `queue.async` sur la
/// file du `TapSink`.
private final class SampleHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable ([Float]) -> Void)?

    func set(_ handler: (@Sendable ([Float]) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
    }

    func deliver(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        handler?(samples)
    }
}

/// Capture l'audio système via `ScreenCaptureKit`, sans vidéo. C'est la seconde
/// piste d'une réunion Teams : ce que disent les participants distants.
///
/// La permission d'enregistrement d'écran est requise. Si elle manque, `start`
/// échoue proprement et l'appelant continue en micro seul (spec D-6) : cette
/// classe ne notifie pas l'utilisateur elle-même.
@MainActor
final class SystemAudioCapture: NSObject, SCStreamOutput {

    /// Appelée à chaque bloc capturé, en 16 kHz mono. Posée et retirée depuis
    /// le main actor, appelée depuis la file `SCStream` : d'où la boîte
    /// verrouillée plutôt qu'une simple propriété.
    private let handler = SampleHandlerBox()
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
    ///
    /// `onSamples` est appelée depuis la file de capture, pas depuis le main
    /// actor : elle doit être `@Sendable` et ne jamais bloquer.
    func start(onSamples: @escaping @Sendable ([Float]) -> Void) async throws {
        // Jamais deux flux : un second démarrage orphelinerait le premier
        // SCStream (session d'enregistrement d'écran jamais arrêtée, audio
        // livré deux fois au même callback). Même garde que le micro.
        guard stream == nil else { throw AudioError.alreadyRecording }
        handler.set(onSamples)
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

    /// Arrête la capture. Idempotent. Le callback est retiré **avant** tout
    /// `await` : une fois `set(nil)` rendu, plus aucune livraison ne peut
    /// atteindre un sink déjà terminé (`deliver` appelle sous le même verrou,
    /// donc une livraison en vol est attendue, jamais doublée).
    func stop() async {
        guard let stream else { return }
        self.stream = nil
        handler.set(nil)
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
        // Livraison directe, sur la file de capture : voir `SampleHandlerBox`
        // pour pourquoi le saut par le main actor a été supprimé.
        handler.deliver(samples)
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
