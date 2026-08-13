import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// « Un engagement pris en 1:1 et non soldé : une ligne de note qualifiée
/// décision ou action pendant un entretien, qui n'a été ni cochée ni
/// explicitement reprise depuis. » — définition de l'auteur, 2026-08-11.
///
/// Ce compteur mesure une **confiance**, pas une charge : il ne compte que ce
/// qui a été promis de vive voix, devant quelqu'un, et qui traîne.
@Suite("EngagementLedger — ce qui a été promis de vive voix et qui traîne")
struct EngagementLedgerTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func oneToOne(_ context: ModelContext, with collab: Collaborator,
                          on date: Date = Date()) -> Meeting {
        let meeting = Meeting(title: "1:1", date: date)
        meeting.kind = .oneToOne
        meeting.participants = [collab]
        context.insert(meeting)
        return meeting
    }

    @Test("Une décision non soldée d'un 1:1 est un engagement")
    func unsettledDecisionCounts() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)
        meeting.decisions = ["Confier le suivi de la migration à Gaëtan"]

        let pending = EngagementLedger.pending(for: alice)
        #expect(pending.count == 1)
        #expect(pending.first?.text == "Confier le suivi de la migration à Gaëtan")
    }

    @Test("Une décision soldée ne compte plus")
    func settledDecisionDropsOut() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)
        meeting.decisions = ["Tenue", "En suspens"]
        meeting.settleDecision(at: 0)

        let pending = EngagementLedger.pending(for: alice)
        #expect(pending.map(\.text) == ["En suspens"])
    }

    @Test("Une action née en 1:1 compte, sauf cochée ou explicitement reprise")
    func actionsCountUnlessCheckedOrTakenUp() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)

        let ouverte = ActionTask(title: "Relancer la DSI"); ouverte.meeting = meeting
        let cochee = ActionTask(title: "Envoyer le mail"); cochee.meeting = meeting
        cochee.isCompleted = true
        let reprise = ActionTask(title: "Cadrer le budget"); reprise.meeting = meeting
        reprise.engagementSettledAt = Date()
        for t in [ouverte, cochee, reprise] { context.insert(t) }

        #expect(EngagementLedger.pending(for: alice).map(\.text) == ["Relancer la DSI"])
    }

    /// Le compteur « ouvertes », lui, compte tout le backlog. Celui-ci ne
    /// compte que ce qui a été promis en face à face.
    @Test("Une action née hors d'un tête-à-tête n'est pas un engagement")
    func backlogFromElsewhereIsNotAnEngagement() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let projet = Meeting(title: "Comité projet", date: Date())
        projet.kind = .project
        projet.participants = [alice]
        context.insert(projet)
        projet.decisions = ["Décision de comité"]
        let task = ActionTask(title: "Tâche de comité"); task.meeting = projet
        context.insert(task)

        #expect(EngagementLedger.pending(for: alice).isEmpty)
    }

    /// « Rouge au-delà de 3, alors que ouvertes reste noir à 10. »
    @Test("Le seuil d'alerte est bas : trois passe, quatre alerte")
    func thresholdIsLow() {
        #expect(EngagementLedger.level(count: 0) == .calme)
        #expect(EngagementLedger.level(count: 3) == .calme)
        #expect(EngagementLedger.level(count: 4) == .alerte)
    }

    @Test("Les engagements sortent du plus ancien au plus récent")
    func oldestFirst() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let vieux = oneToOne(context, with: alice, on: Date(timeIntervalSince1970: 1_000_000))
        vieux.decisions = ["La plus ancienne"]
        let recent = oneToOne(context, with: alice, on: Date(timeIntervalSince1970: 2_000_000))
        recent.decisions = ["La plus récente"]

        #expect(EngagementLedger.pending(for: alice).map(\.text)
                == ["La plus ancienne", "La plus récente"])
    }

    // MARK: - Solder

    /// Sans ce geste, le compteur ne redescend jamais — et un compteur qui ne
    /// redescend jamais cesse d'être lu.
    @Test("Solder une décision la retire du compte")
    func settlingADecisionRemovesIt() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)
        meeting.decisions = ["Tenue", "En suspens"]

        let pending = EngagementLedger.pending(for: alice)
        EngagementLedger.settle(pending[0])

        #expect(EngagementLedger.pending(for: alice).map(\.text) == ["En suspens"])
        #expect(meeting.decisionEntries[0].settledAt != nil)
    }

    /// Solder une action n'est **pas** la cocher : l'engagement est repris, la
    /// tâche reste ouverte dans le backlog.
    @Test("Solder une action la retire du compte sans la terminer")
    func settlingAnActionDoesNotCompleteIt() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)
        let task = ActionTask(title: "Relancer la DSI")
        task.meeting = meeting
        context.insert(task)

        EngagementLedger.settle(EngagementLedger.pending(for: alice)[0])

        #expect(EngagementLedger.pending(for: alice).isEmpty)
        #expect(!task.isCompleted, "l'action reste a faire, seule la promesse est soldee")
        #expect(task.engagementSettledAt != nil)
    }

    @Test("Solder deux fois ne change rien de plus")
    func settlingTwiceIsIdempotent() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let meeting = oneToOne(context, with: alice)
        meeting.decisions = ["Une seule"]

        let engagement = EngagementLedger.pending(for: alice)[0]
        EngagementLedger.settle(engagement, on: Date(timeIntervalSince1970: 1))
        EngagementLedger.settle(engagement, on: Date(timeIntervalSince1970: 2))

        #expect(meeting.decisionEntries[0].settledAt == Date(timeIntervalSince1970: 1))
    }
}
