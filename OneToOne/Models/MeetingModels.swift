import Foundation
import SwiftData

// MARK: - Meeting kinds

enum MeetingKind: String, CaseIterable, Identifiable {
    case global   = "global"     // réunion ad-hoc, participants libres
    case project  = "project"    // liée à un projet
    case oneToOne = "oneToOne"   // 1:1 avec un collaborateur
    case work     = "work"       // réunion de travail (équipe)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .global:   return "Globale"
        case .project:  return "Projet"
        case .oneToOne: return "One-to-One"
        case .work:     return "Architecture"
        }
    }

    var sfSymbol: String {
        switch self {
        case .global:   return "person.3.fill"
        case .project:  return "folder.fill"
        case .oneToOne: return "person.2.fill"
        case .work:     return "briefcase.fill"
        }
    }
}

enum MeetingAttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case participant
    case absent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .participant: return "Participant"
        case .absent: return "Absent"
        }
    }

    var sfSymbol: String {
        switch self {
        case .participant: return "person.fill.checkmark"
        case .absent: return "person.fill.xmark"
        }
    }
}

// MARK: - Ad-hoc attendee helper

/// Participants entrés à la volée dans une réunion. Persistés comme
/// `Collaborator` avec `isAdhoc = true` pour réutilisation ultérieure.
struct AdhocAttendee: Codable, Hashable {
    var name: String
    var role: String
}

// MARK: - Transcript chunk (RAG)

/// Fragment de transcription indexé pour recherche sémantique.
/// Une transcription de réunion est découpée en chunks d'env. 500 tokens
/// avec overlap. Chaque chunk porte son embedding (Float32 contigu dans Data).
@Model
final class TranscriptChunk {
    var chunkId: UUID
    var text: String
    var orderIndex: Int = 0
    var embeddingData: Data?        // Float32 array, ~384 dim (nomic-embed)
    var embeddingModel: String = "" // ex: "nomic-embed-text:v1.5"
    var embeddingDim: Int = 0
    var sourceType: String = "meeting"  // meeting | attachment | mail
    var meeting: Meeting?
    var attachment: MeetingAttachment?
    var mail: ProjectMail?
    var createdAt: Date = Date()

    init(
        text: String,
        orderIndex: Int,
        sourceType: String = "meeting"
    ) {
        self.chunkId = UUID()
        self.text = text
        self.orderIndex = orderIndex
        self.sourceType = sourceType
        self.createdAt = Date()
    }

    /// Décodage des embeddings vers [Float].
    var embeddingVector: [Float] {
        guard let data = embeddingData, embeddingDim > 0 else { return [] }
        return data.withUnsafeBytes { buffer -> [Float] in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer.prefix(embeddingDim))
        }
    }

    func setEmbedding(_ vector: [Float], model: String) {
        self.embeddingModel = model
        self.embeddingDim = vector.count
        var mutable = vector
        self.embeddingData = mutable.withUnsafeMutableBufferPointer { ptr in
            Data(buffer: ptr)
        }
    }
}

// MARK: - Meeting attachment (documents, slides)

@Model
final class SlideCapture: Identifiable {
    var id: UUID = UUID()
    var index: Int
    var capturedAt: Date
    var imagePath: String
    var ocrText: String = ""
    var perceptualHash: String = ""
    var attachment: MeetingAttachment?

    init(index: Int, capturedAt: Date, imagePath: String) {
        self.index = index
        self.capturedAt = capturedAt
        self.imagePath = imagePath
    }
}

@Model
final class MeetingAttachment {
    var fileName: String
    var filePath: String
    var bookmarkData: Data?
    var kind: String = "document"   // pdf | pptx | docx | image | markdown | slides | other
    var extractedText: String = ""  // parsé au import
    var importedAt: Date = Date()
    var meeting: Meeting?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptChunk.attachment)
    var chunks: [TranscriptChunk] = []

    @Relationship(deleteRule: .cascade, inverse: \SlideCapture.attachment)
    var slides: [SlideCapture] = []

    init(url: URL, kind: String = "document") {
        self.fileName = url.lastPathComponent
        self.filePath = url.path
        self.kind = kind
        self.importedAt = Date()
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

extension Sequence where Element == Meeting {
    func uniquedByPersistentModelID() -> [Meeting] {
        var seen = Set<PersistentIdentifier>()
        return filter { seen.insert($0.persistentModelID).inserted }
    }
}

extension Meeting {
    var participantStatuses: [String: String] {
        get {
            (try? JSONDecoder().decode([String: String].self, from: Data(participantStatusesJSON.utf8))) ?? [:]
        }
        set {
            participantStatusesJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "{}"
        }
    }

    func participantStatus(for collaborator: Collaborator) -> MeetingAttendanceStatus {
        guard let raw = participantStatuses[collaborator.ensuredStableID.uuidString],
              let status = MeetingAttendanceStatus(rawValue: raw) else {
            return .participant
        }
        return status
    }

    func setParticipantStatus(_ status: MeetingAttendanceStatus, for collaborator: Collaborator) {
        var map = participantStatuses
        map[collaborator.ensuredStableID.uuidString] = status.rawValue
        participantStatuses = map
    }

    func clearParticipantStatus(for collaborator: Collaborator) {
        var map = participantStatuses
        map.removeValue(forKey: collaborator.ensuredStableID.uuidString)
        participantStatuses = map
    }

    var participantsDescription: String {
        participants.map { collaborator in
            switch participantStatus(for: collaborator) {
            case .participant:
                return collaborator.name
            case .absent:
                return "\(collaborator.name) (absent)"
            }
        }
        .joined(separator: ", ")
    }

    var highlights: [String] {
        var items: [String] = []
        items.append(contentsOf: decisions)
        items.append(contentsOf: keyPoints)
        items.append(contentsOf: tasks.filter { !$0.isCompleted }.map { "Action: \($0.title)" })
        items.append(contentsOf: openQuestions.map { "Point d'attention: \($0)" })

        var seen = Set<String>()
        return items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
