import Foundation
import Observation

/// Ce que le mode séance plein écran sait de lui-même (spec §2.6, capture
/// `1b-mode-seance.png`).
///
/// Vit à part de `MeetingScreenModel`, qui n'en porte qu'**une ligne**
/// (`var session = SessionFullscreenState()`) : les lots 5, 6 et 10 travaillent
/// en parallèle sur le même modèle, et « ajouter en fin de type » est
/// exactement le geste qui a produit six conflits à l'intégration des lots 2 et
/// 3. Un état par lot dans son propre fichier ne peut pas entrer en conflit
/// avec l'état d'un autre.
///
/// Rien n'est persisté : le plein écran est un geste du moment, et une
/// application qui rouvre en plein écran une réunion terminée la veille se
/// trompe sur l'intention.
@MainActor
@Observable
final class SessionFullscreenState {

    /// Le mode est affiché.
    var isPresented = false

    /// Instant d'entrée dans le mode. Sert d'origine au bloc `CAPTURÉ CETTE
    /// SÉANCE` quand aucun enregistrement ne tourne
    /// (`SessionCapturedSummary.debutDeSeance`).
    var enteredAt: Date?

    /// La confirmation de sortie est affichée (`Esc` pendant un
    /// enregistrement).
    var isConfirmingExit = false

    /// La feuille d'assignation est ouverte (`Assigner maintenant`).
    var isAssigning = false

    /// La question en cours de saisie dans le panneau assistant. Portée ici et
    /// non en `@State` pour la même raison que `pendingNoteText` : la colonne
    /// est détruite à chaque entrée/sortie de plein écran, et une question à
    /// moitié tapée n'a pas à disparaître avec elle.
    var assistantDraft = ""

    /// Entre dans le mode et fixe l'origine du temps de séance.
    func enter(now: Date = Date()) {
        guard !isPresented else { return }
        isPresented = true
        enteredAt = now
        isConfirmingExit = false
    }

    /// Sort du mode. `enteredAt` est conservé : une sortie suivie d'une
    /// rentrée dans la même séance ne doit pas remettre les compteurs à zéro.
    func leave() {
        isPresented = false
        isConfirmingExit = false
        isAssigning = false
    }
}

/// La règle de sortie du mode séance (spec §2.6 : « Sortie du mode : `Esc`
/// demande confirmation si l'enregistrement tourne »).
///
/// Trois lignes de code, et pourtant une machine à états à part : c'est la
/// seule règle du lot dont l'erreur coûte une séance entière. Sortir sans
/// confirmation pendant un enregistrement, c'est le risque de l'arrêter par
/// mégarde ; demander confirmation quand rien ne tourne, c'est un dialogue
/// gratuit sur le geste le plus courant de l'écran.
enum SessionExitPolicy {

    /// Ce que `Esc` déclenche.
    enum Effet: Sendable, Equatable {
        /// On sort tout de suite.
        case sortir
        /// On demande confirmation d'abord.
        case demanderConfirmation
        /// La confirmation est déjà à l'écran : `Esc` la referme sans sortir —
        /// le second `Esc` doit annuler le dialogue, pas le valider.
        case fermerLaConfirmation
    }

    /// L'effet d'un `Esc`.
    static func escape(isRecording: Bool, isConfirming: Bool) -> Effet {
        if isConfirming { return .fermerLaConfirmation }
        return isRecording ? .demanderConfirmation : .sortir
    }

    /// Le message du dialogue, exactement celui qu'on veut lire avant de
    /// perdre une séance.
    static let confirmationTitre = "Quitter le mode séance ?"
    static let confirmationMessage = """
    L'enregistrement continue en arrière-plan. Tu retrouveras la réunion \
    en mode En séance, avec ses notes et sa transcription.
    """
}
