import Foundation
import SwiftData

/// Les commandes clavier du tableau d'actions du poste de pilotage
/// (spec §2.7 : « Édition inline sur chaque cellule ; `↑↓` navigue, `Espace`
/// coche, `⌥↑↓` réordonne »).
///
/// Fonctions **pures**, hors de toute vue. Deux raisons précises :
///
/// 1. Un réordonnancement n'est vrai que s'il survit au prochain rendu, c'est-à-dire
///    si `sortOrder` a été réécrit d'une manière que `ActionsRailGrouping.triees`
///    relit à l'identique. Déplacer des lignes dans un tableau SwiftUI sans
///    toucher au modèle donne une illusion qui disparaît au premier
///    rafraîchissement — et c'est exactement ce qu'aucun test de vue ne voit.
/// 2. Le focus posé au passage en mode Relire (« champ d'assignation de la
///    première action non assignée », spec §2.2) doit désigner la **même** ligne
///    que le badge « n sans responsable ». Une seule définition de « sans
///    responsable » ici, reprise de `ActionsRailGrouping.aUnPorteur`.
///
/// `@MainActor` comme `ActionsRailGrouping` et `ActionCardEditing` : ces règles
/// lisent le graphe SwiftData de l'écran, qui vit sur le fil principal.
@MainActor
enum ActionsTableCommands {

    // MARK: - Navigation `↑↓`

    /// La ligne à sélectionner après `↑` (`delta = -1`) ou `↓` (`delta = 1`).
    ///
    /// **Bornée, jamais cyclique** : `↓` sur la dernière ligne ne remonte pas en
    /// tête. Un tableau qui reboucle fait perdre le fil de la lecture — on ne
    /// sait plus si l'on descend pour la première ou la deuxième fois — et la
    /// spec ne le demande pas (contrairement au `Tab` d'une carte, qui boucle
    /// entre trois champs, où l'on ne peut pas se perdre).
    ///
    /// - Returns: l'index de la ligne à sélectionner, `nil` si le tableau est
    ///   vide. Une sélection périmée (index hors du tableau après suppression)
    ///   est ramenée dans les bornes plutôt qu'ignorée : sinon le clavier
    ///   paraîtrait mort jusqu'au prochain clic.
    static func indexSuivant(courant: Int?, nombre: Int, delta: Int) -> Int? {
        guard nombre > 0 else { return nil }
        guard let courant else { return delta >= 0 ? 0 : nombre - 1 }
        let borne = min(max(courant, 0), nombre - 1)
        return min(max(borne + delta, 0), nombre - 1)
    }

    // MARK: - Réordonnancement `⌥↑↓`

    /// La permutation d'indices après `⌥↑` / `⌥↓` sur la ligne `index`.
    ///
    /// Rend la nouvelle liste d'indices — `[0, 2, 1, 3]` pour un échange des
    /// lignes 1 et 2 — plutôt que de muter quoi que ce soit : la vue applique,
    /// le test vérifie.
    ///
    /// - Returns: `nil` quand le déplacement sortirait du tableau ou que
    ///   l'index n'y est pas. Un `nil` se traduit par « la touche n'a rien
    ///   fait », pas par un déplacement muet vers la ligne voisine.
    static func permutation(nombre: Int, index: Int, delta: Int) -> [Int]? {
        guard nombre > 1, index >= 0, index < nombre else { return nil }
        let cible = index + delta
        guard cible >= 0, cible < nombre, delta != 0 else { return nil }
        var indices = Array(0..<nombre)
        indices.swapAt(index, cible)
        return indices
    }

    /// Écrit `sortOrder` selon l'ordre des lignes reçues, en `0…n−1`.
    ///
    /// La **normalisation** compte autant que l'ordre : les actions nées du
    /// composeur portent des `sortOrder` négatifs et non contigus
    /// (`ActionComposerService.plancherSortOrder` place à `minimum − 1`).
    /// Réécrire seulement les deux lignes échangées laisserait des égalités,
    /// que `ActionsRailGrouping.triees` tranche alors par échéance puis par
    /// titre — et la ligne déplacée reviendrait à sa place d'origine.
    ///
    /// N'enregistre pas : l'appelant décide quand persister, comme partout
    /// ailleurs dans le rail.
    static func appliquerOrdre(_ lignes: [ActionTask]) {
        for (index, ligne) in lignes.enumerated() {
            ligne.sortOrder = index
        }
    }

    // MARK: - Focus d'assignation

    /// L'index de la première action que personne ne porte, `nil` si toutes le
    /// sont.
    ///
    /// C'est la cible du focus au passage en mode Relire (spec §2.2). La lecture
    /// de « sans responsable » est celle du rail (`ActionsRailGrouping.aUnPorteur`) :
    /// un nom non résolu par l'extraction compte comme un porteur, sinon le
    /// focus tomberait sur une ligne que le badge « n sans responsable » ne
    /// compte pas.
    static func premiereSansResponsable(_ lignes: [ActionTask]) -> Int? {
        lignes.firstIndex { !ActionsRailGrouping.aUnPorteur($0) }
    }

    // MARK: - Repli

    /// Les lignes affichées et le nombre de celles qui restent
    /// (`n autres · tout afficher`, spec §2.7).
    ///
    /// `restantes` ne descend jamais sous zéro : un tableau de trois lignes ne
    /// doit pas annoncer « −2 autres ».
    static func repli(_ lignes: [ActionTask],
                      limite: Int,
                      tout: Bool) -> (visibles: [ActionTask], restantes: Int) {
        guard !tout, limite > 0, lignes.count > limite else {
            return (visibles: lignes, restantes: 0)
        }
        return (visibles: Array(lignes.prefix(limite)),
                restantes: lignes.count - limite)
    }
}
