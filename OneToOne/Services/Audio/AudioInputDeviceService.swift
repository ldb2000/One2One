// OneToOne/Services/Audio/AudioInputDeviceService.swift
import CoreAudio
import Foundation
import Observation
import os

private let inputLog = Logger(subsystem: "com.onetoone.app", category: "audio-input")

/// Ce que le coordinateur d'enregistrement attend d'un fournisseur d'entrées
/// audio. Doublé en test ; en production, `AudioInputDeviceService.shared`.
@MainActor
protocol AudioInputDeviceProviding: AnyObject {
    var devices: [AudioInputDevice] { get }
    /// Relit la liste maintenant. Idempotent.
    func refresh()
    /// Un flux par abonné ; se termine quand l'abonné lâche le flux.
    func events() -> AsyncStream<AudioInputEvent>
}

/// Énumère les entrées audio du Mac et observe leurs branchements. Il **ne
/// décide rien** : la règle est dans `AudioInputRouting`, l'exécution dans
/// `AudioRecorderService`.
@MainActor
@Observable
final class AudioInputDeviceService: AudioInputDeviceProviding {

    static let shared = AudioInputDeviceService()

    private(set) var devices: [AudioInputDevice] = []

    @ObservationIgnored private var continuations: [UUID: AsyncStream<AudioInputEvent>.Continuation] = [:]
    @ObservationIgnored private var isObserving = false

    init() {
        refresh()
    }

    // MARK: - AudioInputDeviceProviding

    func refresh() {
        let nouvelles = Self.enumerateInputDevices()
        let anciens = Set(devices.map(\.uid))
        let recents = Set(nouvelles.map(\.uid))
        devices = nouvelles
        for uid in anciens.subtracting(recents) { broadcast(.removed(uid: uid)) }
        for uid in recents.subtracting(anciens) { broadcast(.added(uid: uid)) }
    }

    func events() -> AsyncStream<AudioInputEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    /// Pose les écouteurs CoreAudio. À appeler une fois, au lancement de l'app
    /// (`AppDelegate`) ; un second appel est sans effet.
    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            Task { @MainActor in AudioInputDeviceService.shared.refresh() }
        }
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddress, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultAddress, DispatchQueue.main, block)
    }

    private func broadcast(_ event: AudioInputEvent) {
        inputLog.info("AudioInput: \(String(describing: event), privacy: .public)")
        for continuation in continuations.values { continuation.yield(event) }
    }

    // MARK: - CoreAudio (nonisolated, sans état)

    nonisolated static func enumerateInputDevices() -> [AudioInputDevice] {
        let defaut = defaultInputDeviceID()
        return allDeviceIDs()
            .filter { inputStreamCount($0) > 0 }
            .compactMap { id -> AudioInputDevice? in
                guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                      let name = stringProperty(id, kAudioObjectPropertyName) else { return nil }
                return AudioInputDevice(uid: uid,
                                        name: name,
                                        isBuiltIn: transportType(id) == kAudioDeviceTransportTypeBuiltIn,
                                        isSystemDefault: id == defaut)
            }
    }

    nonisolated static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    nonisolated static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private nonisolated static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func inputStreamCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private nonisolated static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else { return 0 }
        return type
    }

    private nonisolated static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
