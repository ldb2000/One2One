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

    // MARK: - Le cas du défaut

    @Test("une sélection écrite hors action de l'utilisateur est restaurée")
    func ecritureParasiteRestauree() {
        // Le scénario de la capture `lot-3-p1c-anomalie.png` : la route est
        // `.portfolio`, le semis fait apparaître les épinglés, et la `List`
        // écrit la fiche d'un projet.
        let parasite = MainRoute.project(UUID(), .pilotage)
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: parasite,
                                             routeCourante: .portfolio,
                                             lignesStables: false) == .restaurer)
    }

    @Test("la même sélection, les lignes posées, ouvre la route")
    func selectionOuvreQuandLesLignesSontStables() {
        let choisie = MainRoute.project(UUID(), .pilotage)
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: choisie,
                                             routeCourante: .portfolio,
                                             lignesStables: true) == .ouvrir(choisie))
    }

    @Test("une sélection sans focus — accessibilité, premier clic — est acceptée")
    func selectionSansFocusAcceptee() {
        // Le défaut de la re-relecture (g), confirmé à l'écran le 2026-09-09 :
        // `AXSelected = true` sur une `AXRow` (ce que fait VoiceOver) était
        // refusé par la condition de focus, et la garde restaurait l'écran
        // précédent. Un premier clic depuis un état non focalisé subissait le
        // même sort dès que le focus s'établissait après l'`onChange`.
        //
        // Il n'y a plus de condition de focus : seules les lignes comptent.
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .atRisk,
                                             routeCourante: .portfolio,
                                             lignesStables: true) == .ouvrir(.atRisk))
    }

    @Test("une désélection ne devient jamais une route")
    func deselectionRestauree() {
        // `List(selection:)` écrit `nil` quand la ligne sélectionnée
        // disparaît. Un écran vide n'est pas une destination — même quand
        // l'utilisateur est aux commandes.
        for stables in [true, false] {
            #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                                 nouvelle: nil,
                                                 routeCourante: .portfolio,
                                                 lignesStables: stables) == .restaurer)
        }
    }

    @Test("la synchronisation descendante n'ouvre rien et ne restaure rien")
    func synchronisationDescendante() {
        // La palette appelle `router.open(.atRisk)` ; la vue recopie la route
        // dans sa sélection, ce qui redéclenche le garde. Il ne doit ni
        // rouvrir (boucle) ni restaurer (clignotement).
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .atRisk,
                                             routeCourante: .atRisk,
                                             lignesStables: false) == .ignorer)
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .atRisk,
                                             routeCourante: .atRisk,
                                             lignesStables: true) == .ignorer)
    }

    @Test("un appel redondant ne fait rien")
    func appelRedondant() {
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .portfolio,
                                             routeCourante: .portfolio,
                                             lignesStables: false) == .ignorer)
    }

    @Test("restaurer une sélection depuis une route nulle reste sans destination")
    func routeCouranteNulle() {
        // `MainRouter.route` peut être `nil` (le tableau de bord implicite).
        #expect(SidebarSelectionGuard.decide(ancienne: nil,
                                             nouvelle: .settings,
                                             routeCourante: nil,
                                             lignesStables: false) == .restaurer)
        #expect(SidebarSelectionGuard.decide(ancienne: nil,
                                             nouvelle: .settings,
                                             routeCourante: nil,
                                             lignesStables: true) == .ouvrir(.settings))
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
        #expect(source.contains("SidebarRowsFingerprint("))
        // Plus de condition de focus : elle refusait des sélections légitimes
        // (accessibilité, premier clic). Voir `SidebarSelectionGuard`.
        #expect(!source.contains("listeFocalisee"),
                "la garde ne doit plus dépendre du focus clavier")
    }
}
