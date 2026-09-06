import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ChatSession — persistance de l'historique du chatbot")
@MainActor
struct ChatSessionTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @Test("3 messages ajoutés, rechargés depuis un nouveau ModelContext, restent dans l'ordre")
    func messagesSurviveContextReload() throws {
        let container = try makeContainer()
        let writeContext = ModelContext(container)

        let session = ChatSession()
        writeContext.insert(session)

        let contents = ["Bonjour", "Où en est le projet X ?", "Merci"]
        for (index, content) in contents.enumerated() {
            let entity = ChatMessageEntity(role: index == 1 ? "assistant" : "user", content: content, orderIndex: index)
            entity.session = session
            writeContext.insert(entity)
        }
        try writeContext.save()
        let sessionID = session.id

        let readContext = ModelContext(container)
        let reloaded = try readContext.fetch(FetchDescriptor<ChatSession>(
            predicate: #Predicate { $0.id == sessionID }
        )).first
        let messages = reloaded?.messages.sorted(by: { $0.orderIndex < $1.orderIndex })

        #expect(messages?.count == 3)
        #expect(messages?.map(\.content) == contents)
    }

    @Test("Supprimer une session supprime ses messages en cascade")
    func deletingSessionCascadesToMessages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let session = ChatSession()
        context.insert(session)
        for index in 0..<3 {
            let entity = ChatMessageEntity(role: "user", content: "msg \(index)", orderIndex: index)
            entity.session = session
            context.insert(entity)
        }
        try context.save()

        context.delete(session)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<ChatMessageEntity>())
        #expect(remaining.isEmpty)
    }

    @Test("Mapper ChatMessage <-> ChatMessageEntity : roundtrip préserve rôle et contenu")
    func chatMessageRoundtrip() throws {
        let user = ChatMessage(role: .user, content: "Quelle est la phase du projet ?")
        let userEntity = ChatMessageEntity.from(user, orderIndex: 0)
        #expect(userEntity.role == "user")
        #expect(userEntity.asChatMessage.role == .user)
        #expect(userEntity.asChatMessage.content == user.content)

        let assistant = ChatMessage(role: .assistant, content: "Le projet est en phase Build.")
        let assistantEntity = ChatMessageEntity.from(assistant, orderIndex: 1)
        #expect(assistantEntity.role == "assistant")
        #expect(assistantEntity.asChatMessage.role == .assistant)
        #expect(assistantEntity.asChatMessage.content == assistant.content)
    }

    @Test("Limite de 100 sessions : au-delà, les plus anciennes sont supprimées")
    func enforceLimitPrunesOldestSessions() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let now = Date()
        var sessions: [ChatSession] = []
        for index in 0..<105 {
            // updatedAt croissant : index 0 = la plus ancienne, 104 = la plus récente.
            let session = ChatSession(createdAt: now.addingTimeInterval(TimeInterval(index)))
            session.updatedAt = now.addingTimeInterval(TimeInterval(index))
            context.insert(session)
            sessions.append(session)
        }
        try context.save()

        ChatSessionStore.enforceLimit(sessions: sessions, in: context, limit: 100)

        let remaining = try context.fetch(FetchDescriptor<ChatSession>())
        #expect(remaining.count == 100)

        let oldestFiveIDs = Set(sessions.prefix(5).map(\.id))
        let remainingIDs = Set(remaining.map(\.id))
        #expect(oldestFiveIDs.isDisjoint(with: remainingIDs))
    }
}
