import Foundation

/// Décide quelle entrée audio utiliser — au démarrage d'un enregistrement et
/// quand l'entrée en cours disparaît (spec §4.1). Fonctions pures : l'appelant
/// fournit la liste des entrées, la règle ne touche jamais CoreAudio.
enum AudioInputRouting {

    /// Valeur du réglage « par défaut du système » : chaîne vide, stockée telle
    /// quelle dans `AppSettings.preferredAudioInputUID`.
    static let systemDefaultUID = ""

    enum StartVerdict: Equatable, Sendable {
        /// `nil` : on laisse macOS choisir l'entrée par défaut.
        case use(uid: String?)
        /// Le préféré manque, d'autres entrées existent : la feuille de choix.
        case askUser(candidates: [AudioInputDevice], missingPreferredUID: String)
        /// Aucune entrée : l'enregistrement ne peut pas démarrer.
        case noInput
    }

    static func resolveStart(preferredUID: String, devices: [AudioInputDevice]) -> StartVerdict {
        guard !devices.isEmpty else { return .noInput }
        guard preferredUID != systemDefaultUID else { return .use(uid: nil) }
        if devices.contains(where: { $0.uid == preferredUID }) { return .use(uid: preferredUID) }
        return .askUser(candidates: devices, missingPreferredUID: preferredUID)
    }

    enum FallbackVerdict: Equatable, Sendable {
        case switchTo(AudioInputDevice)
        case stopRecording
        case ignore
    }

    /// Repli quand `removedUID` disparaît. `devices` est la liste courante ;
    /// le périphérique retiré en est exclu par sécurité, qu'elle soit
    /// rafraîchie ou non. Ordre : micro intégré (D7), puis défaut système,
    /// puis la première entrée restante, sinon l'arrêt.
    static func fallback(removedUID: String, currentUID: String?, devices: [AudioInputDevice]) -> FallbackVerdict {
        guard let currentUID, currentUID == removedUID else { return .ignore }
        let restantes = devices.filter { $0.uid != removedUID }
        if let integre = restantes.first(where: \.isBuiltIn) { return .switchTo(integre) }
        if let defaut = restantes.first(where: \.isSystemDefault) { return .switchTo(defaut) }
        if let premiere = restantes.first { return .switchTo(premiere) }
        return .stopRecording
    }
}
