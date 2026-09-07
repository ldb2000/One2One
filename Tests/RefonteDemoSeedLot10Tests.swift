import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le jeu de démonstration des quatre captures 1:1.
///
/// Ce test n'est pas décoratif : il **vérifie l'arithmétique des maquettes**.
/// Le lot 10 n'a aucun écran, donc aucune recette visuelle ne peut détecter un
/// jeu de données qui ne tient pas les nombres — et les lots 11 à 14 les
/// compareront à la capture, pas au code.
@Suite("Jeu de démonstration — les deux fils 1:1 des captures")
@MainActor
struct RefonteDemoSeedLot10Tests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }

    private func semer() throws -> (manager: OneOnOneThread,
                                    collaborateur: OneOnOneThread,
                                    context: ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let fils = RefonteDemoSeed.seedOneOnOneThreads(in: context)
        return (fils.manager, fils.collaborator, context)
    }

    // MARK: - Idempotence

    @Test("Semer deux fois ne duplique aucun fil")
    func semerDeuxFois() throws {
        let (manager, _, context) = try semer()
        let seconds = RefonteDemoSeed.seedOneOnOneThreads(in: context)

        #expect(seconds.manager.persistentModelID == manager.persistentModelID)
        #expect(try context.fetch(FetchDescriptor<OneOnOneThread>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Commitment>()).count
                == manager.commitments.count + seconds.collaborator.commitments.count)
        // 14 entretiens menés + 4 subis, pas 36.
        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == 18)
    }

    // MARK: - Fil manager (2a, 2b)

    @Test("Le fil manager tient l'arithmétique de la capture 2b")
    func arithmetiqueDeLaCapture() throws {
        let (fil, _, _) = try semer()

        #expect(fil.myRole == .manager)
        #expect(fil.cadenceDays == 14)
        #expect(fil.collaborator?.name == RefonteDemoSeed.managerThreadCollaborator)

        // « 14ᵉ 1:1 · 4 sept. 2026 ».
        let seances = OneOnOneThreadStore.meetings(of: fil, now: Self.maintenant)
        #expect(seances.count == 14)
        #expect(seances.last?.date == Self.maintenant)
        #expect(OneOnOneThreadStore.sessionNumber(of: seances.last!, in: fil) == 14)

        // « 8 tenus sur 11 · taux 73 % » et « 1 en retard côté manager ».
        let comptes = CommitmentLedger.counts(fil)
        #expect(comptes.kept == 8)
        #expect(comptes.missed == 3)
        #expect(CommitmentLedger.rateLabel(fil) == "8 tenus sur 11 · taux 73 %")
        #expect(CommitmentLedger.lateOnManagerSideLabel(fil, now: Self.maintenant)
                == "1 en retard côté manager")

        // « MORAL — 6 DERNIERS 1:1 » et « en baisse ».
        #expect(MoodTrend.series(fil).map(\.value) == RefonteDemoSeed.managerThreadMoods)
        #expect(MoodTrend.direction(of: fil) == .enBaisse)
        #expect(MoodTrend.deltaLabel(fil) == "↓ vs 21 août (Bien)")

        // « OBJECTIFS S2 » 70 / 25 / 10 %, revue le 18 sept.
        let objectifs = OneOnOneObjectiveList.sorted(fil.objectives)
        #expect(objectifs.map(\.clampedProgress) == [70, 25, 10])
        #expect(objectifs.map(\.tone) == [.ok, .warn, .warn])
        #expect(OneOnOneObjectiveList.reviewLabel(objectifs) == "Revue prévue le 18 sept.")
    }

    @Test("L'ordre du jour de la capture 2a a quatre sujets, dont un reporté")
    func ordreDuJourDeLaCapture() throws {
        let (fil, _, _) = try semer()
        let sujets = AgendaCarryover.sorted(fil.agendaItems)
        #expect(sujets.count == 4)
        #expect(sujets.filter { $0.state == .todo }.count == 3)
        #expect(sujets.last?.text == "Point objectifs S2")
        #expect(sujets.last?.state == .deferred)
        #expect(sujets.filter { $0.addedBySide == .collaborator }.count == 2)
    }

    @Test("Les sujets récurrents du fil manager sont ceux des chips de 2b")
    func chipsDeLaCapture() throws {
        let (fil, _, _) = try semer()
        let topics = RecurringTopicsBuilder.build(fil, now: Self.maintenant, since: nil)
        let premier = try #require(topics.first)
        #expect(premier.family == .charge)
        #expect(RecurringTopicsBuilder.chipLabel(premier) == "Charge de travail · 5")
        #expect(topics.contains { $0.family == .carriere && $0.count == 3 })
        #expect(topics.contains { $0.family == .astreinte })
    }

    @Test("Les trois rappels « à ne pas oublier » sortent dans l'ordre de 2b")
    func rappelsDeLaCapture() throws {
        let (fil, _, _) = try semer()
        let rappels = ReminderRules.reminders(for: fil, now: Self.maintenant)

        // (1) « Vous lui devez un retour sur la grille d'astreinte — reporté
        // 2 fois. » ; (2) « Mobilité archi évoquée 3 fois, jamais tranchée. »
        #expect(rappels.count >= 2)
        #expect(rappels[0].rule == .managerCommitmentLate)
        #expect(rappels[0].tone == .report)
        #expect(rappels[0].text.contains("grille d'astreinte"))
        #expect(rappels[0].text.contains("reporté 2 fois"))
        #expect(rappels[1].rule == .undecidedRecurringTopic)
        #expect(rappels[1].text == "Mobilité archi évoquée 3 fois, jamais tranchée.")
    }

    @Test("La note privée du fil manager ne sort pas du récap collaborateur")
    func notePriveeDuJeu() throws {
        let (fil, _, _) = try semer()
        let derniere = try #require(OneOnOneThreadStore.meetings(of: fil, now: Self.maintenant).last)
        let recap = OneOnOneRecapBuilder.markdown(for: derniere, thread: fil,
                                                  audience: .collaborator, now: Self.maintenant)
        #expect(!recap.contains("Risque de départ"))
        #expect(recap.contains("Charge AP"))
        // Deux cartes de feedback : le 1:1 est « complet » au sens de la spec.
        #expect(recap.contains("Ce que je lui dis"))
        #expect(recap.contains("Ce qu'il me dit"))
    }

    // MARK: - Fil collaborateur (5a, 5b)

    @Test("Le fil collaborateur tient les trois demandes et les trois promesses de 5a")
    func filCollaborateur() throws {
        let (_, fil, _) = try semer()

        #expect(fil.myRole == .collaborator)
        #expect(fil.collaborator?.name == RefonteDemoSeed.collaboratorThreadManager)

        let demandes = AgendaCarryover.requests(of: fil)
        #expect(demandes.count == 3)
        #expect(demandes.map(\.requestStatus) == [.pending, .waiting, .granted])
        #expect(demandes[0].remindedCount == 2)

        // Les trois promesses sont toutes portées par le manager (spec §6.2).
        let promesses = CommitmentLedger.all(fil, side: .manager)
        #expect(promesses.count == 3)
        #expect(CommitmentLedger.all(fil, side: .collaborator).isEmpty)
        #expect(CommitmentLedger.overdue(fil, now: Self.maintenant).count == 1)
        #expect(promesses.map(\.deferralCount).max() == 3)

        // Le tri par retard décroissant met la grille d'astreinte en tête.
        let triees = CommitmentLedger.byLatenessDescending(promesses, now: Self.maintenant)
        #expect(triees.first?.text == "Grille de compensation des astreintes")
    }

    @Test("La demande du 10 juillet reste en warn : 56 jours, pas 60")
    func demandeDe56Jours() throws {
        let (_, fil, _) = try semer()
        let mobilite = try #require(AgendaCarryover.requests(of: fil).first)
        #expect(mobilite.text == "Mobilité vers l'architecture")
        #expect(AgendaCarryover.requestLevel(mobilite, now: Self.maintenant) == .warn)
        #expect(AgendaCarryover.requestHistoryLabel(mobilite)
                == "Demandé le 10 juil. · relancé 2 fois")
    }

    @Test("Toutes les lignes du fil collaborateur sont privées par défaut")
    func toutPriveCoteCollaborateur() throws {
        let (_, fil, _) = try semer()
        #expect(fil.agendaItems.allSatisfy { $0.visibility == .private })
        #expect(fil.commitments.allSatisfy { $0.visibility == .private })

        let derniere = try #require(OneOnOneThreadStore.meetings(of: fil, now: Self.maintenant).last)
        #expect(derniere.timedNotes.allSatisfy { $0.visibility == .private })

        // Capture 5a : « 3 lignes privées seront exclues. » Ici cinq notes,
        // toutes privées — rien ne part sans un geste explicite par ligne.
        let recap = OneOnOneRecapBuilder.markdown(for: derniere, thread: fil,
                                                   audience: .manager, now: Self.maintenant)
        #expect(!recap.contains("Mobilité archi"))
        #expect(OneOnOneRecapBuilder.excludedLinesCount(for: derniere, thread: fil,
                                                         audience: .manager) > 0)
    }
}
