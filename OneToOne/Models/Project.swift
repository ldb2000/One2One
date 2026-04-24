import Foundation
import SwiftData

@Model
final class Project {
    var code: String
    var name: String
    var isArchived: Bool = false
    var domain: String
    var sponsor: String
    var projectType: String
    var phase: String // Cadrage, Design, Build, Run, etc.
    var status: String // Green, Yellow, Red
    var projectDeliveryDate: Date?
    var designEndDeadline: Date?
    var plannedDays: Double?
    var businessPlanningStatus: String?
    var comment: String?
    var followUpNotes: String?
    var cespPlanningStatus: String?
    var technicalSpecStatus: String?
    var comment2: String?
    var additionalInfo: String?
    var buildRetex: String?
    
    // Budgets
    var budgetDeliver: Double?
    var budgetInit: Double?
    var budgetRev: Double?
    var budgetCons: Double?
    var percentConsoCharge: Double?
    
    // Dates
    var startDate: Date?
    var endDateInitial: Date?
    var endDateRevised: Date?
    
    // Progressions
    var productionDeliveryProgress: Double?
    var planningProgress: Double?
    
    // Risques
    var riskLevel: String?  // Critique, Élevé, Modéré, Faible
    var riskDescription: String?
    var keyPoints: [String] = []

    // Technical Documents
    var hasDAT: Bool = false
    var datLink: URL?
    var hasDIT: Bool = false
    var ditLink: URL?

    var entity: Entity?
    
    @Relationship(deleteRule: .cascade, inverse: \ActionTask.project)
    var tasks: [ActionTask] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectAlert.project)
    var alerts: [ProjectAlert] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectAttachment.project)
    var attachments: [ProjectAttachment] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectInfoEntry.project)
    var infoEntries: [ProjectInfoEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectCollaboratorEntry.project)
    var collaboratorEntries: [ProjectCollaboratorEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectMail.project)
    var mails: [ProjectMail] = []

    init(code: String, name: String, domain: String, sponsor: String = "", projectType: String = "Métier", phase: String, status: String = "Unknown") {
        self.code = code
        self.name = name
        self.domain = domain
        self.sponsor = sponsor
        self.projectType = projectType
        self.phase = phase
        self.status = status
    }
}

@Model
final class ProjectInfoEntry {
    var date: Date
    var content: String
    var category: String
    var project: Project?

    init(date: Date = Date(), content: String = "", category: String = "Information") {
        self.date = date
        self.content = content
        self.category = category
    }
}

@Model
final class ProjectCollaboratorEntry {
    var date: Date
    var content: String
    var kind: String
    var isCompleted: Bool
    var collaborator: Collaborator?
    var project: Project?

    init(date: Date = Date(), content: String = "", kind: String = "Information collaborateur", isCompleted: Bool = false) {
        self.date = date
        self.content = content
        self.kind = kind
        self.isCompleted = isCompleted
    }
}

@Model
final class ProjectAttachment {
    var fileName: String
    var filePath: String
    var bookmarkData: Data?
    var category: String
    var comment: String
    var importedAt: Date
    var project: Project?

    init(url: URL, category: String = "Document", comment: String = "", importedAt: Date = Date()) {
        self.fileName = url.lastPathComponent
        self.filePath = url.path
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        self.category = category
        self.comment = comment
        self.importedAt = importedAt
    }

    func resolvedURL() -> URL {
        guard let bookmarkData else {
            return URL(fileURLWithPath: filePath)
        }

        var isStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return resolvedURL
        }

        return URL(fileURLWithPath: filePath)
    }
}
