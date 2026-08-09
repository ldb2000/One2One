import SwiftUI
import SwiftData

/// Liste des actions à traiter, triées par échéance. Offre un filtrage combiné
/// par statut (en cours / terminées / toutes), projet ou entité, collaborateur
/// assigné, échéance, plus une recherche plein-texte sur le titre.
struct ActionsListView: View {
    @Query(sort: \ActionTask.dueDate) private var allTasks: [ActionTask]
    @Query private var projects: [Project]
    @Query private var entities: [Entity]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .pending
    @State private var filterProject: Project?
    @State private var filterEntity: Entity?
    @State private var filterCollaborator: Collaborator?
    @State private var filterDueDate: DueDateFilter = .any
    @State private var viewMode: ActionsViewMode = .liste
    @State private var kanbanGrouping: ActionGrouping = .destinataire

    enum FilterStatus: String, CaseIterable {
        case pending = "En cours"
        case completed = "Terminées"
        case all = "Toutes"
    }

    enum DueDateFilter: String, CaseIterable, Identifiable {
        case any         = "Toutes échéances"
        case withDate    = "Avec échéance"
        case withoutDate = "Sans échéance"
        case overdue     = "En retard"
        var id: String { rawValue }
    }

    /// Applique successivement les filtres actifs à `allTasks` pour un statut
    /// donné (statut, puis projet/entité, collaborateur, échéance, recherche).
    /// `statut` est paramétrable indépendamment de `filterStatus` pour que
    /// `nombreDActions(pour:)` puisse simuler chaque statut sans dupliquer la
    /// chaîne de filtres — `filteredTasks` et le compteur des pilules
    /// partagent ainsi la même logique et ne peuvent plus diverger. L'ordre de
    /// tri par échéance vient de la `@Query` ; le filtrage ne le modifie pas.
    private func actionsFiltrees(statut: FilterStatus) -> [ActionTask] {
        var tasks = allTasks

        switch statut {
        case .pending:
            tasks = tasks.filter { !$0.isCompleted }
        case .completed:
            tasks = tasks.filter { $0.isCompleted }
        case .all:
            break
        }

        if let project = filterProject {
            tasks = tasks.filter { $0.project?.persistentModelID == project.persistentModelID }
        } else if let entity = filterEntity {
            tasks = tasks.filter { $0.project?.entity?.persistentModelID == entity.persistentModelID }
        }

        if let collaborator = filterCollaborator {
            tasks = tasks.filter { $0.collaborator?.persistentModelID == collaborator.persistentModelID }
        }

        switch filterDueDate {
        case .any:
            break
        case .withDate:
            tasks = tasks.filter { $0.dueDate != nil }
        case .withoutDate:
            tasks = tasks.filter { $0.dueDate == nil }
        case .overdue:
            let startOfToday = Calendar.current.startOfDay(for: Date())
            tasks = tasks.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
        }

        if !searchText.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        return tasks
    }

    /// Liste réellement affichée : la chaîne de filtres actifs appliquée au
    /// statut actuellement sélectionné.
    private var filteredTasks: [ActionTask] {
        actionsFiltrees(statut: filterStatus)
    }

