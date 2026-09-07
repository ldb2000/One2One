import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les demandes du côté collaborateur (spec §6.2 : « libellé + statut
/// `Sans réponse` / `En attente` / `Accordé` / `Refusé` + historique court »)
/// vivent sur `OneOnOneAgendaItem` et non sur une table à part : une demande
/// **est** un sujet d'ordre du jour, avec une réponse attendue.
@Suite("Ordre du jour — les colonnes de demande (spec §6.2)")
@MainActor
struct OneOnOneRequestColumnsTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Un sujet est un `topic` sans statut de demande par défaut")
    func defautTopic() throws {
        let context = try makeContext()
        let item = OneOnOneAgendaItem(text: "Charge de travail")
        context.insert(item)
        try context.save()

        #expect(item.kind == .topic)
        #expect(item.requestStatus == .pending)
        #expect(item.requestedAt == nil)
        #expect(item.remindedCount == 0)
    }

    @Test("Les valeurs brutes sont celles de la spécification")
    func valeursBrutes() {
        #expect(AgendaItemKind.topic.rawValue == "topic")
        #expect(AgendaItemKind.request.rawValue == "request")
        #expect(AgendaItemKind.allCases.count == 2)

        #expect(RequestStatus.pending.rawValue == "pending")
        #expect(RequestStatus.waiting.rawValue == "waiting")
        #expect(RequestStatus.granted.rawValue == "granted")
        #expect(RequestStatus.refused.rawValue == "refused")
        #expect(RequestStatus.allCases.count == 4)

        #expect(RequestStatus.pending.label == "Sans réponse")
        #expect(RequestStatus.waiting.label == "En attente")
        #expect(RequestStatus.granted.label == "Accordé")
        #expect(RequestStatus.refused.label == "Refusé")
    }

    @Test("Une demande écrite puis relue conserve son statut et ses relances")
    func allerRetour() throws {
        let context = try makeContext()
        let demande = OneOnOneAgendaItem(text: "Mobilité vers l'architecture",
                                         addedBySide: .collaborator,
                                         kind: .request,
                                         requestStatus: .waiting,
                                         requestedAt: Date(timeIntervalSince1970: 1_783_641_600))
        demande.remindedCount = 2
        context.insert(demande)
        try context.save()

        let relues = try context.fetch(FetchDescriptor<OneOnOneAgendaItem>())
        let relue = try #require(relues.first)
        #expect(relue.kind == .request)
        #expect(relue.kindRaw == "request")
        #expect(relue.requestStatus == .waiting)
        #expect(relue.requestStatusRaw == "waiting")
        #expect(relue.remindedCount == 2)
        #expect(relue.requestedAt == Date(timeIntervalSince1970: 1_783_641_600))
    }

    @Test("Une valeur brute inconnue retombe sur le défaut, sans planter")
    func valeurBruteInconnue() throws {
        let context = try makeContext()
        let item = OneOnOneAgendaItem(text: "Sujet")
        context.insert(item)
        item.kindRaw = "quelque-chose-de-futur"
        item.requestStatusRaw = "autre"

        #expect(item.kind == .topic)
        #expect(item.requestStatus == .pending)
    }
}
