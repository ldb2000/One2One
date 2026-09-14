import Foundation

/// Le pop-up de pré-réunion : le micro préféré manque, voici les sources
/// détectées (spec §1, ligne 1). `Identifiable` pour `.sheet(item:)`.
struct AudioInputChoiceRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let missingPreferredUID: String
    let candidates: [AudioInputDevice]

    init(id: UUID = UUID(), missingPreferredUID: String, candidates: [AudioInputDevice]) {
        self.id = id
        self.missingPreferredUID = missingPreferredUID
        self.candidates = candidates
    }
}

/// Les deux feuilles que le démarrage d'enregistrement peut demander. Une
/// ligne dans `MeetingScreenModel`, tout le reste ici (même règle que
/// `CaptureState`).
struct RecordingPromptState: Equatable, Sendable {
    var audioInputChoice: AudioInputChoiceRequest?
    var permissionHelp: AudioPermissionKind?
    /// Le démarrage qui a ouvert la feuille de choix était-il un enregistrement
    /// **complémentaire** ? Sans cette mémoire, le « Utiliser » de la feuille
    /// repartait toujours sur un démarrage neuf : le nouveau WAV remplaçait
    /// `meeting.wavFilePath` et l'enregistrement précédent restait orphelin
    /// sur le disque.
    var restartAsAppend = false
}
