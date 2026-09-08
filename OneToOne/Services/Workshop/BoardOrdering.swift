import Foundation

/// Ordre des planches dans la séance : `Board.index` est le rang affiché
/// (`Planche n sur m`), et le dock permet de glisser pour réordonner.
///
/// Toutes ces fonctions sont **pures sur la relation** : elles renumérotent des
/// objets déjà chargés, sans toucher au contexte SwiftData ni au disque. Le
/// point d'appel enregistre.
enum BoardOrdering {

    /// Les planches d'une réunion, triées par `index` puis par timecode — deux
    /// planches au même index (import, restauration) restent dans un ordre
    /// stable plutôt que dans l'ordre d'arrivée de la relation.
    static func sorted(_ boards: [Board]) -> [Board] {
        boards.sorted {
            $0.index == $1.index ? $0.t < $1.t : $0.index < $1.index
        }
    }

    /// Renumérote `index` de 0 à n-1 dans l'ordre donné. Après une suppression
    /// ou un glisser, les rangs doivent redevenir contigus : « Planche 3 sur 4 »
    /// n'a pas de sens si les index sont 0, 1, 3, 7.
    static func reindex(_ boards: [Board]) {
        for (rang, planche) in boards.enumerated() where planche.index != rang {
            planche.index = rang
        }
    }

    /// Nouvel ordre après un glisser du dock. `offsets`/`destination` sont ceux
    /// que SwiftUI passe à `onMove`.
    @discardableResult
    static func move(_ boards: [Board], from offsets: IndexSet, to destination: Int) -> [Board] {
        var ordonnees = sorted(boards)
        ordonnees.move(fromOffsets: offsets, toOffset: destination)
        reindex(ordonnees)
        return ordonnees
    }

    /// Nouvel ordre après suppression, avec renumérotation.
    @discardableResult
    static func removing(_ board: Board, from boards: [Board]) -> [Board] {
        let identifiant = board.stableID
        let restantes = sorted(boards).filter { $0.stableID != identifiant || identifiant == nil }
        reindex(restantes)
        return restantes
    }

    /// Titre par défaut d'une nouvelle planche : « Planche 3 » pour la
    /// troisième. Un titre vide dans le dock se lirait comme un défaut.
    static func defaultTitle(forIndex index: Int) -> String {
        "Planche \(index + 1)"
    }

    /// Titre d'une copie. La spec ne le fixe pas ; « (copie) » est la
    /// convention de macOS et se distingue à la lecture du dock.
    static func copyTitle(of title: String) -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "Planche (copie)" : "\(base) (copie)"
    }

    /// Prépare la planche qui suit `board` : même mode, même auteur, timecode
    /// courant, index juste après. La scène est copiée par `BoardStore`.
    static func duplicate(_ board: Board, at t: Double) -> Board {
        Board(index: board.index + 1,
              title: copyTitle(of: board.title),
              mode: board.mode,
              t: t,
              authorNames: board.authorNames)
    }

    /// Insère `nouvelle` juste après `index` dans la liste et renumérote.
    @discardableResult
    static func insert(_ nouvelle: Board, after index: Int, in boards: [Board]) -> [Board] {
        var ordonnees = sorted(boards).filter { $0 !== nouvelle }
        let position = min(max(0, index + 1), ordonnees.count)
        ordonnees.insert(nouvelle, at: position)
        reindex(ordonnees)
        return ordonnees
    }

    /// Libellé du compteur de la barre d'outils : « Planche 3 sur 4 ».
    static func counterLabel(index: Int, total: Int) -> String {
        "Planche \(index + 1) sur \(max(total, index + 1))"
    }

    /// Libellé de fraîcheur : « dernière modif. il y a 12 s ». Pur pour être
    /// testable ; la vue le rafraîchit par `TimelineView`.
    static func freshnessLabel(updatedAt: Date, now: Date) -> String {
        let secondes = max(0, now.timeIntervalSince(updatedAt))
        if secondes < 60 {
            return "dernière modif. il y a \(Int(secondes)) s"
        }
        let minutes = Int(secondes / 60)
        if minutes < 60 {
            return "dernière modif. il y a \(minutes) min"
        }
        let heures = minutes / 60
        return "dernière modif. il y a \(heures) h"
    }
}
