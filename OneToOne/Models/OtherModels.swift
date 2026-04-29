import Foundation
import SwiftData

enum InterviewType: String, CaseIterable {
    case regular = "Entretien"
    case job = "Entretien Job"
    case importPPTX = "Import PPTX"
    case importPDF = "Import PDF"

    var label: String {
        switch self {
        case .regular:
            return "1:1"
        case .job:
            return "Entretien job"
        case .importPPTX:
            return "Import PPTX"
        case .importPDF:
            return "Import PDF"
        }
    }
}

@Model
final class Collaborator {
    var stableID: UUID? = nil
    var name: String
    var role: String
    var isArchived: Bool = false
    var photoPath: String = ""
    var photoBookmarkData: Data?
    /// Adresse email du collaborateur, utilisée pour pré-remplir les
    /// destinataires lors de l'export d'un compte-rendu de réunion.
    /// Renseigné automatiquement à partir des invitations Calendar.
    var email: String = ""

    /// Pinning level in the sidebar: 0 = hidden, 1 = favourite, 2 = pinned.
    var pinLevel: Int = 0

    /// Marks a collaborator created ad-hoc from a meeting (reusable afterwards).
    var isAdhoc: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Interview.collaborator)
    var interviews: [Interview] = []

    @Relationship(deleteRule: .nullify, inverse: \ActionTask.collaborator)
    var assignedTasks: [ActionTask] = []

    @Relationship(deleteRule: .nullify, inverse: \Meeting.participants)
    var meetings: [Meeting] = []

    init(name: String, role: String = "Architecte", isArchived: Bool = false) {
        self.stableID = UUID()
        self.name = name
        self.role = role
        self.isArchived = isArchived
    }

    /// Retourne `stableID` en backfillant un nouvel UUID si la DB contient `nil`
    /// (cas des collabs créés avant l'ajout du champ).
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    func photoURL() -> URL? {
        guard !photoPath.isEmpty else { return nil }

        if let photoBookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: photoBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolvedURL
            }
        }

        return URL(fileURLWithPath: photoPath)
    }
}

@Model
final class Interview {
    var date: Date
    var collaborator: Collaborator?
    var notes: String
    var recordingLink: URL?
    var hasAlert: Bool = false
    var alertDescription: String = ""
    var typeRaw: String?
    var sourceFileName: String?
    var shareWithEveryone: Bool = false
    var contextComment: String = ""
    var candidateLinkedInURL: String = ""
    var candidateLinkedInNotes: String = ""
    var cvExperienceNotes: String = ""
    var cvSkillsNotes: String = ""
    var cvMotivationNotes: String = ""
    var positivePoints: String = ""
    var negativePoints: String = ""
    var trainingAssessment: String = ""
    var generalAssessment: String = ""
    var selectedProject: Project?

    /// Computed property for type-safe access
    var type: InterviewType {
        get { InterviewType(rawValue: typeRaw ?? "") ?? .regular }
        set { typeRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \ActionTask.interview)
    var tasks: [ActionTask] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectAlert.interview)
    var alerts: [ProjectAlert] = []

    @Relationship(deleteRule: .cascade, inverse: \InterviewAttachment.interview)
    var attachments: [InterviewAttachment] = []

    init(date: Date = Date(), notes: String = "", hasAlert: Bool = false, type: InterviewType = .regular) {
        self.date = date
        self.notes = notes
        self.hasAlert = hasAlert
        self.typeRaw = type.rawValue
    }
}

@Model
final class InterviewAttachment {
    var fileName: String
    var filePath: String
    var bookmarkData: Data?
    var comment: String
    var importedAt: Date
    var interview: Interview?

    init(url: URL, comment: String = "", importedAt: Date = Date()) {
        self.fileName = url.lastPathComponent
        self.filePath = url.path
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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

@Model
final class ActionTask {
    var title: String
    var project: Project?
    var interview: Interview?
    var meeting: Meeting?
    var collaborator: Collaborator?
    var dueDate: Date?
    var isCompleted: Bool = false
    var reminderID: String?

    init(title: String, dueDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
    }
}

@Model
final class ProjectAlert {
    var title: String
    var detail: String
    var severityRaw: String  // Critique, Élevé, Modéré, Faible
    var date: Date
    var isResolved: Bool = false
    var project: Project?
    var interview: Interview?

    var severity: String { severityRaw }

    init(title: String, detail: String = "", severity: String = "Modéré", date: Date = Date()) {
        self.title = title
        self.detail = detail
        self.severityRaw = severity
        self.date = date
    }
}

@Model
final class Meeting {
    /// Stable UUID safe to expose in filenames / external IDs.
    /// SwiftData `persistentModelID` is not usable as a string identifier.
    var stableID: UUID = UUID()
    var title: String
    var date: Date
    var notes: String
    var project: Project?

    // Meeting kind (stored as raw, exposed as MeetingKind)
    var kindRaw: String = MeetingKind.global.rawValue
    var kind: MeetingKind {
        get { MeetingKind(rawValue: kindRaw) ?? .global }
        set { kindRaw = newValue.rawValue }
    }

    // Custom prompt / live note
    var customPrompt: String = ""
    var liveNotes: String = ""

    // Transcription
    var rawTranscript: String = ""
    var mergedTranscript: String = ""

    // Generated report
    var summary: String = ""
    var keyPointsJSON: String = "[]"
    var decisionsJSON: String = "[]"
    var openQuestionsJSON: String = "[]"

    // Audio
    var wavFilePath: String?
    var durationSeconds: Int = 0

    // Calendar
    var calendarEventID: String = ""
    var calendarEventTitle: String = ""

    // Report metadata
    /// Durée de la dernière génération de rapport, en secondes (0 si jamais
    /// généré). Utilisé pour afficher "Rapport ✓ (2:34)" et donner un repère
    /// utilisateur sur le coût IA.
    var reportGenerationDurationSeconds: Double = 0

    // Participant statuses / ad-hoc attendees (JSON-encoded)
    var participantStatusesJSON: String = "{}"
    var adhocAttendeesJSON: String = "[]"

    @Relationship(deleteRule: .nullify)
    var participants: [Collaborator] = []

    @Relationship(deleteRule: .cascade, inverse: \ActionTask.meeting)
    var tasks: [ActionTask] = []

    @Relationship(deleteRule: .cascade, inverse: \MeetingAttachment.meeting)
    var attachments: [MeetingAttachment] = []

    @Relationship(deleteRule: .cascade, inverse: \TranscriptChunk.meeting)
    var transcriptChunks: [TranscriptChunk] = []

    init(title: String = "", date: Date = Date(), notes: String = "") {
        self.title = title
        self.date = date
        self.notes = notes
    }

    // MARK: - JSON-backed arrays

    var keyPoints: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(keyPointsJSON.utf8))) ?? [] }
        set { keyPointsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var decisions: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(decisionsJSON.utf8))) ?? [] }
        set { decisionsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    var openQuestions: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(openQuestionsJSON.utf8))) ?? [] }
        set { openQuestionsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    // MARK: - Convenience

    /// Resolved URL for the recorded WAV, nil if the file path is empty.
    var wavFileURL: URL? {
        guard let path = wavFilePath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
