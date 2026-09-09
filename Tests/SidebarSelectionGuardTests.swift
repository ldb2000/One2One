import Testing
import Foundation
@testable import OneToOne

/// Le garde-fou de la sélection de la barre latérale — le correctif du défaut
/// relevé deux fois à la recette du 2026-09-09 : `List(selection:)` réécrivait
/// la route quand l'ensemble des lignes changeait, et l'application ouvrait
/// une fiche de projet que personne n'avait demandée.
///
/// La règle est pure, donc testable sans monter une vue ; le branchement dans
/// `Sidebar.swift`, lui, est vérifié par lecture des sources — l'écriture
/// directe `List(selection: $mainRouter.route)` est désormais interdite.
@Suite("Sélection de la barre latérale")
struct SidebarSelectionGuardTests {

    // MARK: - Outillage

    /// Un clic à l'instant — le contexte nominal d'une sélection voulue.
    private static let clic = EvenementEntree(nature: .souris, age: 0)
    /// Une touche à l'instant : `↑`, `↓` ou `⏎` dans la liste.
    private static let touche = EvenementEntree(nature: .clavier, age: 0)

    /// `decide` avec les valeurs neutres du chemin nominal.
    private func decide(_ nouvelle: MainRoute?,
                        depuis ancienne: MainRoute? = .portfolio,
                        route: MainRoute? = .portfolio,
                        evenement: EvenementEntree? = Self.clic,
                        fenetreActive: Bool = true,
                        lignesStables: Bool = true) -> SidebarSelectionGuard.Decision {
        SidebarSelectionGuard.decide(ancienne: ancienne,
                                     nouvelle: nouvelle,
                                     routeCourante: route,
                                     evenement: evenement,
                                     fenetreActive: fenetreActive,
                                     lignesStables: lignesStables)
    }

    // MARK: - Le cas du défaut

