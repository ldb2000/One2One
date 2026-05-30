import Foundation
import SwiftData

/// Une révision du rapport d'une réunion. Inspiré de tevslin/meeting-reporter:
/// Writer → Critique → Revise loop, avec historique persisté.
///
/// `version` = 1 pour le premier draft, 2 pour la révision après critique, etc.
/// `critique` = retour du LLM critique (nil si pas encore évalué ou jugé OK).
/// `isValidated` = l'utilisateur a figé cette version comme finale.
@Model
final class ReportRevision {

    /// FK vers la réunion. Cascade delete = la suppression du meeting purge
    /// l'historique des révisions.
    var meeting: Meeting?

    /// 1-indexed. Croissant. Unique au sein d'une réunion.
    var version: Int = 1

    /// Le markdown rendu — équivalent de `meeting.summary` au moment du snapshot.
    var body: String = ""

    /// Le retour du LLM critique (vide si pas critiqué).
    var critique: String = ""

    /// Message du Writer en réponse au critique précédent (justifie ce qui
    /// n'a pas été changé). Inspire le pattern `message` dans mm_agent.py.
    var writerMessage: String = ""

    /// Version figée par l'utilisateur = rapport final.
    var isValidated: Bool = false

    var createdAt: Date = Date()

    init(meeting: Meeting? = nil,
         version: Int = 1,
         body: String = "",
         critique: String = "",
         writerMessage: String = "",
         isValidated: Bool = false,
         createdAt: Date = Date()) {
        self.meeting = meeting
        self.version = version
        self.body = body
        self.critique = critique
        self.writerMessage = writerMessage
        self.isValidated = isValidated
        self.createdAt = createdAt
    }
}
