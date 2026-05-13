import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("ManagerReportService — CRUD, archivage, dédup")
struct ManagerReportServiceTests {

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

    @Test("Add nominal item from selection")
    func addNominal() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)

        let item = try ManagerReportService.add(
            snippet: "Hello world",
            sourceField: "transcript",
            range: NSRange(location: 10, length: 11),
            sourceMeeting: meeting,
            contextBefore: "Before.",
            contextAfter: "After.",
            category: "Information",
            tag: "",
            aiSuggestedCategory: "Information",
            in: context
        )
        try context.save()

        #expect(item.rawSnippet == "Hello world")
        #expect(item.sourceRangeStart == 10)
        #expect(item.sourceRangeLength == 11)
        #expect(item.sourceField == "transcript")
        #expect(item.sourceMeeting?.title == "M")
        let all = try context.fetch(FetchDescriptor<ManagerReportItem>())
        #expect(all.count == 1)
    }

    @Test("Add manual item has isManual=true and no source meeting")
    func addManual() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let item = ManagerReportService.addManual(
            snippet: "Préparer point budget",
            category: "Demande",
            tag: "",
            in: context
        )
        try context.save()

        #expect(item.isManual)
        #expect(item.sourceField == "manual")
        #expect(item.sourceMeeting == nil)
        #expect(item.category == "Demande")
    }

    @Test("Duplicate detection: overlap > 50% on same source field+meeting marks both")
    func duplicateDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)

        let first = try ManagerReportService.add(
            snippet: "abcdefghij",
            sourceField: "transcript",
            range: NSRange(location: 0, length: 10),
            sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        // Overlap from 5..15 → overlap chars = 5 over min(10,10)=10 → 50% — must be > 50% to flag.
        // Use 4..14 → overlap = 6 / 10 = 60% → flagged.
        let second = try ManagerReportService.add(
            snippet: "efghijklmn",
            sourceField: "transcript",
            range: NSRange(location: 4, length: 10),
            sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        #expect(second.duplicateOfStableID == first.ensuredStableID.uuidString)
        #expect(first.duplicateOfStableID == second.ensuredStableID.uuidString)
    }

    @Test("Different source meeting does NOT flag duplicate")
    func notDuplicateAcrossMeetings() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let m1 = Meeting(title: "A", date: Date(), notes: "")
        let m2 = Meeting(title: "B", date: Date(), notes: "")
        context.insert(m1); context.insert(m2)

        let first = try ManagerReportService.add(
            snippet: "abcdefghij", sourceField: "transcript",
            range: NSRange(location: 0, length: 10), sourceMeeting: m1,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        let second = try ManagerReportService.add(
            snippet: "efghijklmn", sourceField: "transcript",
            range: NSRange(location: 4, length: 10), sourceMeeting: m2,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()
        #expect(first.duplicateOfStableID == "")
        #expect(second.duplicateOfStableID == "")
    }

    @Test("Delete item removes it from context")
    func deleteItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "M", date: Date(), notes: "")
        context.insert(meeting)
        let item = try ManagerReportService.add(
            snippet: "x", sourceField: "transcript",
            range: NSRange(location: 0, length: 1), sourceMeeting: meeting,
            contextBefore: "", contextAfter: "",
            category: "Information", tag: "", aiSuggestedCategory: nil,
            in: context
        )
        try context.save()

        ManagerReportService.delete(item: item, in: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<ManagerReportItem>())
        #expect(all.isEmpty)
    }

    @Test("archiveCheckedItems archives only checked + non-archived items")
    func archiveOnlyChecked() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let meeting = Meeting(title: "MgrMeeting", date: Date(), notes: "")
        meeting.kindRaw = MeetingKind.manager.rawValue
        context.insert(meeting)

        let a = ManagerReportService.addManual(snippet: "checked", category: "Information", tag: "", in: context)
        a.isCompleted = true
        let b = ManagerReportService.addManual(snippet: "unchecked", category: "Information", tag: "", in: context)
        let c = ManagerReportService.addManual(snippet: "already archived", category: "Information", tag: "", in: context)
        c.isCompleted = true
        c.archivedAt = Date.distantPast
        try context.save()

        let archived = ManagerReportService.archiveCheckedItems(in: meeting, context: context)
        try context.save()

        #expect(archived.count == 1)
        #expect(archived.first?.rawSnippet == "checked")
        #expect(archived.first?.archivedInMeeting?.title == "MgrMeeting")
        #expect(archived.first?.archivedAt != nil)
        // b unchanged
        #expect(b.archivedAt == nil)
        // c unchanged (already archived)
        #expect(c.archivedAt == .distantPast)
    }

    @Test("currentItems excludes archived")
    func currentItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let a = ManagerReportService.addManual(snippet: "live", category: "Information", tag: "", in: context)
        let b = ManagerReportService.addManual(snippet: "old", category: "Information", tag: "", in: context)
        b.archivedAt = Date()
        try context.save()

        let current = try ManagerReportService.currentItems(in: context)
        #expect(current.contains { $0.rawSnippet == "live" })
        #expect(!current.contains { $0.rawSnippet == "old" })
    }

    @Test("archivedItems excludes current")
    func archivedItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let a = ManagerReportService.addManual(snippet: "live", category: "Information", tag: "", in: context)
        let b = ManagerReportService.addManual(snippet: "old", category: "Information", tag: "", in: context)
        b.archivedAt = Date()
        try context.save()

        let archived = try ManagerReportService.archivedItems(in: context)
        #expect(archived.contains { $0.rawSnippet == "old" })
        #expect(!archived.contains { $0.rawSnippet == "live" })
    }
}
