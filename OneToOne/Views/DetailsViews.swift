import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private func interviewTypeIcon(_ type: InterviewType) -> String {
    switch type {
    case .regular:
        return "person.2"
    case .job:
        return "briefcase"
    case .importPPTX, .importPDF:
        return "square.and.arrow.down"
    }
}

private extension String {
    var prependingBulletList: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "• " + trimmed
    }
}

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Query private var entities: [Entity]
    @Query private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingProjectAttachmentImporter = false
    @State private var newProjectAttachmentCategory = "Document"
    @State private var previewedProjectAttachment: ProjectAttachment?
    @State private var selectedCollaboratorForProjectEntry: Collaborator?

    private let riskLevels = ["", "Faible", "Modéré", "Élevé", "Critique"]
    private let phases = ["Cadrage", "Design", "Build", "Run"]
    private let statuses = ["Unknown", "Green", "Yellow", "Red"]
    private let projectTypes = ["Métier", "Transverse", "Technique"]
    private let projectAttachmentCategories = ["DAT", "DIT", "Document"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                        Picker("Type", selection: $project.projectType) {
                            ForEach(projectTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }

                        Picker("Entité", selection: $project.entity) {
                            Text("Aucune").tag(nil as Entity?)
                            ForEach(entities) { entity in
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

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(project.phase == "Build" ? "REX / Infos projet" : "Infos projet / OneToOne")
                                .font(.headline)
                            Spacer()
                            Button(action: addProjectInfoEntry) {
                                Image(systemName: "plus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Ajouter une entrée datée")
                        }

                        Text(project.phase == "Build"
                             ? "Chaque ajout est daté et permet de capitaliser les retours d'expérience du projet."
                             : "Ajoutez ici des informations datées pour comprendre où en est le sujet et garder l'historique des échanges.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        let entries = project.infoEntries.sorted(by: { $0.date > $1.date })
                        if entries.isEmpty {
                            Text("Aucune information projet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(entry.category)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(entry.category == "REX" ? Color.orange.opacity(0.18) : Color.accentColor.opacity(0.15))
                                            .cornerRadius(4)
                                        Text(entry.date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Button(role: .destructive) {
                                            deleteProjectInfoEntry(entry)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    EditableTextEditor(text: Binding(
                                        get: { entry.content },
                                        set: {
                                            entry.content = $0
                                            saveContext()
                                        }
                                    ))
                                    .frame(minHeight: 90)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                } label: {
                    EmptyView()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Informations / actions collaborateurs")
                                .font(.headline)
                            Spacer()
                            Picker("Collaborateur", selection: $selectedCollaboratorForProjectEntry) {
                                Text("Choisir").tag(nil as Collaborator?)
                                ForEach(collaborators.filter { !$0.isArchived }.sorted(by: { $0.name < $1.name })) { collaborator in
                                    Text(collaborator.name).tag(collaborator as Collaborator?)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 180)

                            Button("Ajouter info") {
                                addCollaboratorEntry(kind: "Information collaborateur")
                            }
                            .disabled(selectedCollaboratorForProjectEntry == nil)

                            Button("Ajouter action") {
                                addCollaboratorEntry(kind: "Action collaborateur")
                            }
                            .disabled(selectedCollaboratorForProjectEntry == nil)
                        }

                        let entries = project.collaboratorEntries.sorted(by: { $0.date > $1.date })
                        if entries.isEmpty {
                            Text("Aucune information collaborateur sur ce projet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(entry.kind)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(entry.kind.contains("Action") ? Color.blue.opacity(0.18) : Color.green.opacity(0.18))
                                            .cornerRadius(4)
                                        if let collaborator = entry.collaborator {
                                            Text(collaborator.name)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Text(entry.date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if entry.kind.contains("Action") {
                                            Button(action: {
                                                entry.isCompleted.toggle()
                                                saveContext()
                                            }) {
                                                Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(entry.isCompleted ? .green : .secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Button(role: .destructive) {
                                            context.delete(entry)
                                            saveContext()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    EditableTextEditor(text: Binding(
                                        get: { entry.content },
                                        set: {
                                            entry.content = $0
                                            saveContext()
                                        }
                                    ))
                                    .frame(minHeight: 90)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                } label: {
                    EmptyView()
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

                        if project.attachments.isEmpty {
                            Text("Aucune pièce jointe projet")
                                .foregroundColor(.secondary)
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
                                        Button("Prévisualiser") {
                                            previewedProjectAttachment = attachment
                                        }
                                        .font(.caption)
                                        Button(role: .destructive) {
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
                                if let interview = task.interview {
                                    Text(interview.date, style: .date).font(.caption2).foregroundColor(.secondary)
                                }
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
        .sheet(item: $previewedProjectAttachment) { attachment in
            ProjectAttachmentPreviewSheet(
                attachment: attachment,
                onClose: { previewedProjectAttachment = nil },
                onSave: saveContext
            )
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
                let attachment = ProjectAttachment(url: url, category: newProjectAttachmentCategory)
                attachment.project = project
                context.insert(attachment)
                if newProjectAttachmentCategory == "DAT" {
                    project.hasDAT = true
                } else if newProjectAttachmentCategory == "DIT" {
                    project.hasDIT = true
                }
            }
            saveContext()
        case .failure(let error):
            print("[ProjectDetail] attachment import failed: \(error)")
        }
    }

    private func addProjectInfoEntry() {
        let category = project.phase == "Build" ? "REX" : "Information"
        let entry = ProjectInfoEntry(date: Date(), content: "", category: category)
        entry.project = project
        context.insert(entry)
        saveContext()
    }

    private func deleteProjectInfoEntry(_ entry: ProjectInfoEntry) {
        context.delete(entry)
        saveContext()
    }

    private func addCollaboratorEntry(kind: String) {
        guard let collaborator = selectedCollaboratorForProjectEntry else { return }
        let entry = ProjectCollaboratorEntry(date: Date(), content: "", kind: kind, isCompleted: false)
        entry.project = project
        entry.collaborator = collaborator
        context.insert(entry)
        saveContext()
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

struct CollaboratorDetailView: View {
    @Bindable var collaborator: Collaborator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhotoImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Identité") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 16) {
                            collaboratorPhotoView

                            VStack(alignment: .leading, spacing: 8) {
                                Button("Importer une photo") {
                                    showingPhotoImporter = true
                                }
                                .buttonStyle(.bordered)

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

                GroupBox {
                    let pendingTasks = collaborator.assignedTasks.filter { !$0.isCompleted }
                    let doneTasks = collaborator.assignedTasks.filter { $0.isCompleted }

                    if pendingTasks.isEmpty && doneTasks.isEmpty {
                        Text("Aucune action assignée").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(pendingTasks) { task in
                                HStack {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                        .font(.caption)
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
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
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
                    }
                }

                GroupBox("Réunions") {
                    if collaborator.meetings.isEmpty {
                        Text("Aucune réunion").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(collaborator.meetings.sorted(by: { $0.date > $1.date })) { meeting in
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

                GroupBox("Historique des Entretiens") {
                    if collaborator.interviews.isEmpty {
                        Text("Aucun entretien enregistré").foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(collaborator.interviews.sorted(by: { $0.date > $1.date })) { interview in
                                NavigationLink {
                                    InterviewView(interview: interview)
                                } label: {
                                    HStack {
                                        Image(systemName: interviewTypeIcon(interview.type))
                                        VStack(alignment: .leading) {
                                            Text(interview.date, style: .date)
                                            Text(interview.type.label)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if interview.hasAlert {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                        }
                                        if interview.recordingLink != nil {
                                            Image(systemName: "mic.fill").foregroundColor(.red)
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

                Button(action: addInterview) {
                    Label("Nouvel Entretien", systemImage: "plus")
                }

                Button(role: .destructive, action: deleteCollaborator) {
                    Label("Supprimer définitivement", systemImage: "trash")
                }
            }
        }
    }

    private func addInterview() {
        let newInterview = Interview(date: Date(), notes: "")
        newInterview.collaborator = collaborator
        context.insert(newInterview)
        saveContext()
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

    @ViewBuilder
    private var collaboratorPhotoView: some View {
        if let url = collaborator.photoURL(),
           let image = NSImage(contentsOf: url) {
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
}

struct InterviewView: View {
    @Bindable var interview: Interview
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var allCollaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @StateObject private var mickeyService = MickeyService()
    @StateObject private var remindersService = RemindersService()
    @State private var exportService = ExportService()
    @Environment(\.modelContext) private var context
    @State private var newTaskTitle: String = ""
    @State private var newAlertTitle: String = ""
    @State private var newAlertSeverity: String = "Modéré"
    @State private var selectedProject: Project?
    @State private var selectedCollaborator: Collaborator?
    @State private var newTaskDueDate: Date? = nil
    @State private var showNewTaskDueDate = false
    @State private var selectedAlertProject: Project?
    @State private var showingAttachmentImporter = false
    @State private var showingTranscriptImporter = false
    @State private var showMarkdownPreview = false
    @State private var previewedAttachment: InterviewAttachment?
    @State private var isReformulating = false
    @State private var isImportingTranscript = false
    @State private var reformulationError: String?
    @State private var isPrefillingJobInterview = false

    private var settings: AppSettings {
        settingsList.canonicalSettings ?? AppSettings()
    }

    private var sortedAttachments: [InterviewAttachment] {
        interview.attachments.sorted(by: { $0.importedAt > $1.importedAt })
    }

    private var editableInterviewTypes: [InterviewType] {
        [.regular, .job]
    }

    private var selectedCVAttachment: InterviewAttachment? {
        sortedAttachments.first
    }

    private var actionButtonDisabled: Bool {
        if interview.type == .job {
            return selectedCVAttachment == nil
        }
        return interview.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: { mickeyService.startRecording() }) {
                    Label("Mickey", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button(action: { mickeyService.stopRecording() }) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.bordered)

                Divider().frame(height: 20).padding(.horizontal, 5)

                // Bouton Reformuler
                Button(action: reformulateNotes) {
                    if isReformulating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(interview.type == .job ? "Préremplir via IA" : "Reformuler", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isReformulating || isPrefillingJobInterview || actionButtonDisabled)
                .help(interview.type == .job ? "Preremplit l'evaluation a partir du CV" : "Reformule les notes avec l'IA et extrait les actions")

                Divider().frame(height: 20).padding(.horizontal, 5)

                // Import transcript
                Menu {
                    Button(action: { showingTranscriptImporter = true }) {
                        Label("Importer un fichier...", systemImage: "doc.text")
                    }
                    Button(action: pasteTranscriptFromClipboard) {
                        Label("Coller depuis le presse-papiers", systemImage: "clipboard")
                    }
                } label: {
                    if isImportingTranscript {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Transcript", systemImage: "text.document")
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 120)
                .disabled(isImportingTranscript)
                .help("Importer un transcript (fichier ou presse-papiers) et le reformuler avec l'IA")

                Spacer()

                Picker(
                    "",
                    selection: Binding(
                        get: { interview.type },
                        set: {
                            interview.type = $0
                            saveContext()
                        }
                    )
                ) {
                    ForEach(editableInterviewTypes, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Menu {
                    Button(action: {
                        let md = exportService.exportToMarkdown(interview: interview)
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(md, forType: .string)
                    }) {
                        Label("Copier Markdown", systemImage: "doc.text")
                    }

                    if interview.type == .job {
                        Button(action: {
                            exportService.exportToPDF(
                                interview: interview,
                                fileName: "Entretien_\(interview.date.formatted()).pdf"
                            )
                        }) {
                            Label("Exporter PDF", systemImage: "doc.richtext")
                        }
                    } else {
                        Button(action: {
                            exportService.exportInterviewEmail(interview: interview)
                        }) {
                            Label("Envoyer le mail", systemImage: "envelope")
                        }
                    }

                    Button(action: {
                        let content = exportService.exportToMarkdown(interview: interview)
                        let title = "Entretien \(interview.collaborator?.name ?? "") - \(interview.date.formatted(date: .abbreviated, time: .omitted))"
                        exportService.exportToAppleNotes(title: title, markdownContent: content)
                    }) {
                        Label("Exporter vers Apple Notes", systemImage: "note.text")
                    }
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            // Error banner
            if let error = reformulationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text(error).font(.caption)
                    Spacer()
                    Button("OK") { reformulationError = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
            }

            if interview.type == .job {
                jobInterviewLayout
            } else {
                collaboratorInterviewLayout
            }
        }
        .warmBackground()
        .navigationTitle("Entretien du \(interview.date, style: .date)")
        .fileImporter(
            isPresented: $showingAttachmentImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            importAttachments(result: result)
        }
        .fileImporter(
            isPresented: $showingTranscriptImporter,
            allowedContentTypes: [.pdf, .plainText, .text, .presentation],
            allowsMultipleSelection: false
        ) { result in
            importTranscript(result: result)
        }
        .sheet(item: $previewedAttachment) { attachment in
            AttachmentPreviewSheet(
                attachment: attachment,
                onOpenExternally: { openAttachmentExternally(attachment) },
                onClose: { previewedAttachment = nil },
                onSave: saveContext
            )
        }
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if let file = interview.sourceFileName {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text(file).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Formatting toolbar (hidden in preview mode)
                if !showMarkdownPreview {
                    MarkdownToolbar(textViewID: "interviewNotes")
                    Divider().frame(height: 16).padding(.horizontal, 4)
                }

                // Preview toggle
                Button(action: { showMarkdownPreview.toggle() }) {
                    Image(systemName: showMarkdownPreview ? "eye.fill" : "eye")
                        .foregroundColor(showMarkdownPreview ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showMarkdownPreview ? "Masquer la preview" : "Afficher la preview")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.03))

            if showMarkdownPreview {
                MarkdownTextView(markdown: interview.notes)
            } else {
                MarkdownEditorView(text: $interview.notes, textViewID: "interviewNotes")
            }
        }
    }

    private var attachmentsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(interview.type == .job ? "CV et documents" : "Pièces jointes")
                    .font(.headline)
                if !sortedAttachments.isEmpty {
                    Text("\(sortedAttachments.count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                Spacer()
                Button(action: { showingAttachmentImporter = true }) {
                    Label("Ajouter", systemImage: "paperclip")
                }
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                if sortedAttachments.isEmpty {
                    Text("Aucune pièce jointe")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sortedAttachments) { attachment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Image(systemName: attachmentIcon(for: attachment.fileName))
                                    .foregroundColor(.accentColor)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attachment.fileName)
                                        .font(.body.weight(.medium))
                                        .lineLimit(2)
                                    Text("Ajouté le \(attachment.importedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if !attachment.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(attachment.comment)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Button("Prévisualiser") {
                                    previewedAttachment = attachment
                                }
                                .font(.caption)

                                Button(action: { openAttachmentExternally(attachment) }) {
                                    Image(systemName: "arrow.up.forward.square")
                                }
                                .buttonStyle(.plain)
                                .help("Ouvrir dans l'application par défaut")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteAttachments)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var collaboratorInterviewLayout: some View {
        HSplitView {
            VSplitView {
                collaboratorContextPanel
                    .frame(minHeight: 180)

                notesPanel
                    .frame(minHeight: 240)

                attachmentsPanel
                    .frame(minHeight: 180)
            }
            .frame(minWidth: 340)

            VSplitView {
                actionsPanel
                    .frame(minHeight: 220)

                alertsPanel
                    .frame(minHeight: 240)
            }
            .frame(minWidth: 300, maxWidth: 460)
        }
    }

    private var collaboratorContextPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contexte entretien")
                .font(.headline)

            Picker("Projet", selection: Binding(
                get: { interview.selectedProject },
                set: {
                    interview.selectedProject = $0
                    saveContext()
                }
            )) {
                Text("Aucun projet").tag(nil as Project?)
                ForEach(projects) { project in
                    Text(project.name).tag(project as Project?)
                }
            }
            .pickerStyle(.menu)

            Toggle("Retour à partager avec tout le monde", isOn: Binding(
                get: { interview.shareWithEveryone },
                set: {
                    interview.shareWithEveryone = $0
                    saveContext()
                }
            ))

            EditableTextField(
                placeholder: "Commentaire de contexte / points à partager...",
                text: Binding(
                    get: { interview.contextComment },
                    set: {
                        interview.contextComment = $0
                        saveContext()
                    }
                )
            )
            .frame(height: 24)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var jobInterviewLayout: some View {
        HSplitView {
            VSplitView {
                jobCandidateSummaryPanel
                    .frame(minHeight: 150)

                jobCVReviewPanel
                    .frame(minHeight: 360)
            }
            .frame(minWidth: 430)

            VSplitView {
                jobAssessmentPanel
                    .frame(minHeight: 320)

                attachmentsPanel
                    .frame(minHeight: 180)
            }
            .frame(minWidth: 340, maxWidth: 520)
        }
    }

    private var jobCandidateSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Synthèse candidat")
                .font(.headline)

            EditableTextField(
                placeholder: "URL LinkedIn",
                text: Binding(
                    get: { interview.candidateLinkedInURL },
                    set: {
                        interview.candidateLinkedInURL = $0
                        saveContext()
                    }
                )
            )
            .frame(height: 24)

            EditableTextEditor(text: Binding(
                get: { interview.generalAssessment },
                set: {
                    interview.generalAssessment = $0
                    saveContext()
                }
            ))
            .frame(minHeight: 80)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var jobCVReviewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Analyse CV")
                    .font(.headline)
                Spacer()
                if let cv = selectedCVAttachment {
                    Button("Prévisualiser le CV") {
                        previewedAttachment = cv
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Expérience") {
                        EditableTextEditor(text: Binding(
                            get: { interview.cvExperienceNotes },
                            set: {
                                interview.cvExperienceNotes = $0
                                saveContext()
                            }
                        ))
                        .frame(minHeight: 110)
                    }

                    GroupBox("Compétences") {
                        EditableTextEditor(text: Binding(
                            get: { interview.cvSkillsNotes },
                            set: {
                                interview.cvSkillsNotes = $0
                                saveContext()
                            }
                        ))
                        .frame(minHeight: 110)
                    }

                    GroupBox("Motivation / posture") {
                        EditableTextEditor(text: Binding(
                            get: { interview.cvMotivationNotes },
                            set: {
                                interview.cvMotivationNotes = $0
                                saveContext()
                            }
                        ))
                        .frame(minHeight: 110)
                    }

                    GroupBox("Notes libres") {
                        EditableTextEditor(text: $interview.notes)
                            .frame(minHeight: 110)
                    }
                }
                .padding()
            }
        }
    }

    private var jobAssessmentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Points positifs") {
                    EditableTextEditor(text: Binding(
                        get: { interview.positivePoints },
                        set: {
                            interview.positivePoints = $0
                            saveContext()
                        }
                    ))
                    .frame(minHeight: 110)
                }

                GroupBox("Points négatifs") {
                    EditableTextEditor(text: Binding(
                        get: { interview.negativePoints },
                        set: {
                            interview.negativePoints = $0
                            saveContext()
                        }
                    ))
                    .frame(minHeight: 110)
                }

                GroupBox("Formation") {
                    EditableTextEditor(text: Binding(
                        get: { interview.trainingAssessment },
                        set: {
                            interview.trainingAssessment = $0
                            saveContext()
                        }
                    ))
                    .frame(minHeight: 110)
                }

                GroupBox("Informations LinkedIn") {
                    EditableTextEditor(text: Binding(
                        get: { interview.candidateLinkedInNotes },
                        set: {
                            interview.candidateLinkedInNotes = $0
                            saveContext()
                        }
                    ))
                    .frame(minHeight: 100)
                }
            }
            .padding()
        }
    }

    private var actionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Actions")
                    .font(.headline)
                let taskCount = interview.tasks.filter { !$0.isCompleted }.count
                if taskCount > 0 {
                    Text("\(taskCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Spacer()
                Button(action: sendAllToReminders) {
                    Label("Tout vers Rappels", systemImage: "bell.badge")
                }
                .font(.caption)
                .disabled(interview.tasks.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                ForEach(interview.tasks) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button(action: {
                                task.isCompleted.toggle()
                                saveContext()
                            }) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(task.isCompleted ? .green : .gray)
                            }
                            .buttonStyle(.plain)

                            EditableTextField(placeholder: "Action...", text: Bindable(task).title)
                                .strikethrough(task.isCompleted)
                                .frame(height: 20)

                            Spacer()

                            if task.reminderID == nil {
                                Button(action: { sendToReminders(task: task) }) {
                                    Image(systemName: "bell").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Button(action: {
                                context.delete(task)
                                saveContext()
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Supprimer cette action")
                        }

                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { task.project },
                                set: { task.project = $0; saveContext() }
                            )) {
                                Text("Aucun projet").tag(nil as Project?)
                                ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)
                            .font(.caption)

                            Picker("", selection: Binding(
                                get: { task.collaborator },
                                set: { task.collaborator = $0; saveContext() }
                            )) {
                                Text("Non assigné").tag(nil as Collaborator?)
                                ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)
                            .font(.caption)

                            if let dueDate = task.dueDate {
                                DatePicker("", selection: Binding(
                                    get: { dueDate },
                                    set: { task.dueDate = $0; saveContext() }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                .font(.caption)
                                .frame(width: 100)

                                Button(action: { task.dueDate = nil; saveContext() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { task.dueDate = Date(); saveContext() }) {
                                    Label("Échéance", systemImage: "calendar.badge.plus")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if task.reminderID != nil {
                                Image(systemName: "bell.fill").font(.caption2).foregroundColor(.blue)
                            }
                        }
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteTasks)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                EditableTextField(placeholder: "Nouvelle action...", text: $newTaskTitle)
                    .frame(height: 24)
                HStack(spacing: 8) {
                    Picker("Projet", selection: $selectedProject) {
                        Text("Aucun projet").tag(nil as Project?)
                        ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                    }
                    .pickerStyle(.menu)

                    Picker("Assigné à", selection: $selectedCollaborator) {
                        Text("Non assigné").tag(nil as Collaborator?)
                        ForEach(allCollaborators) { c in Text(c.name).tag(c as Collaborator?) }
                    }
                    .pickerStyle(.menu)
                }

                HStack(spacing: 8) {
                    Toggle(isOn: $showNewTaskDueDate) {
                        Label("Échéance", systemImage: "calendar")
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)

                    if showNewTaskDueDate {
                        DatePicker("", selection: Binding(
                            get: { newTaskDueDate ?? Date() },
                            set: { newTaskDueDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                    }

                    Spacer()
                }

                Button(action: addTask) {
                    Label("Ajouter l'action", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var alertsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Alertes")
                    .font(.headline)
                let alertCount = interview.alerts.filter { !$0.isResolved }.count
                if alertCount > 0 {
                    Text("\(alertCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            List {
                ForEach(interview.alerts.filter { !$0.isResolved }) { alert in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(alertSeverityColor(alert.severity))
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                EditableTextField(
                                    placeholder: "Titre de l'alerte",
                                    text: Binding(
                                        get: { alert.title },
                                        set: {
                                            alert.title = $0
                                            saveContext()
                                        }
                                    )
                                )
                                .frame(height: 24)

                                EditableTextField(
                                    placeholder: "Détail",
                                    text: Binding(
                                        get: { alert.detail },
                                        set: {
                                            alert.detail = $0
                                            saveContext()
                                        }
                                    )
                                )
                                .frame(height: 24)

                                HStack {
                                    Picker(
                                        "Projet",
                                        selection: Binding(
                                            get: { alert.project },
                                            set: {
                                                alert.project = $0
                                                saveContext()
                                            }
                                        )
                                    ) {
                                        Text("Aucun projet").tag(nil as Project?)
                                        ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                                    }
                                    .pickerStyle(.menu)

                                    Picker(
                                        "Sévérité",
                                        selection: Binding(
                                            get: { alert.severityRaw },
                                            set: {
                                                alert.severityRaw = $0
                                                saveContext()
                                            }
                                        )
                                    ) {
                                        Text("Faible").tag("Faible")
                                        Text("Modéré").tag("Modéré")
                                        Text("Élevé").tag("Élevé")
                                        Text("Critique").tag("Critique")
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 120)
                                }
                            }

                            Spacer()

                            Button(action: {
                                alert.isResolved = true
                                saveContext()
                            }) {
                                Image(systemName: "checkmark.circle").foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteAlerts)

                let resolved = interview.alerts.filter { $0.isResolved }
                if !resolved.isEmpty {
                    Section("Résolues") {
                        ForEach(resolved) { alert in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(alert.title).strikethrough().foregroundColor(.secondary)
                                Spacer()
                                if let project = alert.project {
                                    Text(project.name).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                EditableTextField(placeholder: "Nouvelle alerte...", text: $newAlertTitle)
                    .frame(height: 24)
                HStack {
                    Picker("Projet", selection: $selectedAlertProject) {
                        Text("Aucun projet").tag(nil as Project?)
                        ForEach(projects) { p in Text(p.name).tag(p as Project?) }
                    }
                    .pickerStyle(.menu)
                    Picker("Sévérité", selection: $newAlertSeverity) {
                        Text("Faible").tag("Faible")
                        Text("Modéré").tag("Modéré")
                        Text("Élevé").tag("Élevé")
                        Text("Critique").tag("Critique")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                Button(action: addAlert) {
                    Label("Ajouter l'alerte", systemImage: "exclamationmark.triangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(newAlertTitle.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - Transcript Import

    private func importTranscript(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isImportingTranscript = true
            reformulationError = nil

            Task {
                do {
                    let service = AIIngestionService()
                    let text = try service.extractTextPublic(from: url)

                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        await MainActor.run {
                            reformulationError = "Le fichier est vide ou illisible."
                            isImportingTranscript = false
                        }
                        return
                    }

                    await MainActor.run {
                        interview.sourceFileName = url.lastPathComponent
                    }

                    // Reformulate via AI if enabled
                    if settings.useAIForReformulation {
                        let reformService = AIReformulationService()
                        let result = try await reformService.reformulate(notes: text, settings: settings)
                        await MainActor.run {
                            interview.notes = result.reformulatedNotes
                            for action in result.extractedActions {
                                let task = ActionTask(title: action)
                                task.interview = interview
                                context.insert(task)
                            }
                            saveContext()
                            isImportingTranscript = false
                        }
                    } else {
                        // Just paste raw text
                        await MainActor.run {
                            interview.notes = text
                            saveContext()
                            isImportingTranscript = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        reformulationError = "Erreur import transcript: \(error.localizedDescription)"
                        isImportingTranscript = false
                    }
                }
            }
        case .failure(let error):
            reformulationError = "Echec import: \(error.localizedDescription)"
        }
    }

    private func pasteTranscriptFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reformulationError = "Le presse-papiers est vide ou ne contient pas de texte."
            return
        }

        isImportingTranscript = true
        reformulationError = nil
        interview.sourceFileName = "Presse-papiers"

        if settings.useAIForReformulation {
            Task {
                do {
                    let service = AIReformulationService()
                    let result = try await service.reformulate(notes: text, settings: settings)
                    await MainActor.run {
                        interview.notes = result.reformulatedNotes
                        for action in result.extractedActions {
                            let task = ActionTask(title: action)
                            task.interview = interview
                            context.insert(task)
                        }
                        saveContext()
                        isImportingTranscript = false
                    }
                } catch {
                    await MainActor.run {
                        reformulationError = "Erreur reformulation: \(error.localizedDescription)"
                        isImportingTranscript = false
                    }
                }
            }
        } else {
            interview.notes = text
            saveContext()
            isImportingTranscript = false
        }
    }

    // MARK: - Reformulation IA

    private func reformulateNotes() {
        guard settings.useAIForReformulation else {
            reformulationError = "La reformulation IA est desactivee dans les parametres."
            return
        }

        if interview.type == .job {
            prefillJobInterview()
            return
        }

        isReformulating = true
        reformulationError = nil

        Task {
            let service = AIReformulationService()
            do {
                let result = try await service.reformulate(notes: interview.notes, settings: settings)
                await MainActor.run {
                    interview.notes = result.reformulatedNotes

                    // Create tasks from extracted actions
                    for action in result.extractedActions {
                        let task = ActionTask(title: action)
                        task.interview = interview
                        context.insert(task)
                    }

                    saveContext()
                    isReformulating = false
                }
            } catch {
                await MainActor.run {
                    reformulationError = error.localizedDescription
                    isReformulating = false
                }
            }
        }
    }

    private func prefillJobInterview() {
        guard let attachment = selectedCVAttachment else { return }

        isPrefillingJobInterview = true
        reformulationError = nil

        Task {
            let service = AIIngestionService()
            do {
                let draft = try await service.analyzeCandidateFile(at: attachment.resolvedURL(), settings: settings)
                await MainActor.run {
                    interview.generalAssessment = draft.summary
                    interview.positivePoints = draft.positivePoints.joined(separator: "\n• ").prependingBulletList
                    interview.negativePoints = draft.negativePoints.joined(separator: "\n• ").prependingBulletList
                    interview.trainingAssessment = draft.trainingAssessment.joined(separator: "\n• ").prependingBulletList
                    interview.cvExperienceNotes = draft.experienceNotes
                    interview.cvSkillsNotes = draft.skillsNotes
                    interview.cvMotivationNotes = draft.motivationNotes
                    interview.candidateLinkedInNotes = draft.linkedinHints
                    saveContext()
                    isPrefillingJobInterview = false
                }
            } catch {
                await MainActor.run {
                    reformulationError = error.localizedDescription
                    isPrefillingJobInterview = false
                }
            }
        }
    }

    // MARK: - Apple Reminders

    private func sendToReminders(task: ActionTask) {
        Task {
            let granted = await remindersService.requestAccess()
            guard granted else {
                await MainActor.run {
                    reformulationError = "Accès aux Rappels refusé. Autorisez dans Préférences Système."
                }
                return
            }

            let title = task.title + (task.project.map { " (\($0.name))" } ?? "")
            if let reminderID = await remindersService.createReminder(title: title, dueDate: task.dueDate) {
                await MainActor.run {
                    task.reminderID = reminderID
                    saveContext()
                }
            }
        }
    }

    private func sendAllToReminders() {
        Task {
            let granted = await remindersService.requestAccess()
            guard granted else {
                await MainActor.run {
                    reformulationError = "Accès aux Rappels refusé."
                }
                return
            }

            for task in interview.tasks where !task.isCompleted && task.reminderID == nil {
                let title = task.title + (task.project.map { " (\($0.name))" } ?? "")
                if let reminderID = await remindersService.createReminder(title: title, dueDate: task.dueDate) {
                    await MainActor.run {
                        task.reminderID = reminderID
                    }
                }
            }
            await MainActor.run { saveContext() }
        }
    }

    // MARK: - CRUD Actions

    private func addTask() {
        let task = ActionTask(title: newTaskTitle, dueDate: showNewTaskDueDate ? (newTaskDueDate ?? Date()) : nil)
        task.interview = interview
        task.project = selectedProject
        task.collaborator = selectedCollaborator ?? interview.collaborator
        context.insert(task)
        newTaskTitle = ""
        newTaskDueDate = nil
        showNewTaskDueDate = false
        saveContext()
    }

    private func deleteTasks(offsets: IndexSet) {
        let tasks = interview.tasks
        for index in offsets {
            context.delete(tasks[index])
        }
        saveContext()
    }

    // MARK: - CRUD Alertes

    private func addAlert() {
        let alert = ProjectAlert(title: newAlertTitle, severity: newAlertSeverity)
        alert.project = selectedAlertProject
        alert.interview = interview
        context.insert(alert)
        newAlertTitle = ""
        saveContext()
    }

    private func deleteAlerts(offsets: IndexSet) {
        let activeAlerts = interview.alerts.filter { !$0.isResolved }
        for index in offsets {
            context.delete(activeAlerts[index])
        }
        saveContext()
    }

    // MARK: - Pièces jointes

    private func importAttachments(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let attachment = InterviewAttachment(url: url)
                attachment.interview = interview
                context.insert(attachment)
            }
            saveContext()
        case .failure(let error):
            reformulationError = "Échec de l'import des pièces jointes: \(error.localizedDescription)"
        }
    }

    private func deleteAttachments(offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedAttachments[index])
        }
        saveContext()
    }

    private func openAttachmentExternally(_ attachment: InterviewAttachment) {
        let url = attachment.resolvedURL()
        let accessed = url.startAccessingSecurityScopedResource()
        NSWorkspace.shared.open(url)
        if accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func attachmentIcon(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "ppt", "pptx", "key":
            return "display"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "drawio":
            return "square.on.square"
        case "txt", "md":
            return "text.alignleft"
        default:
            return "paperclip"
        }
    }

    private func alertSeverityColor(_ severity: String) -> Color {
        switch severity {
        case "Critique": return .red
        case "Élevé": return .orange
        case "Modéré": return .yellow
        default: return .blue
        }
    }

    // MARK: - Save

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("[InterviewView] save FAILED: \(error)")
        }
    }
}
