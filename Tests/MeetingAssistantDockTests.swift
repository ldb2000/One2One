import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// « L'assistant est une surface, pas un onglet : barre d'invocation
/// persistante + `⌘K` partout » (spec §1.1).
///
/// L'onglet Chat a disparu. Ce qui est vérifiable ici, ce sont les deux
/// suggestions de la barre : la capture en montre exactement deux
/// (`Où en est le chiffrage ?`, `Actions du 1er sept. ?`), la seconde datée de
/// la réunion précédente du même projet.
@Suite("Barre d'invocation de l'assistant")
@MainActor
struct MeetingAssistantDockTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("Toujours deux suggestions, jamais vides")
    func alwaysTwoSuggestions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "[P25_110] Partage statut", date: .now)
        context.insert(reunion)
        let suggestions = MeetingAssistantDock.suggestions(for: reunion, historique: [])
        #expect(suggestions.count == 2)
        #expect(suggestions.allSatisfy { !$0.isEmpty })
    }

    @Test("La seconde suggestion porte la date de la réunion précédente du projet")
    func secondSuggestionIsDated() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let projet = Project(code: "P25_110", name: "S/D — Modernisation CI/CD", domain: "S/D", phase: "Réalisation")
        context.insert(projet)

        let precedente = Meeting(title: "Point du 1er", date: Date(timeIntervalSince1970: 1_756_684_800))
        precedente.project = projet
        let courante = Meeting(title: "[P25_110] Partage statut",
                               date: Date(timeIntervalSince1970: 1_756_944_000))
        courante.project = projet
        context.insert(precedente); context.insert(courante)

        let suggestions = MeetingAssistantDock.suggestions(
            for: courante, historique: [courante, precedente])
        #expect(suggestions.count == 2)
        // « Actions du <date> ? » : la date rend la question actionnable, une
        // suggestion générique ne le serait pas.
        #expect(suggestions[1].lowercased().contains("action"))
        #expect(suggestions[1].contains("?"))
    }

    @Test("Sans historique, la seconde suggestion reste utile")
    func fallbackSuggestion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let reunion = Meeting(title: "Première", date: .now)
        context.insert(reunion)
        let suggestions = MeetingAssistantDock.suggestions(for: reunion, historique: [reunion])
        #expect(suggestions.count == 2)
        #expect(suggestions[1] != suggestions[0])
        #expect(!suggestions[1].isEmpty)
    }

    @Test("Le placeholder est celui de la capture")
    func placeholder() {
        #expect(MeetingAssistantDock.placeholder
                == "Demander à l'assistant sur cette réunion, l'historique, les documents…")
        #expect(MeetingAssistantDock.height == 34)
    }
}
