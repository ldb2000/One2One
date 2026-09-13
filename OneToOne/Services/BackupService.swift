import Foundation
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// Service d'export/import de l'intégralité des données de l'app sous forme
/// d'un unique fichier JSON. Sérialise SwiftData vers des DTO `Codable`
/// auto-contenus (données binaires des pièces jointes/WAV/slides incluses) puis
/// reconstruit le graphe d'objets lors de la restauration.
///
/// Les sauvegardes écrites avant la fusion Note/Réunion contiennent encore des
/// clés `infoEntries` et `collaboratorEntries` : `JSONDecoder` ignore les clés
/// qu'aucune propriété ne réclame, elles restent donc lisibles. Ces tableaux
/// étaient vides dans toutes les bases connues.
final class BackupService {

    /// Le magasin des planches d'atelier — injectable pour que les tests
    /// n'écrivent pas dans le `recordings/` de production. Optionnel plutôt
    /// que défaut `.shared`, dont l'évaluation chez l'appelant n'est pas isolée
    /// sur l'acteur principal.
    private let boardStoreOverride: BoardStore?

    init(boardStore: BoardStore? = nil) {
        self.boardStoreOverride = boardStore
    }

    @MainActor
    private var boardStore: BoardStore { boardStoreOverride ?? .shared }

    struct BackupPayload: Codable {
        var exportedAt: Date
        var settings: SettingsDTO
        var entities: [EntityDTO]
        var projects: [ProjectDTO]
        var collaborators: [CollaboratorDTO]
        /// Optionnel pour rester rétro-compatible avec les anciens backups
        /// (sans réunions). Ajouté en avril 2026 — le backup inclut désormais
        /// transcript, rapport, notes live, WAV, documents joints et slides.
        var meetings: [MeetingDTO]?
        /// Items du rapport manager (V3 — sous-projet C). Optionnel pour rester
        /// rétro-compatible avec les backups antérieurs à cette fonctionnalité.
        var managerReportItems: [ManagerReportItemDTO]?
        var managerMeetingReports: [ManagerMeetingReportDTO]?
        var managerActions: [ManagerActionTaskDTO]?     // V3 — sub-projet C
    }

    struct SettingsDTO: Codable {
        /// Lecture des anciens exports uniquement ; jamais écrit dans les nouveaux.
        var cloudToken: String?
        var apiEndpoint: String
        var modelName: String
        var provider: String
        var importPrompt: String
        var reformulatePrompt: String
        var weeklyExportPrompt: String
        // Manager (sub-projet C)
        var managerName: String?
        var managerEmail: String?
        var managerCategoriesJSON: String?
        var managerReportPrompt: String?
        var aiConfigurationVersion: Int? = nil
        var aiProfilesJSON: String? = nil
        var directModelRepo: String? = nil
        var allowRemoteMailClassification: Bool? = nil
        /// Les vues enregistrées du Portfolio (décision **D4** de la refonte
        /// des projets). Optionnelle : une sauvegarde antérieure au lot 2 n'en
        /// porte pas, et une liste vide est la valeur par défaut du modèle.
        var portfolioSavedViewsJSON: String? = nil
    }

    struct EntityDTO: Codable {
        var name: String
        var summary: String?
    }

    struct ProjectAttachmentDTO: Codable {
        var fileName: String
        var filePath: String
        var bookmarkData: Data?
        var fileData: Data?
        var category: String
        var comment: String
        var importedAt: Date
    }

    struct ProjectDTO: Codable {
        var code: String
        var name: String
        var domain: String
        var sponsor: String
        var projectType: String
        var phase: String
        var status: String
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
        var budgetDeliver: Double?
        var budgetInit: Double?
        var budgetRev: Double?
        var budgetCons: Double?
        var percentConsoCharge: Double?
        var startDate: Date?
        var endDateInitial: Date?
        var endDateRevised: Date?
        var productionDeliveryProgress: Double?
        var planningProgress: Double?
        var riskLevel: String?
        var riskDescription: String?
        var keyPoints: [String]
        var hasDAT: Bool
        var datLink: String?
        var hasDIT: Bool
        var ditLink: String?
        var entityName: String?
        var attachments: [ProjectAttachmentDTO]
        /// Optionnels pour rester lisibles par les sauvegardes antérieures au
        /// lot 19c (fiche projet du lot 9).
        var milestones: [ProjectMilestoneDTO]?
        var contacts: [ProjectContactDTO]?
        /// Épinglage dans la barre latérale (décision **D4** de la refonte des
        /// projets). Optionnel : une sauvegarde antérieure au lot 1 n'en porte
        /// pas, et `false` est la valeur par défaut du modèle.
        var pinned: Bool?
        /// Le périmètre du projet et la date de sa dernière modification,
        /// posée par l'édition in-place (décision **D9**).
        ///
        /// `scopeText` accompagne `scopeUpdatedAt` : sauvegarder la date sans
        /// le texte restaurerait un « mis à jour le … » qui ne désigne rien.
        /// Optionnels, comme tout ce qu'une sauvegarde antérieure ignore.
        var scopeText: String?
        var scopeUpdatedAt: Date?
    }

    struct CollaboratorDTO: Codable {
        var name: String
        var role: String
        var isArchived: Bool
        var photoPath: String
        var photoBookmarkData: Data?
        var photoData: Data?
        /// Les fils 1:1 de ce collaborateur (lot 10, décision D3). Optionnel
        /// pour rester lisible par les sauvegardes antérieures au lot 19c.
        var threads: [OneOnOneThreadDTO]?
    }


    struct TaskDTO: Codable {
        var title: String
        var projectCode: String?
        var dueDate: Date?
        var isCompleted: Bool
        var reminderID: String?
    }

    struct AlertDTO: Codable {
        var title: String
        var detail: String
        var severity: String
        var date: Date
        var isResolved: Bool
        var projectCode: String?
    }

    struct SlideCaptureDTO: Codable {
        var index: Int
        var capturedAt: Date
        var imagePath: String
        var imageFileName: String
        var imageData: Data?
        var ocrText: String
        var perceptualHash: String
    }

    struct MeetingAttachmentDTO: Codable {
        var fileName: String
        var filePath: String
        var bookmarkData: Data?
        var fileData: Data?
        var kind: String
        var extractedText: String
        var importedAt: Date
        var slides: [SlideCaptureDTO]

