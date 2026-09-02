import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Query private var entities: [Entity]
    @Query private var collaborators: [Collaborator]
    @Query private var allMeetings: [Meeting]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingProjectAttachmentImporter = false
    @State private var newProjectAttachmentCategory = "Document"

    private let riskLevels = ["", "Faible", "Modéré", "Élevé", "Critique"]
    private let phases = ["Cadrage", "Design", "Build", "Run"]
    private let statuses = ["Unknown", "Green", "Yellow", "Red"]
    private let projectTypes = ["Métier", "Transverse", "Technique"]
    private let projectAttachmentCategories = ["DAT", "DIT", "Document"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Activité réunions") {
                    MeetingHeatmapView(
                        meetings: MeetingStatsScope.held(
                            allMeetings.filter { $0.project?.persistentModelID == project.persistentModelID }
                        )
                    )
                    .padding(.top, 4)
                }

                // Informations Générales
                GroupBox("Informations Générales") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Code") {
                            EditableTextField(placeholder: "Code", text: $project.code)
                                .frame(height: 24)
                        }
                        LabeledContent("Nom") {
                            EditableTextField(placeholder: "Nom", text: $project.name)
                                .frame(height: 24)
                        }
                        LabeledContent("Domaine") {
                            EditableTextField(placeholder: "Domaine", text: $project.domain)
                                .frame(height: 24)
                        }
                        LabeledContent("Sponsor") {
                            EditableTextField(placeholder: "Sponsor", text: $project.sponsor)
                                .frame(height: 24)
                        }
                        LabeledContent("Chef de projet") {
                            OwnerPickerMenu(
                                label: "Aucun",
                                selection: $project.projectManager,
                                allCollaborators: collaborators,
                                onSaved: { try? context.save() }
                            )
                        }
                        LabeledContent("Architecte technique") {
                            OwnerPickerMenu(
                                label: "Aucun",
                                selection: $project.technicalArchitect,
                                allCollaborators: collaborators,
                                onSaved: { try? context.save() }
                            )
                        }

                        Picker("Type", selection: $project.projectType) {
                            ForEach(projectTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }

                        Picker("Entité", selection: $project.entity) {
                            Text("Aucune").tag(nil as Entity?)
                            ForEach(entities.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { entity in
                                Text(entity.name).tag(entity as Entity?)
                            }
                        }

                        Picker("Phase", selection: $project.phase) {
                            ForEach(phases, id: \.self) { Text($0).tag($0) }
                        }

                        Picker("Statut", selection: $project.status) {
                            ForEach(statuses, id: \.self) { s in
                                HStack {
                                    Circle().fill(statusColor(s)).frame(width: 8, height: 8)
                                    Text(s)
                                }.tag(s)
                            }
                        }

                        LabeledContent("Nombre de jours") {
                            TextField("0", value: $project.plannedDays, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                        }

                        LabeledContent("Deadline fin de design") {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { project.designEndDeadline ?? Date() },
                                    set: { project.designEndDeadline = $0 }
                                ),
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                        }

                        LabeledContent("Informations complémentaires") {
                            EditableTextField(
                                placeholder: "Contexte, dépendances, arbitrages...",
                                text: Binding(
                                    get: { project.additionalInfo ?? "" },
                                    set: { project.additionalInfo = $0 }
                                )
                            )
                            .frame(height: 24)
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Risques
                GroupBox("Risques") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Niveau de risque", selection: Binding(
                            get: { project.riskLevel ?? "" },
                            set: { project.riskLevel = $0.isEmpty ? nil : $0 }
                        )) {
                            ForEach(riskLevels, id: \.self) { level in
                                Text(level.isEmpty ? "Aucun" : level).tag(level)
                            }
                        }

                        LabeledContent("Description du risque") {
                            EditableTextField(placeholder: "Décrivez le risque principal...", text: Binding(
                                get: { project.riskDescription ?? "" },
                                set: { project.riskDescription = $0.isEmpty ? nil : $0 }
                            ))
                            .frame(height: 24)
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Points clés
                GroupBox("Points Clés") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(project.keyPoints.enumerated()), id: \.offset) { index, point in
                            HStack {
                                Text("•")
                                Text(point)
                                Spacer()
                                Button(action: { project.keyPoints.remove(at: index) }) {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        KeyPointAdder(keyPoints: $project.keyPoints)
                    }
                    .padding(.vertical, 5)
                }

                // Commentaires
                GroupBox("Commentaires") {
                    EditableTextEditor(text: Binding(
                        get: { project.comment ?? "" },
                        set: { project.comment = $0 }
                    ))
                    .frame(minHeight: 80)
                }

                // Documents Techniques
                GroupBox("Documents Techniques") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("DAT Effectué", isOn: $project.hasDAT)
                        if project.hasDAT {
                            LabeledContent("Lien DAT") {
                                EditableTextField(placeholder: "https://...", text: Binding(
                                    get: { project.datLink?.absoluteString ?? "" },
                                    set: { project.datLink = URL(string: $0) }
                                ))
                                .frame(height: 24)
                            }
                            if let url = project.datLink {
                                Link("Ouvrir le DAT", destination: url)
                                    .font(.caption)
                            }
                        }

                        Toggle("DIT Effectué", isOn: $project.hasDIT)
                        if project.hasDIT {
                            LabeledContent("Lien DIT") {
                                EditableTextField(placeholder: "https://...", text: Binding(
                                    get: { project.ditLink?.absoluteString ?? "" },
                                    set: { project.ditLink = URL(string: $0) }
                                ))
                                .frame(height: 24)
                            }
                            if let url = project.ditLink {
                                Link("Ouvrir le DIT", destination: url)
                                    .font(.caption)
                            }
                        }

                        Divider().padding(.vertical, 4)

                        HStack {
                            Picker("Type de document", selection: $newProjectAttachmentCategory) {
                                ForEach(projectAttachmentCategories, id: \.self) { category in
                                    Text(category).tag(category)
                                }
                            }
                            .pickerStyle(.menu)

                            Spacer()

                            Button("Ajouter une pièce jointe") {
                                showingProjectAttachmentImporter = true
                            }
                            .buttonStyle(.bordered)
                        }

                        Text("Glissez-déposez un fichier (PDF, PPTX, …) ici pour l'ajouter au projet.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if project.attachments.isEmpty {
                            Text("Aucune pièce jointe projet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.secondary.opacity(0.3),
                                                       style: StrokeStyle(lineWidth: 1, dash: [4]))
                                )
                        } else {
                            ForEach(project.attachments.sorted(by: { $0.importedAt > $1.importedAt })) { attachment in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(attachment.category)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(4)
                                        Text(attachment.fileName)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        Button {
                                            AttachmentImporter.openWithDefaultApp(attachment.resolvedURL())
                                        } label: {
                                            Label("Aperçu", systemImage: "eye")
                                        }
                                        .font(.caption)
                                        .help("Ouvrir dans Aperçu (ou app par défaut pour ce type)")
                                        Button(role: .destructive) {
                                            // Remove the local copy from disk before
                                            // deleting the SwiftData record.
                                            AttachmentImporter.deleteFromDisk(attachment.resolvedURL())
                                            context.delete(attachment)
                                            saveContext()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    EditableTextField(
                                        placeholder: "Commentaire / intérêt du document...",
                                        text: Binding(
                                            get: { attachment.comment },
                                            set: {
                                                attachment.comment = $0
                                                saveContext()
                                            }
                                        )
                                    )
                                    .frame(height: 24)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, 5)
                    // Drag-drop support for files dragged from Finder.
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        var didAdd = false
                        for provider in providers {
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                guard let url = url else { return }
                                Task { @MainActor in
                                    addProjectAttachment(from: url)
                                    saveContext()
                                }
                            }
                            didAdd = true
                        }
                        return didAdd
                    }
                }

                // Flux Mermaid
                GroupBox("Flux Phase") {
                    GanttPhaseView(projects: [project])
                }

                // Alertes du projet
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        let activeAlerts = project.alerts.filter { !$0.isResolved }
                        let resolvedAlerts = project.alerts.filter { $0.isResolved }

                        if activeAlerts.isEmpty && resolvedAlerts.isEmpty {
                            Text("Aucune alerte").foregroundColor(.secondary)
                        }

                        ForEach(activeAlerts) { alert in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(alertColor(alert.severity))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(alert.title).bold()
                                        Spacer()
                                        Text(alert.severity)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(alertColor(alert.severity).opacity(0.2))
                                            .cornerRadius(3)
                                        Text(alert.date, style: .date).font(.caption2).foregroundColor(.secondary)
                                    }
                                    if !alert.detail.isEmpty {
                                        Text(alert.detail).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Button(action: {
                                    alert.isResolved = true
                                    saveContext()
                                }) {
                                    Image(systemName: "checkmark.circle").foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Marquer comme résolue")
                            }
                        }

                        if !resolvedAlerts.isEmpty {
                            DisclosureGroup("Résolues (\(resolvedAlerts.count))") {
                                ForEach(resolvedAlerts) { alert in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                        Text(alert.title).strikethrough().foregroundColor(.secondary)
                                        Spacer()
                                        Text(alert.date, style: .date).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                } label: {
                    HStack {
                        Text("Alertes")
                        let activeCount = project.alerts.filter { !$0.isResolved }.count
                        if activeCount > 0 {
                            Text("\(activeCount)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }

                // Actions en cours
                GroupBox {
                    VStack(alignment: .leading, spacing: 5) {
                        let pendingTasks = project.tasks.filter { !$0.isCompleted }
                        let doneTasks = project.tasks.filter { $0.isCompleted }

                        if pendingTasks.isEmpty && doneTasks.isEmpty {
                            Text("Aucune action").foregroundColor(.secondary)
                        }

                        ForEach(pendingTasks) { task in
                            HStack {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                Text(task.title)
                                Spacer()
                            }
                        }

                        if !doneTasks.isEmpty {
                            DisclosureGroup("Terminées (\(doneTasks.count))") {
                                ForEach(doneTasks) { task in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                        Text(task.title).strikethrough().foregroundColor(.secondary)
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 5)
                } label: {
                    HStack {
                        Text("Actions")
                        let pendingCount = project.tasks.filter { !$0.isCompleted }.count
                        if pendingCount > 0 {
                            Text("\(pendingCount)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }

                GroupBox {
                    DisclosureGroup(isExpanded: .constant(!project.standingPrepNotes.isEmpty)) {
                        VStack(alignment: .leading, spacing: 6) {
                            MarkdownEditorView(
                                text: Binding(
                                    get: { project.standingPrepNotes },
                                    set: {
                                        project.standingPrepNotes = $0
                                        project.standingPrepUpdatedAt = Date()
                                        try? context.save()
                                    }
                                ),
                                textViewID: "projectPrep.\(project.persistentModelID.hashValue)"
                            )
                            .frame(minHeight: 160)
                            HStack {
                                Spacer()
                                Button {
                                    Task { await generatePrepForProject() }
                                } label: {
                                    Label("Générer brouillon IA", systemImage: "wand.and.stars")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Préparation prochaine réunion").font(.headline)
                            Spacer()
                            if let dt = project.standingPrepUpdatedAt {
                                Text("maj \(relativeProjPrepDate(dt))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                NotesSection(target: .project(project))
            }
            .padding()
        }
        .warmBackground()
        .navigationTitle(project.name)
        .fileImporter(
            isPresented: $showingProjectAttachmentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleProjectAttachmentImport(result: result)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Enregistrer") {
                    saveContext()
                }

                Button(project.isArchived ? "Désarchiver" : "Archiver") {
                    project.isArchived.toggle()
                    saveContext()
                    if project.isArchived {
                        dismiss()
                    }
                }

                Button("Supprimer", role: .destructive) {
                    context.delete(project)
                    saveContext()
                    dismiss()
                }
            }
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "green": return .green
        case "yellow": return .yellow
        case "red": return .red
        default: return .gray
        }
    }

    private func alertColor(_ severity: String) -> Color {
        switch severity {
        case "Critique": return .red
        case "Élevé": return .orange
        case "Modéré": return .yellow
        default: return .blue
        }
    }

    private func saveContext() {
        do {
            try context.save()
            SpotlightIndexService.shared.index(project: project)
        } catch {
            print("[ProjectDetail] save FAILED: \(error)")
        }
    }

    private func handleProjectAttachmentImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addProjectAttachment(from: url)
            }
            saveContext()
        case .failure(let error):
            print("[ProjectDetail] attachment import failed: \(error)")
        }
    }

    /// Copies the source URL into Application Support and creates a
    /// `ProjectAttachment` pointing at the local copy. Used both by the
    /// fileImporter callback and by drag-drop.
    private func addProjectAttachment(from sourceURL: URL) {
        do {
            let copied = try AttachmentImporter.copyIntoAppSupport(
                source: sourceURL,
                bucket: .project(code: project.code)
            )
            let attachment = ProjectAttachment(url: copied, category: newProjectAttachmentCategory)
            attachment.project = project
            context.insert(attachment)
            if newProjectAttachmentCategory == "DAT" {
                project.hasDAT = true
            } else if newProjectAttachmentCategory == "DIT" {
                project.hasDIT = true
            }
        } catch {
            print("[ProjectDetail] attachment copy failed: \(error)")
        }
    }

    /// Génère via l'IA un brouillon de préparation pour le projet et l'enregistre
    /// dans `standingPrepNotes` (horodaté). Les erreurs sont seulement loguées.
    @MainActor
    private func generatePrepForProject() async {
        let settings = settingsList.canonicalSettings ?? AppSettings()
        do {
            let md = try await AIReportService.generatePrep(
                collab: nil, project: project, meeting: nil,
                in: context, settings: settings
            )
            project.standingPrepNotes = md
            project.standingPrepUpdatedAt = Date()
            try? context.save()
        } catch {
            print("[ProjectPrep] generation failed: \(error)")
        }
    }

    /// Formatteur de date relative (fr_FR) mis en cache pour éviter une
    /// réallocation à chaque rafraîchissement de la vue.
    private static let relativePrepFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private func relativeProjPrepDate(_ d: Date) -> String {
        Self.relativePrepFormatter.localizedString(for: d, relativeTo: Date())
    }
}

/// Petit composant pour ajouter un point clé
struct KeyPointAdder: View {
    @Binding var keyPoints: [String]
    @State private var newPoint: String = ""

    var body: some View {
        HStack {
            EditableTextField(placeholder: "Ajouter un point clé...", text: $newPoint)
                .frame(height: 22)
            Button(action: {
                guard !newPoint.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                keyPoints.append(newPoint)
                newPoint = ""
            }) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(newPoint.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// Fiche détaillée d'un collaborateur : identité/photo, projets pilotés,
/// préparation du prochain 1:1, actions assignées, réunions et historique d'entretiens.
struct CollaboratorDetailView: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhotoImporter = false
    @State private var showingPhotoSearch = false
    @State private var prepExpanded: Bool = false
    @State private var showingQuickAdd: Bool = false
    @State private var quickAddTitle: String = ""
    @State private var quickAddProject: Project? = nil
    @State private var quickAddDueDate: Date? = nil
    @Query private var allMeetings: [Meeting]
    @Query private var appSettings: [AppSettings]
    @Query(filter: #Predicate<Project> { !$0.isArchived },
           sort: \Project.name) private var availableProjects: [Project]

    @ViewBuilder
    private func ownershipSection(title: String, projects: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.0)
                Text("(\(projects.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ForEach(ProjectStatusPalette.sortedByStatus(projects)) { p in
                NavigationLink {
                    ProjectDetailView(project: p)
                } label: {
                    projectRow(p)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ p: Project) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ProjectStatusPalette.color(p.status))
                .frame(width: 8, height: 8)
            Text(p.code)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.tertiary)
            Text(p.name)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(p.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(ProjectStatusPalette.color(p.status).opacity(0.18)))
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Activité réunions") {
                    MeetingHeatmapView(
                        meetings: MeetingStatsScope.held(
                            allMeetings.filter { meeting in
                                meeting.participants.contains(where: { $0.persistentModelID == collaborator.persistentModelID })
                            }
                        )
                    )
                    .padding(.top, 4)
                }

                GroupBox("Identité") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 16) {
                            collaboratorPhotoView

                            VStack(alignment: .leading, spacing: 8) {
                                Button("Importer une photo") {
                                    showingPhotoImporter = true
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    LinkedInPhotoSearch.openLinkedInSearch(name: collaborator.name)
                                } label: {
                                    Label("Rechercher sur LinkedIn", systemImage: "magnifyingglass")
                                }
                                .buttonStyle(.bordered)
                                .help("Ouvre LinkedIn dans le navigateur. Copiez la photo, puis revenez dans cette fiche et collez avec Cmd+V.")

                                Button {
                                    pasteClipboardPhoto()
                                } label: {
                                    Label("Coller depuis presse-papiers", systemImage: "doc.on.clipboard")
                                }
                                .buttonStyle(.bordered)
                                .keyboardShortcut("v", modifiers: [.command])
                                .help("Coller une image copiée (ex: depuis LinkedIn).")

                                Button {
                                    showingPhotoSearch = true
                                } label: {
                                    Label("Rechercher photo (web)", systemImage: "sparkles.rectangle.stack")
                                }
                                .buttonStyle(.bordered)
                                .help("Rechercher via DuckDuckGo (ou Google CSE si configuré en Préférences).")

                                if collaborator.photoURL() != nil {
                                    Button("Retirer la photo", role: .destructive) {
                                        collaborator.photoPath = ""
                                        collaborator.photoBookmarkData = nil
                                        saveContext()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        LabeledContent("Nom complet") {
                            EditableTextField(placeholder: "Nom complet", text: $collaborator.name)
                                .frame(height: 24)
                        }
                        LabeledContent("Poste / Rôle") {
                            EditableTextField(placeholder: "Poste / Rôle", text: $collaborator.role)
                                .frame(height: 24)
                        }
                    }
                    .padding(.vertical, 5)
                }

                // Projets dont ce collab est archi technique ou chef de projet.
                if !collaborator.projectsAsArchitect.isEmpty
                    || !collaborator.projectsAsManager.isEmpty {
                    GroupBox("Projets") {
                        VStack(alignment: .leading, spacing: 14) {
                            if !collaborator.projectsAsArchitect.isEmpty {
                                ownershipSection(
                                    title: "EN TANT QU'ARCHITECTE TECHNIQUE",
                                    projects: collaborator.projectsAsArchitect
                                )
                            }
                            if !collaborator.projectsAsManager.isEmpty {
                                ownershipSection(
                                    title: "EN TANT QUE CHEF DE PROJET",
                                    projects: collaborator.projectsAsManager
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GroupBox {
                    DisclosureGroup(isExpanded: $prepExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            if collaborator.standingPrepNotes.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("Aucune préparation. Saisis directement ci-dessous ou clique sur « Générer brouillon IA ».")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                    Spacer()
                                }
                                .padding(.bottom, 4)
                            }
                            MarkdownEditorView(
                                text: Binding(
                                    get: { collaborator.standingPrepNotes },
                                    set: {
                                        collaborator.standingPrepNotes = $0
                                        collaborator.standingPrepUpdatedAt = Date()
                                        try? context.save()
                                    }
                                ),
                                textViewID: "collabPrep.\(collaborator.persistentModelID.hashValue)"
                            )
                            .frame(minHeight: 160)
                            HStack {
                                Spacer()
                                Button {
                                    Task { await generatePrepForCollab() }
                                } label: {
                                    Label("Générer brouillon IA", systemImage: "wand.and.stars")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Préparation prochaine 1:1").font(.headline)
                            Spacer()
                            if let dt = collaborator.standingPrepUpdatedAt {
                                Text("maj \(relativeCollabPrepDate(dt))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onAppear {
                        if !prepExpanded {
                            prepExpanded = !collaborator.standingPrepNotes.isEmpty
                        }
                    }
                    .onChange(of: collaborator.standingPrepNotes) { _, newValue in
                        if !newValue.isEmpty && !prepExpanded {
                            prepExpanded = true
                        }
                    }
                    if !prepExpanded && collaborator.standingPrepNotes.isEmpty {
                        HStack {
                            Spacer()
                            Button("Créer une préparation") {
                                prepExpanded = true
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox {
                    let pendingTasks = collaborator.assignedTasks.filter { !$0.isCompleted }
                    let doneTasks = collaborator.assignedTasks.filter { $0.isCompleted }

                    if pendingTasks.isEmpty && doneTasks.isEmpty && !showingQuickAdd {
                        Text("Aucune action assignée").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            if showingQuickAdd {
                                quickAddRow
                                    .padding(.bottom, 6)
                            }
                            ForEach(pendingTasks) { task in
                                HStack {
                                    Button {
                                        task.isCompleted = true
                                        task.completedAt = Date()
                                        try? context.save()
                                    } label: {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Marquer comme fait")

                                    Text(task.title)
                                    Spacer()
                                    if let project = task.project {
                                        Text(project.name)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if let dueDate = task.dueDate {
                                        Text(dueDate, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(dueDate < Date() ? .red : .secondary)
                                    }
                                }
                            }

                            if !doneTasks.isEmpty {
                                DisclosureGroup("Terminées (\(doneTasks.count))") {
                                    ForEach(doneTasks) { task in
                                        HStack {
                                            Button {
                                                task.isCompleted = false
                                                task.completedAt = nil
                                                try? context.save()
                                            } label: {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Marquer comme à faire")

                                            Text(task.title)
                                                .strikethrough()
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Actions en cours")
                        let count = collaborator.assignedTasks.filter { !$0.isCompleted }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        Spacer()
                        Button {
                            showingQuickAdd.toggle()
                            if showingQuickAdd {
                                quickAddTitle = ""
                                quickAddProject = nil
                                quickAddDueDate = nil
                            }
                        } label: {
                            Image(systemName: showingQuickAdd ? "xmark.circle" : "plus.circle.fill")
                                .foregroundStyle(showingQuickAdd ? .secondary : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(showingQuickAdd ? "Annuler" : "Ajouter une action")
                    }
                }

                GroupBox("Réunions") {
                    let heldMeetings = MeetingStatsScope.held(collaborator.meetings)
                    if heldMeetings.isEmpty {
                        Text("Aucune réunion").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(heldMeetings.sorted(by: { $0.date > $1.date })) { meeting in
                                NavigationLink {
                                    MeetingView(meeting: meeting)
                                } label: {
                                    HStack {
                                        Image(systemName: "person.3")
                                        VStack(alignment: .leading) {
                                            Text(meeting.title.isEmpty ? "Réunion sans titre" : meeting.title)
                                            Text(meeting.date, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
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
                            }
                        }
                    }
                }

                NotesSection(target: .collaborator(collaborator))
            }
            .padding()
        }
        .warmBackground()
        .fileImporter(
            isPresented: $showingPhotoImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handlePhotoImport(result: result)
        }
        .sheet(isPresented: $showingPhotoSearch) {
            PhotoSearchSheet(
                initialQuery: collaborator.name,
                googleAPIKey: appSettings.first?.googleCseApiKey ?? "",
                googleCSEID: appSettings.first?.googleCseId ?? ""
            ) { data in
                savePhotoData(data)
            }
        }
        .navigationTitle(collaborator.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    saveContext()
                }) {
                    Label("Enregistrer", systemImage: "checkmark.circle")
                }

                Button(action: {
                    collaborator.isArchived.toggle()
                    saveContext()
                    if collaborator.isArchived {
                        dismiss()
                    }
                }) {
                    Label(collaborator.isArchived ? "Désarchiver" : "Archiver", systemImage: collaborator.isArchived ? "tray.and.arrow.up" : "archivebox")
                }

                Button(role: .destructive, action: deleteCollaborator) {
                    Label("Supprimer définitivement", systemImage: "trash")
                }
            }
        }
    }

    private func deleteCollaborator() {
        context.delete(collaborator)
        saveContext()
        dismiss()
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("[LOG CollaboratorDetail] save FAILED: \(error)")
        }
    }

    /// Génère via l'IA un brouillon de préparation du prochain 1:1 et l'enregistre
    /// dans `standingPrepNotes` (horodaté). Les erreurs sont seulement loguées.
    @MainActor
    private func generatePrepForCollab() async {
        let settings = appSettings.canonicalSettings ?? AppSettings()
        do {
            let md = try await AIReportService.generatePrep(
                collab: collaborator, project: nil, meeting: nil,
                in: context, settings: settings
            )
            collaborator.standingPrepNotes = md
            collaborator.standingPrepUpdatedAt = Date()
            try? context.save()
        } catch {
            print("[CollabPrep] generation failed: \(error)")
        }
    }

    /// Formatteur de date relative (fr_FR) mis en cache (évite une réallocation par rendu).
    private static let relativePrepFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    private func relativeCollabPrepDate(_ d: Date) -> String {
        Self.relativePrepFormatter.localizedString(for: d, relativeTo: Date())
    }

    @ViewBuilder
    private var collaboratorPhotoView: some View {
        if let url = collaborator.photoURL(),
           let image = ImageCache.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor)
                )
        }
    }

    private func handlePhotoImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            collaborator.photoPath = url.path
            collaborator.photoBookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveContext()
        case .failure(let error):
            print("[CollaboratorDetail] photo import failed: \(error)")
        }
    }

    private func pasteClipboardPhoto() {
        guard let data = LinkedInPhotoSearch.pasteImageFromClipboard() else {
            NSSound.beep()
            return
        }
        savePhotoData(data)
    }

    /// Persists raw image bytes to Application Support and updates the
    /// collaborator's photoPath. Uses a fresh UUID per save so two
    /// collaborators can't accidentally overwrite each other's photo
    /// even if their stableIDs collided (legacy data).
    private func savePhotoData(_ data: Data) {
        let dir = URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appending(path: "\(UUID().uuidString).jpg")
        do {
            try data.write(to: target, options: .atomic)
            // Best-effort cleanup of the previous photo if it lived in our
            // managed photos dir (avoid orphaning files across pastes).
            let oldPath = collaborator.photoPath
            if !oldPath.isEmpty,
               oldPath.hasPrefix(dir.path),
               oldPath != target.path {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            collaborator.photoPath = target.path
            collaborator.photoBookmarkData = nil
            saveContext()
        } catch {
            print("[CollaboratorDetail] savePhotoData failed: \(error)")
        }
    }

    // MARK: - Quick-add action row

    @ViewBuilder
    private var quickAddRow: some View {
        HStack(spacing: 8) {
            TextField("Titre de l'action…", text: $quickAddTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitQuickAdd)

            Menu {
                Button("Aucun") { quickAddProject = nil }
                Divider()
                ForEach(availableProjects) { p in
                    Button(p.name) { quickAddProject = p }
                }
            } label: {
                Text(quickAddProject?.name ?? "Projet")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button("Aucune") { quickAddDueDate = nil }
                Button("Aujourd'hui") { quickAddDueDate = Date() }
                Button("Demain") { quickAddDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) }
                Button("Dans une semaine") { quickAddDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) }
            } label: {
                Text(quickAddDueDate.map { quickAddDateLabel($0) } ?? "Échéance")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 110)
            }
            .menuStyle(.borderlessButton)

            Button {
                submitQuickAdd()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(canSubmitQuickAdd ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitQuickAdd)

            Button {
                showingQuickAdd = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var canSubmitQuickAdd: Bool {
        !quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitQuickAdd() {
        let trimmed = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = ActionTask(title: trimmed, dueDate: quickAddDueDate)
        task.collaborator = collaborator
        task.project = quickAddProject
        context.insert(task)
        try? context.save()
        quickAddTitle = ""
        quickAddProject = nil
        quickAddDueDate = nil
        showingQuickAdd = false
    }

    /// Formatteur « jour mois » (fr_FR) mis en cache pour l'étiquette d'échéance.
    private static let quickAddDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    private func quickAddDateLabel(_ d: Date) -> String {
        Self.quickAddDateFormatter.string(from: d)
    }
}
