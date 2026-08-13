import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'en-tête répond à « où en est cette personne ». Il ne peut pas répondre la
/// même chose pour quelqu'un que tu vois en tête-à-tête et pour quelqu'un que
/// tu croises en comité.
///
/// Mesure du 2026-08-13 : sur 366 collaborateurs, **8** ont déjà eu un 1:1,
/// **349** apparaissent dans une réunion. Servir les quatre compteurs de suivi
/// partout, c'est afficher « — 0 0 0 » en 17 pt sur 341 fiches.
///
/// C'est la **cadence** qui tranche : choisir un rythme pour quelqu'un, c'est
/// déclarer qu'on le suit.
@Suite("En-tête de fiche — ce qu'on mesure dépend de ce qu'on suit")
struct FicheHeaderTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private let maintenant = Date(timeIntervalSince1970: 1_760_000_000)

    private func personne(_ context: ModelContext, cadence: OneToOneCadence) -> Collaborator {
        let c = Collaborator(name: "Alice")
        c.oneToOneCadence = cadence
        context.insert(c)
        return c
    }

    @Test("Sans cadence, la personne n'est pas suivie")
    func noCadenceMeansNotFollowed() throws {
        let context = try makeContext()
        #expect(!FicheHeader.isFollowed(personne(context, cadence: .aucune)))
        #expect(FicheHeader.isFollowed(personne(context, cadence: .bimensuelle)))
    }

    @Test("Une personne suivie montre ses compteurs de tête-à-tête")
    func followedShowsOneToOneCounters() throws {
        let context = try makeContext()
        let alice = personne(context, cadence: .bimensuelle)
        let labels = FicheHeader.counters(for: alice, now: maintenant).map(\.label)
        #expect(labels == ["dernier 1:1", "en retard", "ouvertes", "engagements"])
    }

    /// Pour les 341 autres, l'en-tête montre ce qui existe vraiment.
    @Test("Une personne non suivie montre ce qui existe : échanges, réunions, décisions")
    func unfollowedShowsWhatExists() throws {
        let context = try makeContext()
        let alice = personne(context, cadence: .aucune)
        let labels = FicheHeader.counters(for: alice, now: maintenant).map(\.label)
        #expect(labels == ["dernier échange", "réunions", "décisions", "ouvertes"])
    }

    @Test("Les compteurs d'une personne non suivie comptent ses réunions et décisions")
    func unfollowedCountsAreReal() throws {
        let context = try makeContext()
        let alice = personne(context, cadence: .aucune)
        let m = Meeting(title: "Comité", date: maintenant.addingTimeInterval(-14 * 86_400))
        m.kind = .project
        m.participants = [alice]
        context.insert(m)
        m.decisions = ["Une décision", "Une autre"]

        let compteurs = FicheHeader.counters(for: alice, now: maintenant)
        #expect(compteurs[0].value == "2 sem.")
        #expect(compteurs[1].value == "1")
        #expect(compteurs[2].value == "2")
    }

    /// Le seuil bas des engagements ne vaut que pour eux : « ouvertes » reste
    /// neutre à dix, « engagements » alerte à quatre.
    @Test("Seuls les engagements alertent bas")
    func onlyEngagementsAlertLow() throws {
        let context = try makeContext()
        let alice = personne(context, cadence: .bimensuelle)
        let meeting = Meeting(title: "1:1", date: maintenant.addingTimeInterval(-3 * 86_400))
        meeting.kind = .oneToOne
        meeting.participants = [alice]
        context.insert(meeting)
        meeting.decisions = ["a", "b", "c", "d"]

        let compteurs = FicheHeader.counters(for: alice, now: maintenant)
        #expect(compteurs.first(where: { $0.label == "engagements" })?.level == .alerte)
        #expect(compteurs.first(where: { $0.label == "ouvertes" })?.level == .neutre)
    }
}