        // MARK: - Modèle cible (spec §1.3 `Attachment`, lot 6)
        //
        // Tous **optionnels** : une sauvegarde antérieure au lot 6 ne les
        // porte pas, et elle doit rester décodable. La restauration retombe
        // alors sur les valeurs par défaut du modèle, et la migration
        // paresseuse (D5) fera le reste à la première ouverture.
        var scopeRaw: String?
        var mimeType: String?
        var byteCount: Int?
        var addedByName: String?
        var pinnedAtT: Double?
        var citationCount: Int?
        var stableID: UUID?
    }

    struct TranscriptChunkDTO: Codable {
        var chunkId: UUID
        var text: String
        var orderIndex: Int
        var sourceType: String
        var createdAt: Date
    }

    /// Une planche d'atelier. Scène et vignette voyagent **en base64** dans le
    /// JSON, comme `SlideCaptureDTO` : un backup doit rester un seul fichier
    /// auto-contenu, et les chemins d'origine ne survivent pas à une
    /// restauration sur une autre machine.
    struct BoardDTO: Codable {
        var stableID: UUID
        var index: Int
        var title: String
        var modeRaw: String
        var t: Double
        var authorNames: String
        var updatedAt: Date
        var sceneJSON: String?
        var thumbData: Data?
    }

    // MARK: - Les tables du lot 0B (SchemaV3)
    //
    // Neuf tables ont été ajoutées au lot 0B ; seule `Board` était exportée
    // (lot 16, avec son dossier `boards/`). Les huit autres sortaient d'une
    // sauvegarde silencieusement vides. Toutes les clés porteuses
    // (`timedNotes`, `milestones`, `contacts`, `threads`) sont **optionnelles**
    // pour qu'une sauvegarde antérieure se relise, comme `boards` l'a fait.

    /// Note horodatée (spec §1.3, décision D1). Les trois colonnes de la
    /// chaîne de citation sont plates, comme dans le modèle.
    struct MeetingNoteDTO: Codable {
        var stableID: UUID?
        var t: Double
        var text: String
        var kindRaw: String
        /// Le niveau de confidentialité **doit** faire l'aller-retour : le
        /// perdre republierait une note privée dans le prochain récap.
        var visibilityRaw: String
        var authorSideRaw: String
        var sourceKindRaw: String?
        var sourceStableID: UUID?
        var sourceT: Double?
        var orderIndex: Int
        var createdAt: Date
    }

    struct ProjectMilestoneDTO: Codable {
        var stableID: UUID?
        var label: String
        var dueAt: Date?
        var stateRaw: String
        var order: Int
        var createdAt: Date
    }

    struct ProjectContactDTO: Codable {
        var stableID: UUID?
        var name: String
        var role: String
        var order: Int
        var createdAt: Date
    }

    /// Engagement d'un fil 1:1. `promisedInMeetingID` est le `stableID` de la
    /// réunion où il a été pris : une référence, recousue après la
    /// restauration des réunions.
    ///
    /// `linkedAction` n'est **pas** portée : `ActionTask` n'expose pas
    /// d'identité stable, et relier par titre créerait de faux liens entre
    /// deux actions homonymes. Le lien se reconstruit à l'usage ; la dette est
    /// notée dans l'ADR de bilan.
    struct CommitmentDTO: Codable {
        var stableID: UUID?
        var text: String
        var ownerSideRaw: String
        var dueAt: Date?
        var stateRaw: String
        var promisedAt: Date
        var settledAt: Date?
        var deferralCount: Int
        var visibilityRaw: String
        var blocksOther: Bool
        var linkedDecisionIndex: Int?
        var promisedInMeetingID: UUID?
    }

    struct OneOnOneAgendaItemDTO: Codable {
        var stableID: UUID?
        var text: String
        var addedBySideRaw: String
        var order: Int
        var stateRaw: String
        var visibilityRaw: String
        var kindRaw: String
        var requestStatusRaw: String
        var requestedAt: Date?
        var remindedCount: Int
        var createdAt: Date
        var meetingID: UUID?
        var deferredToMeetingID: UUID?
    }

    struct MoodEntryDTO: Codable {
        var stableID: UUID?
        var value: Int
        var recordedAt: Date
        var meetingID: UUID?
    }

    struct OneOnOneObjectiveDTO: Codable {
        var stableID: UUID?
        var label: String
        var progress: Int
        var reviewAt: Date?
        var order: Int
        var createdAt: Date
    }

    /// Le fil d'un collaborateur, avec ses quatre tables filles. Elles sont
    /// nichées et non listées à plat : le fil les possède en cascade, et un
    /// engagement sans son fil n'a pas de sens.
    struct OneOnOneThreadDTO: Codable {
        var stableID: UUID?
        var myRoleRaw: String
        var cadenceDays: Int
        var createdAt: Date
        var commitments: [CommitmentDTO]
        var agendaItems: [OneOnOneAgendaItemDTO]
        var moodEntries: [MoodEntryDTO]
        var objectives: [OneOnOneObjectiveDTO]
    }

    struct MeetingDTO: Codable {
        var stableID: UUID
        var title: String
        var date: Date
        var notes: String
        var kindRaw: String
        var customPrompt: String
        var liveNotes: String
        var rawTranscript: String
        var mergedTranscript: String
        var summary: String
        var keyPointsJSON: String
        var decisionsJSON: String
        var openQuestionsJSON: String
        var wavFileName: String?
        var wavFilePath: String?
        var wavData: Data?
        var durationSeconds: Int
        var calendarEventID: String
        var calendarEventTitle: String
        var reportGenerationDurationSeconds: Double
        var participantStatusesJSON: String
        var adhocAttendeesJSON: String
        var projectCode: String?
        var participantNames: [String]
        var attachments: [MeetingAttachmentDTO]
        var transcriptChunks: [TranscriptChunkDTO]
        /// Optionnel pour rester lisible par les backups antérieurs au lot 16.
        var boards: [BoardDTO]?
        /// Les notes horodatées de la réunion (lot 0B, D1). Optionnel pour la
        /// même raison, à partir du lot 19c.
        var timedNotes: [MeetingNoteDTO]?
    }


    struct ManagerReportItemDTO: Codable {
        var stableID: UUID
        var createdAt: Date
        var rawSnippet: String
        var contextBefore: String
        var contextAfter: String
        var elaboratedText: String?     // Optional pour rétro-compat backups V3.0
        var sourceField: String
        var sourceRangeStart: Int
        var sourceRangeLength: Int
        var category: String
        var tag: String
        var aiSuggestedCategory: String?
        var userNotes: String
        var isCompleted: Bool
        var archivedAt: Date?
        var manualOrder: Int
        var isManual: Bool
        var duplicateOfStableID: String
        var sourceMeetingStableID: UUID?
        var archivedInMeetingStableID: UUID?
    }

