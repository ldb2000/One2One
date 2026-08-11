import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Une décision prise en séance est un **engagement** : elle doit pouvoir être
/// soldée. Elle n'était qu'une chaîne dans `decisionsJSON`, sans état.
///
/// La colonne accueille désormais les deux formes — `["texte"]`, écrite par
/// tout ce qui existait avant, et `[{"text":…,"settledAt":…}]`. Aucune
/// migration : c'est le décodeur qui accepte les deux.
@Suite("DecisionEntry — une décision porte son état de solde")
struct DecisionEntryTests {

    private func makeMeeting() throws -> Meeting {
        let context = ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
        let meeting = Meeting(title: "1:1", date: Date())
        meeting.kind = .oneToOne
        context.insert(meeting)
        return meeting
    }

    @Test("L'ancienne forme, un tableau de chaînes, se lit comme des décisions non soldées")
    func legacyShapeReadsAsUnsettled() throws {
        let meeting = try makeMeeting()
        meeting.decisionsJSON = #"["Confier le suivi à Gaëtan","Envoyer un mail à Loïc"]"#

        let entries = meeting.decisionEntries
        #expect(entries.count == 2)
        #expect(entries.first?.text == "Confier le suivi à Gaëtan")
        #expect(entries.allSatisfy { $0.settledAt == nil })
    }

    @Test("La façade decisions rend les textes, quelle que soit la forme")
    func facadeStillReturnsTexts() throws {
        let meeting = try makeMeeting()
        meeting.decisionsJSON = #"["Ancienne forme"]"#
        #expect(meeting.decisions == ["Ancienne forme"])

        meeting.decisionEntries = [DecisionEntry(text: "Nouvelle forme")]
        #expect(meeting.decisions == ["Nouvelle forme"])
    }

    @Test("Solder une décision se relit après un aller-retour par la colonne")
    func settlingSurvivesARoundTrip() throws {
        let meeting = try makeMeeting()
        meeting.decisionEntries = [
            DecisionEntry(text: "Décision soldée"),
            DecisionEntry(text: "Décision en suspens")
        ]
        let jour = Date(timeIntervalSince1970: 1_754_000_000)
        meeting.settleDecision(at: 0, on: jour)

        let relu = meeting.decisionEntries
        #expect(relu[0].settledAt == jour)
        #expect(relu[1].settledAt == nil)
    }

    /// La régénération d'un rapport réécrit `decisions` en bloc. Une décision
    /// déjà soldée qui survit à la regénération doit le rester : sinon un
    /// engagement tenu ressusciterait à chaque rapport.
    @Test("Réécrire les décisions préserve le solde de celles qui survivent")
    func rewritingPreservesSettlementOfSurvivors() throws {
        let meeting = try makeMeeting()
        meeting.decisionEntries = [DecisionEntry(text: "Tenue"), DecisionEntry(text: "Oubliée")]
        let jour = Date(timeIntervalSince1970: 1_754_000_000)
        meeting.settleDecision(at: 0, on: jour)

        meeting.decisions = ["Tenue", "Nouvelle"]

        let relu = meeting.decisionEntries
        #expect(relu.count == 2)
        #expect(relu.first(where: { $0.text == "Tenue" })?.settledAt == jour)
        #expect(relu.first(where: { $0.text == "Nouvelle" })?.settledAt == nil)
    }
}
