import Foundation
import SwiftData
import UniformTypeIdentifiers
import AppKit

final class BackupService {
    struct BackupPayload: Codable {
        var exportedAt: Date
        var settings: SettingsDTO
        var entities: [EntityDTO]
        var projects: [ProjectDTO]
        var collaborators: [CollaboratorDTO]
        var interviews: [InterviewDTO]
        /// Optionnel pour rester rétro-compatible avec les anciens backups
        /// (sans réunions). Ajouté en avril 2026 — le backup inclut désormais
        /// transcript, rapport, notes live, WAV, documents joints et slides.
        var meetings: [MeetingDTO]?
    }

    struct SettingsDTO: Codable {
        var cloudToken: String
        var apiEndpoint: String
        var modelName: String
        var provider: String
        var importPrompt: String
        var reformulatePrompt: String
        var weeklyExportPrompt: String
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

    struct ProjectInfoEntryDTO: Codable {
        var date: Date
        var content: String
        var category: String
    }

    struct ProjectCollaboratorEntryDTO: Codable {
        var date: Date
        var content: String
        var kind: String
        var isCompleted: Bool
        var collaboratorName: String?
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
        var infoEntries: [ProjectInfoEntryDTO]
        var collaboratorEntries: [ProjectCollaboratorEntryDTO]
        var attachments: [ProjectAttachmentDTO]
    }

    struct CollaboratorDTO: Codable {
        var name: String
        var role: String
        var isArchived: Bool
        var photoPath: String
        var photoBookmarkData: Data?
        var photoData: Data?
    }

    struct InterviewAttachmentDTO: Codable {
        var fileName: String
        var filePath: String
        var bookmarkData: Data?
        var fileData: Data?
        var comment: String
        var importedAt: Date
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
    }

    struct TranscriptChunkDTO: Codable {
        var chunkId: UUID
        var text: String
        var orderIndex: Int
        var sourceType: String
        var createdAt: Date
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
    }

    struct InterviewDTO: Codable {
        var date: Date
        var collaboratorName: String?
        var notes: String
        var recordingLink: String?
        var hasAlert: Bool
        var alertDescription: String
        var typeRaw: String?
        var sourceFileName: String?
        var shareWithEveryone: Bool
        var contextComment: String
        var candidateLinkedInURL: String
        var candidateLinkedInNotes: String
        var cvExperienceNotes: String
        var cvSkillsNotes: String
        var cvMotivationNotes: String
        var positivePoints: String
        var negativePoints: String
        var trainingAssessment: String
        var generalAssessment: String
        var selectedProjectCode: String?
        var attachments: [InterviewAttachmentDTO]
        var tasks: [TaskDTO]
        var alerts: [AlertDTO]
    }

