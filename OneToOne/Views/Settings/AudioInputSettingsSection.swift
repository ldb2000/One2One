import SwiftUI

/// `GroupBox("Entrée audio")` des Réglages (spec §4.5) : le micro préféré,
/// global (D2). La liste vient du service CoreAudio et se met à jour au
/// branchement ; un préféré débranché reste sélectionnable pour ne pas
/// effacer le réglage à son insu.
struct AudioInputSettingsSection: View {

    let settings: AppSettings
    let onSave: () -> Void

    private var service: AudioInputDeviceService { AudioInputDeviceService.shared }

    var body: some View {
        GroupBox("Entrée audio") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Micro préféré", selection: Binding(
                    get: { settings.preferredAudioInputUID },
                    set: { settings.preferredAudioInputUID = $0; onSave() }
                )) {
                    Text("Par défaut du système").tag(AudioInputRouting.systemDefaultUID)
                    ForEach(service.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if prefereAbsent {
                        Text("Micro débranché (\(settings.preferredAudioInputUID))")
                            .tag(settings.preferredAudioInputUID)
                    }
                }
                Text("Utilisé au démarrage de chaque enregistrement. S'il est débranché, l'application propose une autre source ; s'il se déconnecte en cours de réunion, elle bascule sur le micro du Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
        .onAppear { service.refresh() }
    }

    private var prefereAbsent: Bool {
        let uid = settings.preferredAudioInputUID
        return uid != AudioInputRouting.systemDefaultUID && !service.devices.contains { $0.uid == uid }
    }
}
