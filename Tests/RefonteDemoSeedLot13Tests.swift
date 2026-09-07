import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le jeu de démonstration de la capture 5a : les quatre lignes de
/// `CE QUE J'AI LIVRÉ`, et rien de ce qui appartient à Laurent.
///
/// Le semis est **idempotent** — la recette se rejoue, et le menu **Réunion**
/// l'offre sur une base déjà peuplée.
@Suite("Jeu de démonstration — capture 5a (lot 13)")
@MainActor
struct RefonteDemoSeedLot13Tests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Le semis ouvre le fil collaborateur sur la séance du 4 septembre")
    func filEtSeance() throws {
        let context = try makeContext()
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))

        #expect(sortie.thread.myRole == .collaborator)
        #expect(sortie.thread.collaborator?.name == "Yann PENVEN")
        #expect(sortie.meeting.kind == .manager)
        #expect(sortie.meeting.date == RefonteDemoSeed.oneOnOneSeedDate)
    }

    @Test("La colonne `CE QUE J'AI LIVRÉ` porte les quatre lignes de la capture")
    func quatreLivrables() throws {
        let context = try makeContext()
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))

        let actions = try context.fetch(FetchDescriptor<ActionTask>())
        let reunions = try context.fetch(FetchDescriptor<Meeting>())
        let depuis = OneOnOneThreadStore.previousMeeting(before: sortie.meeting,
                                                          in: sortie.thread)?.date
        let lignes = DeliveredItemsBuilder.build(actions: actions, meetings: reunions,
                                                 since: depuis,
                                                 now: sortie.meeting.date)

        #expect(lignes.map(\.text) == ["Reprise du périmètre Nexus",
                                        "Présentation COSUI — risques Jenkins",
                                        "Base PostgreSQL dédiée préparée",
                                        "Tests de clustering en recette"])
        #expect(lignes.map(\.detail) == ["Action close le 29 août · 2 j",
                                          "Réunion du 1er sept. · a débloqué la décision",
                                          "Action close le 2 sept.",
                                          "En cours · bloqué par les comptes GitLab"])
        #expect(lignes.last?.status == .blocked)
        // L'en-tête de la carte : `auto · depuis le 21 août`.
        #expect(DeliveredItemsBuilder.sinceLabel(depuis) == "depuis le 21 août")
    }

    @Test("Les livrables de Laurent restent les siens : ils ne sont pas dans mes preuves")
    func livrablesDeLaurentExclus() throws {
        let context = try makeContext()
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))

        let actions = try context.fetch(FetchDescriptor<ActionTask>())
        let reunions = try context.fetch(FetchDescriptor<Meeting>())
        let depuis = OneOnOneThreadStore.previousMeeting(before: sortie.meeting,
                                                          in: sortie.thread)?.date
        let textes = DeliveredItemsBuilder.build(actions: actions, meetings: reunions,
                                                 since: depuis,
                                                 now: sortie.meeting.date).map(\.text)

        // Le lot 10 sème ces deux-là au nom de Laurent, `destinataire` laissé
        // à son défaut `moi`. C'est `collaborator` qui les écarte.
        #expect(!textes.contains("la reprise du périmètre Nexus"))
        #expect(!textes.contains("la présentation COSUI"))
    }

    @Test("Les trois colonnes de la capture sont peuplées")
    func troisColonnes() throws {
        let context = try makeContext()
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))
        let fil = sortie.thread
        let seance = sortie.meeting

        // Gauche : trois sujets privés, trois demandes.
        #expect(CollaboratorSessionModel.myTopics(fil, for: seance).count == 3)
        #expect(CollaboratorSessionModel.myTopics(fil, for: seance)
            .allSatisfy { $0.visibility == .private })
        #expect(CollaboratorSessionModel.requests(fil).count == 3)

        // Centre : cinq lignes, réparties en deux sections.
        #expect(CollaboratorSessionModel.heardSectionNotes(seance).count == 3)
        #expect(CollaboratorSessionModel.saidSectionNotes(seance).count == 2)
        // Aucune n'est partagée : tout part du défaut `private` (critère n° 2).
        #expect(CollaboratorNotePrivacy.sharedCount(seance.timedNotes) == 0)

        // Droite : trois promesses, dont une en retard.
        #expect(CollaboratorSessionModel.promises(fil, now: seance.date).count == 3)
        #expect(CollaboratorSessionModel.lateBadge(fil, now: seance.date) == "1 en retard")
        #expect(CollaboratorSessionModel.recapButtonLabel(for: fil)
                == "Envoyer mon récap à Yann")
    }

    @Test("L'arbitrage du Webcast est promis pendant la séance et attendu le lendemain")
    func arbitrage() throws {
        let context = try makeContext()
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))
        let arbitrage = try #require(sortie.thread.commitments.first {
            $0.text == "Arbitrage renfort / décalage Webcast"
        })

        #expect(CollaboratorSessionModel.takenTodayPill(arbitrage, now: sortie.meeting.date)
                == "pris aujourd'hui")
        #expect(!CollaboratorSessionModel.isLate(arbitrage, now: sortie.meeting.date))
    }

    @Test("Semer deux fois ne double aucune ligne")
    func idempotence() throws {
        let context = try makeContext()
        _ = RefonteDemoSeed.seedLot13(in: context)
        let sortie = try #require(RefonteDemoSeed.seedLot13(in: context))

        let actions = try context.fetch(FetchDescriptor<ActionTask>())
        #expect(actions.filter { $0.title == "Reprise du périmètre Nexus" }.count == 1)
        #expect(actions.filter { $0.title == "Tests de clustering en recette" }.count == 1)

        let reunions = try context.fetch(FetchDescriptor<Meeting>())
        #expect(reunions.filter { $0.title == "Présentation COSUI — risques Jenkins" }
                    .count == 1)

        let depuis = OneOnOneThreadStore.previousMeeting(before: sortie.meeting,
                                                          in: sortie.thread)?.date
        #expect(DeliveredItemsBuilder.build(actions: actions, meetings: reunions,
                                            since: depuis,
                                            now: sortie.meeting.date).count == 4)
        #expect(CollaboratorSessionModel.myTopics(sortie.thread,
                                                   for: sortie.meeting).count == 3)
    }
}
