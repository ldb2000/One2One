import Foundation
@testable import OneToOne

/// Fournisseur d'entrées scripté : la liste est posée par le test, les
/// événements sont injectés à la main.
@MainActor
final class FakeAudioInputDevices: AudioInputDeviceProviding {
    var devices: [AudioInputDevice]
    var refreshCount = 0
    var terminatedCount = 0
    private var continuations: [AsyncStream<AudioInputEvent>.Continuation] = []

    init(devices: [AudioInputDevice]) { self.devices = devices }

    func refresh() { refreshCount += 1 }

    func events() -> AsyncStream<AudioInputEvent> {
        AsyncStream { continuation in
            self.continuations.append(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.terminatedCount += 1 }
            }
        }
    }

    func emit(_ event: AudioInputEvent) { continuations.forEach { $0.yield(event) } }
}

/// Recorder scripté : enregistre les appels, peut échouer à la bascule.
@MainActor
final class FakeRecorder: RecordingInputSwitching {
    var isRecording = true
    var currentInputUID: String?
    var onInputInterrupted: (@MainActor () -> Void)?
    var switchedTo: [AudioInputDevice?] = []
    var stopCount = 0
    var switchShouldFail = false

    struct SwitchFailed: Error {}

    func switchInput(to device: AudioInputDevice?) throws {
        if switchShouldFail { throw SwitchFailed() }
        switchedTo.append(device)
        currentInputUID = device?.uid
    }

    func stopForInputLoss() { stopCount += 1; isRecording = false }
}

@MainActor
final class FakeNotifier: RecordingNotifying {
    var fallbackNames: [String] = []
    var teamsMissingCount = 0
    func notifyAudioInputFallback(deviceName: String) { fallbackNames.append(deviceName) }
    func notifyTeamsFlowMissing() { teamsMissingCount += 1 }
}
