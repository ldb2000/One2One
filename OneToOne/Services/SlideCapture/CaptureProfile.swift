import Foundation

/// Les trois réglages de capture qu'un **type de réunion** impose par défaut
/// (spec §5.1 : « bascule par défaut activée » — mais pas pour tous les types).
///
/// Copié de `CaptureCore/MeetingType.swift` du dépôt Teams-Capture
/// (programme §2.5, décision D7), transposé sur `MeetingKind` : `work` y est
/// « Architecture » et `manager` « 1:1 Manager ».
///
/// Invariant, vérifié par test : `periodicCapture` n'a de sens qu'avec
/// `detectsAutomatically`. Une capture périodique attend un tick **stable**
/// pour écrire, et c'est le détecteur qui dit si l'image est stable — sans
/// détection, l'échéance ne saurait jamais quand écrire.
struct CaptureProfile: Equatable, Sendable {

    let sensitivity: SlideCaptureSettings.Sensitivity
    /// Le détecteur écrit-il de lui-même quand le contenu se stabilise ?
    /// C'est la bascule « Capturer à chaque changement de partage ».
    let detectsAutomatically: Bool
    /// Intervalle de capture forcée, ou `nil` (bascule « Toutes les 2 minutes »).
    let periodicCapture: Duration?

    init(sensitivity: SlideCaptureSettings.Sensitivity,
         detectsAutomatically: Bool,
         periodicCapture: Duration? = nil) {
        self.sensitivity = sensitivity
        self.detectsAutomatically = detectsAutomatically
        self.periodicCapture = periodicCapture
    }
}

extension MeetingKind {

    /// Réglages appliqués quand la capture s'ouvre sur une réunion de ce type.
    var captureProfile: CaptureProfile {
        switch self {
        case .global, .project:
            return CaptureProfile(sensitivity: .normal, detectsAutomatically: true)
        case .oneToOne, .manager, .note:
            return CaptureProfile(sensitivity: .low, detectsAutomatically: false)
        case .work:
            return CaptureProfile(sensitivity: .high, detectsAutomatically: true)
        case .workshop:
            return CaptureProfile(sensitivity: .high,
                                  detectsAutomatically: true,
                                  periodicCapture: .seconds(120))
        }
    }

    /// Pourquoi ces défauts. Affiché sous les bascules du sélecteur : un défaut
    /// qu'on ne s'explique pas est un défaut qu'on désactive au hasard.
    var captureHint: String {
        switch self {
        case .global, .project:
            return "Réglage de référence : une capture est écrite dès qu'un partage se stabilise."
        case .oneToOne, .manager:
            return "Pas de slides attendus : rien n'est capturé sans votre geste (⌘⇧S)."
        case .note:
            return "Capture purement manuelle : la fenêtre est surveillée, vous décidez quand écrire."
        case .work:
            return "Sensibilité élevée : sur un schéma, les changements sont ténus."
        case .workshop:
            return "Une planche évolue sans jamais se stabiliser franchement : une capture est forcée toutes les 2 minutes."
        }
    }
}
