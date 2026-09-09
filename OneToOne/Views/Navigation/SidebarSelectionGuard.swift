import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// L'événement que l'application traite au moment où la `List` écrit sa
/// sélection — le discriminant de `SidebarSelectionGuard`.
///
/// Une valeur, et non un `NSEvent` : la règle doit se tester sans fenêtre ni
/// boucle d'événements. L'adaptateur `courant()` est le seul point de contact
/// avec AppKit, et il tient en dix lignes sans branche métier.
struct EvenementEntree: Equatable, Sendable {

    /// Ce que l'événement est, du seul point de vue qui compte ici : est-ce un
    /// geste de l'utilisateur ?
    enum Nature: Equatable, Sendable {
        /// Clic — `leftMouseDown`, `leftMouseUp`, `rightMouseDown`,
        /// `otherMouseDown`.
        case souris
        /// Touche — `keyDown` (les flèches et `⏎` de la navigation de liste).
        case clavier
        /// Tout le reste : `appKitDefined`, `periodic`, `systemDefined`,
        /// mouvements de souris… Un remappage de lignes survient sous ceux-là,
        /// jamais sous un clic.
        case autre
    }

    /// Âge maximal d'un événement pour qu'une sélection lui soit imputée.
    ///
    /// `NSApp.currentEvent` **retient le dernier événement traité** quand la
    /// pile d'appel n'en traite plus aucun : sans borne d'âge, un clic vieux
    /// de vingt secondes autoriserait le remappage qu'a produit le
    /// redimensionnement de la recette `p1f`. Une seconde est large pour une
    /// sélection provoquée par un clic, et courte devant ce délai-là.
    static let ageMaximal: TimeInterval = 1

    var nature: Nature
    /// Secondes écoulées depuis l'événement.
    var age: TimeInterval

    /// Un geste d'utilisateur, et récent.
    var estUneEntreeRecente: Bool {
        guard nature != .autre else { return false }
        // Un âge négatif (horloge qui recule, horodatage futur) est refusé :
        // dans le doute, on n'écrit pas la route.
        return age >= 0 && age <= Self.ageMaximal
    }
}

#if canImport(AppKit)
extension EvenementEntree {

    /// L'événement que l'application traite à cet instant, ou `nil`.
    ///
    /// Adaptateur, sans décision : la règle est dans
    /// `SidebarSelectionGuard.decide`. `NSEvent.timestamp` se compare à
    /// `ProcessInfo.systemUptime` — les deux comptent depuis le démarrage de
    /// la machine, ce que `Date()` ne fait pas.
    @MainActor
    static func courant(_ application: NSApplication = .shared) -> EvenementEntree? {
        guard let evenement = application.currentEvent else { return nil }
        let nature: Nature
        switch evenement.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown:
            nature = .souris
        case .keyDown:
            nature = .clavier
        default:
            nature = .autre
        }
        return EvenementEntree(
            nature: nature,
            age: ProcessInfo.processInfo.systemUptime - evenement.timestamp)
    }

    /// L'application est-elle au premier plan, avec une fenêtre à la clé ?
    /// Seconde barrière du chemin sans événement (accessibilité).
    @MainActor
    static func fenetreActive(_ application: NSApplication = .shared) -> Bool {
        application.isActive && application.keyWindow != nil
    }
}
#endif

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
    var projetsRecents: Int
    var collaborateursActifs: Int
    var collaborateursArchives: Int
    var recherche: String
    var sectionProjetsDepliee: Bool
    var collaborateursDeplies: Bool
    var archivesDepliees: Bool
    var projetsArchivesDeplies: Bool
    /// Le nombre total de lignes que la `List` rend, entrées fixes comprises.
    ///
    /// Redondant avec les compteurs ci-dessus dans la plupart des cas, et
    /// c'est voulu : c'est **le** nombre que `NSTableView` indexe. Deux
    /// changements qui se compensent (un projet actif archivé, par exemple)
    /// laisseraient le total identique mais bougeraient les compteurs ; un
    /// groupe qui se déplie sans qu'aucun compteur ne change bougerait le
    /// total. Il faut les deux pour couvrir tout remappage d'index.
    var lignesRendues: Int
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
/// Observé **trois** fois à la recette du 2026-09-09 : `p1a` a photographié la
/// fiche du premier projet archivé au lieu du Portfolio, `p1c` celle de
/// `P25_155` alors que la route demandée était `.portfolio`, et `p1f` a ouvert
/// deux projets sur un simple **redimensionnement** de fenêtre, vingt secondes
/// après le lancement. Ce n'est pas un défaut de recette : tout utilisateur
/// dont les lignes bougent — import xlsx, épinglage depuis la palette, frappe
/// dans le champ de recherche, fenêtre redimensionnée — est dérouté de la même
/// façon, sans rien avoir cliqué.
///
/// ## La règle
///
/// La `List` sélectionne un `@State` **local** ; la route n'est écrite que si
/// la sélection survient **pendant le traitement d'un événement d'entrée de
/// l'utilisateur** — un clic ou une touche, vieux de moins d'une seconde.
/// Sinon le `@State` est **restauré** depuis la route, ce qui remet aussi la
/// surbrillance à sa place.
///
/// ## Deux règles essayées avant celle-ci, et pourquoi elles ont cédé
///
/// **Le focus clavier** (première version). Réfutée à la recette du
/// 2026-09-09 : une ligne sélectionnée par l'accessibilité (`AXSelected` sur
/// une `AXRow`, ce que fait VoiceOver) était refusée, et un premier clic
/// depuis un état non focalisé subissait le même sort dès que le focus
/// s'établissait après l'`onChange`. Une sélection légitime refusée est pire
/// que le défaut : l'utilisateur clique et rien ne se passe.
///
/// **Le délai après un changement de lignes** (deuxième version). Réfutée à la
/// recette `p1f` : vingt secondes après le lancement, un **redimensionnement**
/// de la fenêtre a fait ouvrir deux projets — les deux premières lignes
/// « ÉPINGLÉS » — sans que rien ne soit cliqué. `NSTableView` remappe ses
/// index quand il redispose ses lignes, pas seulement quand leur nombre
/// change : une liste noire temporelle ne peut pas couvrir un événement qui
/// survient à n'importe quel moment de la vie de la fenêtre.
///
/// ## Le discriminant : l'événement en cours de traitement
///
/// Une sélection voulue par un humain arrive **dans** la pile d'appel d'un
/// `NSEvent` : `NSApp.currentEvent` porte alors le clic ou la touche qui la
/// provoque. Un remappage d'index, lui, survient pendant une passe de
/// disposition — hors de tout événement d'entrée, ou sous un événement
/// synthétique (`.appKitDefined`, `.periodic`, `.systemDefined`) ou périmé.
/// C'est une propriété du **défaut**, pas une supposition sur l'intention, et
/// elle ne dépend ni du focus ni de l'horloge des données.
///
/// **Le chemin sans événement reste ouvert, sous condition.** L'accessibilité
/// pose `AXSelected` hors de tout événement d'entrée, et SwiftUI n'expose pas
/// l'origine d'une sélection : refuser toute écriture sans événement casserait
/// VoiceOver. Une écriture sans événement est donc acceptée quand la fenêtre
/// est active **et** que les lignes n'ont pas bougé depuis 300 ms — la
/// deuxième version, conservée comme seconde barrière pour ce seul cas. Elle
/// ne couvre pas le remappage au redimensionnement, mais celui-ci porte un
/// `currentEvent` non nul : c'est le premier chemin qui le refuse.
///
/// **L'ouverture par programme n'est jamais concernée.** La palette `⌘K`, la
/// recette et les sous-sections « ÉPINGLÉS » / « RÉCENTS » appellent
/// `MainRouter.open`/`openProject` directement ; la `List` ne fait alors que
/// recopier la route dans sa sélection, ce que `decide` reconnaît (`.ignorer`).

