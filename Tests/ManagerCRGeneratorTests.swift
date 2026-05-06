import Testing
import SwiftData
import Foundation
@testable import OneToOne

private struct StubAIClient: AIClientProtocol {
    let response: String
    func send(prompt: String, settings: AppSettings) async throws -> String {
        response
    }
}

@Suite("ManagerCRGenerator — prompt + parse + generate")
struct ManagerCRGeneratorTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self, Collaborator.self, Interview.self, ActionTask.self,
            AppSettings.self, Entity.self, Meeting.self, MeetingAttachment.self,
            TranscriptChunk.self, SlideCapture.self, ProjectAlert.self,
            ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, ProjectMail.self, ProjectMailAttachment.self,
            InterviewAttachment.self, SavedPrompt.self, Note.self,
            ManagerReportItem.self, ManagerMeetingReport.self
        ])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true)
        ])
    }

    @Test("buildPrompt includes manager name, items checked snippet, and user prompt")
    @MainActor
    func buildPromptIncludesAll() {
        let s = AppSettings()
        s.managerName = "Alice Manager"
        s.managerReportPrompt = "USER_CUSTOM_PROMPT"

        let m = Meeting(title: "1:1 Mai", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        m.mergedTranscript = "TRANSCRIPT_BODY"

        let item = ManagerReportItem(manualSnippet: "Migration K8s", category: "Risque")
        item.userNotes = "Manager OK pour décaler"
        item.tag = "infra"

        let prompt = ManagerCRGenerator.buildPrompt(meeting: m, items: [item], settings: s)
        #expect(prompt.contains("Alice Manager"))
        #expect(prompt.contains("Migration K8s"))
        #expect(prompt.contains("Risque"))
        #expect(prompt.contains("Manager OK pour décaler"))
        #expect(prompt.contains("TRANSCRIPT_BODY"))
        #expect(prompt.contains("USER_CUSTOM_PROMPT"))
    }

    @Test("buildPrompt falls back to rawTranscript when mergedTranscript empty")
    @MainActor
    func buildPromptFallback() {
        let s = AppSettings(); s.managerName = "M"
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        m.mergedTranscript = ""
        m.rawTranscript = "RAW_BODY"
        let prompt = ManagerCRGenerator.buildPrompt(meeting: m, items: [], settings: s)
        #expect(prompt.contains("RAW_BODY"))
    }

    @Test("parseResponse splits markdown and JSON actions block")
    @MainActor
    func parseSplitsMarkdownAndJSON() {
        let response = """
        ## Points abordés
        - Point 1

        ## Actions
        Action 1 par manager.

        ```json
        { "actions": [{"title": "Faire X", "deadline": "2026-06-01"}, {"title": "Y", "deadline": null}] }
        ```
        """
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown.contains("## Points abordés"))
        #expect(!parsed.markdown.contains("```json"))
        #expect(parsed.actions.count == 2)
        #expect(parsed.actions[0].title == "Faire X")
        #expect(parsed.actions[0].deadlineISO == "2026-06-01")
        #expect(parsed.actions[1].title == "Y")
        #expect(parsed.actions[1].deadlineISO == nil)
    }

    @Test("parseResponse with no fence returns empty actions and full markdown")
    @MainActor
    func parseNoFence() {
        let response = "# CR\nbody only"
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown == "# CR\nbody only")
        #expect(parsed.actions.isEmpty)
    }

    @Test("parseResponse with malformed JSON returns empty actions and intact markdown")
    @MainActor
    func parseMalformedJSON() {
        let response = """
        # Body

        ```json
        { broken
        ```
        """
        let parsed = ManagerCRGenerator.parseResponse(response)
        #expect(parsed.markdown.contains("# Body"))
        #expect(parsed.actions.isEmpty)
    }

    @Test("generate end-to-end creates a ManagerMeetingReport, archives checked items")
    @MainActor
    func generateEndToEnd() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let s = AppSettings(); s.managerName = "Alice"
        context.insert(s)

        let mgrMeeting = Meeting(title: "1:1 Manager", date: Date(), notes: "")
        mgrMeeting.kindRaw = MeetingKind.manager.rawValue
        mgrMeeting.mergedTranscript = "Conversation."
        context.insert(mgrMeeting)

        let item = ManagerReportService.addManual(snippet: "Topic", category: "Information", tag: "", in: context)
        item.isCompleted = true
        try context.save()

        let stub = StubAIClient(response: """
        # Compte-rendu
        Tout va bien.

        ```json
        { "actions": [{"title": "Suivre", "deadline": null}] }
        ```
        """)

        let report = try await ManagerCRGenerator.generate(
            meeting: mgrMeeting,
            items: [item],
            settings: s,
            context: context,
            client: stub
        )

        #expect(report.generatedSummary.contains("# Compte-rendu"))
        #expect(report.extractedActionsJSON.contains("Suivre"))
        #expect(report.itemsSnapshotJSON.contains("Topic"))
        #expect(report.meeting?.title == "1:1 Manager")
        #expect(item.archivedAt != nil)
        #expect(item.archivedInMeeting?.title == "1:1 Manager")

        let saved = try context.fetch(FetchDescriptor<ManagerMeetingReport>())
        #expect(saved.count == 1)
    }

    @Test("generate throws if no items checked")
    @MainActor
    func generateNoItems() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let s = AppSettings(); s.managerName = "A"; context.insert(s)
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        context.insert(m)
        let stub = StubAIClient(response: "# x")

        await #expect(throws: ManagerCRGenerator.GenerationError.self) {
            _ = try await ManagerCRGenerator.generate(
                meeting: m, items: [], settings: s,
                context: context, client: stub
            )
        }
    }

    @Test("generate throws if managerName empty")
    @MainActor
    func generateEmptyManagerName() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let s = AppSettings(); s.managerName = ""; context.insert(s)
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        context.insert(m)
        let item = ManagerReportService.addManual(snippet: "t", category: "Information", tag: "", in: context)
        item.isCompleted = true
        try context.save()
        let stub = StubAIClient(response: "# x")

        await #expect(throws: ManagerCRGenerator.GenerationError.self) {
            _ = try await ManagerCRGenerator.generate(
                meeting: m, items: [item], settings: s,
                context: context, client: stub
            )
        }
    }

    @Test("generate throws if meeting kind is not .manager")
    @MainActor
    func generateWrongKind() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let s = AppSettings(); s.managerName = "A"; context.insert(s)
        let m = Meeting(title: "x", date: Date(), notes: "")
        m.kindRaw = MeetingKind.global.rawValue  // NOT .manager
        context.insert(m)
        let item = ManagerReportService.addManual(snippet: "t", category: "Information", tag: "", in: context)
        item.isCompleted = true
        try context.save()
        let stub = StubAIClient(response: "# x")

        await #expect(throws: ManagerCRGenerator.GenerationError.self) {
            _ = try await ManagerCRGenerator.generate(
                meeting: m, items: [item], settings: s,
                context: context, client: stub
            )
        }
    }

    @Test("materializeActions creates ActionTask(fromManager: true, managerMeeting: m) with parsed deadline")
    @MainActor
    func materializeActionsHappyPath() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m = Meeting(title: "1:1 Manager", date: Date(), notes: "")
        m.kindRaw = MeetingKind.manager.rawValue
        context.insert(m)
        try context.save()

        let actions: [ManagerCRGenerator.ExtractedAction] = [
            ManagerCRGenerator.ExtractedAction(title: "Call X", deadlineISO: "2026-06-15"),
            ManagerCRGenerator.ExtractedAction(title: "Email Y", deadlineISO: nil)
        ]

        let created = try ManagerCRGenerator.materializeActions(actions, in: m, context: context)
        #expect(created.count == 2)
        #expect(created[0].title == "Call X")
        #expect(created[0].fromManager == true)
        #expect(created[0].managerMeeting?.title == "1:1 Manager")
        #expect(created[0].dueDate != nil)
        #expect(created[1].title == "Email Y")
        #expect(created[1].fromManager == true)
        #expect(created[1].dueDate == nil)

        let fetched = try context.fetch(FetchDescriptor<ActionTask>())
        #expect(fetched.count == 2)
    }
}
