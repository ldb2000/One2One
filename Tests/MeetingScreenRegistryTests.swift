import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `isBeingDeleted` est un `@State` : il ne protège que **son** instance de
/// vue. Or la même réunion peut être ouverte deux fois — dans la pile de
/// navigation de la fenêtre principale et dans la fenêtre autonome
/// `1to1-meeting` (`OneToOneApp`). Le registre porte ce que le `@State` ne
/// peut pas porter : combien d'écrans sont montés sur une réunion, et si
/// l'un d'eux l'a supprimée.
@MainActor
@Suite("MeetingScreenRegistry — ce que le @State d'une vue ne peut pas savoir")
struct MeetingScreenRegistryTests {

    private func makeIDs(_ count: Int) throws -> [PersistentIdentifier] {
        let context = ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
        return try (0..<count).map { _ in
            let meeting = Meeting(title: "", date: Date())
            context.insert(meeting)
            try context.save()
            return meeting.persistentModelID
        }
    }

    @Test("Un écran seul n'est présenté nulle part ailleurs")
    func loneScreenIsAlone() throws {
        let registry = MeetingScreenRegistry()
        let id = try makeIDs(1)[0]
        registry.screenAppeared(id)
        #expect(!registry.isPresentedElsewhere(id))
    }

    @Test("Deux écrans sur la même réunion se voient l'un l'autre")
    func twoScreensSeeEachOther() throws {
        let registry = MeetingScreenRegistry()
        let id = try makeIDs(1)[0]
        registry.screenAppeared(id)
        registry.screenAppeared(id)
        #expect(registry.isPresentedElsewhere(id))

        // Le premier se démonte : le second reste seul.
        registry.screenDisappeared(id)
        #expect(!registry.isPresentedElsewhere(id))
    }

    @Test("Deux réunions différentes ne se comptent pas ensemble")
    func distinctMeetingsAreCountedApart() throws {
        let registry = MeetingScreenRegistry()
        let ids = try makeIDs(2)
        registry.screenAppeared(ids[0])
        registry.screenAppeared(ids[1])
        #expect(!registry.isPresentedElsewhere(ids[0]))
        #expect(!registry.isPresentedElsewhere(ids[1]))
    }

    /// Le cas que le `@State` rate : l'écran A supprime la note, l'écran B se
    /// démonte ensuite et réindexerait un modèle disparu, laissant un résultat
    /// Spotlight permanent qui n'ouvre rien.
    @Test("La suppression prononcée par un écran est vue par l'autre")
    func deletionIsSharedAcrossScreens() throws {
        let registry = MeetingScreenRegistry()
        let id = try makeIDs(1)[0]
        registry.screenAppeared(id)
        registry.screenAppeared(id)

        registry.markDeleted(id)
        #expect(registry.isDeleted(id))

        registry.screenDisappeared(id)
        #expect(registry.isDeleted(id), "le second écran doit encore le voir")
    }

    @Test("Le registre oublie une réunion dont plus aucun écran n'est monté")
    func registryForgetsClosedMeetings() throws {
        let registry = MeetingScreenRegistry()
        let id = try makeIDs(1)[0]
        registry.screenAppeared(id)
        registry.markDeleted(id)
        registry.screenDisappeared(id)
        #expect(!registry.isDeleted(id))
        #expect(!registry.isPresentedElsewhere(id))
    }
}
