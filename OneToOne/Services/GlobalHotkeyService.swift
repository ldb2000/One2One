import Foundation
import AppKit
import Carbon.HIToolbox

/// Wrapper Carbon `RegisterEventHotKey` pour des raccourcis globaux qui
/// fonctionnent même quand l'app n'a pas le focus, sans demander la
/// permission Accessibility (contrairement à `CGEventTap`).
@MainActor
final class GlobalHotkeyService {

    static let shared = GlobalHotkeyService()

    private struct Binding {
        let id: UInt32
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var bindings: [String: Binding] = [:]   // serialized HotkeySpec → binding
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Enregistre un raccourci. Si un binding existait déjà pour ce `spec`,
    /// remplace son handler. Retourne `true` si l'enregistrement a réussi.
    @discardableResult
    func register(spec: HotkeySpec, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        unregister(spec: spec)

        guard let keyCode = Self.keyCode(forKeyChar: spec.keyChar) else {
            print("[GlobalHotkey] unknown keyChar: \(spec.keyChar)")
            return false
        }
        var modifiers: UInt32 = 0
        if spec.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if spec.modifiers.contains(.option)  { modifiers |= UInt32(optionKey) }
        if spec.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if spec.modifiers.contains(.shift)   { modifiers |= UInt32(shiftKey) }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4F4E4554), id: id)  // 'ONET'

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            print("[GlobalHotkey] register failed for \(spec.serialized): status=\(status)")
            return false
        }

        bindings[spec.serialized] = Binding(id: id, ref: ref, handler: handler)
        return true
    }

    func unregister(spec: HotkeySpec) {
        guard let binding = bindings.removeValue(forKey: spec.serialized) else { return }
        UnregisterEventHotKey(binding.ref)
    }

    func unregisterAll() {
        for (_, binding) in bindings {
            UnregisterEventHotKey(binding.ref)
        }
        bindings.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, theEvent, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hotKeyID)
            DispatchQueue.main.async {
                GlobalHotkeyService.shared.dispatch(id: hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func dispatch(id: UInt32) {
        guard let binding = bindings.values.first(where: { $0.id == id }) else { return }
        binding.handler()
    }

    /// Mapping des chars vers virtual key codes (Carbon).
    private static func keyCode(forKeyChar char: String) -> UInt32? {
        switch char.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "F1": return UInt32(kVK_F1)
        case "F2": return UInt32(kVK_F2)
        case "F3": return UInt32(kVK_F3)
        case "F4": return UInt32(kVK_F4)
        case "F5": return UInt32(kVK_F5)
        case "F6": return UInt32(kVK_F6)
        case "F7": return UInt32(kVK_F7)
        case "F8": return UInt32(kVK_F8)
        case "F9": return UInt32(kVK_F9)
        case "F10": return UInt32(kVK_F10)
        case "F11": return UInt32(kVK_F11)
        case "F12": return UInt32(kVK_F12)
        default: return nil
        }
    }
}
