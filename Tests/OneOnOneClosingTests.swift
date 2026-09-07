import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// `CLÔTURER` (capture 2a, pied du rail) : le récap, le prochain entretien et
/// la mention des lignes exclues.
///
/// Les trois libellés sont testés sur **le jeu de démonstration** : ce sont les
/// chiffres de la capture, et rien d'autre ne détecterait un compte d'exclusion
/// qui se décale.
@Suite("Clôture du 1:1 — récap, prochain entretien, lignes exclues")
@MainActor
struct OneOnOneClosingTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }

    private func filDeDemonstration() throws -> (OneOnOneThread, Meeting, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let fils = RefonteDemoSeed.seedOneOnOneThreads(in: context)
        let seance = try #require(
            OneOnOneThreadStore.meetings(of: fils.manager, now: Self.maintenant).last)
        return (fils.manager, seance, context)
    }

    @Test("Les trois libellés de CLÔTURER sont ceux de la capture")
    func libelles() throws {
        let (fil, _, _) = try filDeDemonstration()
        #expect(CommitmentsRailModel.recapButtonLabel(for: fil) == "Envoyer le récap à Laurent")
        #expect(CommitmentsRailModel.planNextButtonLabel(for: fil, now: Self.maintenant)
                == "Planifier le prochain — 18 sept.")
        #expect(CommitmentsRailModel.privacyFootnote == "Les notes privées ne sont jamais incluses")
        #expect(CommitmentsRailModel.closingTitle == "CLÔTURER")
    }

    @Test("Le compte des lignes exclues est celui de la note privée de la séance")
    func lignesExclues() throws {
        let (fil, seance, _) = try filDeDemonstration()
        let audience = OneOnOneConfidentiality.recapAudience(for: fil.myRole)
        #expect(audience == .collaborator)

        // Une seule ligne privée dans la séance de la capture : la note
        // `17:30 ● NOTE PRIVÉE — VOUS SEUL`.
        let exclues = OneOnOneRecapBuilder.excludedLinesCount(for: seance, thread: fil,
                                                              audience: audience)
        #expect(exclues == 1)
        #expect(CommitmentsRailModel.excludedLinesLabel(for: seance, in: fil)
                == "1 ligne privée sera exclue.")
    }

    @Test("Sans ligne privée, aucune mention de compte n'est affichée")
    func aucuneLigneExclue() throws {
        let (fil, seance, context) = try filDeDemonstration()
        for note in seance.timedNotes where note.visibility != .shared {
            note.visibility = .shared
        }
        try context.save()
        // La mention permanente reste ; le **compte**, lui, disparaît : « 0
        // ligne privée » attirerait l'œil pour dire qu'il n'y a rien à dire.
        #expect(CommitmentsRailModel.excludedLinesLabel(for: seance, in: fil) == nil)
    }

    @Test("Le récap de clôture n'emporte pas la note privée")
    func recapSansNotePrivee() throws {
        let (fil, seance, _) = try filDeDemonstration()
        let markdown = OneOnOneRecapBuilder.markdown(
            for: seance, thread: fil,
            audience: OneOnOneConfidentiality.recapAudience(for: fil.myRole),
            now: Self.maintenant)
        // Critère chantier 2 n° 1, revérifié depuis l'écran qui déclenche
        // l'envoi : c'est ici que l'utilisateur clique.
        #expect(!markdown.contains("Risque de départ"))
        #expect(markdown.contains("Charge AP"))
    }

    @Test("Les deux intitulés du rail sont ceux de la capture")
    func intitulesDuRail() {
        #expect(CommitmentsRailModel.commitmentsTitle == "ENGAGEMENTS DE CETTE SÉANCE")
        #expect(CommitmentsRailModel.ledgerTitle == "TENUS DEPUIS LE DERNIER 1:1")
    }
}
