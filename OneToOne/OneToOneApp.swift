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
                .environmentObject(router)
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

            // Backfill Collaborator.stableID pour rows créées avant l'ajout du champ.
            let allCollabs = try context.fetch(FetchDescriptor<Collaborator>())
            var backfilled = 0
            for collab in allCollabs where collab.stableID == nil {
                collab.stableID = UUID()
                backfilled += 1
            }
            if backfilled > 0 {
                try context.save()
                print("Reparation SwiftData: \(backfilled) Collaborator.stableID backfilles.")
            }
        } catch {
            print("Echec reparation SwiftData: \(error)")
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
        guard resolved == nil, let token else { return }
        let target = token.meetingID
        let descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == target }
        )
        resolved = try? context.fetch(descriptor).first
    }
}
