import Foundation

/// Alignement et répartition des objets sélectionnés (spec §7.1, mode Schéma).
///
/// **Calculé ici, en Swift, et non délégué au moteur.** L'objet impératif
/// d'Excalidraw 0.18.1 (`excalidrawAPI`) n'expose pas son `actionManager` — il
/// ne porte que `registerAction` — donc ses actions `alignLeft`,
/// `distributeHorizontally`… ne sont pas atteignables depuis le pont. Les
/// recalculer coûte trente lignes, se relit, et **se teste sans WebKit**
/// (plan §8). Le pont ne reçoit qu'un dictionnaire de positions
/// (`moveElements`), appliqué avec capture d'historique pour que `↺` défasse
/// l'alignement comme n'importe quel geste.
enum BoardAlignment {

    /// Les huit opérations de la barre d'alignement.
    enum Operation: String, CaseIterable, Identifiable, Sendable {
        case left
        case horizontalCenter
        case right
        case top
        case verticalCenter
        case bottom
        case distributeHorizontally
        case distributeVertically

        var id: String { rawValue }

        var label: String {
            switch self {
            case .left:                  return "Aligner à gauche"
            case .horizontalCenter:      return "Centrer horizontalement"
            case .right:                 return "Aligner à droite"
            case .top:                   return "Aligner en haut"
            case .verticalCenter:        return "Centrer verticalement"
            case .bottom:                return "Aligner en bas"
            case .distributeHorizontally: return "Répartir horizontalement"
            case .distributeVertically:   return "Répartir verticalement"
            }
        }

        /// Symbole SF du bouton.
        var symbol: String {
            switch self {
            case .left:                   return "align.horizontal.left"
            case .horizontalCenter:       return "align.horizontal.center"
            case .right:                  return "align.horizontal.right"
            case .top:                    return "align.vertical.top"
            case .verticalCenter:         return "align.vertical.center"
            case .bottom:                 return "align.vertical.bottom"
            case .distributeHorizontally: return "arrow.left.and.right"
            case .distributeVertically:   return "arrow.up.and.down"
            }
        }

        /// Répartir, c'est égaliser des intervalles : il en faut **trois** pour
        /// qu'un intervalle existe entre deux autres. Aligner se contente de
        /// deux objets.
        var minimumSelection: Int {
            switch self {
            case .distributeHorizontally, .distributeVertically: return 3
            default: return 2
            }
        }
    }

    /// La position visée d'un objet.
    struct Move: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    /// Un objet de la scène, réduit à sa boîte.
    private struct Box {
        var id: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// Les positions visées, par identifiant d'objet. Vide quand la sélection
    /// est trop courte, quand la scène est illisible, ou quand aucun des
    /// identifiants ne s'y trouve — un alignement qui ne sait pas sur quoi il
    /// porte ne doit rien déplacer.
    static func moves(scene: String,
                      selectedIDs: [String],
                      operation: Operation) -> [String: Move] {
        let boites = boxes(in: scene, ids: selectedIDs)
        guard boites.count >= operation.minimumSelection else { return [:] }

        switch operation {
        case .left:
            let bord = boites.map(\.x).min() ?? 0
            return boites.reduce(into: [:]) { $0[$1.id] = Move(x: bord, y: $1.y) }
        case .right:
            let bord = boites.map(\.maxX).max() ?? 0
            return boites.reduce(into: [:]) { $0[$1.id] = Move(x: bord - $1.width, y: $1.y) }
        case .horizontalCenter:
            let minimum = boites.map(\.x).min() ?? 0
            let maximum = boites.map(\.maxX).max() ?? 0
            let centre = (minimum + maximum) / 2
            return boites.reduce(into: [:]) {
                $0[$1.id] = Move(x: centre - $1.width / 2, y: $1.y)
            }
        case .top:
            let bord = boites.map(\.y).min() ?? 0
            return boites.reduce(into: [:]) { $0[$1.id] = Move(x: $1.x, y: bord) }
        case .bottom:
            let bord = boites.map(\.maxY).max() ?? 0
            return boites.reduce(into: [:]) { $0[$1.id] = Move(x: $1.x, y: bord - $1.height) }
        case .verticalCenter:
            let minimum = boites.map(\.y).min() ?? 0
            let maximum = boites.map(\.maxY).max() ?? 0
            let centre = (minimum + maximum) / 2
            return boites.reduce(into: [:]) {
                $0[$1.id] = Move(x: $1.x, y: centre - $1.height / 2)
            }
        case .distributeHorizontally:
            return distributed(boites, horizontal: true)
        case .distributeVertically:
            return distributed(boites, horizontal: false)
        }
    }

    /// Répartition : les deux extrêmes restent en place, les autres se posent à
    /// intervalles égaux entre eux. On répartit les **blancs**, pas les centres
    /// — c'est ce qu'attend l'œil quand les objets n'ont pas la même largeur.
    private static func distributed(_ boites: [Box], horizontal: Bool) -> [String: Move] {
        let triees = boites.sorted { horizontal ? $0.x < $1.x : $0.y < $1.y }
        let debut = horizontal ? (triees.first?.x ?? 0) : (triees.first?.y ?? 0)
        let fin = horizontal ? (triees.map(\.maxX).max() ?? 0) : (triees.map(\.maxY).max() ?? 0)
        let etendue = fin - debut
        let occupe = triees.reduce(0.0) { $0 + (horizontal ? $1.width : $1.height) }
        let intervalles = Double(triees.count - 1)
        // Des objets qui se chevauchent déjà plus que l'étendue : le blanc
        // serait négatif, on les colle plutôt que de les inverser.
        let blanc = max(0, (etendue - occupe) / intervalles)

        var resultat: [String: Move] = [:]
        var curseur = debut
        for boite in triees {
            resultat[boite.id] = horizontal
                ? Move(x: curseur, y: boite.y)
                : Move(x: boite.x, y: curseur)
            curseur += (horizontal ? boite.width : boite.height) + blanc
        }
        return resultat
    }

    /// Lit la scène et n'en garde que les objets sélectionnés, dans l'ordre de
    /// la scène. Un identifiant inconnu est ignoré : la sélection remontée par
    /// la page peut désigner un objet que la scène sur disque n'a pas encore.
    private static func boxes(in scene: String, ids: [String]) -> [Box] {
        guard !ids.isEmpty,
              let data = scene.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return [] }

        let voulus = Set(ids)
        return elements.compactMap { element in
            guard let id = element["id"] as? String, voulus.contains(id),
                  (element["isDeleted"] as? Bool) != true,
                  let x = (element["x"] as? NSNumber)?.doubleValue,
                  let y = (element["y"] as? NSNumber)?.doubleValue
            else { return nil }
            return Box(id: id,
                       x: x,
                       y: y,
                       width: (element["width"] as? NSNumber)?.doubleValue ?? 0,
                       height: (element["height"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    /// Sérialise les positions pour le pont : `{"id": {"x": …, "y": …}}`.
    static func json(_ moves: [String: Move]) -> String {
        let objet = moves.mapValues { ["x": $0.x, "y": $0.y] }
        guard let data = try? JSONSerialization.data(withJSONObject: objet, options: [.sortedKeys]),
              let texte = String(data: data, encoding: .utf8)
        else { return "{}" }
        return texte
    }
}
