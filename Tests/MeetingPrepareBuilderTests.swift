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
}
