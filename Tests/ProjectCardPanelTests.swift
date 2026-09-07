import Testing
import SwiftData
import SwiftUI
@testable import OneToOne

/// Le panneau de la fiche projet. Les tests portent sur ce qui est vérifiable
/// sans session graphique : la géométrie, les libellés exacts de la capture
/// `3b-fiche-projet.png` et la construction des vues.
@Suite("Fiche projet — panneau de 430 px")
@MainActor
struct ProjectCardPanelTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("La largeur du panneau est celle de la spec §1.2")
    func widthMatchesSpec() {
        #expect(ProjectCardPanel.width == 430)
        #expect(ProjectCardPanel.width == One2OneToken.projectPanelWidth)
    }

    /// Les libellés de la capture, au mot près : « FICHE PROJET », « STATUT »,
    /// « BUDGET CONSOMMÉ », « JALONS », « PÉRIMÈTRE & CONTEXTE », « RISQUES »,
    /// « INTERLOCUTEURS ».
    @Test("Les libellés de section sont ceux de la capture")
    func sectionLabelsMatchCapture() {
        #expect(ProjectCardPanel.headerLabel == "FICHE PROJET")
        #expect(ProjectCardPanel.statusLabel == "STATUT")
        #expect(ProjectCardPanel.budgetLabel == "BUDGET CONSOMMÉ")
        #expect(ProjectCardPanel.milestonesLabel == "JALONS")
        #expect(ProjectCardPanel.scopeLabel == "PÉRIMÈTRE & CONTEXTE")
        #expect(ProjectCardPanel.risksLabel == "RISQUES")
        #expect(ProjectCardPanel.contactsLabel == "INTERLOCUTEURS")
        #expect(ProjectCardPanel.newMilestonePlaceholder == "Nouveau jalon…")
        #expect(ProjectCardPanel.newMilestoneHint == "date · statut")
    }

    /// Le pied porte la mention de visibilité de la spec §4.3 et les deux
    /// boutons. Une fiche est visible de toute l'équipe projet : le dire est
    /// une obligation de la spec, pas une politesse.
    @Test("Le pied dit la visibilité et la reprise en préparation")
    func footerStatesVisibility() {
        #expect(ProjectCardPanel.footerNotice
                == "Visible par toute l'équipe projet · reprise automatiquement "
                 + "en préparation de la prochaine réunion")
    }

    @Test("Le menu de statut offre exactement les trois valeurs de la spec")
    func statusMenuHasThreeValues() {
        #expect(ProjectCardStatus.allCases.count == 3)
        #expect(ProjectCardStatus.allCases.map(\.label)
                == ["Sous contrôle", "À surveiller", "En risque"])
    }

    /// Le point coloré du statut et celui d'un jalon viennent des jetons, pas
    /// d'une couleur écrite dans la vue.
    @Test("Les points d'état sont teintés par les jetons")
    func stateDotsUseTokens() {
        #expect(ProjectCardPanel.color(for: ProjectCardStatus.ok) == One2OneToken.ok)
        #expect(ProjectCardPanel.color(for: ProjectCardStatus.watch) == One2OneToken.warn)
        #expect(ProjectCardPanel.color(for: ProjectCardStatus.risk) == One2OneToken.report)

        #expect(ProjectCardPanel.color(for: MilestoneState.done) == One2OneToken.ok)
        #expect(ProjectCardPanel.color(for: MilestoneState.late) == One2OneToken.warn)
        #expect(ProjectCardPanel.color(for: MilestoneState.inProgress) == One2OneToken.action)
        // Un jalon prévu est un cercle vide sur la capture : la couleur ne
        // sert qu'au contour.
        #expect(ProjectCardPanel.color(for: MilestoneState.planned) == One2OneToken.ink4)

        #expect(ProjectCardPanel.color(for: MeetingKPI.Level.critique) == One2OneToken.report)
        #expect(ProjectCardPanel.color(for: MeetingKPI.Level.eleve) == One2OneToken.report)
        #expect(ProjectCardPanel.color(for: MeetingKPI.Level.modere) == One2OneToken.warn)
        #expect(ProjectCardPanel.color(for: MeetingKPI.Level.faible) == One2OneToken.ink4)
    }

    @Test("La barre de budget prend la teinte du ratio")
    func budgetBarUsesToneTokens() {
        #expect(ProjectCardPanel.color(for: BudgetTone.ok) == One2OneToken.ok)
        #expect(ProjectCardPanel.color(for: BudgetTone.warn) == One2OneToken.warn)
        #expect(ProjectCardPanel.color(for: BudgetTone.report) == One2OneToken.report)
    }

    @Test("Le panneau se construit pour le projet de la capture")
    func panelBuilds() throws {
        let context = ModelContext(try makeContainer())
        let reunion = RefonteDemoSeed.seed(in: context)
        let projet = try #require(reunion.project)

        var ouvert = true
        let panneau = ProjectCardPanel(project: projet,
                                       meeting: reunion,
                                       meetings: [reunion],
                                       settings: AppSettings(),
                                       isPresented: Binding(get: { ouvert },
                                                            set: { ouvert = $0 }))
        #expect(panneau.project.code == "P25_110")
        #expect(ProjectCardPanel.width == 430)
    }

    /// La feuille de diff doit se construire même sans proposition : c'est
    /// l'état où l'utilisateur a tout traité, et un plantage à ce moment-là
    /// serait le pire moment possible.
    @Test("La feuille de diff se construit avec zéro proposition")
    func diffSheetBuildsEmpty() {
        var brouillon = ProjectCardDraft()
        let feuille = ProjectCardSuggestionsSheet(
            updates: [],
            draft: Binding(get: { brouillon }, set: { brouillon = $0 }),
            onClose: {}
        )
        #expect(feuille.updates.isEmpty)
        #expect(ProjectCardSuggestionsSheet.emptyNotice
                == "Toutes les propositions ont été traitées.")
    }

    @Test("La feuille de diff nomme les deux gestes de la spec")
    func diffSheetActionLabels() {
        #expect(ProjectCardSuggestionsSheet.acceptLabel == "Accepter")
        #expect(ProjectCardSuggestionsSheet.ignoreLabel == "Ignorer")
        #expect(ProjectCardSuggestionsSheet.title == "PROPOSITIONS DE L'ASSISTANT")
    }
}
