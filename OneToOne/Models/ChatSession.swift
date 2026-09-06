import Foundation
import SwiftData

/// Une conversation persistée de l'assistant IA global (`ChatbotView`). Chaque session
/// regroupe ses messages (`ChatMessageEntity`) et est retrouvée après fermeture de l'app —
/// contrairement au chat inline de réunion (`MeetingChatView`), qui reste éphémère.
@Model
final class ChatSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Dérivé du premier message utilisateur (tronqué à 60 caractères) ; `nil` tant que la
    /// session ne contient que le message d'accueil.
    var title: String?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.session)
    var messages: [ChatMessageEntity] = []

    init(createdAt: Date = Date(), title: String? = nil) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.title = title
    }
}

/// Un message persisté d'une `ChatSession`. `orderIndex` fixe l'ordre d'affichage —
/// ne pas se fier à `createdAt` seul (deux messages peuvent partager le même instant).
@Model
final class ChatMessageEntity {
    var id: UUID = UUID()
    /// Brut "user" | "assistant" — wrapper calculé `asChatMessage` pour le typage.
    /// `ChatMessage.Role` n'est pas `String`-backed (hors périmètre de cette PR) :
    /// la conversion se fait ici à la main plutôt que via `rawValue`.
    var role: String = "user"
    var content: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()
    var session: ChatSession?

    init(role: String, content: String, orderIndex: Int, createdAt: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    /// Reconstruit le `ChatMessage` (struct RAM) affiché par `ChatbotView`.
    var asChatMessage: ChatMessage {
        ChatMessage(role: role == "user" ? .user : .assistant, content: content)
    }

    static func from(_ message: ChatMessage, orderIndex: Int) -> ChatMessageEntity {
        let role = message.role == .user ? "user" : "assistant"
        return ChatMessageEntity(role: role, content: message.content, orderIndex: orderIndex)
    }
}
