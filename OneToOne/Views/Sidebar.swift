import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MainSidebarView: View {
    @Query private var projects: [Project]
    @Query private var collaborators: [Collaborator]
    @Query private var entities: [Entity]
    @Environment(\.modelContext) private var context
    @State private var searchText: String = ""
    @State private var expandedEntityNames: Set<String> = []
    @State private var selectedProjectIDs: Set<PersistentIdentifier> = []
    @State private var isMultiSelectMode = false
    @State private var renamingCollaborator: Collaborator?
    @State private var renamingName: String = ""

    // MARK: - Filtered data

    private var filteredEntities: [Entity] {
        guard !searchText.isEmpty else { return entities }
        return entities.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredActiveCollaborators: [Collaborator] {
        let active = collaborators.filter { !$0.isArchived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.role.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredArchivedCollaborators: [Collaborator] {
        let archived = collaborators.filter { $0.isArchived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return archived }
        return archived.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func filteredProjectsFor(entity: Entity) -> [Project] {
        let entityProjects = entity.projects.filter { !$0.isArchived }.sorted(by: { $0.name < $1.name })
        guard !searchText.isEmpty else { return entityProjects }
        return entityProjects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText) ||
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredOrphanProjects: [Project] {
        let orphans = projects.filter { $0.entity == nil && !$0.isArchived }.sorted(by: { $0.name < $1.name })
        guard !searchText.isEmpty else { return orphans }
        return orphans.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText) ||
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredArchivedProjects: [Project] {
        let archived = projects.filter { $0.isArchived }.sorted(by: { $0.name < $1.name })
        guard !searchText.isEmpty else { return archived }
        return archived.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText) ||
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Body

    private var selectedProjects: [Project] {
        projects.filter { selectedProjectIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Multi-select action bar
            if isMultiSelectMode && !selectedProjectIDs.isEmpty {
                multiSelectBar
            }

            List {
                NavigationLink {
                    DashboardView()
                } label: {
                    Label("Tableau de bord", systemImage: "chart.bar.fill")
                }

                NavigationLink {
                    ChatbotView()
                } label: {
                    Label("Assistant IA", systemImage: "bubble.left.and.text.bubble.right.fill")
                }

                NavigationLink {
                    ActionsListView()
                } label: {
                    Label("Actions", systemImage: "checklist")
                }

                NavigationLink {
                    MeetingsListView()
                } label: {
                    Label("Réunions", systemImage: "person.3")
                }

                Section("Collaborateurs Actifs") {
                    ForEach(filteredActiveCollaborators) { collaborator in
                        NavigationLink {
                            CollaboratorDetailView(collaborator: collaborator)
                        } label: {
                            HStack(spacing: 8) {
                                SidebarCollaboratorAvatar(collaborator: collaborator)
                                Text(collaborator.name)
                            }
                        }
                        .contextMenu {
                            Button("Renommer") {
                                renamingName = collaborator.name
                                renamingCollaborator = collaborator
                            }
                            Button(collaborator.isArchived ? "Désarchiver" : "Archiver") {
                                collaborator.isArchived.toggle()
                                saveContext()
                            }
                            Divider()
                            Button("Supprimer", role: .destructive) {
                                context.delete(collaborator)
                                saveContext()
                            }
                        }
                    }
                    .onDelete(perform: deleteCollaborators)

                    Button(action: addCollaborator) {
                        Label("Ajouter", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if !filteredArchivedCollaborators.isEmpty {
                    Section("Archives") {
                        ForEach(filteredArchivedCollaborators) { collaborator in
                            NavigationLink {
                            CollaboratorDetailView(collaborator: collaborator)
                        } label: {
                                HStack(spacing: 8) {
                                    SidebarCollaboratorAvatar(collaborator: collaborator)
                                    Text(collaborator.name)
                                }
                                .foregroundColor(.secondary)
                            }
                            .contextMenu {
                                Button("Renommer") {
                                    renamingName = collaborator.name
                                    renamingCollaborator = collaborator
                                }
                                Button("Désarchiver") {
                                    collaborator.isArchived = false
                                    saveContext()
                                }
                                Divider()
                                Button("Supprimer", role: .destructive) {
                                    context.delete(collaborator)
                                    saveContext()
                                }
                            }
                        }
                        .onDelete(perform: deleteCollaborators)
                    }
                }

                Section("Projets par Entité") {
                    ForEach(filteredEntities.sorted(by: { $0.name < $1.name })) { entity in
                        let entityProjects = filteredProjectsFor(entity: entity)
                        if !entityProjects.isEmpty || searchText.isEmpty {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedEntityNames.contains(entity.name) || !searchText.isEmpty },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedEntityNames.insert(entity.name)
                                        } else {
                                            expandedEntityNames.remove(entity.name)
                                        }
                                    }
                                )
                            ) {
                                ForEach(entityProjects) { project in
                                    projectRow(project)
                                }

                                Button(action: { addProject(to: entity) }) {
                                    Label("Ajouter un projet", systemImage: "plus.circle")
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            } label: {
                                HStack {
                                    Label(entity.name, systemImage: "building.2")
                                    Spacer()
                                    Text("\(entityProjects.count)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .dropDestination(for: String.self) { codes, _ in
                                moveProjects(codes: codes, to: entity)
                                return true
                            }
                        }
                    }

                    let orphans = filteredOrphanProjects
                    if !orphans.isEmpty || searchText.isEmpty {
                        DisclosureGroup("Sans Entité") {
                            ForEach(orphans) { project in
                                projectRow(project)
                            }
                        }
                        .dropDestination(for: String.self) { codes, _ in
                            moveProjectsToNone(codes: codes)
                            return true
                        }
                    }

                    Button(action: addProject) {
                        Label("Ajouter Projet", systemImage: "plus.circle")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if !filteredArchivedProjects.isEmpty {
                    Section("Projets Archivés") {
                        ForEach(filteredArchivedProjects) { project in
                            projectRow(project)
                                .foregroundColor(.secondary)
                        }
                        .onDelete(perform: deleteArchivedProjects)
                    }
                }

                Spacer()

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Paramètres", systemImage: "gear")
                    }
                }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Rechercher...")
            .listStyle(.sidebar)
            .sheet(item: $renamingCollaborator) { collaborator in
                VStack(spacing: 16) {
                    Text("Renommer le collaborateur")
                        .font(.headline)
                    EditableTextField(placeholder: "Nom", text: $renamingName)
                        .frame(width: 300, height: 28)
                    HStack {
                        Button("Annuler") {
                            renamingCollaborator = nil
                        }
                        .keyboardShortcut(.cancelAction)
                        Button("Renommer") {
                            collaborator.name = renamingName
                            saveContext()
                            renamingCollaborator = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(renamingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(24)
                .frame(minWidth: 350)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isMultiSelectMode.toggle()
                        if !isMultiSelectMode { selectedProjectIDs.removeAll() }
                    }) {
                        Image(systemName: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(isMultiSelectMode ? .accentColor : .secondary)
                    }
                    .help(isMultiSelectMode ? "Quitter la selection multiple" : "Selection multiple de projets")
                }
            }
        }
    }

    // MARK: - Project Row (selectable in multi-select mode)

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        if isMultiSelectMode {
            Button(action: {
                toggleSelection(project)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: selectedProjectIDs.contains(project.persistentModelID) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedProjectIDs.contains(project.persistentModelID) ? .accentColor : .secondary)
                    projectLabel(for: project)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ProjectDetailView(project: project)
            } label: {
                projectLabel(for: project)
            }
            .draggable(project.code)
        }
    }

    private func toggleSelection(_ project: Project) {
        let id = project.persistentModelID
        if selectedProjectIDs.contains(id) {
            selectedProjectIDs.remove(id)
        } else {
            selectedProjectIDs.insert(id)
        }
    }

    // MARK: - Multi-select Action Bar

    private var multiSelectBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(selectedProjectIDs.count) projet(s) selectionne(s)")
                    .font(.caption.bold())
                Spacer()
                Button("Tout deselect.") { selectedProjectIDs.removeAll() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 8) {
                // Phase
                Menu {
                    ForEach(["Cadrage", "Design", "Build", "Run"], id: \.self) { phase in
                        Button(phase) { batchSetPhase(phase) }
                    }
                } label: {
                    Label("Phase", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 80)

                // Status
                Menu {
                    ForEach(["Green", "Yellow", "Red", "Unknown"], id: \.self) { status in
                        Button(status) { batchSetStatus(status) }
                    }
                } label: {
                    Label("Statut", systemImage: "circle.fill")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 80)

                // Entity
                Menu {
                    Button("Aucune entite") { batchSetEntity(nil) }
                    Divider()
                    ForEach(entities.sorted(by: { $0.name < $1.name })) { entity in
                        Button(entity.name) { batchSetEntity(entity) }
                    }
                } label: {
                    Label("Entite", systemImage: "building.2")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 80)

                Spacer()

                // Archive
                Button(action: batchArchive) {
                    Label("Archiver", systemImage: "archivebox")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                // Delete
                Button(action: batchDelete) {
                    Label("Suppr.", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Batch Operations

    private func batchSetPhase(_ phase: String) {
        for project in selectedProjects { project.phase = phase }
        try? context.save()
    }

    private func batchSetStatus(_ status: String) {
        for project in selectedProjects { project.status = status }
        try? context.save()
    }

    private func batchSetEntity(_ entity: Entity?) {
        for project in selectedProjects { project.entity = entity }
        try? context.save()
    }

    private func batchArchive() {
        for project in selectedProjects { project.isArchived = true }
        try? context.save()
        selectedProjectIDs.removeAll()
    }

    private func batchDelete() {
        for project in selectedProjects { context.delete(project) }
        try? context.save()
        selectedProjectIDs.removeAll()
    }

    // MARK: - Project label with risk indicator

    @ViewBuilder
    private func projectLabel(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                StatusIcon(status: project.status)
                Text(project.name)
                    .lineLimit(1)
                Spacer()
                if let risk = project.riskLevel, !risk.isEmpty {
                    riskBadge(risk)
                }
            }

            HStack(spacing: 6) {
                Text(project.projectType)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(4)
                Text("Sponsor: \(project.sponsor.isEmpty ? "Non renseigné" : project.sponsor)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func riskBadge(_ level: String) -> some View {
        let color: Color = switch level {
        case "Critique": .red
        case "Élevé": .orange
        case "Modéré": .yellow
        default: .green
        }
        Text(level)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    // MARK: - Drag & Drop

    private func moveProjects(codes: [String], to entity: Entity) {
        for code in codes {
            if let project = projects.first(where: { $0.code == code }) {
                project.entity = entity
                print("[Sidebar] Moved '\(project.name)' -> entity '\(entity.name)'")
            }
        }
        saveContext()
    }

    private func moveProjectsToNone(codes: [String]) {
        for code in codes {
            if let project = projects.first(where: { $0.code == code }) {
                project.entity = nil
                print("[Sidebar] Moved '\(project.name)' -> Sans Entité")
            }
        }
        saveContext()
    }

    // MARK: - CRUD

    private func addCollaborator() {
        let newCollab = Collaborator(name: "Nouveau Collaborateur")
        context.insert(newCollab)
        saveContext()
    }

    private func addProject() {
        let newProject = Project(code: nextProjectCode(), name: "Nouveau Projet", domain: "General", sponsor: "", projectType: "Métier", phase: "Cadrage")
        context.insert(newProject)
        saveContext()
    }

    private func addProject(to entity: Entity) {
        let newProject = Project(code: nextProjectCode(), name: "Nouveau Projet", domain: entity.name, sponsor: "", projectType: "Métier", phase: "Cadrage")
        newProject.entity = entity
        context.insert(newProject)
        expandedEntityNames.insert(entity.name)
        saveContext()
    }

    private func deleteCollaborators(offsets: IndexSet) {
        let activeCollabs = collaborators.filter { !$0.isArchived }
        for index in offsets {
            context.delete(activeCollabs[index])
        }
        saveContext()
    }

    private func deleteArchivedProjects(offsets: IndexSet) {
        let archivedProjects = projects.filter { $0.isArchived }.sorted(by: { $0.name < $1.name })
        for index in offsets {
            context.delete(archivedProjects[index])
        }
        saveContext()
    }

    private func nextProjectCode() -> String {
        let existingCodes = Set(projects.map(\.code))
        var index = 1
        var candidate = "PXX_\(String(format: "%03d", index))"
        while existingCodes.contains(candidate) {
            index += 1
            candidate = "PXX_\(String(format: "%03d", index))"
        }
        return candidate
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Erreur de sauvegarde SwiftData: \(error)")
        }
    }
}

// MARK: - Entity Detail View

struct EntityDetailView: View {
    @Bindable var entity: Entity
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Détails de l'Entité") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Nom") {
                        EditableTextField(placeholder: "Nom", text: $entity.name)
                            .frame(height: 24)
                    }
                    LabeledContent("Description") {
                        EditableTextField(placeholder: "Description", text: Binding(
                            get: { entity.summary ?? "" },
                            set: { entity.summary = $0 }
                        ))
                        .frame(height: 24)
                    }
                }
                .padding(.vertical, 5)
            }

            GroupBox("Projets associés") {
                if entity.projects.isEmpty {
                    Text("Aucun projet associé").foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(entity.projects) { project in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    StatusIcon(status: project.status)
                                    Text(project.name)
                                    Spacer()
                                    Text(project.code).font(.caption).foregroundColor(.secondary)
                                    if let risk = project.riskLevel, !risk.isEmpty {
                                        Text(risk).font(.caption2)
                                            .padding(.horizontal, 4)
                                            .background(riskColor(risk).opacity(0.2))
                                            .foregroundColor(riskColor(risk))
                                            .cornerRadius(3)
                                    }
                                }
                                Text("\(project.projectType) • Sponsor: \(project.sponsor.isEmpty ? "Non renseigné" : project.sponsor)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .warmBackground()
        .navigationTitle(entity.name)
        .toolbar {
            Button("Enregistrer") {
                do {
                    try context.save()
                } catch {
                    print("[EntityDetail] save FAILED: \(error)")
                }
            }
        }
    }

    private func riskColor(_ level: String) -> Color {
        switch level {
        case "Critique": return .red
        case "Élevé": return .orange
        case "Modéré": return .yellow
        default: return .green
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Query private var projects: [Project]
    @Query private var interviews: [Interview]
    @Query private var collaborators: [Collaborator]
    @Query private var entities: [Entity]
    @Query private var meetings: [Meeting]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @State private var showingFileImporter = false
    @State private var isProcessing = false
    @State private var isExportingWeekly = false
    @State private var importError: String?
    @State private var importResult: String?
    @State private var weeklyReport: String?
    // Import prompt sheet
    @State private var showingImportPromptSheet = false
    @State private var pendingImportURL: URL?
    @State private var pendingImportFileName: String = ""
    @State private var importCustomPrompt: String = ""
    @State private var extractedFilePreview: String = ""
    // Rollback
    @State private var lastImportProjectIDs: [Project] = []
    @State private var lastImportCollaboratorIDs: [Collaborator] = []
    @State private var lastImportInterview: Interview?
    @State private var canRollback = false

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    private var thisWeekInterviews: [Interview] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return interviews.filter { $0.date >= weekAgo }
    }

    private var riskyProjects: [Project] {
        projects.filter { p in
            p.status.lowercased() == "red" || p.status.lowercased() == "yellow" ||
            p.riskLevel == "Critique" || p.riskLevel == "Élevé"
        }
    }

    private var pendingTasksByProject: [(String, [ActionTask])] {
        projects
            .map { ($0.name, $0.tasks.filter { !$0.isCompleted }) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0 < $1.0 }
    }

    private var pendingTasksByCollaborator: [(String, [ActionTask])] {
        collaborators
            .map { collaborator in
                // Use direct assignedTasks relationship, falling back to interview-based lookup
                let directTasks = collaborator.assignedTasks.filter { !$0.isCompleted }
                let interviewTasks = collaborator.interviews.flatMap { $0.tasks }.filter { !$0.isCompleted && $0.collaborator == nil }
                let allTasks = directTasks + interviewTasks
                // Deduplicate by persistentModelID
                var seen = Set<PersistentIdentifier>()
                let unique = allTasks.filter { seen.insert($0.persistentModelID).inserted }
                return (collaborator.name, unique)
            }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Tableau de bord")
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    Button(action: exportProjectOverview) {
                        Label("Exporter les projets", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button(action: generateWeeklyReport) {
                        if isExportingWeekly {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export Hebdo", systemImage: "calendar.badge.clock")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExportingWeekly || thisWeekInterviews.isEmpty)
                    .help("Générer le rapport hebdomadaire des modifications")

                    Button(action: { showingFileImporter = true }) {
                        Label("Importer", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }

                if isProcessing {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyse IA en cours...")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }

                if let error = importError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                        Spacer()
                        Button("OK") { importError = nil }
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                if let result = importResult {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(result)
                        Spacer()
                        if canRollback {
                            Button(action: rollbackLastImport) {
                                Label("Annuler l'import", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                        Button("OK") {
                            importResult = nil
                            canRollback = false
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                // Stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    StatCard(title: "Total Projets", value: "\(projects.count)", color: .blue)
                    StatCard(title: "En Build", value: "\(projects.filter { $0.phase == "Build" }.count)", color: .orange)
                    StatCard(title: "En Run", value: "\(projects.filter { $0.phase == "Run" }.count)", color: .green)

                    StatCard(title: "Risques Critiques", value: "\(projects.filter { $0.riskLevel == "Critique" }.count)", color: .red)
                    StatCard(title: "Risques Élevés", value: "\(projects.filter { $0.riskLevel == "Élevé" }.count)", color: .orange)
                    StatCard(title: "DAT Manquantes", value: "\(projects.filter { !$0.hasDAT }.count)", color: .purple)
                }

                // Risks & alerts
                if !riskyProjects.isEmpty {
                    SectionView(title: "Risques & Alertes") {
                        ForEach(riskyProjects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    StatusIcon(status: project.status)
                                    Text(project.name).font(.headline)
                                    Spacer()
                                    if let risk = project.riskLevel {
                                        Text(risk)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(riskColor(risk).opacity(0.2))
                                            .foregroundColor(riskColor(risk))
                                            .cornerRadius(4)
                                    }
                                }
                                if let riskDesc = project.riskDescription, !riskDesc.isEmpty {
                                    Text(riskDesc)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                if !project.keyPoints.isEmpty {
                                    ForEach(project.keyPoints, id: \.self) { point in
                                        HStack(alignment: .top, spacing: 4) {
                                            Text("•")
                                            Text(point).font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                }
                                if let comment = project.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Gantt-like phase overview
                SectionView(title: "Vue Phases Projets") {
                    EntityGroupedGanttView(entities: entities, orphanProjects: projects.filter { $0.entity == nil })
                }

                if !pendingTasksByProject.isEmpty {
                    SectionView(title: "Actions en cours par projet") {
                        ForEach(pendingTasksByProject, id: \.0) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.0).font(.headline)
                                ForEach(entry.1) { task in
                                    Text("• \(task.title)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !pendingTasksByCollaborator.isEmpty {
                    SectionView(title: "Actions en cours par collaborateur") {
                        ForEach(pendingTasksByCollaborator, id: \.0) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.0).font(.headline)
                                ForEach(entry.1) { task in
                                    HStack {
                                        Text("• \(task.title)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let dueDate = task.dueDate {
                                            Spacer()
                                            Text(dueDate, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(dueDate < Date() ? .red : .secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Recent meetings
                let recentMeetings = meetings.filter {
                    $0.date >= (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
                }.sorted(by: { $0.date > $1.date })

                if !recentMeetings.isEmpty {
                    SectionView(title: "Réunions récentes") {
                        ForEach(recentMeetings) { meeting in
                            NavigationLink {
                                MeetingView(meeting: meeting)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title.isEmpty ? "Réunion sans titre" : meeting.title)
                                            .font(.headline)
                                        Text(meeting.date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if !meeting.participants.isEmpty {
                                            Text(meeting.participants.map(\.name).joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    let pendingCount = meeting.tasks.filter { !$0.isCompleted }.count
                                    if pendingCount > 0 {
                                        Text("\(pendingCount)")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.orange)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Weekly report
                if let report = weeklyReport {
                    SectionView(title: "Rapport Hebdomadaire") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Spacer()
                                Button(action: {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(report, forType: .string)
                                }) {
                                    Label("Copier", systemImage: "doc.on.doc")
                                }
                                .font(.caption)
                                Button("Fermer") { weeklyReport = nil }
                                    .font(.caption)
                            }
                            Text(report)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding()
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
        .warmBackground()
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .presentation, .plainText, .text, .commaSeparatedText, .spreadsheet, .item],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .sheet(isPresented: $showingImportPromptSheet) {
            ImportPromptSheet(
                fileName: pendingImportFileName,
                filePreview: extractedFilePreview,
                prompt: $importCustomPrompt,
                onCancel: {
                    showingImportPromptSheet = false
                    pendingImportURL = nil
                },
                onImport: {
                    executeImport()
                }
            )
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard settings.useAIForImport else {
                importError = "L'import IA est desactive dans les parametres. Activez 'Import de fichiers' dans Fonctionnalites IA."
                return
            }

            // Store URL and filename first
            let fileName = url.lastPathComponent
            pendingImportURL = url
            pendingImportFileName = fileName

            // Extract text preview and show prompt sheet
            let service = AIIngestionService()
            do {
                let text = try service.extractTextPublic(from: url)
                extractedFilePreview = text.isEmpty ? "(extraction vide — le fichier sera envoye tel quel a l'IA)" : String(text.prefix(500))
            } catch {
                extractedFilePreview = "(erreur extraction: \(error.localizedDescription) — l'IA tentera quand meme)"
            }

            // Replace {{fileName}} placeholder in prompt
            importCustomPrompt = settings.importPrompt
                .replacingOccurrences(of: "{{fileName}}", with: fileName)
            showingImportPromptSheet = true
        case .failure(let error):
            importError = "Echec de l'import: \(error.localizedDescription)"
        }
    }

    private func executeImport() {
        guard let url = pendingImportURL else { return }
        showingImportPromptSheet = false
        isProcessing = true
        importError = nil
        importResult = nil
        canRollback = false

        // Auto-backup before import
        do {
            let backupService = BackupService()
            let backupData = try backupService.backup(
                settings: settings,
                entities: entities,
                projects: projects,
                collaborators: collaborators,
                interviews: interviews
            )
            let backupDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("OneToOne/backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let dateStr = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = backupDir.appendingPathComponent("pre-import-\(dateStr).json")
            try backupData.write(to: backupURL)
            print("[Import] Auto-backup saved: \(backupURL.lastPathComponent)")
        } catch {
            print("[Import] Auto-backup failed (continuing import): \(error)")
        }

        Task {
            let service = AIIngestionService()
            do {
                let extracted = try await service.processFileWithPrompt(
                    at: url,
                    customPrompt: importCustomPrompt,
                    settings: settings
                )
                await MainActor.run {
                    let result = service.applyExtractedData(extracted, fileName: url.lastPathComponent, in: context)
                    lastImportProjectIDs = result.projects
                    lastImportCollaboratorIDs = result.collaborators
                    lastImportInterview = result.interview
                    canRollback = true
                    isProcessing = false
                    importResult = "\(result.projects.count) projets et \(result.collaborators.count) collaborateurs importes depuis \(url.lastPathComponent)"
                    pendingImportURL = nil
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    importError = error.localizedDescription
                    pendingImportURL = nil
                }
            }
        }
    }

    private func rollbackLastImport() {
        // Delete the interview and its tasks
        if let interview = lastImportInterview {
            for task in interview.tasks { context.delete(task) }
            context.delete(interview)
        }
        // Note: we don't delete projects/collaborators that may have existed before
        // We only delete those that were newly created (have no other references)
        // For safety, just delete the interview — projects may have been updated, not created
        do {
            try context.save()
            canRollback = false
            importResult = nil
            importError = nil
            lastImportProjectIDs = []
            lastImportCollaboratorIDs = []
            lastImportInterview = nil
        } catch {
            importError = "Echec du rollback: \(error.localizedDescription)"
        }
    }

    private func generateWeeklyReport() {
        guard settings.useAIForWeeklyExport else {
            importError = "L'export hebdo IA est desactive dans les parametres."
            return
        }

        isExportingWeekly = true
        weeklyReport = nil

        Task {
            let service = AIReformulationService()
            do {
                let report = try await service.generateWeeklyExport(
                    interviews: thisWeekInterviews,
                    settings: settings
                )
                await MainActor.run {
                    weeklyReport = report
                    isExportingWeekly = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isExportingWeekly = false
                }
            }
        }
    }

    private func riskColor(_ level: String) -> Color {
        switch level {
        case "Critique": return .red
        case "Élevé": return .orange
        case "Modéré": return .yellow
        default: return .green
        }
    }

    private func exportProjectOverview() {
        let content = ExportService().exportProjectsOverview(projects: projects, entities: entities)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Synthese_Projets.md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                importError = "Échec de l'export: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Gantt Phase View

struct GanttPhaseView: View {
    let projects: [Project]
    private let phases = ["Cadrage", "Design", "Build", "Run"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Projet")
                    .font(.caption.bold())
                    .frame(width: 180, alignment: .leading)
                ForEach(phases, id: \.self) { phase in
                    Text(phase)
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ForEach(projects.sorted(by: { $0.name < $1.name })) { project in
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        StatusIcon(status: project.status)
                        Text(project.name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(width: 180, alignment: .leading)

                    ForEach(phases, id: \.self) { phase in
                        let isCurrent = project.phase == phase
                        let phaseIndex = phases.firstIndex(of: phase) ?? 0
                        let currentIndex = phases.firstIndex(of: project.phase) ?? 0
                        let isPast = phaseIndex < currentIndex

                        Rectangle()
                            .fill(isCurrent ? phaseColor(project.status) : (isPast ? Color.green.opacity(0.3) : Color.gray.opacity(0.1)))
                            .frame(height: 20)
                            .overlay {
                                if isCurrent {
                                    Text(phase)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }

    private func phaseColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "red": return .red
        case "yellow": return .orange
        case "green": return .green
        default: return .blue
        }
    }
}

struct EntityGroupedGanttView: View {
    let entities: [Entity]
    let orphanProjects: [Project]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(entities.sorted(by: { $0.name < $1.name })) { entity in
                let entityProjects = entity.projects.sorted(by: { $0.name < $1.name })
                if !entityProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entity.name)
                            .font(.headline)
                        GanttPhaseView(projects: entityProjects)
                    }
                }
            }

            if !orphanProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sans entité")
                        .font(.headline)
                    GanttPhaseView(projects: orphanProjects.sorted(by: { $0.name < $1.name }))
                }
            }
        }
    }
}

// MARK: - Reusable components

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.black.opacity(0.55))
            Text(value)
                .font(.title)
                .bold()
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.80))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SidebarCollaboratorAvatar: View {
    let collaborator: Collaborator

    var body: some View {
        if let url = collaborator.photoURL(),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                )
        }
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.top)
            Divider()
            content()
        }
    }
}

// MARK: - Import Prompt Sheet

struct ImportPromptSheet: View {
    let fileName: String
    let filePreview: String
    @Binding var prompt: String
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Import: \(fileName)")
                        .font(.headline)
                    Text("Personnalisez le prompt avant d'envoyer a l'IA")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            GroupBox("Apercu du fichier") {
                ScrollView {
                    Text(filePreview.isEmpty ? "(aucun texte extrait)" : filePreview + (filePreview.count >= 500 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            GroupBox("Prompt d'import") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le contenu du fichier sera ajoute a la fin du prompt.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    EditableTextEditor(text: $prompt)
                        .frame(minHeight: 180)
                }
            }

            HStack {
                Button("Annuler") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: onImport) {
                    Label("Lancer l'import IA", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 500)
    }
}
