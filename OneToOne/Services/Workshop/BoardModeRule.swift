import Foundation

/// La règle du sélecteur de mode (spec §7.1) : « Le changement de mode ne
/// convertit pas la planche : il crée une nouvelle planche, **sauf si la
/// planche courante est vide** ».
///
/// Fonction pure, testée avant sa vue : le sélecteur de `WorkshopToolbar` ne
/// fait qu'appliquer le verdict.
enum BoardModeRule {

    enum Outcome: Equatable {
        /// Rien à faire : c'est déjà le mode demandé.
        case unchanged
        /// La planche courante est vide : on change son mode sur place, sans
        /// laisser derrière soi une planche vierge de plus.
        case convertInPlace
        /// La planche courante porte du travail : le nouveau mode ouvre une
        /// nouvelle planche.
        case createNew
    }

    static func outcome(currentMode: BoardMode,
                        requested: BoardMode,
                        isCurrentEmpty: Bool) -> Outcome {
        if currentMode == requested { return .unchanged }
        return isCurrentEmpty ? .convertInPlace : .createNew
    }

    /// Variante qui lit la scène elle-même — le point d'appel n'a pas à savoir
    /// comment on décide qu'une scène est vide.
    static func outcome(currentMode: BoardMode,
                        requested: BoardMode,
                        scene: String) -> Outcome {
        outcome(currentMode: currentMode,
                requested: requested,
                isCurrentEmpty: BoardScene.isEmpty(scene))
    }
}
