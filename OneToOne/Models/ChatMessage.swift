import Foundation

/// Un message affiché dans un fil de conversation IA (envoyé par l'utilisateur ou l'assistant).
/// Partagé par `ChatbotView` (assistant global) et `MeetingChatView` (chat inline de réunion).
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role {
        case user
        case assistant
    }
}
