import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le retard affiché en en-tête de fiche n'a de sens que **relativement à un
/// rythme convenu**. Sans cadence choisie, l'écart reste un écart : on
/// l'affiche, on ne le colore pas.
@Suite("Rythme des 1:1 — un écart n'est un retard que face à une cadence")
struct OneToOneRhythmTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private let maintenant = Date(timeIntervalSince1970: 1_760_000_000)

    private func collaborator(_ context: ModelContext,
                              cadence: OneToOneCadence,
                              dernierIlYAJours: Int?) -> Collaborator {
        let collab = Collaborator(name: "Alice")
        collab.oneToOneCadence = cadence
        context.insert(collab)
        if let jours = dernierIlYAJours {
            let meeting = Meeting(title: "1:1",
                                  date: maintenant.addingTimeInterval(-Double(jours) * 86_400))
            meeting.kind = .oneToOne
            meeting.participants = [collab]
            context.insert(meeting)
        }
        return collab
    }

    @Test("Sans cadence, aucun retard — même après onze semaines")
    func noCadenceMeansNoLateness() throws {
        let context = try makeContext()
        let collab = collaborator(context, cadence: .aucune, dernierIlYAJours: 77)
        #expect(OneToOneRhythm.weeksSinceLast(for: collab, now: maintenant) == 11)
        #expect(!OneToOneRhythm.isLate(for: collab, now: maintenant))
    }

    @Test("Au-delà de la cadence convenue, c'est un retard")
    func beyondTheCadenceIsLate() throws {
        let context = try makeContext()
        let enRetard = collaborator(context, cadence: .bimensuelle, dernierIlYAJours: 20)
        #expect(OneToOneRhythm.isLate(for: enRetard, now: maintenant))
    }

    @Test("Dans la cadence, pas de retard")
    func withinTheCadenceIsFine() throws {
        let context = try makeContext()
        let aJour = collaborator(context, cadence: .bimensuelle, dernierIlYAJours: 10)
        #expect(!OneToOneRhythm.isLate(for: aJour, now: maintenant))
    }

    /// Quelqu'un qu'on n'a jamais vu n'est pas « en retard » : il n'y a pas de
    /// rythme à rattraper, il y en a un à commencer. La fiche le dit autrement
    /// — « Créer le premier 1:1 ».
    @Test("Sans aucun 1:1 tenu, il n'y a pas d'écart à mesurer")
    func neverMetIsNotLate() throws {
        let context = try makeContext()
        let jamais = collaborator(context, cadence: .bimensuelle, dernierIlYAJours: nil)
        #expect(OneToOneRhythm.weeksSinceLast(for: jamais, now: maintenant) == nil)
        #expect(!OneToOneRhythm.isLate(for: jamais, now: maintenant))
    }

    /// Une note est une réunion avec soi-même, une réunion projet n'est pas un
    /// tête-à-tête : ni l'une ni l'autre ne remet le compteur à zéro.
    @Test("Seul un tête-à-tête remet le compteur à zéro")
    func onlyFaceToFaceResetsTheClock() throws {
        let context = try makeContext()
        let collab = collaborator(context, cadence: .bimensuelle, dernierIlYAJours: 30)
        let projet = Meeting(title: "Comité", date: maintenant)
        projet.kind = .project
        projet.participants = [collab]
        context.insert(projet)

        #expect(OneToOneRhythm.weeksSinceLast(for: collab, now: maintenant) == 4)
        #expect(OneToOneRhythm.isLate(for: collab, now: maintenant))
    }

    // MARK: - Le graphe d'écart

    /// « Un carré vide ne dit rien ; passer de 2 à 11 semaines d'écart est *le*
    /// signal du produit. » La heatmap 52 semaines est remplacée par la suite
    /// des écarts entre deux tête-à-tête consécutifs.
    @Test("Les écarts se lisent entre deux tête-à-tête consécutifs")
    func gapsAreMeasuredBetweenConsecutiveMeetings() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Alice")
        context.insert(collab)
        // Trois 1:1 : il y a 8 semaines, 6 semaines, 2 semaines.
        for semaines in [8.0, 6.0, 2.0] {
            let m = Meeting(title: "1:1", date: maintenant.addingTimeInterval(-semaines * 7 * 86_400))
            m.kind = .oneToOne
            m.participants = [collab]
            context.insert(m)
        }

        // Deux intervalles (8→6 et 6→2), puis l'écart courant depuis le dernier.
        #expect(OneToOneRhythm.gaps(for: collab, now: maintenant) == [2, 4, 2])
    }

    @Test("Un seul tête-à-tête ne donne que l'écart courant")
    func aSingleMeetingGivesOnlyTheCurrentGap() throws {
        let context = try makeContext()
        let collab = collaborator(context, cadence: .aucune, dernierIlYAJours: 21)
        #expect(OneToOneRhythm.gaps(for: collab, now: maintenant) == [3])
    }

    @Test("Sans aucun tête-à-tête, il n'y a rien à tracer")
    func noMeetingsMeansNoChart() throws {
        let context = try makeContext()
        let collab = collaborator(context, cadence: .bimensuelle, dernierIlYAJours: nil)
        #expect(OneToOneRhythm.gaps(for: collab, now: maintenant).isEmpty)
    }

    /// Les seuils de la spec : neutre en deçà de 5 semaines, `warn` de 5 à 7,
    /// `late` à partir de 8.
    @Test("Les trois seuils de couleur du graphe")
    func chartThresholds() {
        #expect(OneToOneRhythm.severity(ofGap: 4) == .neutre)
        #expect(OneToOneRhythm.severity(ofGap: 5) == .attention)
        #expect(OneToOneRhythm.severity(ofGap: 7) == .attention)
        #expect(OneToOneRhythm.severity(ofGap: 8) == .alerte)
    }
}
