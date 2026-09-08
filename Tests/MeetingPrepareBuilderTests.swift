import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le mode Préparer des types multi-participants (spec §2.2) : « Actions
/// ouvertes reportées + derniers points + alertes en colonne principale ; rail
/// réduit. »
///
/// Le calcul est extrait de la vue : ce sont les bornes qui comptent (trois
/// derniers points, du même projet, la réunion courante exclue) et ce sont
/// elles qu'on peut vérifier.
@Suite("Mode Préparer — contenu")
@MainActor
struct MeetingPrepareBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeProject(_ nom: String) -> Project {
        Project(code: "P25", name: nom, domain: "S/D", phase: "Réalisation")
    }

    @Test("Au plus trois derniers points, du même projet, la réunion courante exclue")
    func lastPoints() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projet = makeProject("S/D — Modernisation CI/CD")
        context.insert(projet)
        let maintenant = Date(timeIntervalSince1970: 1_756_944_000)

        func creer(_ jours: Int, _ titre: String, projet: Project?) -> Meeting {
            let m = Meeting(title: titre,
                            date: maintenant.addingTimeInterval(TimeInterval(-86_400 * jours)))
            m.project = projet
            m.shortSummary = "résumé de \(titre)"
            context.insert(m)
            return m
        }

        let courante = creer(0, "aujourd'hui", projet: projet)
        let autres = [creer(1, "hier", projet: projet),
                      creer(2, "avant-hier", projet: projet),
                      creer(3, "il y a trois jours", projet: projet),
                      creer(4, "il y a quatre jours", projet: projet)]
        let autreProjet = makeProject("Autre chantier")
        context.insert(autreProjet)
        let ailleurs = creer(1, "ailleurs", projet: autreProjet)

        let ctx = MeetingPrepareBuilder.build(meeting: courante,
                                              allMeetings: [courante] + autres + [ailleurs])
        #expect(ctx.lastPoints.count == MeetingPrepareBuilder.lastPointsCount)
        #expect(ctx.lastPoints.map(\.title) == ["hier", "avant-hier", "il y a trois jours"])
        #expect(!ctx.lastPoints.contains { $0.title == "aujourd'hui" })
        #expect(!ctx.lastPoints.contains { $0.title == "ailleurs" })
        #expect(ctx.lastPoints.first?.shortSummary == "résumé de hier")
    }

    @Test("Une réunion postérieure n'est pas un « dernier point »")
    func futureMeetingsAreExcluded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projet = makeProject("P")
        context.insert(projet)
        let maintenant = Date(timeIntervalSince1970: 1_756_944_000)

        let courante = Meeting(title: "courante", date: maintenant)
        courante.project = projet
        let suivante = Meeting(title: "suivante", date: maintenant.addingTimeInterval(86_400))
        suivante.project = projet
        context.insert(courante); context.insert(suivante)

        let ctx = MeetingPrepareBuilder.build(meeting: courante,
                                              allMeetings: [courante, suivante])
        #expect(ctx.lastPoints.isEmpty)
    }

    @Test("Sans projet, aucun dernier point mais jamais d'erreur")
    func noProject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let seule = Meeting(title: "seule", date: .now)
        context.insert(seule)
        let ctx = MeetingPrepareBuilder.build(meeting: seule, allMeetings: [seule])
        #expect(ctx.lastPoints.isEmpty)
        #expect(ctx.alertTitles.isEmpty)
        #expect(ctx.carriedActions.isEmpty)
    }

    @Test("Les alertes non résolues du projet remontent, les résolues non")
    func alerts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projet = makeProject("P")
        context.insert(projet)
        let ouverte = ProjectAlert(title: "ouverte", severity: "Critique")
        let fermee = ProjectAlert(title: "fermée", severity: "Critique")
        fermee.isResolved = true
        context.insert(ouverte); context.insert(fermee)
        projet.alerts = [ouverte, fermee]

        let reunion = Meeting(title: "R", date: .now)
        reunion.project = projet
        context.insert(reunion)

        let ctx = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: [reunion])
        #expect(ctx.alertTitles == ["ouverte"])
    }

    @Test("Les actions reportées sont celles qui viennent d'une autre réunion et restent ouvertes")
    func carriedActions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let precedente = Meeting(title: "1er sept.", date: Date(timeIntervalSince1970: 1_756_684_800))
        let courante = Meeting(title: "4 sept.", date: Date(timeIntervalSince1970: 1_756_944_000))
        context.insert(precedente); context.insert(courante)

        let reportee = ActionTask(title: "Préparer gitlab.rb et valider les flux")
        reportee.carriedFromMeeting = precedente
        let reporteeClose = ActionTask(title: "Déjà faite")
        reporteeClose.carriedFromMeeting = precedente
        reporteeClose.isCompleted = true
        let neuve = ActionTask(title: "Née ici")
        for t in [reportee, reporteeClose, neuve] {
            context.insert(t)
            t.meeting = courante
        }

        let ctx = MeetingPrepareBuilder.build(meeting: courante,
                                              allMeetings: [precedente, courante])
        #expect(ctx.carriedActions.count == 1)
        #expect(ctx.carriedActions.first?.title == "Préparer gitlab.rb et valider les flux")
        #expect(ctx.carriedActions.first?.fromTitle == "1er sept.")
    }

    // MARK: - Reprise de la fiche projet (lot 9)

    /// Spec §4.3 : « reprise automatiquement en préparation de la prochaine
    /// réunion ». Le mode Préparer résume la fiche — statut, budget, jalons
    /// proches, risques élevés — et propose de l'ouvrir.
    @Test("Sans projet, il n'y a pas de fiche à reprendre")
    func noProjectMeansNoCard() throws {
        let context = ModelContext(try makeContainer())
        let reunion = Meeting(title: "Réunion libre", date: Date())
        context.insert(reunion)

        let ctx = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: [reunion])
        #expect(ctx.projectCard == nil)
        #expect(ctx.nearMilestones.isEmpty)
        #expect(ctx.highRisks.isEmpty)
    }

    @Test("La fiche du projet est reprise avec son statut et son budget")
    func cardIsCarried() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject("S/D — Modernisation CI/CD")
        projet.status = "Yellow"
        projet.budgetCons = 40_000
        projet.budgetInit = 61_000
        context.insert(projet)
        let reunion = Meeting(title: "Point", date: Date())
        context.insert(reunion)
        reunion.project = projet

        let ctx = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: [reunion])
        let carte = try #require(ctx.projectCard)
        #expect(carte.statusLabel == "À surveiller")
        #expect(carte.budget?.total == 61_000)
    }

    /// La fenêtre est de trente jours : au-delà, un jalon n'est pas un sujet de
    /// la prochaine réunion.
    @Test("Les jalons repris sont ceux des trente prochains jours, plus les bloqués")
    func nearMilestonesWindow() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject("Projet")
        context.insert(projet)
        let maintenant = Date(timeIntervalSince1970: 1_757_000_000)
        let reunion = Meeting(title: "Point", date: maintenant)
        context.insert(reunion)
        reunion.project = projet

        let jour = 86_400.0
        let gabarits: [(String, Double?, MilestoneState)] = [
            ("Dans 10 jours", 10 * jour, .planned),
            ("Dans 29 jours", 29 * jour, .planned),
            ("Dans 31 jours", 31 * jour, .planned),
            ("Passé mais fait", -5 * jour, .done),
            ("Fait dans 3 jours", 3 * jour, .done),
            ("Bloqué sans date", nil, .late),
            ("Sans date ni blocage", nil, .planned)
        ]
        for (index, gabarit) in gabarits.enumerated() {
            let jalon = ProjectMilestone(label: gabarit.0,
                                         dueAt: gabarit.1.map { maintenant.addingTimeInterval($0) },
                                         state: gabarit.2,
                                         order: index)
            context.insert(jalon)
            jalon.project = projet
        }

        let ctx = MeetingPrepareBuilder.build(meeting: reunion,
                                              allMeetings: [reunion],
                                              now: maintenant)
        #expect(MeetingPrepareBuilder.nearMilestoneWindowDays == 30)
        #expect(ctx.nearMilestones.map(\.label)
                == ["Dans 10 jours", "Dans 29 jours", "Bloqué sans date"])
    }

    /// Seuls les risques « Critique » et « Élevé » remontent : un risque
    /// modéré n'est pas un sujet d'ordre du jour.
    @Test("Les risques repris sont les critiques et les élevés, non résolus")
    func highRisksOnly() throws {
        let context = ModelContext(try makeContainer())
        let projet = makeProject("Projet")
        context.insert(projet)
        let reunion = Meeting(title: "Point", date: Date())
        context.insert(reunion)
        reunion.project = projet

        for (titre, gravite) in [("Critique ouvert", "Critique"),
                                 ("Élevé ouvert", "Élevé"),
                                 ("Modéré ouvert", "Modéré"),
                                 ("Faible ouvert", "Faible")] {
            let alerte = ProjectAlert(title: titre, severity: gravite)
            context.insert(alerte)
            alerte.project = projet
        }
        let resolue = ProjectAlert(title: "Critique réglé", severity: "Critique")
        resolue.isResolved = true
        context.insert(resolue)
        resolue.project = projet

        let ctx = MeetingPrepareBuilder.build(meeting: reunion, allMeetings: [reunion])
        #expect(ctx.highRisks.map(\.title) == ["Critique ouvert", "Élevé ouvert"])
    }
}
