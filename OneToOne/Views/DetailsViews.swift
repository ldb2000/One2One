import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// La fiche projet complète — le formulaire à plat historique.
///
/// Depuis le lot 4 de la refonte des projets, ce n'est plus l'écran par
/// défaut d'un projet mais son **onglet « Fiche complète »**
/// (`ProjectScreen`, capture `1d-ecran-projet-pilotage.png`). Deux choses en
/// sont sorties, et rien n'y est entré :
///
/// - la **heatmap de 52 semaines** (`MeetingHeatmapView`), remplacée par la
///   tuile « RYTHME » de l'onglet Pilotage — huit barres sur douze semaines.
///   La vue n'est pas supprimée : le tableau de bord l'emploie encore ;
/// - la **barre d'outils**. « Archiver » et « Supprimer » sont passés dans le
///   menu `···` de l'en-tête de l'écran projet, avec confirmation pour la
///   seconde ; « Enregistrer » reste, mais dans le corps de la fiche — une
///   barre d'outils de fenêtre, sous un écran à six onglets, n'appartenait
///   plus à ce qu'elle surmontait.
struct ProjectDetailView: View {
    @Bindable var project: Project
    @Query private var entities: [Entity]
    @Query private var collaborators: [Collaborator]
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @State private var showingProjectAttachmentImporter = false
    @State private var newProjectAttachmentCategory = "Document"

    /// Le libellé du bouton d'enregistrement, descendu de la barre d'outils
    /// dans le corps de la fiche (lot 4).
    static let enregistrer = "Enregistrer"

    private let riskLevels = ["", "Faible", "Modéré", "Élevé", "Critique"]
    private let phases = ["Cadrage", "Design", "Build", "Run"]
    private let statuses = ["Unknown", "Green", "Yellow", "Red"]
    private let projectTypes = ["Métier", "Transverse", "Technique"]
    private let projectAttachmentCategories = ["DAT", "DIT", "Document"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Button(Self.enregistrer) { saveContext() }
                        .buttonStyle(.bordered)
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
