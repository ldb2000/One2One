import Testing
import SwiftData
import CoreSpotlight
import Foundation
@testable import OneToOne

@MainActor
@Suite("QuickLaunchURLHandler")
struct QuickLaunchURLHandlerTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Collaborator.self, Meeting.self, Project.self,
            ActionTask.self, AppSettings.self, Entity.self,
            ProjectAlert.self,
            ProjectAttachment.self, MeetingAttachment.self, TranscriptChunk.self,
            SlideCapture.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("Activity with collaborator-<uuid> id triggers router.startOneToOne")
    func activityRoutes() throws {
        let context = try makeContext()
        let collab = Collaborator(name: "Eve")
        context.insert(collab)
        try context.save()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "collaborator-\(collab.ensuredStableID.uuidString)"
        ]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken != nil)
        #expect(router.pendingToken?.autoStartRecording == true)
    }

    @Test("Unknown identifier is a no-op")
    func unknownIdentifierNoOp() throws {
        let context = try makeContext()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "collaborator-deadbeef-dead-dead-dead-deaddeaddead"]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken == nil)
    }

    @Test("Identifier without 'collaborator-' prefix is ignored")
    func wrongPrefixIgnored() throws {
        let context = try makeContext()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "project-something"]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken == nil)
    }

    @Test("Activity with meeting-<uuid> id opens the existing meeting without recording")
    func meetingActivityOpensMeeting() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Point hebdo", date: Date())
        context.insert(meeting)
        try context.save()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "meeting-\(meeting.ensuredStableID.uuidString)"
        ]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken?.meetingID == meeting.ensuredStableID)
        #expect(router.pendingToken?.autoStartRecording == false)
    }

    @Test("Activity with unknown meeting-<uuid> id is a no-op")
    func unknownMeetingIdentifierNoOp() throws {
        let context = try makeContext()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "meeting-deadbeef-dead-dead-dead-deaddeaddead"]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken == nil)
    }

    @Test("Activity with meeting-<uuid> id opens an existing note without recording")
    func noteActivityOpensNote() throws {
        let context = try makeContext()
        let note = NoteFactory.make(body: "Idée archi")
        context.insert(note)
        try context.save()

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "meeting-\(note.ensuredStableID.uuidString)"
        ]

        let router = QuickLaunchRouter.testInstance()
        QuickLaunchURLHandler.handle(activity: activity, router: router, context: context)

        #expect(router.pendingToken?.meetingID == note.ensuredStableID)
        #expect(router.pendingToken?.autoStartRecording == false)
    }
}
