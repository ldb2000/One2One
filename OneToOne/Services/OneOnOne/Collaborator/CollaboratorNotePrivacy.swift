import Foundation
import SwiftData

/// Le geste `Partager la ligne` (capture 5a) et le défaut qui le rend
/// nécessaire — le critère d'acceptation chantier 5 **n° 2** : « aucune note du
/// collaborateur ne devient visible du manager sans un geste explicite sur
/// cette ligne ».
///
/// Pourquoi un service et non une ligne dans la vue : la promesse porte sur ce
/// qui **ne** se produit pas. Une bascule écrite dans le corps d'une `View` ne
/// peut pas être vérifiée autrement qu'en cliquant, et le jour où l'écran
/// gagnerait un « tout partager » personne ne verrait que la promesse est
/// rompue.
///
/// La table de bascule elle-même n'est pas ici : elle vit une seule fois, dans
/// `OneOnOneConfidentiality.toggledPrivacy(_:role:)` (lot 10). Ce qui est ici,
/// c'est **l'unicité du geste**.
@MainActor
enum CollaboratorNotePrivacy {

    /// La visibilité d'une ligne écrite dans cet écran : `private`, sans
    /// exception ni réglage (spec §6.1).
    ///
    /// Redite volontaire de `OneOnOneConfidentiality.defaultVisibility(for:)` :
    /// l'écran n'a pas de bascule de séance — contrairement au 1:1 mené, où les
    /// pilules `Partagé` / `Privé` de l'en-tête déplacent le défaut. Ici la
    /// pilule d'en-tête est un **état**, et cette constante est ce qui le dit.
    static let defaultVisibility: Visibility = .private

    /// Passe **une** ligne en `shared`.
    ///
    /// - Returns: `false` quand rien n'a changé — ligne déjà partagée, ou ligne
    ///   `escalated`. Une ligne montée à la hiérarchie ne redescend pas vers le
    ///   manager par ce geste (D9) : le menu de la ligne sait la ramener à
    ///   `private`, et c'est le seul chemin.
    @discardableResult
    static func shareLine(_ note: MeetingNote, in context: ModelContext?) -> Bool {
        guard note.visibility == .private else { return false }
        note.visibility = .shared
        try? context?.save()
        return true
    }

    /// Le nombre de lignes partagées d'une séance — ce que le test du critère
    /// n° 2 compte, et ce que l'écran peut afficher si le besoin s'en fait
    /// sentir.
    static func sharedCount(_ notes: [MeetingNote]) -> Int {
        notes.filter { $0.visibility == .shared }.count
    }
}
