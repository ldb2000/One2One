import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le drain verse la prep « en attente » d'un collaborateur dans la réunion
/// où on va le voir. Deux défauts constatés sur le store réel le 2026-08-14 :
/// il brûlait sa seule chance sur un tirage vide, et il ne regardait qu'un
/// participant.
@MainActor
@Suite("Report de préparation — la chance du drain — ne pas brûler sa chance sur un tirage vide")
struct PrepDrainChanceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func unATrois(_ context: ModelContext, _ participants: [Collaborator]) -> Meeting {
        let m = Meeting(title: "1:1", date: Date())
        m.kind = .oneToOne
        m.participants = participants
        context.insert(m)
        return m
    }

    /// Le cas de l'auteur : la réunion est ouverte avant que la prep soit
    /// écrite. Le drain ne doit pas se déclarer fait, sans quoi la prep
    /// écrite ensuite n'entrera jamais.
    @Test("Un drain qui ne ramène rien ne se déclare pas fait")
    func emptyDrawDoesNotBurnTheChance() throws {
        let context = try makeContext()
        let barba = Collaborator(name: "BARBA Jean Marc")
        context.insert(barba)
        let reunion = unATrois(context, [barba])

        PrepCarryoverService.drainStandingIntoMeeting(reunion, in: context)
        #expect(!reunion.prepDrainDone, "rien n'a été versé : la chance reste ouverte")

        // La prep arrive après coup, comme dans la vraie vie.
        barba.standingPrepNotes = "- [ ] Point mobilité"
        PrepCarryoverService.drainStandingIntoMeeting(reunion, in: context)

        #expect(reunion.prepNotes.contains("Point mobilité"))
        #expect(reunion.prepDrainDone)
        #expect(barba.standingPrepNotes.isEmpty, "la prep a été consommée")
    }

    /// Sur un 1:1, `participants.first` peut être soi-même : la prep de
    /// l'autre ne serait jamais lue.
    @Test("La prep de chaque participant est versée, pas seulement celle du premier")
    func everyParticipantsPrepIsDrained() throws {
        let context = try makeContext()
        let moi = Collaborator(name: "DE BERTI Laurent")
        let paoli = Collaborator(name: "PAOLI Nicolas")
        paoli.standingPrepNotes = "- [ ] Reprise du chantier IAM"
        context.insert(moi); context.insert(paoli)
        let reunion = unATrois(context, [moi, paoli])

        PrepCarryoverService.drainStandingIntoMeeting(reunion, in: context)

        #expect(reunion.prepNotes.contains("chantier IAM"))
        #expect(paoli.standingPrepNotes.isEmpty)
    }

    @Test("Une prep déjà versée n'est pas versée deux fois")
    func drainingTwiceKeepsOneCopy() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice")
        alice.standingPrepNotes = "- [ ] Un point"
        context.insert(alice)
        let reunion = unATrois(context, [alice])

        PrepCarryoverService.drainStandingIntoMeeting(reunion, in: context)
        PrepCarryoverService.drainStandingIntoMeeting(reunion, in: context)

        let occurrences = reunion.prepNotes.components(separatedBy: "Un point").count - 1
        #expect(occurrences == 1)
    }

    /// Les réunions déjà brûlées avant le correctif : elles portent le
    /// drapeau sans avoir rien reçu, il faut leur rouvrir la porte.
    @Test("Une réunion marquée drainée mais sans préparation retrouve sa chance")
    func burnedDrainsAreReopened() throws {
        let context = try makeContext()
        let brulee = Meeting(title: "1:1 du 13/08", date: Date())
        brulee.kind = .oneToOne
        brulee.prepDrainDone = true
        let servie = Meeting(title: "1:1 servi", date: Date())
        servie.kind = .oneToOne
        servie.prepDrainDone = true
        servie.prepNotes = "- [ ] Un point déjà versé"
        context.insert(brulee); context.insert(servie)

        let rouvertes = PrepCarryoverService.reopenBurnedDrains(in: context)

        #expect(rouvertes == 1)
        #expect(!brulee.prepDrainDone)
        #expect(servie.prepDrainDone, "celle qui a recu quelque chose garde son drapeau")
        #expect(PrepCarryoverService.reopenBurnedDrains(in: context) == 0)
    }
}