enum SidebarSelectionGuard {

    /// Délai pendant lequel une écriture de sélection **sans événement** est
    /// refusée après un changement de la composition des lignes.
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
    ///   - evenement: l'événement que l'application traite à cet instant
    ///     (`EvenementEntree.courant()`), ou `nil` s'il n'y en a aucun.
    ///   - fenetreActive: l'application est au premier plan et sa fenêtre a la
    ///     clé. Ne sert qu'au chemin sans événement.
    ///   - lignesStables: le résultat de `lignesStables(depuis:)`. Ne sert,
    ///     lui aussi, qu'au chemin sans événement.
    static func decide(ancienne: MainRoute?,
                       nouvelle: MainRoute?,
                       routeCourante: MainRoute?,
                       evenement: EvenementEntree?,
                       fenetreActive: Bool,
                       lignesStables: Bool) -> Decision {
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

        // Le chemin nominal : un clic ou une touche est en cours de
        // traitement. C'est la seule preuve directe qu'un humain a agi.
        if let evenement {
            return evenement.estUneEntreeRecente ? .ouvrir(nouvelle) : .restaurer
        }

        // Le chemin sans événement : l'accessibilité. Deux garde-fous, parce
        // qu'on n'a plus de preuve directe — la fenêtre doit être celle avec
        // laquelle on interagit, et les lignes doivent être posées.
        return fenetreActive && lignesStables ? .ouvrir(nouvelle) : .restaurer
    }

    /// Les lignes sont-elles posées depuis assez longtemps pour qu'une
    /// sélection soit crédible ?
    ///
    /// - Parameter lignesChangeesIlYA: secondes écoulées depuis le dernier
    ///   changement de `SidebarRowsFingerprint`. **`nil` répond `false`** : au
    ///   lancement, tant que la vue n'a pas enregistré un premier rendu avec
    ///   ses données, on ne sait pas si les lignes sont stables — et c'est
    ///   précisément l'instant où le semis les fait toutes apparaître. La vue
    ///   pose donc l'horodatage dès son `onAppear`, ce qui ouvre la voie
    ///   300 ms plus tard.
    static func lignesStables(
        depuis lignesChangeesIlYA: TimeInterval?,
        delai: TimeInterval = delaiApresChangementDeLignes
    ) -> Bool {
        guard let lignesChangeesIlYA else { return false }
        // Un délai négatif (horloge qui recule, date future) est traité comme
        // « à l'instant » : dans le doute, on refuse d'écrire la route.
        return lignesChangeesIlYA >= delai
    }
}
