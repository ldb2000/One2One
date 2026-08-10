import Foundation
import SwiftData

/// Combien d'écrans `MeetingView` sont montés sur une réunion, et laquelle
/// vient d'être supprimée.
///
/// Ce que `MeetingView.isBeingDeleted` ne peut pas porter : c'est un `@State`,
/// il ne protège que **son** instance de vue. Or la même réunion s'ouvre
/// jusqu'à deux fois — dans la pile de navigation de la fenêtre principale et
/// dans la fenêtre autonome `1to1-meeting` (`OneToOneApp`). Deux conséquences,
/// que ce registre coupe :
/// - supprimer pendant qu'un autre écran observe encore le modèle fait
///   crasher SwiftData, et différer d'un tour de boucle n'y change rien
///   puisque l'autre écran, lui, ne se démonte pas ;
/// - le second écran, avec son drapeau resté faux, réindexerait à sa
///   fermeture un modèle disparu, laissant un résultat Spotlight permanent
///   qui n'ouvre rien.
///
/// Contrat d'appel : `screenAppeared` au montage, `screenDisappeared` en
/// **dernier** au démontage (les lectures se font avant, l'écran qui interroge
/// se compte donc lui-même). Le registre oublie une réunion dès que son
/// dernier écran se démonte : rien à purger.
@MainActor
final class MeetingScreenRegistry {

    static let shared = MeetingScreenRegistry()

    private var mountedScreens: [PersistentIdentifier: Int] = [:]
    private var deleted: Set<PersistentIdentifier> = []

    /// Accessible pour les tests, qui veulent un registre à eux.
    init() {}

    func screenAppeared(_ id: PersistentIdentifier) {
        mountedScreens[id, default: 0] += 1
    }

    func screenDisappeared(_ id: PersistentIdentifier) {
        let remaining = (mountedScreens[id] ?? 0) - 1
        if remaining > 0 {
            mountedScreens[id] = remaining
        } else {
            mountedScreens[id] = nil
            deleted.remove(id)
        }
    }

    /// Vrai quand un **autre** écran que l'appelant est monté sur la réunion.
    func isPresentedElsewhere(_ id: PersistentIdentifier) -> Bool {
        (mountedScreens[id] ?? 0) > 1
    }

    /// Consigne qu'un écran a supprimé la réunion. Les autres écrans montés
    /// dessus le liront à leur fermeture.
    func markDeleted(_ id: PersistentIdentifier) {
        deleted.insert(id)
    }

    func isDeleted(_ id: PersistentIdentifier) -> Bool {
        deleted.contains(id)
    }
}
