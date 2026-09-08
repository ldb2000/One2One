import Foundation

/// Les pilules **visibles en permanence** sous le composeur, par type de
/// réunion et par rôle (spec §2.4 : « les commandes `/` visibles en permanence,
/// pas de découverte cachée »).
///
/// Pourquoi une fonction et non une liste : les captures ne montrent pas les
/// mêmes pilules selon l'écran — `/engagement /feedback /privé` côté manager
/// (2a), `/promesse /demande /preuve` côté collaborateur (5a), et les quatre du
/// lot 2 partout ailleurs. Une liste unique afficherait dix pilules dont sept
/// hors sujet, ce qui est une autre façon de cacher les trois qui comptent.
///
/// Pur et sans état : le câblage dans le composeur appartient aux lots 11 à 14
/// (`Views/Meeting/Spaces/Notes/**` n'est pas modifié par le lot 10).
enum NoteCommandCatalog {

    /// Une pilule du composeur : soit une commande du parseur de base, soit une
    /// commande propre au 1:1.
    enum Entry: Equatable, Sendable, Identifiable {
        case base(NoteCommandParser.Command)
        case oneOnOne(NoteCommandParser.OneOnOneCommand)

        var pill: String {
            switch self {
            case let .base(commande):     return commande.pill
            case let .oneOnOne(commande): return commande.pill
            }
        }

        var id: String { pill }
    }

    /// Les pilules à afficher.
    ///
    /// - Parameters:
    ///   - kind: le type de la réunion ouverte.
    ///   - role: le rôle du fil, quand il y en a un. **Il prime sur le type** :
    ///     c'est le rôle qui dit ce que j'ai le droit d'écrire, et une réunion
    ///     mal typée à l'import ne doit pas m'ouvrir le composeur du manager.
    static func commands(for kind: MeetingKind, role: OneOnOneSide?) -> [Entry] {
        let effectif = role ?? OneOnOneThreadStore.role(for: kind)
        switch effectif {
        case .manager:
            return [.oneOnOne(.engagement), .base(.feedback), .base(.secret)]
        case .collaborator:
            return [.base(.promise), .base(.request), .base(.proof)]
        case nil:
            return NoteCommandParser.visiblePills.map(Entry.base)
        }
    }
}
