import Foundation

/// La file d'assignation du bandeau `EN ATTENTE` du mode séance (spec §2.6 :
/// « `EN ATTENTE — n actions sans responsable` + `Assigner maintenant` : ouvre
/// une file d'assignation en 3 clics (responsable → échéance → suivante) »).
///
/// Machine à états **pure et générique** : elle ne connaît ni `ActionTask`, ni
/// SwiftData, ni le clavier. Trois raisons, toutes vérifiables :
///
/// - « en 3 clics » est une affirmation sur un nombre de gestes. Comptée dans
///   une vue, elle n'est vérifiable qu'à la main, une fois, par la personne qui
///   vient de l'écrire.
/// - la sortie (`Esc`) doit fonctionner **à n'importe quelle étape**, y compris
///   la dernière ; c'est exactement le cas qu'un test manuel ne refait pas.
/// - une file vide ne doit rien ouvrir : `Assigner maintenant` sur zéro action
///   en attente est une impasse, pas un formulaire vide.
///
/// Générique sur l'identifiant pour rester testable sans base : la vue
/// l'instancie sur `PersistentIdentifier`, les tests sur `Int`.
struct AssignmentQueue<ID: Hashable & Sendable>: Sendable, Equatable {

    /// Les trois étapes, dans l'ordre de la spec. `suivante` est bien une
    /// étape et non un effet de bord de la précédente : c'est le troisième
    /// clic, celui qui confirme qu'on en a fini avec cette action.
    enum Etape: Sendable, Equatable, CaseIterable {
        case responsable
        case echeance
        case suivante
    }

    /// Ce qui peut arriver à la file. Le clavier de la feuille s'y traduit :
    /// `Tab` et `⌘⏎` avancent, `Esc` sort (spec §2.6, périmètre n° 5 du lot).
    enum Evenement: Sendable, Equatable {
        /// `Tab` — passe au champ suivant, puis à l'action suivante.
        case tab
        /// `⌘⏎` — valide, même effet que `Tab` : dans une file d'assignation,
        /// valider *est* passer à la suite.
        case commandReturn
        /// « Passer » — laisse cette action telle quelle et va à la suivante.
        case passer
        /// `Esc` — quitte la file.
        case escape
    }

    /// Nombre de gestes par action. La spec le fixe à trois ; le test le lit
    /// ici plutôt que de le recompter, sinon il ne vérifierait rien.
    static var gestesParAction: Int { Etape.allCases.count }

    /// Les actions à traiter, dans l'ordre reçu.
    let elements: [ID]

    /// Index de l'action courante. Peut valoir `elements.count` : la file est
    /// alors terminée.
    private(set) var index: Int

    /// Étape courante pour l'action courante.
    private(set) var etape: Etape

    /// Vrai après un `Esc`. Distinct de `estTerminee` : sortir avant la fin
    /// n'est pas la même chose qu'avoir tout assigné, et le bandeau doit
    /// pouvoir le dire.
    private(set) var estSortie: Bool

    /// Ouvre la file. Une liste vide donne une file **déjà terminée** : rien à
    /// présenter.
    init(_ elements: [ID]) {
        self.elements = elements
        self.index = 0
        self.etape = .responsable
        self.estSortie = false
    }

    /// L'action en cours de traitement, `nil` quand la file est terminée ou
    /// qu'on en est sorti.
    var courant: ID? {
        guard !estSortie, index >= 0, index < elements.count else { return nil }
        return elements[index]
    }

    /// Vrai quand toutes les actions ont été parcourues.
    var estTerminee: Bool { index >= elements.count }

    /// Vrai quand la feuille doit être fermée : plus rien à faire, ou sortie
    /// demandée.
    var estClose: Bool { estSortie || estTerminee }

    /// Progression, pour le libellé `n / total` de la feuille. `numero` est
    /// borné au total : une file terminée affiche `3 / 3` et non `4 / 3`.
    var progression: (numero: Int, total: Int) {
        (min(index + 1, elements.count), elements.count)
    }

    // MARK: - Transitions

    /// Applique un événement et rend le nouvel état.
    ///
    /// `Esc` sort **quelle que soit l'étape**, y compris sur la dernière action
    /// et y compris quand la file est déjà terminée (l'appeler alors est sans
    /// effet observable, mais ne doit pas être une erreur).
    func apres(_ evenement: Evenement) -> Self {
        var suivant = self
        switch evenement {
        case .escape:
            suivant.estSortie = true
        case .tab, .commandReturn:
            suivant.avance()
        case .passer:
            suivant.passeALaSuivante()
        }
        return suivant
    }

    /// Avance d'une étape ; à la dernière, passe à l'action suivante.
    private mutating func avance() {
        guard !estClose else { return }
        switch etape {
        case .responsable: etape = .echeance
        case .echeance:    etape = .suivante
        case .suivante:    passeALaSuivante()
        }
    }

    private mutating func passeALaSuivante() {
        guard !estClose else { return }
        index += 1
        etape = .responsable
    }

    // MARK: - Libellés

    /// Le libellé de l'étape, celui que la feuille met au-dessus du champ.
    static func libelle(_ etape: Etape) -> String {
        switch etape {
        case .responsable: return "Responsable"
        case .echeance:    return "Échéance"
        case .suivante:    return "Suivante"
        }
    }
}

/// Le bandeau `EN ATTENTE` lui-même : quelles actions sont « sans
/// responsable », et comment le compter s'écrit.
///
/// Séparé de la file parce que ce n'est pas la même question : la file dit
/// *comment on avance*, ceci dit *sur quoi*. Et parce que la règle « sans
/// responsable » doit être **la même** que celle du groupe `À ASSIGNER` du
/// rail (lot 3) : deux définitions finiraient par afficher deux nombres pour
/// le même écran.
@MainActor
enum PendingAssignment {

    /// Les actions ouvertes de la réunion qui n'ont personne pour les porter,
    /// dans l'ordre du rail.
    ///
    /// Délègue à `ActionsRailGrouping` : le groupe `À ASSIGNER` est déjà la
    /// réponse à cette question, il est déjà trié et déjà testé.
    static func sansResponsable(_ tasks: [ActionTask]) -> [ActionTask] {
        ActionsRailGrouping.groupes(for: tasks)
            .first { $0.identite == .aAssigner }?
            .actions ?? []
    }

    /// « 3 actions sans responsable » — le libellé de la capture, au pluriel
    /// près. Zéro n'a pas de libellé : le bandeau disparaît.
    static func libelle(_ compte: Int) -> String? {
        switch compte {
        case ..<1: return nil
        case 1:    return "1 action sans responsable"
        default:   return "\(compte) actions sans responsable"
        }
    }
}
