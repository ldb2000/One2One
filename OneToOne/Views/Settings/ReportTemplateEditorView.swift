import SwiftUI
import SwiftData

/// Sheet to edit a ReportTemplate's name, kind, sections, history mode,
/// and prompt body. A clickable variables palette inserts {{var}} at cursor.
struct ReportTemplateEditorView: View {
    @Bindable var template: ReportTemplate
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var sections: [TemplateSection] = []
    @State private var promptBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Nom du template", text: $template.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Picker("Catégorie", selection: Binding(
                    get: { template.kind },
                    set: { template.kind = $0 }
                )) {
                    ForEach(ReportTemplateKind.allCases) { k in
                        Label(k.label, systemImage: k.sfSymbol).tag(k)
                    }
                }
                .frame(maxWidth: 220)
                Spacer()
                Button("Fermer") { save(); onClose() }
                    .keyboardShortcut(.cancelAction)
            }

            historyConfigRow

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Sections").font(.headline)
                    sectionsEditor
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading) {
                    Text("Variables").font(.headline)
                    variablesPalette
                }
                .frame(width: 220)
            }

            Text("Prompt").font(.headline)
            TextEditor(text: $promptBody)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3))
                )
        }
        .padding(16)
        .onAppear {
            sections = template.sections
            promptBody = template.promptBody
        }
        .onDisappear { save() }
    }

    private var historyConfigRow: some View {
        HStack(spacing: 16) {
            Picker("Historique", selection: Binding(
                get: { template.historyMode },
                set: { template.historyMode = $0 }
            )) {
                ForEach(HistoryMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .frame(maxWidth: 280)

            Stepper("N: \(template.historyN)", value: $template.historyN, in: 0...5)
            Stepper("K: \(template.historyK)", value: $template.historyK, in: 0...20)
        }
    }

    private var sectionsEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($sections) { $s in
                HStack {
                    TextField("Titre", text: $s.title)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    TextField("Indication pour l'IA", text: $s.hint)
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        sections.removeAll { $0.id == s.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                sections.append(TemplateSection(title: "Nouvelle section", hint: ""))
            } label: {
                Label("Ajouter une section", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var variablesPalette: some View {
        let groups: [(String, [String])] = [
            ("Réunion", ["title","date","duration","kind","participants","transcript","notes","custom_prompt"]),
            ("Projet", ["project.name","project.code","project.entity","project.phase","project.status","project.planning","project.actions_ouvertes","project.dernier_rapport","project.historique_n"]),
            ("Collab", ["collab.name","collab.role","collab.email","collab.actions_ouvertes","collab.dernier_1to1","collab.notes"]),
            ("Manager", ["manager.items_actuels","manager.dernier_cr"]),
            ("Global", ["actions_overdue","actions_du_jour","historique_n","contexte_general","date_now","semaine","mois"])
        ]
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups, id: \.0) { group in
                    Text(group.0).font(.caption.bold()).foregroundColor(.secondary)
                    ForEach(group.1, id: \.self) { name in
                        Button {
                            promptBody.append("{{\(name)}}")
                        } label: {
                            HStack {
                                Text("{{\(name)}}").font(.caption.monospaced())
                                Spacer()
                                Image(systemName: "plus.circle").foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func save() {
        template.sections = sections
        template.promptBody = promptBody
        template.updatedAt = Date()
        try? context.save()
    }
}
