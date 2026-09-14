import Foundation

/// Une entrée audio telle que la règle de routage la voit : une valeur, sans
/// identifiant CoreAudio. L'UID est stable pour un même appareil physique
/// (iPhone en Continuité compris) ; le nom est relu à chaque énumération et
/// jamais persisté.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    var id: String { uid }
    let uid: String
    let name: String
    /// Type de transport `kAudioDeviceTransportTypeBuiltIn` : c'est ainsi que
    /// le micro du Mac est reconnu, jamais par son nom (décision D7).
    let isBuiltIn: Bool
    /// Entrée par défaut du système à l'instant de l'énumération.
    let isSystemDefault: Bool
}

/// Ce que le service CoreAudio publie quand la liste des entrées change.
enum AudioInputEvent: Equatable, Sendable {
    case added(uid: String)
    case removed(uid: String)
}