    struct ManagerMeetingReportDTO: Codable {
        var stableID: UUID
        var generatedAt: Date
        var generatedSummary: String
        var durationSeconds: Double
        var modelUsed: String
        var itemsSnapshotJSON: String
        var extractedActionsJSON: String
        var meetingStableID: UUID?
    }

    struct ManagerActionTaskDTO: Codable {
        var title: String
        var dueDate: Date?
        var isCompleted: Bool
        var reminderID: String?
        var managerMeetingStableID: UUID?
    }

    /// Sérialise l'ensemble des données fournies en un payload JSON auto-contenu
    /// (ISO-8601, clés triées). Les fichiers référencés (pièces jointes, WAV,
    /// images de slides) sont embarqués sous forme de `Data` lorsqu'ils existent.
    @MainActor
    func backup(
        settings: AppSettings,
        entities: [Entity],
        projects: [Project],
        collaborators: [Collaborator],
        meetings: [Meeting] = [],
        managerReportItems: [ManagerReportItem] = [],
        managerMeetingReports: [ManagerMeetingReport] = [],
        managerActions: [ActionTask] = []
    ) throws -> Data {
        // Les fils 1:1 ne sont pas une relation de `Collaborator` (le lot 10
        // les a voulus interrogeables, pas possédés) : aucun appelant ne peut
        // donc les passer. On les lit dans le contexte des collaborateurs
        // exportés — un fetch, pas un par collaborateur.
        let tousLesFils: [OneOnOneThread] = {
            guard let contexte = collaborators.compactMap(\.modelContext).first else { return [] }
            return (try? contexte.fetch(FetchDescriptor<OneOnOneThread>())) ?? []
        }()

        let payload = BackupPayload(
            exportedAt: Date(),
            settings: SettingsDTO(
                cloudToken: nil,
                apiEndpoint: settings.apiEndpoint,
                modelName: settings.modelName,
                provider: settings.providerRaw,
                importPrompt: settings.importPrompt,
                reformulatePrompt: settings.reformulatePrompt,
                weeklyExportPrompt: settings.weeklyExportPrompt,
                managerName: settings.managerName,
                managerEmail: settings.managerEmail,
                managerCategoriesJSON: settings.managerCategoriesJSON,
                managerReportPrompt: settings.managerReportPrompt,
                aiConfigurationVersion: 1,
                aiProfilesJSON: try AIConfigurationStore.encode(AIConfigurationStore.profiles(for: settings).map {
                    var profile = $0
                    profile.credentialID = nil
                    return profile
                }),
                directModelRepo: settings.directModelRepo,
                allowRemoteMailClassification: settings.allowRemoteMailClassification,
                portfolioSavedViewsJSON: settings.portfolioSavedViewsJSON
            ),
            entities: entities.map { EntityDTO(name: $0.name, summary: $0.summary) },
            projects: projects.map { project in
                ProjectDTO(
                    code: project.code,
                    name: project.name,
                    domain: project.domain,
                    sponsor: project.sponsor,
                    projectType: project.projectType,
                    phase: project.phase,
                    status: project.status,
                    projectDeliveryDate: project.projectDeliveryDate,
                    designEndDeadline: project.designEndDeadline,
                    plannedDays: project.plannedDays,
                    businessPlanningStatus: project.businessPlanningStatus,
                    comment: project.comment,
                    followUpNotes: project.followUpNotes,
                    cespPlanningStatus: project.cespPlanningStatus,
                    technicalSpecStatus: project.technicalSpecStatus,
                    comment2: project.comment2,
                    additionalInfo: project.additionalInfo,
                    buildRetex: project.buildRetex,
                    budgetDeliver: project.budgetDeliver,
                    budgetInit: project.budgetInit,
                    budgetRev: project.budgetRev,
                    budgetCons: project.budgetCons,
                    percentConsoCharge: project.percentConsoCharge,
                    startDate: project.startDate,
                    endDateInitial: project.endDateInitial,
                    endDateRevised: project.endDateRevised,
                    productionDeliveryProgress: project.productionDeliveryProgress,
                    planningProgress: project.planningProgress,
                    riskLevel: project.riskLevel,
                    riskDescription: project.riskDescription,
                    keyPoints: project.keyPoints,
                    hasDAT: project.hasDAT,
                    datLink: project.datLink?.absoluteString,
                    hasDIT: project.hasDIT,
                    ditLink: project.ditLink?.absoluteString,
                    entityName: project.entity?.name,
                    attachments: project.attachments.map {
                        ProjectAttachmentDTO(
                            fileName: $0.fileName,
                            filePath: $0.filePath,
                            bookmarkData: $0.bookmarkData,
                            fileData: fileData(fromPath: $0.filePath),
                            category: $0.category,
                            comment: $0.comment,
                            importedAt: $0.importedAt
                        )
                    },
                    milestones: project.milestones
                        .sorted { $0.order < $1.order }
                        .map { jalon in
                            ProjectMilestoneDTO(
                                stableID: jalon.ensuredStableID,
                                label: jalon.label,
                                dueAt: jalon.dueAt,
                                stateRaw: jalon.stateRaw,
                                order: jalon.order,
                                createdAt: jalon.createdAt
                            )
                        },
                    contacts: project.contacts
                        .sorted { $0.order < $1.order }
                        .map { contact in
                            ProjectContactDTO(
                                stableID: contact.ensuredStableID,
                                name: contact.name,
                                role: contact.role,
                                order: contact.order,
                                createdAt: contact.createdAt
                            )
                        },
                    pinned: project.pinned,
                    scopeText: project.scopeText,
                    scopeUpdatedAt: project.scopeUpdatedAt
                )
            },
            collaborators: collaborators.map { collaborateur in
                CollaboratorDTO(
                    name: collaborateur.name,
                    role: collaborateur.role,
                    isArchived: collaborateur.isArchived,
                    photoPath: collaborateur.photoPath,
                    photoBookmarkData: collaborateur.photoBookmarkData,
                    photoData: fileData(fromPath: collaborateur.photoPath),
                    threads: Self.threadDTOs(for: collaborateur, among: tousLesFils)
                )
            },
            meetings: meetings.map { meeting in
                MeetingDTO(
                    stableID: meeting.ensuredStableID,
                    title: meeting.title,
                    date: meeting.date,
                    notes: meeting.notes,
                    kindRaw: meeting.kindRaw,
                    customPrompt: meeting.customPrompt,
                    liveNotes: meeting.liveNotes,
                    rawTranscript: meeting.rawTranscript,
                    mergedTranscript: meeting.mergedTranscript,
                    summary: meeting.summary,
                    keyPointsJSON: meeting.keyPointsJSON,
                    decisionsJSON: meeting.decisionsJSON,
                    openQuestionsJSON: meeting.openQuestionsJSON,
                    wavFileName: meeting.wavFilePath.map { URL(fileURLWithPath: $0).lastPathComponent },
                    wavFilePath: meeting.wavFilePath,
                    wavData: meeting.wavFilePath.flatMap { fileData(fromPath: $0) },
                    durationSeconds: meeting.durationSeconds,
                    calendarEventID: meeting.calendarEventID,
                    calendarEventTitle: meeting.calendarEventTitle,
                    reportGenerationDurationSeconds: meeting.reportGenerationDurationSeconds,
                    participantStatusesJSON: meeting.participantStatusesJSON,
                    adhocAttendeesJSON: meeting.adhocAttendeesJSON,
                    projectCode: meeting.project?.code,
                    participantNames: meeting.participants.map(\.name),
                    attachments: meeting.attachments.map { att in
                        MeetingAttachmentDTO(
                            fileName: att.fileName,
                            filePath: att.filePath,
                            bookmarkData: att.bookmarkData,
                            fileData: fileData(fromPath: att.filePath),
                            kind: att.kind,
                            extractedText: att.extractedText,
                            importedAt: att.importedAt,
                            slides: att.slides.map { slide in
                                let slideURL = URL(fileURLWithPath: slide.imagePath)
                                return SlideCaptureDTO(
                                    index: slide.index,
                                    capturedAt: slide.capturedAt,
                                    imagePath: slide.imagePath,
                                    imageFileName: slideURL.lastPathComponent,
                                    imageData: fileData(fromPath: slide.imagePath),
                                    ocrText: slide.ocrText,
                                    perceptualHash: slide.perceptualHash
                                )
                            },
                            scopeRaw: att.scopeRaw,
                            mimeType: att.mimeType,
                            byteCount: att.byteCount,
                            addedByName: att.addedByName,
                            pinnedAtT: att.pinnedAtT,
                            citationCount: att.citationCount,
                            stableID: att.stableID
                        )
                    },
                    transcriptChunks: meeting.transcriptChunks
                        .sorted { $0.orderIndex < $1.orderIndex }
                        .map { chunk in
                            TranscriptChunkDTO(
                                chunkId: chunk.chunkId,
                                text: chunk.text,
                                orderIndex: chunk.orderIndex,
                                sourceType: chunk.sourceType,
                                createdAt: chunk.createdAt
                            )
                        },
                    boards: meeting.boards.map { board in
                        let identifiant = board.ensuredStableID
                        let reunion = meeting.ensuredStableID
                        return BoardDTO(
                            stableID: identifiant,
                            index: board.index,
                            title: board.title,
                            modeRaw: board.modeRaw,
                            t: board.t,
                            authorNames: board.authorNames,
                            updatedAt: board.updatedAt,
                            sceneJSON: boardStore.loadScene(board: board,
                                                                   meetingStableID: reunion),
                            thumbData: boardStore.thumbnailData(board: board,
                                                                       meetingStableID: reunion)
                        )
                    },
                    timedNotes: meeting.timedNotes
                        .sorted { ($0.t, $0.orderIndex) < ($1.t, $1.orderIndex) }
                        .map { note in
                            MeetingNoteDTO(
                                stableID: note.ensuredStableID,
                                t: note.t,
                                text: note.text,
                                kindRaw: note.kindRaw,
                                visibilityRaw: note.visibilityRaw,
                                authorSideRaw: note.authorSideRaw,
                                sourceKindRaw: note.sourceKindRaw,
                                sourceStableID: note.sourceStableID,
                                sourceT: note.sourceT,
                                orderIndex: note.orderIndex,
                                createdAt: note.createdAt
                            )
                        }
                )
            },
            managerReportItems: managerReportItems.map { item in
                ManagerReportItemDTO(
                    stableID: item.ensuredStableID,
                    createdAt: item.createdAt,
                    rawSnippet: item.rawSnippet,
                    contextBefore: item.contextBefore,
                    contextAfter: item.contextAfter,
                    elaboratedText: item.elaboratedText,
                    sourceField: item.sourceField,
                    sourceRangeStart: item.sourceRangeStart,
                    sourceRangeLength: item.sourceRangeLength,
                    category: item.category,
                    tag: item.tag,
                    aiSuggestedCategory: item.aiSuggestedCategory,
                    userNotes: item.userNotes,
                    isCompleted: item.isCompleted,
                    archivedAt: item.archivedAt,
                    manualOrder: item.manualOrder,
                    isManual: item.isManual,
                    duplicateOfStableID: item.duplicateOfStableID,
                    sourceMeetingStableID: item.sourceMeeting?.stableID,
                    archivedInMeetingStableID: item.archivedInMeeting?.stableID
                )
            },
            managerMeetingReports: managerMeetingReports.map { report in
                ManagerMeetingReportDTO(
                    stableID: report.ensuredStableID,
                    generatedAt: report.generatedAt,
                    generatedSummary: report.generatedSummary,
                    durationSeconds: report.durationSeconds,
                    modelUsed: report.modelUsed,
                    itemsSnapshotJSON: report.itemsSnapshotJSON,
                    extractedActionsJSON: report.extractedActionsJSON,
                    meetingStableID: report.meeting?.stableID
                )
            }
            ,
            managerActions: managerActions.map { task in
                ManagerActionTaskDTO(
                    title: task.title,
                    dueDate: task.dueDate,
                    isCompleted: task.isCompleted,
                    reminderID: task.reminderID,
                    managerMeetingStableID: task.managerMeeting?.stableID
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Restaure un backup JSON dans le `ModelContext` : supprime d'abord toutes
    /// les données existantes, puis reconstruit le graphe d'objets et réécrit les
    /// fichiers embarqués sur disque. Opération destructive (remplace tout).
    ///
    /// (La fabrique des DTO de fil vit juste au-dessus de `restore`.)

    /// Les fils d'un collaborateur, parmi ceux du contexte.
    ///
    /// Comparaison par `persistentModelID` : deux objets SwiftData du même
    /// contexte partagent leur identité, et `===` sur des classes `@Model`
    /// proxifiées n'est pas fiable.
    private static func threadDTOs(for collaborateur: Collaborator,
                                   among fils: [OneOnOneThread]) -> [OneOnOneThreadDTO]? {
        let siens = fils.filter {
            $0.collaborator?.persistentModelID == collaborateur.persistentModelID
        }
        guard !siens.isEmpty else { return nil }
        return siens.map { fil in
            OneOnOneThreadDTO(
                stableID: fil.ensuredStableID,
                myRoleRaw: fil.myRoleRaw,
                cadenceDays: fil.cadenceDays,
                createdAt: fil.createdAt,
                commitments: fil.commitments.map { engagement in
                    CommitmentDTO(
                        stableID: engagement.ensuredStableID,
                        text: engagement.text,
                        ownerSideRaw: engagement.ownerSideRaw,
                        dueAt: engagement.dueAt,
                        stateRaw: engagement.stateRaw,
                        promisedAt: engagement.promisedAt,
                        settledAt: engagement.settledAt,
                        deferralCount: engagement.deferralCount,
                        visibilityRaw: engagement.visibilityRaw,
                        blocksOther: engagement.blocksOther,
                        linkedDecisionIndex: engagement.linkedDecisionIndex,
                        promisedInMeetingID: engagement.promisedInMeeting?.ensuredStableID
                    )
                },
                agendaItems: fil.agendaItems
                    .sorted { $0.order < $1.order }
                    .map { sujet in
                        OneOnOneAgendaItemDTO(
                            stableID: sujet.ensuredStableID,
                            text: sujet.text,
                            addedBySideRaw: sujet.addedBySideRaw,
                            order: sujet.order,
                            stateRaw: sujet.stateRaw,
                            visibilityRaw: sujet.visibilityRaw,
                            kindRaw: sujet.kindRaw,
                            requestStatusRaw: sujet.requestStatusRaw,
                            requestedAt: sujet.requestedAt,
                            remindedCount: sujet.remindedCount,
                            createdAt: sujet.createdAt,
                            meetingID: sujet.meeting?.ensuredStableID,
                            deferredToMeetingID: sujet.deferredToMeeting?.ensuredStableID
                        )
                    },
                moodEntries: fil.moodEntries
                    .sorted { $0.recordedAt < $1.recordedAt }
                    .map { humeur in
                        MoodEntryDTO(
                            stableID: humeur.ensuredStableID,
                            value: humeur.value,
                            recordedAt: humeur.recordedAt,
                            meetingID: humeur.meeting?.ensuredStableID
                        )
                    },
                objectives: fil.objectives
                    .sorted { $0.order < $1.order }
                    .map { objectif in
                        OneOnOneObjectiveDTO(
                            stableID: objectif.ensuredStableID,
                            label: objectif.label,
                            progress: objectif.progress,
                            reviewAt: objectif.reviewAt,
                            order: objectif.order,
                            createdAt: objectif.createdAt
                        )
                    }
            )
        }
    }

    @MainActor
    func restore(from data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard (payload.settings.aiConfigurationVersion ?? 0) <= 1 else {
            throw AIEndpointError.invalidConfiguration
        }
        // Valider avant toute suppression et ignorer les références de secrets
        // de la machine d'origine, même dans un export modifié manuellement.
        var restoredProfilesJSON = ""
        if let json = payload.settings.aiProfilesJSON, !json.isEmpty {
            guard let bytes = json.data(using: .utf8),
                  let profiles = try? JSONDecoder().decode([AIEndpointProfile].self, from: bytes),
                  Set(profiles.map(\.provider)).count == profiles.count else {
                throw AIEndpointError.invalidConfiguration
            }
            restoredProfilesJSON = try AIConfigurationStore.encode(profiles.map {
                var profile = $0
                profile.credentialID = nil
                return profile
            })
        }
        let restoredFilesDirectory = try createRestoreFilesDirectory()

        let existingProjects = try context.fetch(FetchDescriptor<Project>())
        let existingCollaborators = try context.fetch(FetchDescriptor<Collaborator>())
        let existingEntities = try context.fetch(FetchDescriptor<Entity>())
        let existingSettings = try context.fetch(FetchDescriptor<AppSettings>())
        let existingMeetings = try context.fetch(FetchDescriptor<Meeting>())
        let existingMgrItems = try context.fetch(FetchDescriptor<ManagerReportItem>())
        let existingMgrReports = try context.fetch(FetchDescriptor<ManagerMeetingReport>())
        for item in existingMgrItems { context.delete(item) }
        for report in existingMgrReports { context.delete(report) }

        // Also clear pre-existing manager-extracted actions (those with fromManager=true).
        let existingMgrActions = (try? context.fetch(FetchDescriptor<ActionTask>(
            predicate: #Predicate { $0.fromManager == true }
        ))) ?? []
        for action in existingMgrActions { context.delete(action) }

        // Les réunions (notes comprises) sont indexées dans Spotlight :
        // `remove(meeting:)` avant `delete`, sinon l'index garde des entrées
        // cliquables pointant sur des modèles disparus — rien ne rappelle
        // jamais `remove` pour un modèle qui n'existe plus.
        for meeting in existingMeetings {
            SpotlightIndexService.shared.remove(meeting: meeting)
            context.delete(meeting)
        }
        for project in existingProjects { context.delete(project) }
        for collaborator in existingCollaborators { context.delete(collaborator) }
        for entity in existingEntities { context.delete(entity) }
        for setting in existingSettings { context.delete(setting) }

        let restoredSettings = AppSettings()
        restoredSettings.cloudToken = payload.settings.cloudToken ?? ""
        restoredSettings.apiEndpoint = payload.settings.apiEndpoint
        restoredSettings.modelName = payload.settings.modelName
        restoredSettings.providerRaw = payload.settings.provider
        restoredSettings.aiProfilesJSON = restoredProfilesJSON
        restoredSettings.directModelRepo = payload.settings.directModelRepo ?? AIProvider.legacyDirectModelRepo
        // La restauration n'autorise pas à elle seule de nouveaux envois de mails.
        restoredSettings.allowRemoteMailClassification = false
        restoredSettings.importPrompt = payload.settings.importPrompt
        restoredSettings.reformulatePrompt = payload.settings.reformulatePrompt
        restoredSettings.weeklyExportPrompt = payload.settings.weeklyExportPrompt
        context.insert(restoredSettings)
        restoredSettings.managerName = payload.settings.managerName ?? ""
        restoredSettings.managerEmail = payload.settings.managerEmail ?? ""
        restoredSettings.managerCategoriesJSON = payload.settings.managerCategoriesJSON ?? AppSettings.defaultManagerCategoriesJSON
        restoredSettings.managerReportPrompt = payload.settings.managerReportPrompt ?? AppSettings.defaultManagerReportPrompt
        // Vues enregistrées du Portfolio : « [] » plutôt que `nil` pour une
        // sauvegarde antérieure au lot 2 — le décodeur de `portfolioSavedViews`
        // rend une liste vide sur toute chaîne illisible, mais la colonne, elle,
        // ne doit pas rester vide au sens de « chaîne vide ».
        restoredSettings.portfolioSavedViewsJSON = payload.settings.portfolioSavedViewsJSON ?? "[]"

        var entityMap: [String: Entity] = [:]
        for entityDTO in payload.entities {
            let entity = Entity(name: entityDTO.name, summary: entityDTO.summary)
            context.insert(entity)
            entityMap[entity.name] = entity
        }

        var projectMap: [String: Project] = [:]
        for projectDTO in payload.projects {
            let project = Project(
                code: projectDTO.code,
                name: projectDTO.name,
                domain: projectDTO.domain,
                sponsor: projectDTO.sponsor,
                projectType: projectDTO.projectType,
                phase: projectDTO.phase,
                status: projectDTO.status
            )
            project.projectDeliveryDate = projectDTO.projectDeliveryDate
            project.designEndDeadline = projectDTO.designEndDeadline
            project.plannedDays = projectDTO.plannedDays
            project.businessPlanningStatus = projectDTO.businessPlanningStatus
            project.comment = projectDTO.comment
            project.followUpNotes = projectDTO.followUpNotes
            project.cespPlanningStatus = projectDTO.cespPlanningStatus
            project.technicalSpecStatus = projectDTO.technicalSpecStatus
            project.comment2 = projectDTO.comment2
            project.additionalInfo = projectDTO.additionalInfo
            project.buildRetex = projectDTO.buildRetex
            project.budgetDeliver = projectDTO.budgetDeliver
            project.budgetInit = projectDTO.budgetInit
            project.budgetRev = projectDTO.budgetRev
            project.budgetCons = projectDTO.budgetCons
            project.percentConsoCharge = projectDTO.percentConsoCharge
            project.startDate = projectDTO.startDate
            project.endDateInitial = projectDTO.endDateInitial
            project.endDateRevised = projectDTO.endDateRevised
            project.productionDeliveryProgress = projectDTO.productionDeliveryProgress
            project.planningProgress = projectDTO.planningProgress
            project.riskLevel = projectDTO.riskLevel
            project.riskDescription = projectDTO.riskDescription
            project.keyPoints = projectDTO.keyPoints
            project.hasDAT = projectDTO.hasDAT
            project.datLink = projectDTO.datLink.flatMap(URL.init(string:))
            project.hasDIT = projectDTO.hasDIT
            project.ditLink = projectDTO.ditLink.flatMap(URL.init(string:))
            project.entity = projectDTO.entityName.flatMap { entityMap[$0] }
            // Refonte des projets : épinglage (D4) et date de périmètre (D9).
            // Une sauvegarde antérieure ne les porte pas — les défauts du
            // modèle s'appliquent alors.
            project.pinned = projectDTO.pinned ?? false
            project.scopeText = projectDTO.scopeText ?? ""
            project.scopeUpdatedAt = projectDTO.scopeUpdatedAt
            context.insert(project)

            for attachmentDTO in projectDTO.attachments {
                let restoredURL = try restoredFileURL(
                    fileName: attachmentDTO.fileName,
                    filePath: attachmentDTO.filePath,
                    fileData: attachmentDTO.fileData,
                    in: restoredFilesDirectory
                )
                let attachment = ProjectAttachment(
                    url: restoredURL,
                    category: attachmentDTO.category,
                    comment: attachmentDTO.comment,
                    importedAt: attachmentDTO.importedAt
                )
                attachment.fileName = attachmentDTO.fileName
                attachment.bookmarkData = attachmentDTO.bookmarkData
                attachment.project = project
                context.insert(attachment)
            }

            // Fiche projet (lot 9) : jalons et interlocuteurs.
            for jalonDTO in projectDTO.milestones ?? [] {
                let jalon = ProjectMilestone(label: jalonDTO.label,
                                             dueAt: jalonDTO.dueAt,
                                             order: jalonDTO.order)
                jalon.stableID = jalonDTO.stableID
                jalon.stateRaw = jalonDTO.stateRaw
                jalon.createdAt = jalonDTO.createdAt
                context.insert(jalon)
                jalon.project = project
            }
            for contactDTO in projectDTO.contacts ?? [] {
                let contact = ProjectContact(name: contactDTO.name,
                                             role: contactDTO.role,
                                             order: contactDTO.order)
                contact.stableID = contactDTO.stableID
                contact.createdAt = contactDTO.createdAt
                context.insert(contact)
                contact.project = project
            }

            projectMap[project.code] = project
        }

        var collaboratorMap: [String: Collaborator] = [:]
        for collaboratorDTO in payload.collaborators {
            let collaborator = Collaborator(
                name: collaboratorDTO.name,
                role: collaboratorDTO.role,
                isArchived: collaboratorDTO.isArchived
            )
            if collaboratorDTO.photoData != nil || !collaboratorDTO.photoPath.isEmpty {
                let restoredPhotoURL = try restoredFileURL(
                    fileName: URL(fileURLWithPath: collaboratorDTO.photoPath).lastPathComponent,
                    filePath: collaboratorDTO.photoPath,
                    fileData: collaboratorDTO.photoData,
                    in: restoredFilesDirectory
                )
                collaborator.photoPath = restoredPhotoURL.path
            } else {
                collaborator.photoPath = ""
            }
            collaborator.photoBookmarkData = collaboratorDTO.photoBookmarkData
            context.insert(collaborator)
            collaboratorMap[collaborator.name] = collaborator
        }

        for meetingDTO in payload.meetings ?? [] {
            let meeting = Meeting(
                title: meetingDTO.title,
                date: meetingDTO.date,
                notes: meetingDTO.notes
            )
            meeting.stableID = meetingDTO.stableID
            meeting.kindRaw = meetingDTO.kindRaw
            meeting.customPrompt = meetingDTO.customPrompt
            meeting.liveNotes = meetingDTO.liveNotes
            meeting.rawTranscript = meetingDTO.rawTranscript
            meeting.mergedTranscript = meetingDTO.mergedTranscript
            meeting.summary = meetingDTO.summary
            meeting.keyPointsJSON = meetingDTO.keyPointsJSON
            meeting.decisionsJSON = meetingDTO.decisionsJSON
            meeting.openQuestionsJSON = meetingDTO.openQuestionsJSON
            meeting.durationSeconds = meetingDTO.durationSeconds
            meeting.calendarEventID = meetingDTO.calendarEventID
            meeting.calendarEventTitle = meetingDTO.calendarEventTitle
            meeting.reportGenerationDurationSeconds = meetingDTO.reportGenerationDurationSeconds
            meeting.participantStatusesJSON = meetingDTO.participantStatusesJSON
            meeting.adhocAttendeesJSON = meetingDTO.adhocAttendeesJSON
            meeting.project = meetingDTO.projectCode.flatMap { projectMap[$0] }
            meeting.participants = meetingDTO.participantNames.compactMap { collaboratorMap[$0] }

            if meetingDTO.wavData != nil || meetingDTO.wavFilePath != nil {
                let restoredWav = try restoredFileURL(
                    fileName: meetingDTO.wavFileName ?? "audio.wav",
                    filePath: meetingDTO.wavFilePath ?? "",
                    fileData: meetingDTO.wavData,
                    in: restoredFilesDirectory
                )
                meeting.wavFilePath = restoredWav.path
            }
            context.insert(meeting)

            for attachmentDTO in meetingDTO.attachments {
                let restoredURL = try restoredFileURL(
                    fileName: attachmentDTO.fileName,
                    filePath: attachmentDTO.filePath,
                    fileData: attachmentDTO.fileData,
                    in: restoredFilesDirectory
                )
                let attachment = MeetingAttachment(url: restoredURL, kind: attachmentDTO.kind)
                attachment.fileName = attachmentDTO.fileName
                attachment.filePath = restoredURL.path
                attachment.bookmarkData = attachmentDTO.bookmarkData
                attachment.extractedText = attachmentDTO.extractedText
                attachment.importedAt = attachmentDTO.importedAt
                // Colonnes du modèle cible (lot 6). Absentes d'une sauvegarde
                // antérieure : on garde alors les défauts du modèle, et la
                // migration paresseuse (D5) complétera à la première ouverture
                // de l'espace Ressources.
                if let raw = attachmentDTO.scopeRaw { attachment.scopeRaw = raw }
                if let mime = attachmentDTO.mimeType { attachment.mimeType = mime }
                if let octets = attachmentDTO.byteCount { attachment.byteCount = octets }
                if let auteur = attachmentDTO.addedByName { attachment.addedByName = auteur }
                attachment.pinnedAtT = attachmentDTO.pinnedAtT
                if let citations = attachmentDTO.citationCount { attachment.citationCount = citations }
                attachment.stableID = attachmentDTO.stableID ?? UUID()
                attachment.meeting = meeting
                context.insert(attachment)

                for slideDTO in attachmentDTO.slides {
                    let restoredSlideURL = try restoredFileURL(
                        fileName: slideDTO.imageFileName,
                        filePath: slideDTO.imagePath,
                        fileData: slideDTO.imageData,
                        in: restoredFilesDirectory
                    )
                    let slide = SlideCapture(
                        index: slideDTO.index,
                        capturedAt: slideDTO.capturedAt,
                        imagePath: restoredSlideURL.path
                    )
                    slide.ocrText = slideDTO.ocrText
                    slide.perceptualHash = slideDTO.perceptualHash
                    slide.attachment = attachment
                    context.insert(slide)
                }
            }

            for chunkDTO in meetingDTO.transcriptChunks {
                let chunk = TranscriptChunk(
                    text: chunkDTO.text,
                    orderIndex: chunkDTO.orderIndex,
                    sourceType: chunkDTO.sourceType
                )
                chunk.chunkId = chunkDTO.chunkId
                chunk.createdAt = chunkDTO.createdAt
                chunk.meeting = meeting
                context.insert(chunk)
            }

            // Les planches : la ligne d'abord, puis la scène et la vignette
            // réécrites dans `recordings/<uuid>/boards/` de la réunion
            // restaurée — et non à leur chemin d'origine, qui n'existe plus.
            for boardDTO in meetingDTO.boards ?? [] {
                let board = Board(index: boardDTO.index,
                                  title: boardDTO.title,
                                  mode: BoardMode(rawValue: boardDTO.modeRaw) ?? .sketch,
                                  t: boardDTO.t,
                                  authorNames: boardDTO.authorNames,
                                  updatedAt: boardDTO.updatedAt)
                board.stableID = boardDTO.stableID
                context.insert(board)
                board.meeting = meeting
                if let scene = boardDTO.sceneJSON {
                    _ = try? boardStore.save(scene: scene, board: board, meeting: meeting)
                    board.updatedAt = boardDTO.updatedAt
                }
                if let vignette = boardDTO.thumbData {
                    try? boardStore.saveThumbnail(vignette, board: board, meeting: meeting)
                }
            }

            // Les notes horodatées (lot 0B, D1). `visibilityRaw` est réécrit
            // tel quel : une note privée doit rester privée après un
            // aller-retour, c'est la raison d'être de la table.
            for noteDTO in meetingDTO.timedNotes ?? [] {
                let note = MeetingNote(t: noteDTO.t,
                                       text: noteDTO.text,
                                       orderIndex: noteDTO.orderIndex,
                                       createdAt: noteDTO.createdAt)
                note.stableID = noteDTO.stableID
                note.kindRaw = noteDTO.kindRaw
                note.visibilityRaw = noteDTO.visibilityRaw
                note.authorSideRaw = noteDTO.authorSideRaw
                note.sourceKindRaw = noteDTO.sourceKindRaw
                note.sourceStableID = noteDTO.sourceStableID
                note.sourceT = noteDTO.sourceT
                context.insert(note)
                note.meeting = meeting
            }
        }

        // Build a stableID → Meeting map so we can rebind manager item relations.
        let restoredMeetings = try context.fetch(FetchDescriptor<Meeting>())
        let meetingByStableID: [UUID: Meeting] = Dictionary(
            uniqueKeysWithValues: restoredMeetings.compactMap { meeting in
                meeting.stableID.map { ($0, meeting) }
            }
        )

        // ------------------------------------------------------------------
        // Les fils 1:1 (lot 10, D3). Restaurés ici et non dans la boucle des
        // collaborateurs : leurs engagements, sujets et humeurs référencent des
        // **réunions**, et `meetingByStableID` n'existe qu'une fois toutes les
        // réunions insérées.
        // ------------------------------------------------------------------
        for collaboratorDTO in payload.collaborators {
            guard let fils = collaboratorDTO.threads, !fils.isEmpty,
                  let collaborateur = collaboratorMap[collaboratorDTO.name] else { continue }
            for filDTO in fils {
                let fil = OneOnOneThread(collaborator: collaborateur,
                                         cadenceDays: filDTO.cadenceDays,
                                         createdAt: filDTO.createdAt)
                fil.stableID = filDTO.stableID
                fil.myRoleRaw = filDTO.myRoleRaw
                context.insert(fil)
                fil.collaborator = collaborateur

                for engagementDTO in filDTO.commitments {
                    let engagement = Commitment(text: engagementDTO.text)
                    engagement.stableID = engagementDTO.stableID
                    engagement.ownerSideRaw = engagementDTO.ownerSideRaw
                    engagement.dueAt = engagementDTO.dueAt
                    engagement.stateRaw = engagementDTO.stateRaw
                    engagement.promisedAt = engagementDTO.promisedAt
                    engagement.settledAt = engagementDTO.settledAt
                    engagement.deferralCount = engagementDTO.deferralCount
                    engagement.visibilityRaw = engagementDTO.visibilityRaw
                    engagement.blocksOther = engagementDTO.blocksOther
                    engagement.linkedDecisionIndex = engagementDTO.linkedDecisionIndex
                    engagement.promisedInMeeting = engagementDTO.promisedInMeetingID
                        .flatMap { meetingByStableID[$0] }
                    context.insert(engagement)
                    engagement.thread = fil
                }

                for sujetDTO in filDTO.agendaItems {
                    let sujet = OneOnOneAgendaItem(text: sujetDTO.text, order: sujetDTO.order)
                    sujet.stableID = sujetDTO.stableID
                    sujet.addedBySideRaw = sujetDTO.addedBySideRaw
                    sujet.stateRaw = sujetDTO.stateRaw
                    sujet.visibilityRaw = sujetDTO.visibilityRaw
                    sujet.kindRaw = sujetDTO.kindRaw
                    sujet.requestStatusRaw = sujetDTO.requestStatusRaw
                    sujet.requestedAt = sujetDTO.requestedAt
                    sujet.remindedCount = sujetDTO.remindedCount
                    sujet.createdAt = sujetDTO.createdAt
                    sujet.meeting = sujetDTO.meetingID.flatMap { meetingByStableID[$0] }
                    sujet.deferredToMeeting = sujetDTO.deferredToMeetingID
                        .flatMap { meetingByStableID[$0] }
                    context.insert(sujet)
                    sujet.thread = fil
                }

                for humeurDTO in filDTO.moodEntries {
                    let humeur = MoodEntry(value: humeurDTO.value,
                                           recordedAt: humeurDTO.recordedAt)
                    humeur.stableID = humeurDTO.stableID
                    humeur.meeting = humeurDTO.meetingID.flatMap { meetingByStableID[$0] }
                    context.insert(humeur)
                    humeur.thread = fil
                }

                for objectifDTO in filDTO.objectives {
                    let objectif = OneOnOneObjective(label: objectifDTO.label,
                                                     progress: objectifDTO.progress,
                                                     order: objectifDTO.order)
                    objectif.stableID = objectifDTO.stableID
                    objectif.reviewAt = objectifDTO.reviewAt
                    objectif.createdAt = objectifDTO.createdAt
                    context.insert(objectif)
                    objectif.thread = fil
                }
            }
        }

        for itemDTO in payload.managerReportItems ?? [] {
            let item = ManagerReportItem(
                rawSnippet: itemDTO.rawSnippet,
                sourceField: itemDTO.sourceField,
                sourceRangeStart: itemDTO.sourceRangeStart,
                sourceRangeLength: itemDTO.sourceRangeLength,
                sourceMeeting: itemDTO.sourceMeetingStableID.flatMap { meetingByStableID[$0] }
            )
            item.stableID = itemDTO.stableID
            item.createdAt = itemDTO.createdAt
            item.contextBefore = itemDTO.contextBefore
            item.contextAfter = itemDTO.contextAfter
            item.elaboratedText = itemDTO.elaboratedText ?? ""
            item.category = itemDTO.category
            item.tag = itemDTO.tag
            item.aiSuggestedCategory = itemDTO.aiSuggestedCategory
            item.userNotes = itemDTO.userNotes
            item.isCompleted = itemDTO.isCompleted
            item.archivedAt = itemDTO.archivedAt
            item.manualOrder = itemDTO.manualOrder
            item.isManual = itemDTO.isManual
            item.duplicateOfStableID = itemDTO.duplicateOfStableID
            item.archivedInMeeting = itemDTO.archivedInMeetingStableID.flatMap { meetingByStableID[$0] }
            context.insert(item)
        }

        for reportDTO in payload.managerMeetingReports ?? [] {
            let mtg = reportDTO.meetingStableID.flatMap { meetingByStableID[$0] }
            let report = ManagerMeetingReport(meeting: mtg)
            report.stableID = reportDTO.stableID
            report.generatedAt = reportDTO.generatedAt
            report.generatedSummary = reportDTO.generatedSummary
            report.durationSeconds = reportDTO.durationSeconds
            report.modelUsed = reportDTO.modelUsed
            report.itemsSnapshotJSON = reportDTO.itemsSnapshotJSON
            report.extractedActionsJSON = reportDTO.extractedActionsJSON
            context.insert(report)
        }

        for actionDTO in payload.managerActions ?? [] {
            let task = ActionTask(title: actionDTO.title, dueDate: actionDTO.dueDate)
            task.isCompleted = actionDTO.isCompleted
            task.reminderID = actionDTO.reminderID
            task.fromManager = true
            task.managerMeeting = actionDTO.managerMeetingStableID.flatMap { meetingByStableID[$0] }
            context.insert(task)
        }

        try context.save()
    }

    func saveBackupPanel(defaultFileName: String = "OneToOne_Backup.json") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = defaultFileName
        return panel.runModal() == .OK ? panel.url : nil
    }

    func openBackupPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func fileData(fromPath path: String) -> Data? {
        guard !path.isEmpty else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func createRestoreFilesDirectory() throws -> URL {
        let baseDirectory = URL.applicationSupportDirectory
            .appending(path: "OneToOne")
            .appending(path: "RestoredFiles")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory
    }

    private func restoredFileURL(
        fileName: String,
        filePath: String,
        fileData: Data?,
        in directory: URL
    ) throws -> URL {
        let fallbackName = fileName.isEmpty ? URL(fileURLWithPath: filePath).lastPathComponent : fileName
        guard !fallbackName.isEmpty else {
            return URL(fileURLWithPath: filePath)
        }

        if let fileData {
            let destinationURL = uniqueDestinationURL(for: fallbackName, in: directory)
            try fileData.write(to: destinationURL)
            return destinationURL
        }

        return URL(fileURLWithPath: filePath)
    }

    private func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: fileName).pathExtension
        var candidate = directory.appending(path: fileName)
        var index = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixedName = ext.isEmpty ? "\(baseName)_\(index)" : "\(baseName)_\(index).\(ext)"
            candidate = directory.appending(path: suffixedName)
            index += 1
        }

        return candidate
    }
}