    @Test("le remappage au redimensionnement est refusé — recette p1f")
    func remappageAuRedimensionnement() {
        // Vingt secondes après le lancement, un redimensionnement de la
        // fenêtre a fait ouvrir deux projets. `NSApp.currentEvent` porte alors
        // un événement synthétique, ou le dernier clic — vieux de vingt
        // secondes. Les deux sont refusés.
        let parasite = MainRoute.project(UUID(), .pilotage)
        #expect(decide(parasite,
                       evenement: EvenementEntree(nature: .autre, age: 0)) == .restaurer)
        #expect(decide(parasite,
                       evenement: EvenementEntree(nature: .souris, age: 20)) == .restaurer)
        // Et sans aucun événement, la seule fenêtre active ne suffit pas si
        // les lignes viennent de bouger.
        #expect(decide(parasite, evenement: nil, lignesStables: false) == .restaurer)
    }

    @Test("le remappage au semis est refusé — recettes p1a et p1c")
    func remappageAuSemis() {
        // Le premier défaut, celui du lot 3 : le semis fait apparaître les
        // lignes, l'index est retraduit, aucun événement d'entrée n'est en
        // cours.
        let parasite = MainRoute.project(UUID(), .pilotage)
        #expect(decide(parasite, evenement: nil, lignesStables: false) == .restaurer)
    }

    @Test("un clic ouvre la route")
    func clicOuvre() {
        let choisie = MainRoute.project(UUID(), .pilotage)
        #expect(decide(choisie, evenement: Self.clic) == .ouvrir(choisie))
    }

    @Test("une touche ouvre la route — ↑, ↓ et ⏎ dans la liste")
    func toucheOuvre() {
        #expect(decide(.atRisk, evenement: Self.touche) == .ouvrir(.atRisk))
    }

    @Test("un clic ouvre même si les lignes viennent de bouger")
    func clicPrimeSurLesLignes() {
        // L'événement est une preuve directe ; la stabilité des lignes n'est
        // qu'un repli pour le chemin sans événement. Cliquer une ligne qui
        // vient d'apparaître doit marcher.
        #expect(decide(.atRisk, evenement: Self.clic, lignesStables: false) == .ouvrir(.atRisk))
    }

    @Test("un événement synthétique n'est pas une action de l'utilisateur")
    func evenementsSynthetiques() {
        // `.appKitDefined`, `.periodic`, `.systemDefined`, mouvements de
        // souris : tous rangés en `.autre` par l'adaptateur.
        #expect(decide(.atRisk,
                       evenement: EvenementEntree(nature: .autre, age: 0)) == .restaurer)
    }

    @Test("un événement d'entrée périmé est refusé")
    func evenementPerime() {
        // `NSApp.currentEvent` retient le dernier événement traité quand plus
        // rien n'est en cours : sans borne d'âge, un vieux clic autoriserait
        // tout.
        #expect(decide(.atRisk,
                       evenement: EvenementEntree(nature: .souris, age: 5)) == .restaurer)
        #expect(EvenementEntree.ageMaximal == 1)
        #expect(decide(.atRisk,
                       evenement: EvenementEntree(nature: .souris, age: 1)) == .ouvrir(.atRisk))
        #expect(decide(.atRisk,
                       evenement: EvenementEntree(nature: .souris, age: 1.01)) == .restaurer)
    }

    @Test("un âge négatif est refusé")
    func ageNegatif() {
        #expect(decide(.atRisk,
                       evenement: EvenementEntree(nature: .souris, age: -1)) == .restaurer)
    }

    @Test("l'accessibilité sélectionne hors événement : acceptée si la fenêtre est active")
    func accessibilite() {
        // VoiceOver pose `AXSelected` sans qu'aucun `NSEvent` ne soit en
        // cours. Refuser toute écriture sans événement le casserait — c'est le
        // défaut de la première version de cette garde.
        #expect(decide(.atRisk, evenement: nil,
                       fenetreActive: true, lignesStables: true) == .ouvrir(.atRisk))
        // Mais pas si la fenêtre n'est pas celle avec laquelle on interagit,
        // ni si les lignes viennent de bouger.
        #expect(decide(.atRisk, evenement: nil,
                       fenetreActive: false, lignesStables: true) == .restaurer)
        #expect(decide(.atRisk, evenement: nil,
                       fenetreActive: true, lignesStables: false) == .restaurer)
    }

    @Test("une désélection ne devient jamais une route")
    func deselectionRestauree() {
        // `List(selection:)` écrit `nil` quand la ligne sélectionnée
        // disparaît. Un écran vide n'est pas une destination — même sous un
        // clic franc.
        #expect(decide(nil, evenement: Self.clic) == .restaurer)
        #expect(decide(nil, evenement: nil) == .restaurer)
    }

    @Test("la synchronisation descendante n'ouvre rien et ne restaure rien")
    func synchronisationDescendante() {
        // La palette appelle `router.open(.atRisk)` ; la vue recopie la route
        // dans sa sélection, ce qui redéclenche le garde. Il ne doit ni
        // rouvrir (boucle) ni restaurer (clignotement) — quel que soit le
        // contexte, puisqu'aucun événement n'est en cause.
        #expect(decide(.atRisk, route: .atRisk, evenement: nil) == .ignorer)
        #expect(decide(.atRisk, route: .atRisk, evenement: Self.clic) == .ignorer)
        #expect(decide(.atRisk, route: .atRisk,
                       evenement: nil, fenetreActive: false,
                       lignesStables: false) == .ignorer)
    }

    @Test("un appel redondant ne fait rien")
    func appelRedondant() {
        #expect(decide(.portfolio, evenement: nil) == .ignorer)
    }

    @Test("restaurer une sélection depuis une route nulle reste sans destination")
    func routeCouranteNulle() {
        // `MainRouter.route` peut être `nil` (le tableau de bord implicite).
        #expect(decide(.settings, depuis: nil, route: nil,
                       evenement: nil, lignesStables: false) == .restaurer)
        #expect(decide(.settings, depuis: nil, route: nil,
                       evenement: Self.clic) == .ouvrir(.settings))
    }

    // MARK: - Quand les lignes sont-elles posées ?

    @Test("avant le premier rendu, rien n'est stable")
    func avantLePremierRendu() {
        // `nil` = la vue n'a pas encore horodaté de rendu. C'est l'instant du
        // lancement, où le semis fait apparaître toutes les lignes d'un coup :
        // c'est exactement là qu'il ne faut rien écrire.
        #expect(!SidebarSelectionGuard.lignesStables(depuis: nil))
    }

    @Test("des lignes posées depuis assez longtemps sont stables")
    func lignesPosees() {
        #expect(SidebarSelectionGuard.lignesStables(depuis: 5))
        #expect(SidebarSelectionGuard.lignesStables(depuis: 60))
    }

    @Test("juste après un changement de lignes, rien n'est stable")
    func fenetreApresChangementDeLignes() {
        // Épingler un projet depuis la palette, un import xlsx, une frappe
        // dans le champ de recherche : les lignes bougent, l'index de
        // `NSTableView` est remappé.
        #expect(!SidebarSelectionGuard.lignesStables(depuis: 0))
        #expect(!SidebarSelectionGuard.lignesStables(depuis: 0.29))
        // La borne est inclusive : au délai, la voie est libre.
        #expect(SidebarSelectionGuard.lignesStables(depuis: 0.3))
        #expect(SidebarSelectionGuard.delaiApresChangementDeLignes == 0.3)
    }

    @Test("un délai négatif est traité comme « à l'instant »")
    func delaiNegatif() {
        // Horloge qui recule, date future : dans le doute, on n'écrit pas.
        #expect(!SidebarSelectionGuard.lignesStables(depuis: -1))
    }

    // MARK: - L'empreinte des lignes

    @Test("l'empreinte change quand une ligne naît ou meurt")
    func empreinteSensibleAuxLignes() {
        let base = Self.empreinteDuSemis

        var epingleDePlus = base; epingleDePlus.projetsEpingles = 4
        #expect(epingleDePlus != base, "un épinglage ajoute une ligne")

        var semis = base; semis.projetsActifs = 0
        #expect(semis != base, "le semis fait naître soixante-deux lignes")

        var recherche = base; recherche.recherche = "ged"
        #expect(recherche != base, "une recherche filtre les lignes")

        var arbre = base; arbre.arbreDeplie = true
        #expect(arbre != base, "déplier un groupe ajoute ses lignes")

        var archives = base; archives.projetsArchivesDeplies = true
        #expect(archives != base, "c'est le groupe de la capture p1a")

        var recent = base; recent.projetsRecents = 1
        #expect(recent != base, "ouvrir un projet ajoute une ligne « RÉCENTS »")

        // Le total est le nombre que `NSTableView` indexe : deux changements
        // qui se compensent laisseraient les compteurs cohérents mais
        // décaleraient les index, et l'inverse est vrai aussi.
        var total = base; total.lignesRendues += 1
        #expect(total != base, "le nombre de lignes rendues fait partie de l'empreinte")
    }

    @Test("l'empreinte ignore ce qui ne déplace aucune ligne")
    func empreinteInsensibleAuReste() {
        // Renommer un projet, changer son statut, sauvegarder le contexte :
        // aucune ligne ne naît ni ne meurt, donc la sélection reste valable et
        // le garde ne doit pas se fermer pour rien.
        let a = Self.empreinteDuSemis
        let b = Self.empreinteDuSemis
        #expect(a == b)
    }

    /// L'empreinte du portefeuille de démonstration, section « Projets »
    /// dépliée et arbre replié — l'état de la capture `p1c`.
    private static let empreinteDuSemis = SidebarRowsFingerprint(
        projetsActifs: 62, projetsArchives: 14, projetsEpingles: 3,
        projetsRecents: 0, collaborateursActifs: 7, collaborateursArchives: 0,
        entites: 8, recherche: "", sectionProjetsDepliee: true,
        arbreDeplie: false, collaborateursDeplies: true, archivesDepliees: false,
        projetsArchivesDeplies: false, lignesRendues: 19)

    // MARK: - Le branchement, par lecture des sources

    private static var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func source(_ chemin: String) -> String {
        (try? String(contentsOf: racine.appendingPathComponent(chemin), encoding: .utf8)) ?? ""
    }

    @Test("la barre latérale ne branche plus la route directement sur la List")
    func listeNeSelectionnePlusLaRoute() {
        let source = Self.source("OneToOne/Views/Sidebar.swift")
        #expect(!source.isEmpty, "Sidebar.swift introuvable")
        // Le défaut, dans sa forme exacte, et dans les deux qui reviendraient
        // au même.
        #expect(!source.contains("List(selection: $mainRouter.route)"),
                "la List ne doit plus écrire la route : elle sélectionne un @State local")
        #expect(!source.contains("selection: $mainRouter.route"))
        #expect(!source.contains("@Bindable var mainRouter"),
                "plus aucun binding en écriture sur le routeur depuis la barre latérale")
        // Et ce qui doit être là à la place.
        #expect(source.contains("List(selection: $selectionDeLaListe)"))
        #expect(source.contains("SidebarSelectionGuard.decide("))
        #expect(source.contains("SidebarSelectionGuard.lignesStables("))
        // Le discriminant principal : l'événement en cours de traitement, lu
        // au moment exact où la `List` écrit.
        #expect(source.contains("evenement: EvenementEntree.courant()"))
        #expect(source.contains("fenetreActive: EvenementEntree.fenetreActive()"))
        #expect(source.contains("SidebarRowsFingerprint("))
        // Plus de condition de focus : elle refusait des sélections légitimes
        // (accessibilité, premier clic). Voir `SidebarSelectionGuard`.
        #expect(!source.contains("listeFocalisee"),
                "la garde ne doit plus dépendre du focus clavier")
    }
}
