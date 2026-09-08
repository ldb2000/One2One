import Foundation

/// Un objet de planche marqué **question** ou **risque** (spec §7.2 : la
/// section `SUR CETTE PLANCHE` « liste des éléments annotés comme
/// question/risque »).
///
/// L'annotation vit dans `customData` de l'élément Excalidraw. C'est le seul
/// champ que le moteur transporte sans y toucher : elle survit à la
/// sauvegarde, à la duplication d'une planche et à l'export `.excalidraw`. La
/// poser passe par le pont (`setSelectionKind`) ; la relire est **pur**, donc
/// testable sans WebKit (plan §8).
struct BoardAnnotation: Identifiable, Equatable, Sendable {

    /// Les deux natures de la spec. Valeurs brutes écrites dans la scène : ne
    /// pas les renommer, des planches déjà enregistrées les portent.
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case question = "question"
        case risk     = "risk"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .question: return "Question"
            case .risk:     return "Risque"
            }
        }

        /// Entrée du menu contextuel de la toile.
        var menuLabel: String {
            switch self {
            case .question: return "Marquer comme question"
            case .risk:     return "Marquer comme risque"
            }
        }
    }

    /// Clé de `customData`. Préfixée : `customData` est un espace partagé, et
    /// une clé `kind` nue entrerait en conflit avec n'importe quel autre outil
    /// qui lirait la même scène.
    static let customDataKey = "one2oneKind"

    /// Identifiant de l'élément annoté — c'est lui qu'on resélectionne quand on
    /// clique la ligne du dock.
    var id: String
    var kind: Kind
    /// Le libellé de l'objet, tel qu'il s'affiche dans la liste et tel que
    /// `＋ Action depuis la sélection` le reprend.
    var text: String

    /// Les objets annotés d'une scène, **dans l'ordre de la scène** — celui du
    /// dock. Une scène illisible en rend zéro : le dock affiche alors sa
    /// section vide, la planche n'est pas perdue pour autant.
    static func list(in scene: String) -> [BoardAnnotation] {
        guard let data = scene.data(using: .utf8),
              let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = objet["elements"] as? [[String: Any]]
        else { return [] }

        // Le texte d'une boîte vit dans un élément lié (`containerId`), pas
        // dans la boîte : on indexe une fois plutôt que de rebalayer par objet.
        var textesLies: [String: String] = [:]
        for element in elements where (element["type"] as? String) == "text" {
            guard let conteneur = element["containerId"] as? String,
                  let texte = element["text"] as? String
            else { continue }
            textesLies[conteneur] = texte
        }

        return elements.compactMap { element in
            guard (element["isDeleted"] as? Bool) != true,
                  let id = element["id"] as? String,
                  let custom = element["customData"] as? [String: Any],
                  let brut = custom[customDataKey] as? String,
                  let nature = Kind(rawValue: brut)
            else { return nil }
            let propre = (element["text"] as? String) ?? ""
            let texte = propre.isEmpty ? (textesLies[id] ?? "") : propre
            return BoardAnnotation(id: id, kind: nature, text: texte)
        }
    }
}