    /// Nombre d'actions que donnerait un statut, **les autres filtres restant
    /// appliqués** : le compteur doit refléter ce qu'on obtiendra en cliquant,
    /// pas un total abstrait. Réutilise `actionsFiltrees(statut:)` — jamais de
    /// second endroit qui recalcule la même chaîne de filtres.
    private func nombreDActions(pour statut: FilterStatus) -> Int {
        actionsFiltrees(statut: statut).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters bar
            HStack(spacing: 12) {
                SegmentedFilter(options: FilterStatus.allCases,
                                selection: $filterStatus,
                                libelle: { $0.rawValue },
                                compteur: { nombreDActions(pour: $0) })

                projectFilterMenu

                Picker("Assigné à", selection: $filterCollaborator) {
                    Text("Tous").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Picker("Échéance", selection: $filterDueDate) {
                    ForEach(DueDateFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 170)

                Spacer()

                if viewMode == .kanban || viewMode == .sticky {
                    Picker("", selection: $kanbanGrouping) {
                        ForEach(ActionGrouping.allCases, id: \.self) { g in Text(g.label).tag(g) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .help("Regrouper par…")
                }

                Picker("", selection: $viewMode) {
                    ForEach(ActionsViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Changer de vue")

                Button(action: addAction) {
                    Label("Nouvelle action", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Task list
            if filteredTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune action trouvée")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == .eisenhower {
                EisenhowerBoard(tasks: filteredTasks, onToggle: { task in
                    task.isCompleted.toggle()
                    task.completedAt = task.isCompleted ? Date() : nil
                    saveContext()
                }, fillsAvailableSpace: true)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == .kanban {
                KanbanBoard(
                    columns: KanbanBoard.columns(for: kanbanGrouping, tasks: filteredTasks),
                    tasks: filteredTasks,
                    onToggle: { task in
                        task.isCompleted.toggle()
                        task.completedAt = task.isCompleted ? Date() : nil
                        saveContext()
                    },
                    onChanged: saveContext,
                    fillsAvailableSpace: true
                )
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == .calendar {
                ScrollView {
                    CalendarBoard(tasks: filteredTasks, onToggle: { task in
                        task.isCompleted.toggle()
                        task.completedAt = task.isCompleted ? Date() : nil
                        saveContext()
                    }, fillsAvailableSpace: true)
                    .padding()
                }
            } else if viewMode == .sticky {
                ScrollView {
                    StickyBoard(
                        tasks: filteredTasks,
                        columns: KanbanBoard.columns(for: kanbanGrouping, tasks: filteredTasks),
                        allCollaborators: collaborators,
                        onToggle: { task in
                            task.isCompleted.toggle()
                            task.completedAt = task.isCompleted ? Date() : nil
                            saveContext()
                        },
                        onChanged: saveContext,
                        onDelete: { task in context.delete(task); saveContext() },
                        fillsAvailableSpace: true
                    )
                    .padding()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredTasks.enumerated()), id: \.element.persistentModelID) { index, task in
                            ActionTaskRow(
                                task: task,
                                estPaire: index.isMultiple(of: 2),
                                projects: projects,
                                collaborators: collaborators,
                                onSave: saveContext,
                                onDelete: { context.delete(task); saveContext() }
                            )
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher une action...")
        .navigationTitle("Actions")
    }

    private func saveContext() {
        do { try context.save() } catch { print("Save error: \(error)") }
    }

    /// Hierarchical project filter: Entities at the top level, each opens
    /// a submenu of its projects. "Sans entité" groups orphan projects.
    private var projectFilterMenu: some View {
        Menu {
            Button("Tous les projets") {
                filterProject = nil
                filterEntity = nil
            }
            Divider()
            let sortedEntities = entities.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ForEach(sortedEntities) { entity in
                let entityProjects = projects
                    .filter { $0.entity?.persistentModelID == entity.persistentModelID && !$0.isArchived }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !entityProjects.isEmpty {
                    Menu(entity.name) {
                        Button("Tous les projets de \(entity.name)") {
                            filterEntity = entity
                            filterProject = nil
                        }
                        Divider()
                        ForEach(entityProjects) { p in
                            Button(p.name) {
                                filterProject = p
                                filterEntity = nil
                            }
                        }
                    }
                }
            }
            let orphans = projects
                .filter { $0.entity == nil && !$0.isArchived }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if !orphans.isEmpty {
                Divider()
                Menu("Sans entité") {
                    ForEach(orphans) { p in
                        Button(p.name) {
                            filterProject = p
                            filterEntity = nil
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(currentProjectFilterLabel).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var currentProjectFilterLabel: String {
        if let p = filterProject { return p.name }
        if let e = filterEntity { return "📂 \(e.name)" }
        return "Tous les projets"
    }

    private func addAction() {
        let task = ActionTask(title: "Nouvelle action")
        task.project = filterProject
        task.collaborator = filterCollaborator
        context.insert(task)
        saveContext()
    }
}

/// Renders Collaborator picker options groupés selon le filtre de la sidebar
/// (clé `@AppStorage("sidebar.collabsFilter")`, valeurs `"pinned"` / `"favourites"`
/// / `"both"`, défaut `"both"`) :
/// - `pinned`     → épinglés au top, divider, le reste A–Z
/// - `favourites` → favoris au top, divider, le reste A–Z
/// - `both`       → épinglés ET favoris au top (alpha mixé), divider, le reste A–Z
/// Inclut tous les collaborateurs non-archivés pour ne pas masquer un favori.
struct CollaboratorPickerOptions: View {
    let collaborators: [Collaborator]
    @AppStorage("sidebar.collabsFilter") private var collabsFilter: String = "both"

    var body: some View {
        let groups = partitioned()
        Group {
            ForEach(groups.top) { c in
                Label(c.name, systemImage: pillIcon(for: c)).tag(c as Collaborator?)
            }
            if !groups.top.isEmpty && !groups.rest.isEmpty {
                Divider()
            }
            ForEach(groups.rest) { c in
                Text(c.name).tag(c as Collaborator?)
            }
        }
    }

    private func partitioned() -> (top: [Collaborator], rest: [Collaborator]) {
        let active = collaborators
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch collabsFilter {
        case "pinned":
            return (active.filter { $0.pinLevel == 2 },
                    active.filter { $0.pinLevel != 2 })
        case "favourites":
            return (active.filter { $0.pinLevel == 1 },
                    active.filter { $0.pinLevel != 1 })
        default:  // both
            return (active.filter { $0.pinLevel >= 1 },
                    active.filter { $0.pinLevel == 0 })
        }
    }

    private func pillIcon(for c: Collaborator) -> String {
        switch c.pinLevel {
        case 2:  return "pin.fill"
        case 1:  return "star.fill"
        default: return "person"
        }
    }
}

/// Ligne d'action façon liste GitHub.
/// - Ouverte : case à cocher (la *forme* de l'icône vient de `taskStatus` — en
///   retard / aujourd'hui / sous 48 h / à venir / sans date ; sa *couleur* vient
///   de la règle d'urgence partagée `Urgence.pour` / `AppTheme.couleur`, seuil de
///   7 jours, la même que celle de l'échéance affichée à droite) + titre éditable
///   en double-clic + sous-titre (date de création) + métadonnées alignées à
///   droite (code projet, avatar du porteur, échéance colorée par l'urgence) +
///   compteur de commentaires + chevron de dépliage + suppression.
/// - Terminée : rendue en bloc façon note (porteur, dates, commentaires, projet).
/// - Le dépliage (chevron ou tap sur la ligne) affiche le fil de commentaires,
///   le champ d'ajout, et les sélecteurs projet / assigné / échéance modifiables
///   en place.
struct ActionTaskRow: View {
    @Bindable var task: ActionTask
    /// Parité de la ligne dans la liste affichée, pour la teinte alternée.
    let estPaire: Bool
    let projects: [Project]
    let collaborators: [Collaborator]
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var expanded: Bool = false
    @State private var newCommentText: String = ""

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        Group {
            if task.isCompleted {
                completedNoteView
            } else {
                openTaskView
            }
        }
        .background(rowBackground)
        .overlay(
            Rectangle().frame(height: 1)
                .foregroundColor(AppTheme.separateur),
            alignment: .bottom
        )
    }

    // MARK: - Open (GitHub-style)

    private var openTaskView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: toggleCompleted) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(statusHelp)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isEditingTitle {
                            TextField("Action…", text: $task.title, onCommit: {
                                isEditingTitle = false
                                onSave()
                            })
                            .textFieldStyle(.plain)
                            .font(AppTheme.titreLigne)
                        } else {
                            Text(task.title.isEmpty ? "Sans titre" : task.title)
                                .font(AppTheme.titreLigne)
                                .foregroundColor(task.title.isEmpty ? .secondary : .primary)
                                .onTapGesture(count: 2) { isEditingTitle = true }
                        }

                        if task.fromManager {
                            Label("manager", systemImage: "person.crop.square.filled.and.at.rectangle")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    sousTitre
                }

                Spacer(minLength: 8)

                metadonneesADroite

                if !task.comments.isEmpty {
                    Label("\(task.comments.count)", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditingTitle { expanded.toggle() }
            }

            if expanded {
                Divider()
                expandedDetails
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
    }

    @State private var isEditingTitle: Bool = false
    @State private var isHovering: Bool = false

    /// Le fond de base (teinte alternée) reste toujours posé ; le survol
    /// superpose un voile par-dessus au lieu de le remplacer, pour assombrir
    /// la ligne dans les deux parités au lieu d'inverser le sens visuel sur
    /// les lignes impaires.
    private var rowBackground: some View {
        ZStack {
            estPaire ? AppTheme.fondContenu : AppTheme.ligneAlternee
            if isHovering {
                AppTheme.separateur.opacity(0.35)
            }
        }
        .onHover { isHovering = $0 }
    }

    /// Sous-titre gris sous le titre : seule métadonnée qui reste alignée à
    /// gauche après le déplacement du reste vers `metadonneesADroite`.
    private var sousTitre: some View {
        Group {
            if let createdAt = task.createdAt {
                Text("ouverte le \(Self.dateFmt.string(from: createdAt))")
            } else {
                Text("")
            }
        }
        .font(AppTheme.sousTitre)
        .foregroundStyle(AppTheme.texteSecondaire)
    }

    /// Métadonnées alignées à droite, dans l'ordre de la capture 3 :
    /// code projet, avatar du porteur, échéance colorée par l'urgence.
    private var metadonneesADroite: some View {
        HStack(spacing: 12) {
            Text(task.project?.code ?? "—")
                .font(AppTheme.chasseFixe)
                .foregroundStyle(AppTheme.texteSecondaire)
                .frame(minWidth: 64, alignment: .trailing)

            if let collab = task.collaborator {
                Avatar(nom: collab.name)
            } else {
                Color.clear.frame(width: 22, height: 22)
            }

            MetaValue(texte: libelleEcheance, urgence: urgence)
                .help(task.dueDate.map { Self.dateFmt.string(from: $0) } ?? "Sans échéance")
        }
    }

    private var urgence: Urgence {
        Urgence.pour(task.dueDate, maintenant: Date())
    }

    /// Format court de la capture : « 27/07 ». Un tiret cadratin si aucune
    /// échéance — jamais une case vide.
    private var libelleEcheance: String {
        guard let due = task.dueDate else { return "—" }
        return Self.echeanceFmt.string(from: due)
    }

    private static let echeanceFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM"
        return f
    }()

    // MARK: - Status visuals

    private enum TaskStatus {
        case overdue, dueToday, dueSoon, upcoming, undated
    }

    private var taskStatus: TaskStatus {
        guard let due = task.dueDate else { return .undated }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let in48h = cal.date(byAdding: .day, value: 2, to: today) ?? today
        if due < today { return .overdue }
        if due < tomorrow { return .dueToday }
        if due < in48h { return .dueSoon }
        return .upcoming
    }

    private var statusIcon: String {
        switch taskStatus {
        case .overdue:  return "exclamationmark.circle.fill"
        case .dueToday: return "circle.fill"
        case .dueSoon:  return "circle.fill"
        case .upcoming: return "circle"
        case .undated:  return "circle.dashed"
        }
    }

    /// Dérive **toujours** de la règle d'urgence partagée (`Urgence.pour`, seuil
    /// 7 jours), la même que celle qui colore la date via `MetaValue` — jamais
    /// des seuils de `taskStatus` (aujourd'hui / demain / 48 h), pour que la
    /// puce et la date ne puissent plus se contredire sur une même ligne.
    private var statusColor: Color {
        AppTheme.couleur(urgence)
    }

    private var statusHelp: String {
        switch taskStatus {
        case .overdue:  return "En retard — cliquer pour marquer comme terminée"
        case .dueToday: return "À échéance aujourd'hui"
        case .dueSoon:  return "Échéance dans les 48h"
        case .upcoming: return "À venir"
        case .undated:  return "Sans date"
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { task.project },
                    set: { task.project = $0; onSave() }
                )) {
                    Text("Aucun projet").tag(nil as Project?)
                    ForEach(projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { p in Text(p.name).tag(p as Project?) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .font(.caption)

                Picker("", selection: Binding(
                    get: { task.collaborator },
                    set: { task.collaborator = $0; onSave() }
                )) {
                    Text("Non assigné").tag(nil as Collaborator?)
                    CollaboratorPickerOptions(collaborators: collaborators)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .font(.caption)

                DatePicker("", selection: Binding(
                    get: { task.dueDate ?? Date() },
                    set: { task.dueDate = $0; onSave() }
                ), displayedComponents: .date)
                .labelsHidden()
                .font(.caption)
                .opacity(task.dueDate == nil ? 0.6 : 1.0)

                if task.dueDate != nil {
                    Button(action: { task.dueDate = nil; onSave() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // Comments thread
            if !task.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Commentaires").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(task.comments.sorted { $0.date < $1.date }) { c in
                        HStack(alignment: .top, spacing: 6) {
                            Text(Self.dateFmt.string(from: c.date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 84, alignment: .leading)
                            Text(c.text).font(.caption)
                            Spacer()
                            Button {
                                if let comment = task.comments.first(where: { $0.persistentModelID == c.persistentModelID }) {
                                    context.delete(comment)
                                    onSave()
                                }
                            } label: {
                                Image(systemName: "xmark.circle").font(.caption2).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add comment
            HStack {
                TextField("Ajouter un commentaire…", text: $newCommentText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Ajouter") { addComment() }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .controlSize(.small)
            }
        }
        .padding(.leading, 34)
    }

    // MARK: - Completed (note-style)

    private var completedNoteView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleCompleted) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                Text(task.title)
                    .font(.body.bold())
                    .strikethrough()
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let collab = task.collaborator {
                    Text("Owner: \(collab.name)").font(.caption)
                }
                Text("Du \(formattedOrUnknown(task.createdAt)) au \(formattedOrUnknown(task.completedAt))")
                    .font(.caption)
                ForEach(task.comments.sorted { $0.date < $1.date }) { c in
                    Text("\(Self.dateFmt.string(from: c.date)) — \(c.text)")
                        .font(.caption)
                }
                if let project = task.project {
                    Text("Projet: \(project.name)").font(.caption.italic())
                }
            }
            .foregroundColor(.secondary)
            .padding(.leading, 34)
        }
        .padding(.vertical, 6)
    }

    private func formattedOrUnknown(_ date: Date?) -> String {
        guard let date else { return "?" }
        return Self.dateFmt.string(from: date)
    }

    // MARK: - Mutations

    private func toggleCompleted() {
        task.isCompleted.toggle()
        if task.isCompleted {
            task.completedAt = Date()
        } else {
            task.completedAt = nil
        }
        onSave()
    }

    private func addComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let c = ActionComment(text: trimmed)
        context.insert(c)
        c.task = task
        newCommentText = ""
        onSave()
    }
}
