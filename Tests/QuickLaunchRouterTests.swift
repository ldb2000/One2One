import Testing
import SwiftData
import Foundation
@testable import OneToOne

@MainActor
@Suite("QuickLaunchRouter")
struct QuickLaunchRouterTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Collaborator.self, Meeting.self, Project.self,
            Interview.self, ActionTask.self, AppSettings.self, Entity.self,
            ProjectAlert.self, ProjectInfoEntry.self, ProjectCollaboratorEntry.self,
            ProjectAttachment.self, MeetingAttachment.self, TranscriptChunk.self,
            SlideCapture.self, InterviewAttachment.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("startOneToOne creates Meeting kind=.oneToOne with collab as sole participant")
    func startOneToOneCreatesTaggedMeeting() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Alice", role: "Dev")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        let meeting = router.startOneToOne(collaborator: collab,
                                           autoStartRecording: true,
                                           in: context)

        #expect(meeting.kind == .oneToOne)
        #expect(meeting.title == "1:1 — Alice")
        #expect(meeting.participants.count == 1)
        #expect(meeting.participants.first?.stableID == collab.stableID)
    }

    @Test("startOneToOne publishes pendingToken with autoStart flag")
    func startOneToOnePublishesToken() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Bob")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        let meeting = router.startOneToOne(collaborator: collab,
                                           autoStartRecording: true,
                                           in: context)

        let token = try #require(router.pendingToken)
        #expect(token.meetingID == meeting.stableID)
        #expect(token.autoStartRecording == true)
    }

    @Test("startOneToOne with autoStartRecording=false sets flag accordingly")
    func startOneToOneWithoutAutoStart() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Carol")
        context.insert(collab)
        try context.save()

        let router = QuickLaunchRouter.testInstance()
        _ = router.startOneToOne(collaborator: collab,
                                 autoStartRecording: false,
                                 in: context)

        #expect(router.pendingToken?.autoStartRecording == false)
    }
}
