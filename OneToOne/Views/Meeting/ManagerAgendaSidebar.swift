import SwiftUI
import SwiftData

/// Sidebar shown inside MeetingView when `meeting.kind == .manager`.
/// Lists items from the current manager report (archivedAt == nil), separated
/// into "à aborder" / "abordés", with a notes editor per expanded item and a
/// "Générer CR manager" footer button.
struct ManagerAgendaSidebar: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt == nil })
    private var rawItems: [ManagerReportItem]

    private var items: [ManagerReportItem] {
        rawItems.sorted {
            if $0.manualOrder != $1.manualOrder {
                return $0.manualOrder < $1.manualOrder
            }
            return $0.createdAt > $1.createdAt
        }
    }

    @State private var expandedItemID: UUID?
    @State private var filterCategory: String?

    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var pendingActions: [ManagerCRGenerator.ExtractedAction] = []
    @State private var showActionReview = false
    @State private var showAddManual = false
    @State private var manualSnippet = ""
    @State private var manualCategory = "Information"
    @State private var manualTag = ""
    @State private var pendingDeleteItem: ManagerReportItem?

    private var unchecked: [ManagerReportItem] {
        items.filter { !$0.isCompleted && passesFilter($0) }
    }
    private var checked: [ManagerReportItem] {
        items.filter { $0.isCompleted && passesFilter($0) }
    }

    private func passesFilter(_ item: ManagerReportItem) -> Bool {
        if let f = filterCategory { return item.category == f }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if unchecked.isEmpty && checked.isEmpty {
                        ContentUnavailableView(
                            "Aucun point à aborder",
                            systemImage: "checklist",
                            description: Text("Ajoute des points depuis tes réunions ou via le bouton ci-dessous.")
                        )
                        .padding(.vertical, 32)
                    } else {
                        if !unchecked.isEmpty {
                            Text("À aborder").font(.caption.bold()).foregroundColor(.secondary)
                            ForEach(unchecked) { item in itemRow(item) }
                        }
                        if !checked.isEmpty {
                            Text("Abordés (\(checked.count))").font(.caption.bold()).foregroundColor(.secondary).padding(.top, 8)
                            ForEach(checked) { item in itemRow(item) }
                        }
                    }
                }
                .padding(12)
            }

            footer
        }
        .frame(minWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showActionReview) {
            ManagerActionReviewSheet(
                actions: pendingActions,
                onCancel: { showActionReview = false },
                onConfirm: { kept in
                    showActionReview = false
                    do {
                        _ = try ManagerCRGenerator.materializeActions(kept, in: meeting, context: context)
                    } catch {
                        generationError = error.localizedDescription
                    }
                }
            )
        }
        .sheet(isPresented: $showAddManual) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter un point").font(.headline)
                TextField("Description", text: $manualSnippet, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                Picker("Catégorie", selection: $manualCategory) {
                    ForEach(settings.managerCategories, id: \.self) { Text($0).tag($0) }
                }
                TextField("Tag (optionnel)", text: $manualTag).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annuler") { showAddManual = false; manualSnippet = ""; manualTag = "" }
                    Button("Ajouter") {
                        let snippet = manualSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !snippet.isEmpty else { return }
                        _ = ManagerReportService.addManual(
                            snippet: snippet, category: manualCategory, tag: manualTag, in: context
                        )
                        try? context.save()
                        manualSnippet = ""; manualTag = ""
                        showAddManual = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
        .confirmationDialog(
            "Supprimer ce point du rapport manager ?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            ),
            presenting: pendingDeleteItem
        ) { item in
            Button("Supprimer", role: .destructive) {
                ManagerReportService.delete(item: item, in: context)
                pendingDeleteItem = nil
            }
            Button("Annuler", role: .cancel) { pendingDeleteItem = nil }
        } message: { item in
            Text(item.elaboratedText.isEmpty ? item.rawSnippet : item.elaboratedText)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: MeetingKind.manager.sfSymbol).foregroundColor(.accentColor)
                Text("Agenda manager").font(.headline)
                Spacer()
            }
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories, id: \.self) {
                        Text($0).tag($0 as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = generationError {
                Text(err).font(.caption).foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button {
                showAddManual = true
            } label: {
                Label("Ajouter point", systemImage: "plus.circle")
            }
            Spacer()
            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Génération…")
                    }
                } else {
                    Label("Générer CR manager", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || checked.isEmpty)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func itemRow(_ item: ManagerReportItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { item.isCompleted },
                    set: { newValue in
                        item.isCompleted = newValue
                        try? context.save()
                    }
                )).labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.category)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                        if !item.tag.isEmpty {
                            Text("#\(item.tag)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    contextualSnippet(item: item, expanded: expandedItemID == item.stableID)
                    if let src = item.sourceMeeting {
                        Text("• \(src.title.isEmpty ? "Réunion" : src.title) · \(src.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    if expandedItemID == item.stableID {
                        expandedItemID = nil
                    } else {
                        expandedItemID = item.stableID
                    }
                } label: {
                    Image(systemName: expandedItemID == item.stableID ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    pendingDeleteItem = item
                } label: {
                    Image(systemName: "trash").foregroundColor(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Supprimer définitivement")
            }
            if expandedItemID == item.stableID {
                TextEditor(text: Binding(
                    get: { item.userNotes },
                    set: { newValue in
                        item.userNotes = newValue
                        try? context.save()
                    }
                ))
                .font(.callout)
                .frame(minHeight: 70, maxHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Display priority: elaboratedText > contextBefore+rawSnippet+contextAfter > rawSnippet alone.
    @ViewBuilder
    private func contextualSnippet(item: ManagerReportItem, expanded: Bool) -> some View {
        let elaborated = item.elaboratedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !elaborated.isEmpty {
            Text(elaborated)
                .font(.callout)
                .lineLimit(expanded ? nil : 4)
        } else {
            let before = item.contextBefore.trimmingCharacters(in: .whitespacesAndNewlines)
            let after = item.contextAfter.trimmingCharacters(in: .whitespacesAndNewlines)
            if before.isEmpty && after.isEmpty {
                Text(item.rawSnippet)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 2)
            } else {
                (
                    (before.isEmpty
                        ? Text("")
                        : Text("…\(before) ").foregroundColor(.secondary))
                    + Text(item.rawSnippet).foregroundColor(.primary)
                        .fontWeight(.medium)
                    + (after.isEmpty
                        ? Text("")
                        : Text(" \(after)…").foregroundColor(.secondary))
                )
                .font(.callout)
                .lineLimit(expanded ? nil : 4)
            }
        }
    }

    @MainActor
    private func generate() async {
        generationError = nil
        isGenerating = true
        defer { isGenerating = false }

        let toGenerate = checked
        do {
            let report = try await ManagerCRGenerator.generate(
                meeting: meeting, items: toGenerate, settings: settings, context: context
            )
            // Decode actions from the generated report.
            if let data = report.extractedActionsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ManagerCRGenerator.ExtractedAction].self, from: data) {
                pendingActions = decoded
                showActionReview = true
            }
        } catch {
            generationError = error.localizedDescription
        }
    }
}