    func backup(
        settings: AppSettings,
        entities: [Entity],
        projects: [Project],
        collaborators: [Collaborator],
        interviews: [Interview],
        meetings: [Meeting] = []
    ) throws -> Data {
        let payload = BackupPayload(
            exportedAt: Date(),
            settings: SettingsDTO(
                cloudToken: settings.cloudToken,
                apiEndpoint: settings.apiEndpoint,
                modelName: settings.modelName,
                provider: settings.provider.rawValue,
                importPrompt: settings.importPrompt,
                reformulatePrompt: settings.reformulatePrompt,
                weeklyExportPrompt: settings.weeklyExportPrompt
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
                    infoEntries: project.infoEntries.map {
                        ProjectInfoEntryDTO(date: $0.date, content: $0.content, category: $0.category)
                    },
                    collaboratorEntries: project.collaboratorEntries.map {
                        ProjectCollaboratorEntryDTO(
                            date: $0.date,
                            content: $0.content,
                            kind: $0.kind,
                            isCompleted: $0.isCompleted,
                            collaboratorName: $0.collaborator?.name
                        )
                    },
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
                    }
                )
            },
            collaborators: collaborators.map {
                CollaboratorDTO(
                    name: $0.name,
                    role: $0.role,
                    isArchived: $0.isArchived,
                    photoPath: $0.photoPath,
                    photoBookmarkData: $0.photoBookmarkData,
                    photoData: fileData(fromPath: $0.photoPath)
                )
            },
            interviews: interviews.map { interview in
                InterviewDTO(
                    date: interview.date,
                    collaboratorName: interview.collaborator?.name,
                    notes: interview.notes,
                    recordingLink: interview.recordingLink?.absoluteString,
                    hasAlert: interview.hasAlert,
                    alertDescription: interview.alertDescription,
                    typeRaw: interview.typeRaw,
                    sourceFileName: interview.sourceFileName,
                    shareWithEveryone: interview.shareWithEveryone,
                    contextComment: interview.contextComment,
                    candidateLinkedInURL: interview.candidateLinkedInURL,
                    candidateLinkedInNotes: interview.candidateLinkedInNotes,
                    cvExperienceNotes: interview.cvExperienceNotes,
                    cvSkillsNotes: interview.cvSkillsNotes,
                    cvMotivationNotes: interview.cvMotivationNotes,
                    positivePoints: interview.positivePoints,
                    negativePoints: interview.negativePoints,
                    trainingAssessment: interview.trainingAssessment,
                    generalAssessment: interview.generalAssessment,
                    selectedProjectCode: interview.selectedProject?.code,
                    attachments: interview.attachments.map {
                        InterviewAttachmentDTO(
                            fileName: $0.fileName,
                            filePath: $0.filePath,
                            bookmarkData: $0.bookmarkData,
                            fileData: fileData(fromPath: $0.filePath),
                            comment: $0.comment,
                            importedAt: $0.importedAt
                        )
                    },
                    tasks: interview.tasks.map {
                        TaskDTO(
                            title: $0.title,
                            projectCode: $0.project?.code,
                            dueDate: $0.dueDate,
                            isCompleted: $0.isCompleted,
                            reminderID: $0.reminderID
                        )
                    },
                    alerts: interview.alerts.map {
                        AlertDTO(
                            title: $0.title,
                            detail: $0.detail,
                            severity: $0.severityRaw,
                            date: $0.date,
                            isResolved: $0.isResolved,
                            projectCode: $0.project?.code
                        )
                    }
                )
            },
            meetings: meetings.map { meeting in
                let wavURL = meeting.wavFilePath.map { URL(fileURLWithPath: $0) }
                return MeetingDTO(
                    stableID: meeting.stableID,
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
                    wavFileName: wavURL?.lastPathComponent,
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
                            }
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
                        }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    func restore(from data: Data, into context: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        let restoredFilesDirectory = try createRestoreFilesDirectory()

        let existingProjects = try context.fetch(FetchDescriptor<Project>())
        let existingCollaborators = try context.fetch(FetchDescriptor<Collaborator>())
        let existingInterviews = try context.fetch(FetchDescriptor<Interview>())
        let existingEntities = try context.fetch(FetchDescriptor<Entity>())
        let existingSettings = try context.fetch(FetchDescriptor<AppSettings>())
        let existingMeetings = try context.fetch(FetchDescriptor<Meeting>())

        for meeting in existingMeetings { context.delete(meeting) }
        for interview in existingInterviews { context.delete(interview) }
        for project in existingProjects { context.delete(project) }
        for collaborator in existingCollaborators { context.delete(collaborator) }
        for entity in existingEntities { context.delete(entity) }
        for setting in existingSettings { context.delete(setting) }

        let restoredSettings = AppSettings()
        restoredSettings.cloudToken = payload.settings.cloudToken
        restoredSettings.apiEndpoint = payload.settings.apiEndpoint
        restoredSettings.modelName = payload.settings.modelName
        restoredSettings.provider = AIProvider(rawValue: payload.settings.provider) ?? .claudeOAuth
        restoredSettings.importPrompt = payload.settings.importPrompt
        restoredSettings.reformulatePrompt = payload.settings.reformulatePrompt
        restoredSettings.weeklyExportPrompt = payload.settings.weeklyExportPrompt
        context.insert(restoredSettings)

        var entityMap: [String: Entity] = [:]
        for entityDTO in payload.entities {
            let entity = Entity(name: entityDTO.name, summary: entityDTO.summary)
            context.insert(entity)
            entityMap[entity.name] = entity
        }

        var projectMap: [String: Project] = [:]
        var pendingCollaboratorEntries: [(ProjectCollaboratorEntry, String?)] = []
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
            context.insert(project)

            for infoDTO in projectDTO.infoEntries {
                let entry = ProjectInfoEntry(date: infoDTO.date, content: infoDTO.content, category: infoDTO.category)
                entry.project = project
                context.insert(entry)
            }

            for collaboratorEntryDTO in projectDTO.collaboratorEntries {
                let entry = ProjectCollaboratorEntry(
                    date: collaboratorEntryDTO.date,
                    content: collaboratorEntryDTO.content,
                    kind: collaboratorEntryDTO.kind,
                    isCompleted: collaboratorEntryDTO.isCompleted
                )
                entry.project = project
                context.insert(entry)
                pendingCollaboratorEntries.append((entry, collaboratorEntryDTO.collaboratorName))
            }

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

        for (entry, collaboratorName) in pendingCollaboratorEntries {
            entry.collaborator = collaboratorName.flatMap { collaboratorMap[$0] }
        }

        for interviewDTO in payload.interviews {
            let interview = Interview(
                date: interviewDTO.date,
                notes: interviewDTO.notes,
                hasAlert: interviewDTO.hasAlert,
                type: InterviewType(rawValue: interviewDTO.typeRaw ?? "") ?? .regular
            )
            interview.collaborator = interviewDTO.collaboratorName.flatMap { collaboratorMap[$0] }
            interview.recordingLink = interviewDTO.recordingLink.flatMap(URL.init(string:))
            interview.alertDescription = interviewDTO.alertDescription
            interview.typeRaw = interviewDTO.typeRaw
            interview.sourceFileName = interviewDTO.sourceFileName
            interview.shareWithEveryone = interviewDTO.shareWithEveryone
            interview.contextComment = interviewDTO.contextComment
            interview.candidateLinkedInURL = interviewDTO.candidateLinkedInURL
            interview.candidateLinkedInNotes = interviewDTO.candidateLinkedInNotes
            interview.cvExperienceNotes = interviewDTO.cvExperienceNotes
            interview.cvSkillsNotes = interviewDTO.cvSkillsNotes
            interview.cvMotivationNotes = interviewDTO.cvMotivationNotes
            interview.positivePoints = interviewDTO.positivePoints
            interview.negativePoints = interviewDTO.negativePoints
            interview.trainingAssessment = interviewDTO.trainingAssessment
            interview.generalAssessment = interviewDTO.generalAssessment
            interview.selectedProject = interviewDTO.selectedProjectCode.flatMap { projectMap[$0] }
            context.insert(interview)

            for attachmentDTO in interviewDTO.attachments {
                let restoredURL = try restoredFileURL(
                    fileName: attachmentDTO.fileName,
                    filePath: attachmentDTO.filePath,
                    fileData: attachmentDTO.fileData,
                    in: restoredFilesDirectory
                )
                let attachment = InterviewAttachment(
                    url: restoredURL,
                    comment: attachmentDTO.comment,
                    importedAt: attachmentDTO.importedAt
                )
                attachment.fileName = attachmentDTO.fileName
                attachment.bookmarkData = attachmentDTO.bookmarkData
                attachment.interview = interview
                context.insert(attachment)
            }

            for taskDTO in interviewDTO.tasks {
                let task = ActionTask(title: taskDTO.title, dueDate: taskDTO.dueDate)
                task.project = taskDTO.projectCode.flatMap { projectMap[$0] }
                task.isCompleted = taskDTO.isCompleted
                task.reminderID = taskDTO.reminderID
                task.interview = interview
                context.insert(task)
            }

            for alertDTO in interviewDTO.alerts {
                let alert = ProjectAlert(
                    title: alertDTO.title,
                    detail: alertDTO.detail,
                    severity: alertDTO.severity,
                    date: alertDTO.date
                )
                alert.isResolved = alertDTO.isResolved
                alert.project = alertDTO.projectCode.flatMap { projectMap[$0] }
                alert.interview = interview
                context.insert(alert)
            }
        }

        // MARK: - Meetings (live notes, transcript, rapport, WAV, attachments, slides)

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
