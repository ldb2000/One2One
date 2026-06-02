import SwiftUI
import SwiftData

/// "Suivi manager" sidebar destination. Three tabs:
/// - Rapport courant: items à aborder (archivedAt == nil)
/// - Historique: items archivés (archivedAt != nil)
/// - Actions demandées: ActionTask.fromManager == true
struct ManagerTrackingView: View {

    @Query private var settingsList: [AppSettings]
    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt == nil })
    private var rawCurrentItems: [ManagerReportItem]

    @Query(filter: #Predicate<ManagerReportItem> { $0.archivedAt != nil })
    private var rawArchivedItems: [ManagerReportItem]

    @Query(filter: #Predicate<ActionTask> { $0.fromManager == true })
    private var managerActions: [ActionTask]

    @Environment(\.modelContext) private var context

    @State private var selectedTab: Tab = .current
    @State private var filterCategory: String?
    @State private var historySearch: String = ""
    @State private var showAddManual = false
    @State private var manualSnippet = ""
    @State private var manualCategory = "Information"
    @State private var manualTag = ""

    /// Onglets du suivi manager.
    enum Tab: String, Identifiable, CaseIterable {
        /// Points actifs à aborder (`archivedAt == nil`).
        case current = "Rapport courant"
        /// Points archivés (`archivedAt != nil`).
        case history = "Historique"
        /// Actions demandées au manager (`ActionTask.fromManager == true`).
        case actions = "Actions demandées"
        var id: String { rawValue }
    }

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    /// Points actifs triés par ordre manuel puis par date de création (plus récent d'abord).
    private var currentItems: [ManagerReportItem] {
        rawCurrentItems.sorted {
            if $0.manualOrder != $1.manualOrder { return $0.manualOrder < $1.manualOrder }
            return $0.createdAt > $1.createdAt
        }
    }

    /// Points archivés triés par date d'archivage décroissante.
    private var archivedItems: [ManagerReportItem] {
        rawArchivedItems.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    private var sortedManagerActions: [ActionTask] {
        managerActions.sorted { lhs, rhs in
            (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
    }

    /// Points actifs filtrés par la catégorie sélectionnée (toutes si aucun filtre).
    private var filteredCurrent: [ManagerReportItem] {
        guard let f = filterCategory else { return currentItems }
        return currentItems.filter { $0.category == f }
    }

    /// Points archivés filtrés par catégorie puis par la recherche texte (snippet, notes, tag).
    private var filteredHistory: [ManagerReportItem] {
        var result = archivedItems
        if let f = filterCategory {
            result = result.filter { $0.category == f }
        }
        let q = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.rawSnippet.lowercased().contains(q) ||
                $0.userNotes.lowercased().contains(q) ||
                $0.tag.lowercased().contains(q)
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 12)

            Group {
                switch selectedTab {
                case .current: currentTab
                case .history: historyTab
                case .actions: actionsTab
                }
            }
        }
        .navigationTitle("Suivi manager")
        .sheet(isPresented: $showAddManual) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ajouter un point").font(.headline)
                TextField("Description", text: $manualSnippet, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Picker("Catégorie", selection: $manualCategory) {
                    ForEach(settings.managerCategories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { Text($0).tag($0) }
                }
                TextField("Tag", text: $manualTag).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Annuler") { showAddManual = false; manualSnippet = ""; manualTag = "" }
                    Button("Ajouter") {
                        let snippet = manualSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !snippet.isEmpty else { return }
                        _ = ManagerReportService.addManual(snippet: snippet, category: manualCategory, tag: manualTag, in: context)
                        try? context.save()
                        manualSnippet = ""; manualTag = ""; showAddManual = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualSnippet.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20).frame(minWidth: 420)
        }
    }

    @ViewBuilder
    private var currentTab: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { Text($0).tag($0 as String?) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button {
                    showAddManual = true
                } label: { Label("Ajouter", systemImage: "plus.circle") }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            if filteredCurrent.isEmpty {
                ContentUnavailableView(
                    "Aucun point à aborder",
                    systemImage: "tray",
                    description: Text("Sélectionne du texte dans une réunion pour commencer.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredCurrent) { item in
                        ItemRow(item: item, settings: settings, onDelete: {
                            ManagerReportService.delete(item: item, in: context)
                        })
                            .swipeActions {
                                Button(role: .destructive) {
                                    ManagerReportService.delete(item: item, in: context)
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    ManagerReportService.delete(item: item, in: context)
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyTab: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filtre", selection: $filterCategory) {
                    Text("Toutes catégories").tag(nil as String?)
                    ForEach(settings.managerCategories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) { Text($0).tag($0 as String?) }
                }
                .pickerStyle(.menu)
                TextField("Recherche", text: $historySearch).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Spacer()
            }
            .padding(16)

            if filteredHistory.isEmpty {
                ContentUnavailableView("Aucun élément archivé", systemImage: "archivebox")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredHistory) { item in
                        ItemRow(item: item, settings: settings, showArchiveDate: true, onDelete: {
                            ManagerReportService.delete(item: item, in: context)
                        })
                            .swipeActions {
                                Button(role: .destructive) {
                                    ManagerReportService.delete(item: item, in: context)
                                } label: { Label("Supprimer", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    ManagerReportService.delete(item: item, in: context)
                                } label: { Label("Supprimer définitivement", systemImage: "trash") }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsTab: some View {
        if sortedManagerActions.isEmpty {
            ContentUnavailableView("Aucune action manager", systemImage: "checklist")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("À faire") {
                    ForEach(sortedManagerActions.filter { !$0.isCompleted }) { task in
                        actionRow(task)
                    }
                }
                Section("Faites") {
                    ForEach(sortedManagerActions.filter { $0.isCompleted }) { task in
                        actionRow(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ task: ActionTask) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { task.isCompleted },
                set: { newValue in task.isCompleted = newValue; try? context.save() }
            )).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.callout)
                if let due = task.dueDate {
                    Text("Échéance \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(due < Date() ? .red : .secondary)
                }
                if let m = task.managerMeeting {
                    Text("1:1 du \(m.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Item row

    /// Ligne d'un point du rapport manager : badge catégorie/tag, extrait contextuel, notes et source.
    private struct ItemRow: View {
        let item: ManagerReportItem
        let settings: AppSettings
        /// Affiche la date d'archivage (utilisé dans l'onglet Historique).
        var showArchiveDate: Bool = false
        /// Callback de suppression ; le bouton corbeille n'apparaît que s'il est fourni.
        var onDelete: (() -> Void)? = nil
        @Environment(\.modelContext) private var context
        @State private var confirmDelete = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.category)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                    if !item.tag.isEmpty {
                        Text("#\(item.tag)").font(.caption2).foregroundColor(.secondary)
                    }
                    if !item.duplicateOfStableID.isEmpty {
                        Label("Doublon possible", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    if showArchiveDate, let d = item.archivedAt {
                        Text(d.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    if onDelete != nil {
                        Button {
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help("Supprimer définitivement ce point")
                        .confirmationDialog(
                            "Supprimer ce point du rapport manager ?",
                            isPresented: $confirmDelete
                        ) {
                            Button("Supprimer", role: .destructive) {
                                onDelete?()
                            }
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text(item.elaboratedText.isEmpty ? item.rawSnippet : item.elaboratedText)
                        }
                    }
                }
                contextualSnippet(item: item)
                if !item.userNotes.isEmpty {
                    Text(item.userNotes).font(.caption).foregroundColor(.secondary)
                }
                if let src = item.sourceMeeting {
                    Text("Source : \(src.title.isEmpty ? "Réunion" : src.title) · \(src.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }

        /// Display priority:
        /// 1. `elaboratedText` (AI-rédigé / utilisateur-édité) si non-vide
        /// 2. Sinon contextBefore + rawSnippet (medium) + contextAfter inline
        /// 3. Sinon rawSnippet seul
        @ViewBuilder
        private func contextualSnippet(item: ManagerReportItem) -> some View {
            let elaborated = item.elaboratedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !elaborated.isEmpty {
                Text(elaborated).font(.callout).lineLimit(5)
            } else {
                let before = item.contextBefore.trimmingCharacters(in: .whitespacesAndNewlines)
                let after = item.contextAfter.trimmingCharacters(in: .whitespacesAndNewlines)
                if before.isEmpty && after.isEmpty {
                    Text(item.rawSnippet).font(.callout).lineLimit(3)
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
                    .lineLimit(5)
                }
            }
        }
    }
}
