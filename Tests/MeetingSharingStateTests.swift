import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'état de partage, **dérivable sans le tiroir**.
///
/// Critère d'acceptation n° 2 du chantier 3 : « l'état de partage est lisible
/// depuis la barre du haut sans ouvrir le tiroir ». Le test le tient au sens
/// littéral — le libellé de la pilule se calcule d'une fonction pure, à partir
/// d'un booléen et d'un compte, sans jamais instancier ni consulter la vue du
/// tiroir.
@Suite("Partage à l'écran : l'état de la barre du haut")
struct MeetingSharingStateTests {

    // MARK: - Le compte de la capture

    /// `3a-tiroir-ressources.png` l'énonce en trois endroits : six présents au
    /// bandeau, `Partage actif · 5 voient` dans la barre, `l'accès aux 6
    /// participants` au pied. On ne se compte pas parmi ceux à qui l'on montre
    /// quelque chose.
    @Test("Six présents font cinq spectateurs")
    func compteDeLaCapture() {
        #expect(MeetingSharingState.viewerCount(presentCount: 6) == 5)
        #expect(MeetingSharingState.pillLabel(isPresenting: true, presentCount: 6)
                == "● Partage actif · 5 voient")
    }

    @Test("Un seul spectateur se dit au singulier")
    func singulier() {
        #expect(MeetingSharingState.pillLabel(isPresenting: true, presentCount: 2)
                == "● Partage actif · 1 voit")
    }

    /// Une note prise seul : on partage, mais personne ne regarde. Le compte
    /// ne descend pas sous zéro.
    @Test("Le compte ne devient jamais négatif")
    func jamaisNegatif() {
        #expect(MeetingSharingState.viewerCount(presentCount: 1) == 0)
        #expect(MeetingSharingState.viewerCount(presentCount: 0) == 0)
        #expect(MeetingSharingState.pillLabel(isPresenting: true, presentCount: 0)
                == "● Partage actif")
    }

    /// Spec §4.2 : « sans partage, la pilule disparaît (pas d'état grisé) ».
    @Test("Sans partage, aucun libellé")
    func sansPartage() {
        #expect(MeetingSharingState.pillLabel(isPresenting: false, presentCount: 6) == nil)
    }

    // MARK: - Lecture de la réunion

    @Test("Les présents sont comptés sur les statuts, pas sur la liste")
    @MainActor
    func presents() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)
        for nom in ["Pierre-Yves", "Nathalie", "Cédric", "Lucas", "Camille", "Laurent"] {
            let c = Collaborator(name: nom)
            context.insert(c)
            reunion.participants.append(c)
            reunion.setParticipantStatus(.present, for: c)
        }
        #expect(MeetingSharingState.presentCount(for: reunion) == 6)

        // Un refus retire la personne du compte : elle ne voit rien.
        let absent = try #require(reunion.participants.first)
        reunion.setParticipantStatus(.refused, for: absent)
        #expect(MeetingSharingState.presentCount(for: reunion) == 5)
        #expect(MeetingSharingState.pillLabel(
            isPresenting: true,
            presentCount: MeetingSharingState.presentCount(for: reunion))
                == "● Partage actif · 4 voient")
    }

    /// Le critère, au sens littéral : l'état se lit depuis un `ResourcesState`
    /// **et une réunion**, sans qu'aucune vue de tiroir n'existe.
    @Test("L'état se dérive de l'état d'écran seul")
    @MainActor
    func derivableSansLeTiroir() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)
        for nom in ["A", "B", "C"] {
            let c = Collaborator(name: nom)
            context.insert(c)
            reunion.participants.append(c)
            reunion.setParticipantStatus(.present, for: c)
        }

        let state = ResourcesState()
        #expect(MeetingSharingState.pillLabel(
            isPresenting: state.isPresenting,
            presentCount: MeetingSharingState.presentCount(for: reunion)) == nil)

        state.present(UUID())
        #expect(MeetingSharingState.pillLabel(
            isPresenting: state.isPresenting,
            presentCount: MeetingSharingState.presentCount(for: reunion))
                == "● Partage actif · 2 voient")

        state.stopPresenting()
        #expect(MeetingSharingState.pillLabel(
            isPresenting: state.isPresenting,
            presentCount: MeetingSharingState.presentCount(for: reunion)) == nil)
    }
}
