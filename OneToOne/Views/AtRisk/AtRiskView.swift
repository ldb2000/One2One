import SwiftUI
import SwiftData

/// La vue « À risque » (capture `1f-vue-a-risque.png`) : les projets groupés
/// par **motif**, pas par entité, et une décision par ligne.
///
/// **Elle ne calcule rien** : `AtRiskBuilder` construit les trois groupes une
/// fois, sur changement du store (décision **D11**). Ce fichier assemble les
/// groupes et exécute les trois gestes :
///
/// - **Replanifier** — l'écran projet, onglet « Fiche complète », le jalon
///   dépassé en attente d'édition (`MainRouter.pendingFocusField`) ;
/// - **Planifier** — une réunion de projet datée d'aujourd'hui + sept jours,
///   puis l'écran projet sur l'onglet « Réunions & CR » ;
/// - **Compléter** — l'écran projet, onglet « Pilotage », le champ manquant
///   actif : sélecteur de collaborateur **prérempli** pour le chef de projet
///   (décision **D3**), champ de saisie pour le sponsor, menu pour le statut.
///
/// Le nom du projet, lui, ouvre simplement l'écran projet sur le Pilotage.
struct AtRiskView: View {

    // MARK: - Libellés et mesures du handoff §1f

    static let titre = "À risque"
    static let vide = "Aucun projet ne demande de décision."

    static let tailleTitre: CGFloat = 17
    static let tailleSousTitre: CGFloat = 12
    static let tailleVide: CGFloat = 12.5

    static let margeH: CGFloat = 22
    static let margeHaute: CGFloat = 16
    static let margeBasse: CGFloat = 22
    static let ecartEntete: CGFloat = 5
    static let ecartGroupes: CGFloat = 18
    static let ecartEnteteGroupes: CGFloat = 18

    // MARK: - Entrées

    @Environment(MainRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @Query private var meetings: [Meeting]

    @State private var rapport = AtRiskReport()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.ecartEnteteGroupes) {
                entete
                if rapport.estVide {
                    Text(Self.vide)
                        .font(.plexSans(Self.tailleVide))
                        .foregroundStyle(One2OneToken.inkMuted)
                } else {
                    groupes
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.margeH)
            .padding(.top, Self.margeHaute)
            .padding(.bottom, Self.margeBasse)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(One2OneToken.bgCanvas)
        .onAppear { recharger() }
        .onChange(of: projects.count) { _, _ in recharger() }
        .onChange(of: meetings.count) { _, _ in recharger() }
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: Self.ecartEntete) {
            Text(Self.titre)
                .font(.plexSans(Self.tailleTitre, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text(rapport.subtitle)
                .font(.plexSans(Self.tailleSousTitre))
                .foregroundStyle(One2OneToken.inkMuted)
        }
    }

    @ViewBuilder
    private var groupes: some View {
        VStack(alignment: .leading, spacing: Self.ecartGroupes) {
            if !rapport.overdueMilestones.isEmpty {
                AtRiskGroup(libelle: AtRiskGroup.titreJalons,
                            teinte: One2OneToken.report,
                            lignes: rapport.overdueMilestones,
                            onOuvrir: ouvrir,
                            onAgir: agir)
            }
            if !rapport.silent30Days.isEmpty {
                AtRiskGroup(libelle: AtRiskGroup.titreSilences,
                            teinte: One2OneToken.warn,
                            lignes: rapport.silent30Days,
                            onOuvrir: ouvrir,
                            onAgir: agir)
            }
            if !rapport.incomplete.isEmpty {
                AtRiskGroup(libelle: AtRiskGroup.titreFiches,
                            teinte: One2OneToken.inkMuted,
                            lignes: rapport.incomplete,
                            onOuvrir: ouvrir,
                            onAgir: agir)
            }
        }
    }

    // MARK: - État dérivé

    private func recharger() {
        rapport = AtRiskBuilder.build(projects: projects, meetings: meetings, today: Date())
    }

    private func projet(_ ligne: AtRiskItem) -> Project? {
        projects.first { $0.persistentModelID == ligne.project }
    }

    // MARK: - Gestes

    /// Le nom cliqué : l'écran projet, sur le Pilotage.
    private func ouvrir(_ ligne: AtRiskItem) {
        guard let projet = projet(ligne) else { return }
        router.openProject(projet)
    }

    private func agir(_ ligne: AtRiskItem) {
        guard let projet = projet(ligne) else { return }
        switch ligne.action {
        case .replan(let jalon):
            replanifier(jalon, of: projet)
        case .schedule:
            planifier(projet)
        case .complete(let champ):
            router.openProject(projet, tab: .pilotage, focus: ProjectField(champ))
        }
    }

    /// « Replanifier » — l'onglet « Fiche complète », le jalon désigné.
    ///
    /// `ensuredStableID` et non `stableID` : les jalons créés avant l'ajout de
    /// la colonne en portent `nil`, et une consigne d'édition ne peut pas
    /// désigner un jalon sans identifiant.
    private func replanifier(_ identifiant: PersistentIdentifier, of projet: Project) {
        guard let jalon = projet.milestones.first(where: { $0.persistentModelID == identifiant })
        else {
            router.openProject(projet, tab: .fiche)
            return
        }
        router.openProject(projet, tab: .fiche, focus: .milestone(jalon.ensuredStableID))
    }

    /// « Planifier » — une réunion de projet dans sept jours, puis l'onglet
    /// « Réunions & CR ».
    ///
    /// Nommée comme le projet et de type `.project`, comme le fait
    /// « Démarrer une réunion » de l'écran projet ; c'est la seule différence
    /// avec elle : la date.
    private func planifier(_ projet: Project) {
        let reunion = Meeting(title: projet.name,
                              date: AtRiskBuilder.dateDePlanification(from: Date()),
                              notes: "")
        reunion.kind = .project
        context.insert(reunion)
        reunion.project = projet
        do {
            try context.save()
        } catch {
            print("[AtRiskView] création de la réunion échouée : \(error)")
        }
        recharger()
        router.openProject(projet, tab: .meetings)
    }
}
