import Foundation

/// Ce qui, dans la barre latérale, fait apparaître ou disparaître une ligne.
///
/// Deux empreintes différentes = la `List` ne contient plus les mêmes lignes,
/// donc l'index de sélection que `NSTableView` conserve ne désigne plus la
/// même chose. C'est le signal que `SidebarSelectionGuard` attend pour se
/// méfier d'une écriture de sélection.
///
/// **Des comptes et des drapeaux, pas les objets.** Un `Equatable` sur les
/// modèles se recalculerait à chaque sauvegarde du contexte ; ici, seule une
/// ligne qui naît ou meurt change l'empreinte. Renommer un projet n'en change
/// aucune, et c'est voulu — renommer ne déplace pas la sélection.
struct SidebarRowsFingerprint: Equatable, Sendable {
    var projetsActifs: Int
    var projetsArchives: Int
    var projetsEpingles: Int
    var collaborateursActifs: Int
    var collaborateursArchives: Int
    var entites: Int
    var recherche: String
    var sectionProjetsDepliee: Bool
    var arbreDeplie: Bool
    var collaborateursDeplies: Bool
    var archivesDepliees: Bool
    var projetsArchivesDeplies: Bool
}

/// Le garde-fou qui empêche `List(selection:)` de réécrire la route de la
/// fenêtre principale sans que l'utilisateur ait rien demandé.
///
/// ## Le défaut qu'il corrige
///
/// La barre latérale était une `List(selection: $mainRouter.route)` : le
/// binding de sélection **était** la route. Or `NSTableView`, sous une `List`
/// SwiftUI, conserve un **index** de ligne sélectionnée. Quand l'ensemble des
/// lignes change — un semis qui ajoute soixante-deux projets, une sous-section
/// « ÉPINGLÉS » ou « RÉCENTS » qui apparaît, un groupe « Projets Archivés » qui
/// se déplie, une recherche qui filtre —, l'index est conservé et retraduit en
/// **tag d'une autre ligne**, que SwiftUI écrit alors dans le binding. La route
/// change, et l'écran affiché avec elle.
///
/// Observé deux fois à la recette du 2026-09-09 : `p1a` a photographié la fiche
/// du premier projet archivé au lieu du Portfolio, `p1c` celle de `P25_155`
/// alors que la route demandée était `.portfolio`. Ce n'est pas un défaut de
/// recette : tout utilisateur dont les lignes bougent — import xlsx, épinglage
/// depuis la palette, frappe dans le champ de recherche — est dérouté de la
/// même façon, sans rien avoir cliqué.
///
/// ## La règle
///
/// La `List` sélectionne un `@State` **local** ; la route n'est écrite que si
/// le changement de sélection vient d'une action de l'utilisateur. Sinon le
/// `@State` est **restauré** depuis la route, ce qui remet aussi la
/// surbrillance à sa place.
///
/// Deux conditions, et il faut les deux (`estUneSelectionUtilisateur`) :
///
/// 1. **La liste a le focus.** Une `List` ne prend le focus que si on a cliqué
///    dedans ou tabulé jusqu'à elle — c'est la preuve la moins chère qu'un
///    humain est aux commandes, et la seule qui couvre `↑`/`↓` : la navigation
///    clavier de `NSTableView` ne remonte pas jusqu'à un `onKeyPress` de la
///    vue SwiftUI, donc un drapeau armé par les touches raterait les flèches.
/// 2. **Les lignes n'ont pas changé à l'instant.** Le focus seul ne suffit
///    pas : épingler un projet depuis la palette pendant que la barre latérale
///    a le focus fait bouger les lignes sans qu'on ait touché à la barre. Le
///    délai est court — un humain ne clique pas une ligne dans les trois
///    dixièmes de seconde qui suivent son apparition, et s'il le fait, sa
///    sélection est simplement ignorée une fois.
///
/// Une liste blanche (le focus) **et** une liste noire (le changement de
/// lignes) : chacune couvre le trou de l'autre.
enum SidebarSelectionGuard {

    /// Délai pendant lequel une écriture de sélection est refusée après un
    /// changement de la composition des lignes.
    static let delaiApresChangementDeLignes: TimeInterval = 0.3

    /// Ce que la vue doit faire d'un changement de sélection.
    ///
    /// Trois cas et non un `MainRoute?` : « ne rien faire parce que la
    /// sélection est déjà juste » et « ne rien faire **et** remettre la
    /// sélection en place » sont deux réponses différentes, et les confondre
    /// ferait soit clignoter la surbrillance, soit la laisser sur une ligne
    /// que l'écran n'affiche pas — le symptôme même qu'on corrige.
    enum Decision: Equatable, Sendable {
        /// Ouvrir cette route : l'utilisateur a choisi une ligne.
        case ouvrir(MainRoute)
        /// Rien à faire : la sélection dit déjà ce que la route dit.
        case ignorer
        /// Écriture non sollicitée : remettre la sélection sur la route.
        case restaurer
    }

    /// Que faire du passage de `ancienne` à `nouvelle` ?
    ///
    /// - Parameters:
    ///   - ancienne: la sélection d'avant, pour reconnaître un non-changement.
    ///   - nouvelle: ce que la `List` vient d'écrire. `nil` = désélection.
    ///   - routeCourante: ce que le routeur affiche à cet instant.
    ///   - utilisateur: le résultat d'`estUneSelectionUtilisateur`.
    static func decide(ancienne: MainRoute?,
                       nouvelle: MainRoute?,
                       routeCourante: MainRoute?,
                       utilisateur: Bool) -> Decision {
        // Rien n'a bougé : le cas ne devrait pas arriver (`onChange` compare
        // avant d'appeler), mais un appel redondant ne doit rien casser.
        if ancienne == nouvelle && nouvelle == routeCourante { return .ignorer }

        // Désélection. `List(selection:)` en écrit une quand la ligne
        // sélectionnée disparaît — et un écran vide n'est pas une destination.
        guard let nouvelle else { return .restaurer }

        // La sélection rattrape simplement la route (c'est la synchronisation
        // descendante qui vient de l'écrire) : il n'y a rien à ouvrir, et rien
        // à restaurer non plus.
        if nouvelle == routeCourante { return .ignorer }

        return utilisateur ? .ouvrir(nouvelle) : .restaurer
    }

    /// Le changement de sélection vient-il d'une action de l'utilisateur ?
    ///
    /// - Parameters:
    ///   - listeFocalisee: la `List` a le focus clavier.
    ///   - lignesChangeesIlYA: secondes écoulées depuis le dernier changement
    ///     de `SidebarRowsFingerprint`, ou `nil` s'il n'y en a jamais eu.
    static func estUneSelectionUtilisateur(
        listeFocalisee: Bool,
        lignesChangeesIlYA: TimeInterval?,
        delai: TimeInterval = delaiApresChangementDeLignes
    ) -> Bool {
        guard listeFocalisee else { return false }
        guard let lignesChangeesIlYA else { return true }
        // Un délai négatif (horloge qui recule, date future) est traité comme
        // « à l'instant » : dans le doute, on refuse d'écrire la route.
        return lignesChangeesIlYA >= delai
    }
}
