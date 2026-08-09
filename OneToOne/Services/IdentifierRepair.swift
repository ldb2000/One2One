import Foundation

/// Réparation d'identifiants dupliqués.
///
/// Un `UUID` non optionnel sur un `@Model` SwiftData reçoit sa valeur au moment de la
/// **migration**, pas à l'insertion : toutes les lignes déjà présentes en base se
/// retrouvent alors avec le même identifiant. On répare les données au démarrage plutôt
/// que de modifier le schéma, qui coûterait une migration de plus.
///
/// Cette fonction ne connaît pas SwiftData : c'est ce qui la rend vérifiable seule.
enum IdentifierRepair {

    /// Les éléments dont l'identifiant doit être réattribué.
    ///
    /// Pour chaque groupe d'identifiants identiques, le **premier rencontré** est
    /// conservé et les suivants sont rendus. L'ordre d'entrée est préservé, de sorte
    /// que deux exécutions sur la même liste réparent exactement les mêmes lignes.
    static func duplicates<Element>(in elements: [Element],
                                    identifier: (Element) -> UUID) -> [Element] {
        var vus = Set<UUID>()
        var aReattribuer: [Element] = []
        for element in elements {
            if vus.insert(identifier(element)).inserted == false {
                aReattribuer.append(element)
            }
        }
        return aReattribuer
    }
}
