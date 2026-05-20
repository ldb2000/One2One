import SwiftUI
import SwiftData

/// Token passed to the `prep-standalone` window to identify the prep target.
/// Carries either a Collaborator stableID or a Project stableID (exactly one).
struct PrepWindowToken: Codable, Hashable {
    let collabID: UUID?
    let projectID: UUID?
}

/// Fenêtre standalone d'édition d'une prep "standing" lancée depuis le menubar.
struct PrepWindowView: View {
    let token: PrepWindowToken
    @Environment(\.modelContext) private var context
    @Query private var allCollabs: [Collaborator]
    @Query private var allProjects: [Project]
    @Query private var settingsList: [AppSettings]
    @State private var isGenerating = false
    @State private var error: String?

    private var resolvedCollab: Collaborator? {
        guard let id = token.collabID else { return nil }
        return allCollabs.first { $0.stableID == id }
    }
    private var resolvedProject: Project? {
        guard let id = token.projectID else { return nil }
        return allProjects.first { $0.stableID == id }
    }
    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            footer
        }
        .padding(14)
        .frame(minWidth: 600, minHeight: 480)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Image(systemName: "checklist")
            if let c = resolvedCollab {
                Text("Préparation 1:1 — \(c.name)").font(.headline)
            } else if let p = resolvedProject {
                Text("Préparation projet — \(p.name)").font(.headline)
            } else {
                Text("Préparation").font(.headline)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let c = resolvedCollab {
            MarkdownEditorView(
                text: Binding(
                    get: { c.standingPrepNotes },
                    set: {
                        c.standingPrepNotes = $0
                        c.standingPrepUpdatedAt = Date()
                        try? context.save()
                    }
                ),
                textViewID: "prepWindow.collab.\(c.persistentModelID.hashValue)"
            )
        } else if let p = resolvedProject {
            MarkdownEditorView(
                text: Binding(
                    get: { p.standingPrepNotes },
                    set: {
                        p.standingPrepNotes = $0
                        p.standingPrepUpdatedAt = Date()
                        try? context.save()
                    }
                ),
                textViewID: "prepWindow.project.\(p.persistentModelID.hashValue)"
            )
        } else {
            Text("Cible introuvable.").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                Task { await runGenerate() }
            } label: {
                Label(isGenerating ? "Génère…" : "Générer brouillon IA",
                      systemImage: "wand.and.stars")
            }
            .disabled(isGenerating)
        }
    }

    @MainActor
    private func runGenerate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let md = try await AIReportService.generatePrep(
                collab: resolvedCollab, project: resolvedProject, meeting: nil,
                in: context, settings: settings
            )
            if let c = resolvedCollab {
                c.standingPrepNotes = md
                c.standingPrepUpdatedAt = Date()
            } else if let p = resolvedProject {
                p.standingPrepNotes = md
                p.standingPrepUpdatedAt = Date()
            }
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
