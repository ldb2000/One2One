import SwiftUI
import SwiftData
import AppKit
import Combine
import CoreSpotlight

@main
struct OneToOneApp: App {
    /// Container partagé pour les déclencheurs hors hiérarchie SwiftUI
    /// (AppIntent perform, Carbon hotkey callback). Initialisé dans `init()`.
    static var sharedContainer: ModelContainer!

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    init() {
        // Store dédié sous `Application Support/OneToOne/OneToOne.store` :
        // évite la collision avec `default.store` (utilisé par d'autres libs
        // CoreData qui partagent ce nom par défaut) et garantit la persistance
        // continue des données métier (Project, Meeting, Interview…).
        let storeDir = URL.applicationSupportDirectory.appending(path: "OneToOne", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appending(path: "OneToOne.store")

        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: OneToOneMigrationPlan.self,
                configurations: configuration
            )
            Self.sharedContainer = container
        } catch {
            // Migration impossible — sauvegarde le store cassé puis recrée
            // un store vide. ⚠️ destructif, n'arrive que si la migration
            // SwiftData échoue (schéma fondamentalement incompatible).
            print("SwiftData schema migration failed, backing up store: \(error)")
            let backupURL = storeDir.appending(path: "OneToOne.store.broken-\(Int(Date().timeIntervalSince1970))")
            for suffix in ["", "-wal", "-shm"] {
                let fileURL = suffix.isEmpty
                    ? storeURL
                    : storeURL.deletingLastPathComponent().appending(path: "OneToOne.store\(suffix)")
                let dst = suffix.isEmpty
                    ? backupURL
                    : backupURL.deletingLastPathComponent().appending(path: "\(backupURL.lastPathComponent)\(suffix)")
                try? FileManager.default.moveItem(at: fileURL, to: dst)
            }
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: OneToOneMigrationPlan.self,
                    configurations: configuration
                )
                Self.sharedContainer = container
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    @StateObject private var router = QuickLaunchRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environmentObject(router)
        }
        .modelContainer(container)

        WindowGroup(id: "1to1-meeting", for: OneToOneLaunchToken.self) { $token in
            OneToOneMeetingWindowContent(token: token)
                .preferredColorScheme(.light)
                .environmentObject(router)
        }
        .modelContainer(container)

        WindowGroup(id: "prep-standalone", for: PrepWindowToken.self) { $token in
            if let t = token {
                PrepWindowView(token: t)
                    .preferredColorScheme(.light)
            }
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @State private var selectedTab: String? = "Dashboard"
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var router: QuickLaunchRouter
    @State private var didRunDataRepair = false
    
    var body: some View {
        NavigationSplitView {
            MainSidebarView()
                .focusSection()
        } detail: {
            DashboardView()
                .focusSection()
        }
        .onAppear {
            // Indispensable quand l'app est lancée via swift run :
            // sans ça, l'app reste un processus "accessory" qui ne reçoit
            // pas les événements clavier.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // Forcer la fenêtre principale comme key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            repairStoreIfNeeded()
            reindexSpotlight()

            // Re-index Spotlight when app is about to terminate
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                reindexSpotlight()
            }

            registerHotkeys()

            NotificationCenter.default.addObserver(
                forName: .collaboratorHotkeysChanged,
                object: nil,
                queue: .main
            ) { _ in
                registerHotkeys()
            }

            NotificationCenter.default.addObserver(
                forName: .openPrepWindow,
                object: nil,
                queue: .main
            ) { note in
                if let token = note.userInfo?["token"] as? PrepWindowToken {
                    Task { @MainActor in
                        openWindow(id: "prep-standalone", value: token)
                    }
                }
            }
        }
        .onReceive(router.$pendingToken.compactMap { $0 }) { token in
            openWindow(id: "1to1-meeting", value: token)
            // Drain so the same token doesn't fire twice on view remount.
            _ = router.consumePendingToken()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            QuickLaunchURLHandler.handle(activity: activity,
                                         router: router,
                                         context: context)
        }
    }

    private func registerHotkeys() {
        GlobalHotkeyService.shared.unregisterAll()

        let settings: AppSettings? = (try? context.fetch(FetchDescriptor<AppSettings>()))?.canonicalSettings
        let map = settings?.collaboratorHotkeys ?? [:]

        // Overlay (default ⌃⌥⌘1 if absent)
        let overlaySpec = HotkeySpec(serialized: map["__overlay__"] ?? "⌃⌥⌘1")
            ?? HotkeySpec(modifiers: [.control, .option, .command], keyChar: "1")
        _ = GlobalHotkeyService.shared.register(spec: overlaySpec) {
            OneToOneQuickPickerWindow.shared.present()
        }

        // Per-collab
        for (key, serialized) in map where key != "__overlay__" {
            guard let spec = HotkeySpec(serialized: serialized),
                  let uuid = UUID(uuidString: key) else { continue }
            _ = GlobalHotkeyService.shared.register(spec: spec) {
                Task { @MainActor in
                    let descriptor = FetchDescriptor<Collaborator>(
                        predicate: #Predicate { $0.stableID == uuid }
                    )
                    guard let collab = try? context.fetch(descriptor).first else { return }
                    QuickLaunchRouter.shared.startOneToOne(
                        collaborator: collab,
                        autoStartRecording: true,
                        in: context
                    )
                }
            }
        }
    }

    private func reindexSpotlight() {
        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            SpotlightIndexService.shared.indexAll(projects: allProjects, collaborators: allCollabs)
        } catch {
            print("[Spotlight] Failed to fetch for indexing: \(error)")
        }
    }

    private func repairStoreIfNeeded() {
        guard !didRunDataRepair else { return }
        didRunDataRepair = true

        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            let sortedProjects = allProjects.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }

            var seenCodes = Set<String>()
            var changed = false
            var generatedIndex = 1

            for project in sortedProjects {
                let trimmed = project.code.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseCode = trimmed.isEmpty ? "PXX_AUTO" : trimmed
                var candidate = baseCode
                var duplicateSuffix = 1

                while seenCodes.contains(candidate) {
                    if trimmed.isEmpty {
                        candidate = "PXX_AUTO_\(generatedIndex)"
                        generatedIndex += 1
                    } else {
                        candidate = "\(baseCode)_\(duplicateSuffix)"
                        duplicateSuffix += 1
                    }
                }

                if candidate != project.code {
                    project.code = candidate
                    changed = true
                }
                seenCodes.insert(candidate)
            }

            if changed {
                try context.save()
                print("Reparation SwiftData: codes projet dupliques corriges.")
            }

            // Backfill Project.stableID — new Optional field, nil on existing rows.
            let allProjectsForBackfill = try context.fetch(FetchDescriptor<Project>())
            var seenProjectIDs = Set<UUID>()
            var projectBackfilled = 0
            for proj in allProjectsForBackfill {
                if let id = proj.stableID, seenProjectIDs.insert(id).inserted { continue }
                proj.stableID = UUID()
                projectBackfilled += 1
            }
            if projectBackfilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(projectBackfilled) Project.stableID backfilles.")
            }

            // Backfill Collaborator.stableID — handles both nil rows and
            // duplicates from the legacy non-Optional `UUID()` default that
            // SwiftData applied identically to existing rows.
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            var seenCollabIDs = Set<UUID>()
            var backfilled = 0
            for collab in allCollabs {
                if let id = collab.stableID, seenCollabIDs.insert(id).inserted { continue }
                collab.stableID = UUID()
                backfilled += 1
            }
            if backfilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(backfilled) Collaborator.stableID backfilles.")
            }

            // Backfill Meeting.stableID — pre-Optional rows may have nil or
            // share duplicates from the legacy non-Optional default. Detect
            // both and assign unique UUIDs.
            let allMeetings = try context.fetch(FetchDescriptor<Meeting>())
            var seenIDs = Set<UUID>()
            var meetingFilled = 0
            for meeting in allMeetings {
                if let id = meeting.stableID, seenIDs.insert(id).inserted { continue }
                meeting.stableID = UUID()
                meetingFilled += 1
            }
            if meetingFilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(meetingFilled) Meeting.stableID backfilles.")
            }

            // Defensive dedup for the 4 stableID Optionals + SlideCapture.id.
            // Same pattern as Meeting/Collaborator: nil rows OR duplicates
            // get a fresh UUID.
            deduplicateOptional(context: context, label: "NoteAttachment",
                                fetch: FetchDescriptor<NoteAttachment>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicateOptional(context: context, label: "ManagerReportItem",
                                fetch: FetchDescriptor<ManagerReportItem>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicateOptional(context: context, label: "ManagerMeetingReport",
                                fetch: FetchDescriptor<ManagerMeetingReport>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicateOptional(context: context, label: "TranscriptSegment",
                                fetch: FetchDescriptor<TranscriptSegment>(),
                                get: { $0.stableID }, set: { $0.stableID = $1 })
            deduplicate(context: context, label: "SlideCapture",
                        fetch: FetchDescriptor<SlideCapture>(),
                        get: { $0.id }, set: { $0.id = $1 })

            BuiltInTemplates.seedIfNeeded(in: context)
            try context.save()
        } catch {
            print("Echec reparation SwiftData: \(error)")
        }
    }

    /// Same as `deduplicate` but for Optional UUID fields — nil rows are
    /// also backfilled.
    private func deduplicateOptional<T: PersistentModel>(
        context: ModelContext,
        label: String,
        fetch: FetchDescriptor<T>,
        get: (T) -> UUID?,
        set: (T, UUID) -> Void
    ) {
        guard let all = try? context.fetch(fetch) else { return }
        var seen = Set<UUID>()
        var fixed = 0
        for row in all {
            if let id = get(row), seen.insert(id).inserted { continue }
            set(row, UUID())
            fixed += 1
        }
        if fixed > 0 {
            try? context.save()
            print("Reparation SwiftData: \(fixed) \(label).stableID backfilles.")
        }
    }

    /// Scans a SwiftData entity for rows whose UUID identifier collides
    /// with another, and reassigns each duplicate a fresh UUID. Saves
    /// once when any change is made. Quiet on no-op.
    private func deduplicate<T: PersistentModel>(
        context: ModelContext,
        label: String,
        fetch: FetchDescriptor<T>,
        get: (T) -> UUID,
        set: (T, UUID) -> Void
    ) {
        guard let all = try? context.fetch(fetch) else { return }
        var seen = Set<UUID>()
        var fixed = 0
        for row in all {
            let id = get(row)
            if seen.insert(id).inserted { continue }
            set(row, UUID())
            fixed += 1
        }
        if fixed > 0 {
            try? context.save()
            print("Reparation SwiftData: \(fixed) \(label) UUID dedoublonnes.")
        }
    }
}

/// Contenu de la fenêtre `1to1-meeting`. Résout le token vers un `Meeting`
/// via `stableID`, présente `MeetingView` avec `autoStartRecording`.
struct OneToOneMeetingWindowContent: View {
    let token: OneToOneLaunchToken?
    @Environment(\.modelContext) private var context
    @State private var resolved: Meeting?

    var body: some View {
        Group {
            if let resolved {
                MeetingView(meeting: resolved, autoStartRecording: token?.autoStartRecording ?? false)
            } else {
                ProgressView()
                    .frame(minWidth: 600, minHeight: 400)
            }
        }
        .onAppear { resolveIfNeeded() }
        .onChange(of: token) { _, _ in resolveIfNeeded() }
    }

    private func resolveIfNeeded() {
        guard let token else { return }
        if let resolved, resolved.stableID == token.meetingID { return }
        let target = token.meetingID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == target }
        )
        resolved = try? context.fetch(descriptor).first
    }
}
