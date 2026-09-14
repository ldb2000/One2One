// OneToOne/Views/Meeting/Capture/RecordingPromptSheets.swift
import SwiftUI

/// Les deux feuilles du démarrage d'enregistrement, en un modificateur : la
/// vue de réunion reste un routeur.
struct RecordingPromptSheets: ViewModifier {
    let screen: MeetingScreenModel
    /// Le second paramètre est `restartAsAppend` : la vue de réunion route
    /// vers le démarrage complémentaire plutôt que vers un démarrage neuf.
    let onUseDevice: (AudioInputDevice, Bool) -> Void
    let onCancelChoice: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { screen.recordingPrompts.audioInputChoice },
                set: { screen.recordingPrompts.audioInputChoice = $0 }
            )) { request in
                AudioInputChoiceSheet(request: request,
                                      onUse: { device in
                                          let asAppend = screen.recordingPrompts.restartAsAppend
                                          screen.recordingPrompts.audioInputChoice = nil
                                          onUseDevice(device, asAppend)
                                      },
                                      onCancel: { screen.recordingPrompts.audioInputChoice = nil; onCancelChoice() })
            }
            .sheet(item: Binding(
                get: { screen.recordingPrompts.permissionHelp },
                set: { screen.recordingPrompts.permissionHelp = $0 }
            )) { kind in
                AudioPermissionHelpSheet(kind: kind) { screen.recordingPrompts.permissionHelp = nil }
            }
    }
}
