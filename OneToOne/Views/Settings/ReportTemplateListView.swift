import SwiftUI
import SwiftData

/// CRUD list of ReportTemplates, split into two sections: built-in templates
/// (italic, can be reset to their seed defaults but not deleted) and custom
/// templates (editable and deletable). Both can be duplicated into a new custom.
struct ReportTemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ReportTemplate.name) private var templates: [ReportTemplate]
    @State private var editing: ReportTemplate?
    @State private var search: String = ""

    private var filtered: [ReportTemplate] {
        guard !search.isEmpty else { return templates.filter { !$0.isArchived } }
        return templates.filter { !$0.isArchived && $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var builtIns: [ReportTemplate] {
        filtered.filter { $0.isBuiltIn }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var customs: [ReportTemplate] {
        filtered.filter { !$0.isBuiltIn }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Rechercher…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let t = ReportTemplate(name: "Nouveau template", kind: .custom)
                    context.insert(t)
                    try? context.save()
                    editing = t
                } label: {
                    Label("Nouveau", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if !builtIns.isEmpty {
                Text("Templates fournis").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(builtIns) { t in row(t) }
            }
            if !customs.isEmpty {
                Divider().padding(.vertical, 4)
                Text("Templates personnalisés").font(.caption.bold()).foregroundColor(.secondary)
                ForEach(customs) { t in row(t) }
            }
        }
        .sheet(item: $editing) { t in
            ReportTemplateEditorView(template: t) { editing = nil }
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    /// Row for one template: edit and duplicate are always available; built-in
    /// templates additionally offer "Restaurer défaut" (reset to seed), while
    /// custom templates offer destructive deletion instead.
    @ViewBuilder
    private func row(_ t: ReportTemplate) -> some View {
        HStack {
            Image(systemName: t.kind.sfSymbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name)
                    .font(.body)
                    .italic(t.isBuiltIn)
                Text(t.kind.label).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Modifier") { editing = t }
                .buttonStyle(.bordered).controlSize(.small)
            Button("Dupliquer") {
                let copy = ReportTemplate(
                    name: t.name + " (copie)",
                    kind: t.kind,
                    promptBody: t.promptBody,
                    sections: t.sections,
                    historyMode: t.historyMode,
                    historyN: t.historyN,
                    historyK: t.historyK,
                    isBuiltIn: false
                )
                context.insert(copy)
                try? context.save()
            }
            .buttonStyle(.bordered).controlSize(.small)
            if t.isBuiltIn {
                Button("Restaurer défaut") {
                    if let seed = BuiltInTemplates.dict[t.name] {
                        t.promptBody = seed.promptBody
                        t.sections = seed.sections
                        t.historyMode = seed.historyMode
                        t.historyN = seed.historyN
                        t.historyK = seed.historyK
                        try? context.save()
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button(role: .destructive) {
                    context.delete(t)
                    try? context.save()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
