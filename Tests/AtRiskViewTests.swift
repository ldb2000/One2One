import Testing
import SwiftUI
import Foundation
import SwiftData
@testable import OneToOne

/// La vue « À risque » (capture `1f-vue-a-risque.png`) : les libellés au mot
/// près, les mesures du handoff, et le mécanisme de champ actif que ses trois
/// actions posent sur le routeur.
///
/// Ce que ces tests **ne** prouvent pas : le rendu. Ils figent ce qu'une
/// relecture ne peut pas vérifier à l'œil — l'orthographe d'un titre, la
/// teinte d'un groupe, le fait qu'une consigne d'édition ne vaille qu'une
/// fois.
@Suite("Vue À risque — libellés, mesures et champ actif")
@MainActor
struct AtRiskViewTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func reglagesEnMemoire() -> UserDefaults {
        let suite = "AtRiskViewTests-\(UUID().uuidString)"
        let reglages = UserDefaults(suiteName: suite)!
        reglages.removePersistentDomain(forName: suite)
        return reglages
    }

    // MARK: - Les libellés de la capture

    @Test("L'en-tête porte le titre et le sous-titre de la capture")
    func enTete() {
        #expect(AtRiskView.titre == "À risque")
        let matin = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        #expect(AtRiskBuilder.sousTitre(projets: 7, at: matin)
                == "7 projets demandent une décision · mis à jour ce matin")
    }

    @Test("Les trois titres de groupe s'écrivent au mot près, avec leur compte")
    func titresDeGroupe() {
        #expect(AtRiskGroup.titreJalons == "JALON DÉPASSÉ")
        #expect(AtRiskGroup.titreSilences == "SANS RÉUNION DEPUIS 30 J")
        #expect(AtRiskGroup.titreFiches == "FICHE INCOMPLÈTE")
        #expect(AtRiskGroup.titre(AtRiskGroup.titreJalons, 2) == "JALON DÉPASSÉ — 2")
        #expect(AtRiskGroup.titre(AtRiskGroup.titreSilences, 3) == "SANS RÉUNION DEPUIS 30 J — 3")
        #expect(AtRiskGroup.titre(AtRiskGroup.titreFiches, 2) == "FICHE INCOMPLÈTE — 2")
        // Un cadratin, comme la maquette — pas un tiret d'incise ni un moins.
        #expect(AtRiskGroup.titre("X", 1).contains(" — "))
    }

    @Test("Les trois actions s'intitulent Replanifier, Planifier, Compléter")
    func intitulesDesActions() {
        #expect(AtRiskAction.schedule.libelle == "Planifier")
        #expect(AtRiskAction.complete(field: .sponsor).libelle == "Compléter")
        #expect(AtRiskAction.complete(field: .manager).libelle == "Compléter")
        #expect(AtRiskAction.complete(field: .status).libelle == "Compléter")
    }

    @Test("« Replanifier » est l'intitulé du groupe des jalons du semis")
    func intituleReplanifier() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let lignes = AtRiskBuilder.build(projects: try contexte.fetch(FetchDescriptor<Project>()),
                                         meetings: try contexte.fetch(FetchDescriptor<Meeting>()),
                                         today: Date()).overdueMilestones
        #expect(!lignes.isEmpty)
        #expect(lignes.allSatisfy { $0.action.libelle == "Replanifier" })
    }

    @Test("L'invite d'un portefeuille sain est une phrase, pas un vide")
    func inviteVide() {
        #expect(AtRiskView.vide == "Aucun projet ne demande de décision.")
        #expect(AtRiskReport().estVide)
        #expect(AtRiskReport().projectCount == 0)
    }

    // MARK: - Les mesures du handoff §1f

    @Test("Les tailles de la vue respectent le plancher d'`inkMuted`")
    func mesures() {
        #expect(AtRiskView.tailleTitre == 17)
        #expect(AtRiskView.tailleSousTitre == 12)
        // Le sous-titre et le détail sont en `inkMuted` : jamais sous 11,5 pt.
        #expect(AtRiskView.tailleSousTitre >= 11.5)
        #expect(AtRiskGroup.tailleDetail >= 11.5)
        #expect(AtRiskGroup.tailleNom == 13)
        #expect(AtRiskGroup.tailleDetail == 12)
        #expect(AtRiskGroup.largeurDuBord == 3)
        #expect(AtRiskGroup.rayon == 7)
    }

    @Test("Aucun texte du dossier n'est en `inkMuted` sous 11,5 pt")
    func planchierInkMuted() throws {
        let racine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("OneToOne/Views/AtRisk")
        let fichiers = try FileManager.default.contentsOfDirectory(at: racine,
                                                                   includingPropertiesForKeys: nil)
        #expect(fichiers.count == 2)
        for fichier in fichiers where fichier.pathExtension == "swift" {
            let texte = try String(contentsOf: fichier, encoding: .utf8)
            // Les couleurs viennent toutes des jetons (D17) : aucun littéral.
            #expect(!texte.contains("Color(hex:"))
            #expect(!texte.contains("Color(red:"))
        }
    }

    @Test("Les trois groupes portent les teintes du handoff")
    func teintesDesGroupes() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("OneToOne/Views/AtRisk/AtRiskView.swift"),
            encoding: .utf8)
        #expect(source.contains("teinte: One2OneToken.report"))
        #expect(source.contains("teinte: One2OneToken.warn"))
        #expect(source.contains("teinte: One2OneToken.inkMuted"))
    }

    @Test("La route `.atRisk` monte la vue, plus l'invite du lot 0")
    func routeCablee() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("OneToOne/Views/Navigation/MainDetailView.swift"),
            encoding: .utf8)
        #expect(source.contains("case .atRisk:"))
        #expect(source.contains("AtRiskView()"))
        #expect(!source.contains("MainDetailPlaceholder(titre: \"À risque\""))
        // L'écran de recette `p1f` y mène sans clic.
        #expect(RecetteScreen.aRisque.rawValue == "p1f")
        #expect(RecetteScreen.aRisque.cible == .fenetrePrincipale(.atRisk))
    }

    // MARK: - Le champ actif (`MainRouter.pendingFocusField`)

    @Test("Le champ en attente se consomme une fois")
    func champConsommeUneFois() {
        let routeur = MainRouter(defaults: reglagesEnMemoire())
        #expect(routeur.pendingFocusField == nil)
        #expect(routeur.consumePendingFocusField() == nil)

        routeur.pendingFocusField = .sponsor
        #expect(routeur.consumePendingFocusField() == .sponsor)
        #expect(routeur.pendingFocusField == nil)
        #expect(routeur.consumePendingFocusField() == nil)
    }

    @Test("`openProject(focus:)` pose la consigne et la route ensemble")
    func ouvertureAvecChamp() throws {
        let contexte = try contexteEnMemoire()
        let projet = Project(code: "P25_001", name: "ASP – VM", domain: "ASP",
                             sponsor: "", projectType: "Métier", phase: "Build",
                             status: "Unknown")
        contexte.insert(projet)
        let routeur = MainRouter(defaults: reglagesEnMemoire())

        routeur.openProject(projet, tab: .pilotage, focus: .manager)
        #expect(routeur.route == .project(projet.ensuredStableID, .pilotage))
        #expect(routeur.pendingFocusField == .manager)

        // Sans champ, la consigne est **effacée** : une ouverture ordinaire ne
        // doit pas hériter d'une consigne restée d'un clic précédent.
        routeur.openProject(projet, tab: .meetings)
        #expect(routeur.pendingFocusField == nil)
        #expect(routeur.route == .project(projet.ensuredStableID, .meetings))
    }

    @Test("Les trois champs de « Compléter » se traduisent en `ProjectField`")
    func traductionDesChamps() {
        #expect(ProjectField(.sponsor) == .sponsor)
        #expect(ProjectField(.manager) == .manager)
        #expect(ProjectField(.status) == .status)
        // Le jalon est désigné par son `stableID`, pas par son rang.
        let jeton = UUID()
        #expect(ProjectField.milestone(jeton) == .milestone(jeton))
        #expect(ProjectField.milestone(jeton) != .milestone(UUID()))
    }

    @Test("Un champ déjà ouvert ne se rouvre pas sur une demande extérieure")
    func ouvertureExterieure() {
        #expect(EditableInPlace<Text>.doitOuvrir(demande: true, enEdition: false))
        #expect(!EditableInPlace<Text>.doitOuvrir(demande: true, enEdition: true))
        #expect(!EditableInPlace<Text>.doitOuvrir(demande: false, enEdition: false))
    }

    @Test("L'écran projet consomme la consigne à son apparition")
    func ecranProjetConsomme() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("OneToOne/Views/Project/ProjectScreen.swift"),
            encoding: .utf8)
        #expect(source.contains("consumePendingFocusField()"))
        #expect(source.contains("champActif: champActif"))
        #expect(source.contains("onChampConsomme: { champActif = nil }"))
    }

    // MARK: - Le sélecteur de chef de projet (D3)

    @Test("Le sélecteur met la suggestion en tête, sans la dédoubler")
    func selecteurPrerempli() throws {
        let contexte = try contexteEnMemoire()
        let noms = ["ORSET Jean-Baptiste", "PENVEN Yann", "RIGAUT Manuel"]
        let collaborateurs = noms.map { nom -> Collaborator in
            let c = Collaborator(name: nom, role: "Chef de projet")
            contexte.insert(c)
            return c
        }
        let suggere = collaborateurs[1]
        let picker = ManagerPicker(suggestion: suggere,
                                   collaborateurs: collaborateurs) { _ in }
        #expect(picker.ordonnes.map(\.name)
                == ["PENVEN Yann", "ORSET Jean-Baptiste", "RIGAUT Manuel"])
        #expect(picker.ordonnes.count == collaborateurs.count)

        let sansSuggestion = ManagerPicker(suggestion: nil,
                                           collaborateurs: collaborateurs) { _ in }
        #expect(sansSuggestion.ordonnes.map(\.name) == noms)
        #expect(ManagerPicker(suggestion: nil, collaborateurs: []) { _ in }.ordonnes.isEmpty)
    }

    @Test("La suggestion du sélecteur est celle de `ProjectPeople` (D3)")
    func suggestionDuSemis() throws {
        let contexte = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projets = try contexte.fetch(FetchDescriptor<Project>())
        let collaborateurs = try contexte.fetch(FetchDescriptor<Collaborator>())
        // `P25_099` porte « NOMINE Laurent » au xlsx sans relation : c'est lui
        // que « Compléter » doit proposer en tête.
        let vm = try #require(projets.first { $0.code == "P25_099" })
        #expect(ProjectPeople.manager(of: vm) == nil)
        #expect(ProjectPeople.suggestedManager(for: vm, among: collaborateurs)?.name
                == "NOMINE Laurent")
    }

    @Test("Les libellés du sélecteur et du menu de statut")
    func libellesDesSelecteurs() {
        #expect(ManagerPicker.titre == "Affecter un chef de projet")
        #expect(ManagerPicker.suggere == "Suggéré")
        #expect(StatusPicker.titre == "STATUT")
        #expect(ProjectHeader.changerLeStatut == "Changer le statut du projet")
        // Le menu écrit les libellés français mais rend la valeur persistée.
        #expect(ProjectStatus.allCases.map(\.displayLabel)
                == ["Au vert", "À surveiller", "En alerte", "Statut inconnu"])
        #expect(ProjectStatus.allCases.map(\.label)
                == ["Green", "Yellow", "Red", "Unknown"])
    }
}
