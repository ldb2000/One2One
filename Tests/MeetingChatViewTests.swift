import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("MeetingChatView — respect du toggle tool calling (B2-ui MeetingView)")
@MainActor
struct MeetingChatViewTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test("Toggle actif : le chemin choisi est sendWithToolLoop (B2)")
    func chatHonorsToolCallingToggleWhenEnabled() throws {
        let context = try makeContext()

        let meeting = Meeting(title: "Point hebdo", date: Date(), notes: "")
        context.insert(meeting)

        let settings = AppSettings()
        settings.chatbotToolCallingEnabled = true
        context.insert(settings)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(MeetingChatView.shouldUseToolCalling(settingsList: reloaded) == true)
    }

    @Test("Toggle inactif (ou aucun AppSettings) : le chemin choisi est send (B1)")
    func chatHonorsToolCallingToggleWhenDisabled() throws {
        let context = try makeContext()

        let meeting = Meeting(title: "Point hebdo", date: Date(), notes: "")
        context.insert(meeting)

        let settings = AppSettings()
        settings.chatbotToolCallingEnabled = false
        context.insert(settings)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(MeetingChatView.shouldUseToolCalling(settingsList: reloaded) == false)

        // Aucun AppSettings du tout → repli sur false (pas de crash, pas de tool calling par défaut).
        #expect(MeetingChatView.shouldUseToolCalling(settingsList: []) == false)
    }

    @Test("Le prompt inclut le contexte historique et l'historique de conversation quand présents")
    func promptIncludesHistoricalContextAndConversationHistory() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Comité de pilotage", date: Date(), notes: "")
        context.insert(meeting)

        let view = MeetingChatView(meeting: meeting)
        let prompt = view.makePrompt(
            question: "Où en est le projet ?",
            historicalContext: "[1] 01/01/2026 — Réunion précédente: point d'avancement.",
            history: "Utilisateur: bonjour\n\nAssistant: bonjour, comment puis-je aider ?"
        )

        #expect(prompt.contains("Comité de pilotage"))
        #expect(prompt.contains("Contexte historique"))
        #expect(prompt.contains("Réunion précédente"))
        #expect(prompt.contains("Conversation antérieure"))
        #expect(prompt.contains("Où en est le projet ?"))
    }

    @Test("Sans contexte historique ni conversation antérieure, le prompt reste propre (pas de sections vides)")
    func promptOmitsEmptySections() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Point rapide", date: Date(), notes: "")
        context.insert(meeting)

        let view = MeetingChatView(meeting: meeting)
        let prompt = view.makePrompt(question: "Résume la réunion", historicalContext: "", history: "")

        #expect(!prompt.contains("Contexte historique"))
        #expect(!prompt.contains("Conversation antérieure"))
        #expect(prompt.contains("Résume la réunion"))
    }
}
