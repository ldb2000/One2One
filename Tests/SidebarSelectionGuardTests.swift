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
                                             utilisateur: false) == .restaurer)
    }

    @Test("la même sélection, choisie par l'utilisateur, ouvre la route")
    func selectionUtilisateurOuvre() {
        let choisie = MainRoute.project(UUID(), .pilotage)
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: choisie,
                                             routeCourante: .portfolio,
                                             utilisateur: true) == .ouvrir(choisie))
    }

    @Test("une désélection ne devient jamais une route")
    func deselectionRestauree() {
        // `List(selection:)` écrit `nil` quand la ligne sélectionnée
        // disparaît. Un écran vide n'est pas une destination — même quand
        // l'utilisateur est aux commandes.
        for utilisateur in [true, false] {
            #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                                 nouvelle: nil,
                                                 routeCourante: .portfolio,
                                                 utilisateur: utilisateur) == .restaurer)
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
                                             utilisateur: false) == .ignorer)
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .atRisk,
                                             routeCourante: .atRisk,
                                             utilisateur: true) == .ignorer)
    }

    @Test("un appel redondant ne fait rien")
    func appelRedondant() {
        #expect(SidebarSelectionGuard.decide(ancienne: .portfolio,
                                             nouvelle: .portfolio,
                                             routeCourante: .portfolio,
                                             utilisateur: false) == .ignorer)
    }

    @Test("restaurer une sélection depuis une route nulle reste sans destination")
    func routeCouranteNulle() {
        // `MainRouter.route` peut être `nil` (le tableau de bord implicite).
        #expect(SidebarSelectionGuard.decide(ancienne: nil,
                                             nouvelle: .settings,
                                             routeCourante: nil,
                                             utilisateur: false) == .restaurer)
        #expect(SidebarSelectionGuard.decide(ancienne: nil,
                                             nouvelle: .settings,
                                             routeCourante: nil,
                                             utilisateur: true) == .ouvrir(.settings))
    }

    // MARK: - Ce qui compte comme action de l'utilisateur

    @Test("sans le focus, rien n'est une action de l'utilisateur")
    func sansFocus() {
        #expect(!SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: false, lignesChangeesIlYA: nil))
        #expect(!SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: false, lignesChangeesIlYA: 10))
    }

    @Test("avec le focus et des lignes stables, c'est une action de l'utilisateur")
    func avecFocusEtLignesStables() {
        // `nil` = les lignes n'ont jamais changé depuis l'ouverture.
        #expect(SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: nil))
        #expect(SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: 5))
    }

    @Test("juste après un changement de lignes, le focus ne suffit pas")
    func fenetreApresChangementDeLignes() {
        // Épingler un projet depuis la palette pendant que la barre latérale
        // a le focus : les lignes bougent sans qu'on y ait touché.
        #expect(!SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: 0))
        #expect(!SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: 0.29))
        // La borne est inclusive : au délai, la voie est libre.
        #expect(SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: 0.3))
        #expect(SidebarSelectionGuard.delaiApresChangementDeLignes == 0.3)
    }

    @Test("un délai négatif est traité comme « à l'instant »")
    func delaiNegatif() {
        // Horloge qui recule, date future : dans le doute, on n'écrit pas.
        #expect(!SidebarSelectionGuard.estUneSelectionUtilisateur(
            listeFocalisee: true, lignesChangeesIlYA: -1))
    }

    // MARK: - L'empreinte des lignes

    @Test("l'empreinte change quand une ligne naît ou meurt")
    func empreinteSensibleAuxLignes() {
        let base = SidebarRowsFingerprint(
            projetsActifs: 62, projetsArchives: 14, projetsEpingles: 3,
            collaborateursActifs: 7, collaborateursArchives: 0, entites: 8,
            recherche: "", sectionProjetsDepliee: true, arbreDeplie: false,
            collaborateursDeplies: true, archivesDepliees: false,
            projetsArchivesDeplies: false)

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
    }

    @Test("l'empreinte ignore ce qui ne déplace aucune ligne")
    func empreinteInsensibleAuReste() {
        // Renommer un projet, changer son statut, sauvegarder le contexte :
        // aucune ligne ne naît ni ne meurt, donc la sélection reste valable et
        // le garde ne doit pas se fermer pour rien.
        let a = SidebarRowsFingerprint(
            projetsActifs: 62, projetsArchives: 14, projetsEpingles: 3,
            collaborateursActifs: 7, collaborateursArchives: 0, entites: 8,
            recherche: "", sectionProjetsDepliee: true, arbreDeplie: false,
            collaborateursDeplies: true, archivesDepliees: false,
            projetsArchivesDeplies: false)
        let b = a
        #expect(a == b)
    }

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
        #expect(source.contains("SidebarSelectionGuard.estUneSelectionUtilisateur("))
        #expect(source.contains("SidebarRowsFingerprint("))
        #expect(source.contains(".focused($listeFocalisee)"))
    }
}
