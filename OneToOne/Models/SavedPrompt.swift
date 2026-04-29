import Foundation
import SwiftData

/// Prompt enregistré par l'utilisateur dans la galerie "Enregistré".
/// `promptText` contient des placeholders `{Key}` (ex: `{Collaborateur}`)
/// qui seront proposés comme variables typées dans la sheet de config.
@Model
final class SavedPrompt {
    var stableID: UUID? = nil
    var title: String
    var promptText: String
    var iconName: String
    var createdAt: Date

    init(title: String,
         promptText: String,
         iconName: String = "bookmark.fill",
         createdAt: Date = Date()) {
        self.stableID = UUID()
        self.title = title
        self.promptText = promptText
        self.iconName = iconName
        self.createdAt = createdAt
    }
}
