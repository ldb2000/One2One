import EventKit
import Foundation
import SwiftData

// MARK: - Meeting kinds

/// Type de réunion. Détermine le contexte (projet, collaborateur, manager) et
/// l'UI associée. Valeur brute persistée en string sur `Meeting`.
enum MeetingKind: String, CaseIterable, Identifiable {
    /// Réunion ad-hoc, participants libres.
    case global   = "global"     // réunion ad-hoc, participants libres
    /// Réunion liée à un projet.
    case project  = "project"    // liée à un projet
    /// Entretien 1:1 avec un collaborateur.
    case oneToOne = "oneToOne"   // 1:1 avec un collaborateur
    /// Réunion de travail (équipe).
    case work     = "work"       // réunion de travail (équipe)
    /// Entretien 1:1 avec le manager direct.
    case manager  = "manager"    // 1:1 avec le manager direct
    /// Note libre — une réunion avec soi-même : ni audio, ni transcription, ni rapport.
    case note     = "note"
    /// Atelier : la séance produit des planches (croquis, schéma, manuscrit)
    /// plutôt qu'un ordre du jour. Cf. spec §7.
    case workshop = "workshop"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .global:   return "Globale"
        case .project:  return "Projet"
        case .oneToOne: return "One-to-One"
        case .work:     return "Architecture"
        case .manager:  return "1:1 Manager"
        case .note:     return "Note"
        case .workshop: return "Atelier"
        }
    }

    var sfSymbol: String {
        switch self {
        case .global:   return "person.3.fill"
        case .project:  return "folder.fill"
        case .oneToOne: return "person.2.fill"
        case .work:     return "briefcase.fill"
        case .manager:  return "person.crop.square.filled.and.at.rectangle"
        case .note:     return "note.text"
        case .workshop: return "rectangle.3.group.bubble"
        }
    }
}

/// Statut de présence d'un collaborateur à une réunion.
/// Persisté par collaborateur dans `Meeting.participantStatusesJSON`.
/// ⚠️ Les raw values (`"participant"`/`"absent"`) sont conservées pour la
/// compatibilité des données existantes ; ne pas les renommer.
enum MeetingAttendanceStatus: String, Codable, CaseIterable, Identifiable {
    case present = "participant"
    case refused = "absent"
    case pending = "pending"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .present: return "Présent"
        case .refused: return "A refusé"
        case .pending: return "En attente"
        }
    }

    var sfSymbol: String {
        switch self {
        case .present: return "person.fill.checkmark"
        case .refused: return "person.fill.xmark"
        case .pending: return "person.fill.questionmark"
        }
    }

    /// Mappe un statut de participation EventKit vers un statut de présence.
    static func fromCalendar(_ ek: EKParticipantStatus) -> MeetingAttendanceStatus {
        switch ek {
        case .declined: return .refused
        case .tentative, .pending: return .pending
        default: return .present   // accepted, unknown, delegated…
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

    /// Décode `embeddingData` (Float32 contigu) vers `[Float]` de longueur
    /// `embeddingDim` (~384 pour nomic-embed). Renvoie `[]` si non indexé.
    var embeddingVector: [Float] {
        guard let data = embeddingData, embeddingDim > 0 else { return [] }
        return data.withUnsafeBytes { buffer -> [Float] in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer.prefix(embeddingDim))
        }
    }

    /// Encode `vector` (Float32 contigu) dans `embeddingData` et mémorise le
    /// modèle et la dimension. `vector` doit être l'embedding produit par `model`.
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

/// Portée d'une pièce jointe (spec §1.3 `Attachment.scope`) : rattachée à la
/// séance ou au dossier du projet.
enum AttachmentScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case meeting = "meeting"
    case project = "project"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meeting: return "Cette séance"
        case .project: return "Le projet"
        }
    }
}

/// Provenance d'une capture (spec §1.3 `Capture.source`).
enum CaptureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case teams  = "teams"
    case zoom   = "zoom"
    case screen = "screen"
    case region = "region"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .teams:  return "Teams"
        case .zoom:   return "Zoom"
        case .screen: return "Écran entier"
        case .region: return "Zone"
        }
    }
}

/// Ce qui a déclenché une capture (spec §1.3 `Capture.trigger`).
enum CaptureTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Geste explicite (bouton, `⌘⇧S`, pastille).
    case manual      = "manual"
    /// Changement de partage détecté à l'image.
    case shareChange = "share_change"
    /// Capture périodique (« toutes les 2 minutes »).
    case interval    = "interval"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:      return "⌘⇧S"
        case .shareChange: return "auto"
        case .interval:    return "2 min"
        }
    }
}

@Model
final class SlideCapture: Identifiable {
    var id: UUID = UUID()
    var index: Int
    var capturedAt: Date
    var imagePath: String
    var ocrText: String = ""
    var perceptualHash: String = ""

    /// Instant sur l'axe temps de la réunion, en secondes. **L'axe de référence
    /// est l'audio** (`MeetingPlayhead`), pas l'horloge de la session de
    /// capture : `capturedAt` reste la date murale, `t` la position dans la
    /// séance. `nil` pour une capture faite hors enregistrement.
    var t: Double? = nil

    var sourceRaw: String = CaptureSource.screen.rawValue
    var source: CaptureSource {
        get { CaptureSource(rawValue: sourceRaw) ?? .screen }
        set { sourceRaw = newValue.rawValue }
    }

    var triggerRaw: String = CaptureTrigger.manual.rawValue
    var trigger: CaptureTrigger {
        get { CaptureTrigger(rawValue: triggerRaw) ?? .manual }
        set { triggerRaw = newValue.rawValue }
    }

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

    // MARK: - Modèle cible (spec §1.3 `Attachment`)

    var scopeRaw: String = AttachmentScope.meeting.rawValue
    var scope: AttachmentScope {
        get { AttachmentScope(rawValue: scopeRaw) ?? .meeting }
        set { scopeRaw = newValue.rawValue }
    }

    /// Type MIME, quand il est connu à l'import. Vide sinon — `kind` reste la
    /// classification utilisée par les vues.
    var mimeType: String = ""
    /// Taille du fichier copié, en octets. `0` = inconnue (lignes antérieures
    /// à la politique « copie, jamais référence », D5).
    var byteCount: Int = 0
    /// Qui a déposé la pièce, en clair (app mono-utilisateur).
    var addedByName: String = ""
    /// Timecode auquel la pièce a été épinglée dans la séance. `nil` = non
    /// épinglée.
    var pinnedAtT: Double? = nil
    /// Nombre de citations de la pièce dans les notes et le rapport.
    var citationCount: Int = 0

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
            return .present
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
            case .present:
                return collaborator.name
            case .refused:
                return "\(collaborator.name) (a refusé)"
            case .pending:
                return "\(collaborator.name) (en attente)"
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

    /// Duration to display in stats. Priority:
    /// 1. Calendar-scheduled duration (`scheduledStart`/`scheduledEnd`) — Outlook-style;
    /// 2. Pre-existing `meetingDurationSeconds` cache (legacy calendar field);
    /// 3. Fallback to recording duration (`durationSeconds`) for ad-hoc meetings.
    /// Inverted scheduled bounds are treated as invalid.
    var effectiveDuration: TimeInterval {
        if let s = scheduledStart, let e = scheduledEnd, e > s {
            return e.timeIntervalSince(s)
        }
        if meetingDurationSeconds > 0 {
            return TimeInterval(meetingDurationSeconds)
        }
        return TimeInterval(durationSeconds)
    }
}
