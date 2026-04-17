import SwiftUI
import SwiftData
import AppKit

@main
struct OneToOneApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Project.self, ProjectInfoEntry.self, ProjectCollaboratorEntry.self, ProjectAttachment.self, Collaborator.self, Interview.self, ActionTask.self, ProjectAlert.self, AppSettings.self, Entity.self, InterviewAttachment.self, Meeting.self])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Schema incompatible — delete old store and retry
            print("SwiftData schema migration failed, resetting store: \(error)")
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            for suffix in ["", "-wal", "-shm"] {
                let fileURL = suffix.isEmpty ? url : url.deletingLastPathComponent().appending(path: "default.store\(suffix)")
                try? FileManager.default.removeItem(at: fileURL)
            }
            do {
                container = try ModelContainer(for: schema)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @State private var selectedTab: String? = "Dashboard"
    @Environment(\.modelContext) private var context
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
        }
    }

    private func reindexSpotlight() {
        do {
            let allProjects = try context.fetch(FetchDescriptor<Project>())
            SpotlightIndexService.shared.indexAll(projects: allProjects)
        } catch {
            print("[Spotlight] Failed to fetch projects for indexing: \(error)")
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
        } catch {
            print("Echec reparation SwiftData: \(error)")
        }
    }
}
