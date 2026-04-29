import SwiftUI
import SwiftData
import AppKit

/// Section de la fenêtre Settings pour configurer:
/// 1. Le raccourci d'ouverture du picker overlay (`⌃⌥⌘1` par défaut).
/// 2. Un raccourci individuel par collaborateur épinglé (pinLevel ≥ 1).
struct SettingsHotkeysSection: View {
    @Query(filter: #Predicate<Collaborator> { $0.pinLevel >= 1 && !$0.isArchived },
           sort: \Collaborator.name) private var pinnedCollabs: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context

    private var settings: AppSettings? { settingsList.canonicalSettings }

    var body: some View {
        Section("Raccourcis 1:1") {
            HStack {
                Label("Ouvrir le sélecteur 1:1", systemImage: "magnifyingglass")
                Spacer()
                HotkeyCaptureField(
                    keyspec: Binding(
                        get: { settings?.collaboratorHotkeys["__overlay__"] ?? "⌃⌥⌘1" },
                        set: { newValue in setHotkey("__overlay__", to: newValue) }
                    )
                )
            }

            if pinnedCollabs.isEmpty {
                Text("Épingle un collaborateur dans la sidebar pour lui assigner un raccourci.")
                    .font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(pinnedCollabs) { collab in
                    HStack {
                        Image(systemName: "person.crop.circle").foregroundColor(.accentColor)
                        Text(collab.name)
                        Spacer()
                        HotkeyCaptureField(
                            keyspec: Binding(
                                get: { settings?.collaboratorHotkeys[collab.ensuredStableID.uuidString] ?? "" },
                                set: { newValue in setHotkey(collab.ensuredStableID.uuidString, to: newValue) }
                            )
                        )
                    }
                }
            }
        }
    }

    private func setHotkey(_ key: String, to newValue: String) {
        guard let settings else { return }
        var map = settings.collaboratorHotkeys
        if newValue.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = newValue
        }
        settings.collaboratorHotkeys = map
        try? context.save()
        NotificationCenter.default.post(name: .collaboratorHotkeysChanged, object: nil)
    }
}

extension Notification.Name {
    static let collaboratorHotkeysChanged = Notification.Name("collaboratorHotkeysChanged")
}

/// Champ qui capture la prochaine combinaison de touches et la sérialise via
/// `HotkeySpec`. Clic = mode capture; Échap pendant capture = clear.
struct HotkeyCaptureField: View {
    @Binding var keyspec: String
    @State private var capturing = false

    var body: some View {
        Button {
            capturing.toggle()
            if capturing { startMonitoring() }
        } label: {
            Text(capturing ? "Tape la combinaison..." : (keyspec.isEmpty ? "—" : keyspec))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 140, alignment: .center)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(capturing ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Clic pour modifier; Échap pour effacer")
    }

    private func startMonitoring() {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            defer { if !capturing, let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }

            if event.keyCode == 0x35 {  // Esc
                keyspec = ""
                capturing = false
                return nil
            }

            var mods: Set<HotkeySpec.Modifier> = []
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            if event.modifierFlags.contains(.option)  { mods.insert(.option) }
            if event.modifierFlags.contains(.control) { mods.insert(.control) }
            if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }

            guard !mods.isEmpty, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
                return event
            }
            let spec = HotkeySpec(modifiers: mods, keyChar: chars)
            keyspec = spec.serialized
            capturing = false
            return nil
        }
    }
}
