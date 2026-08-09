import SwiftUI
import SwiftData

/// Liste des actions à traiter, triées par échéance. Offre un filtrage combiné
/// par portée d'échéance (en retard / cette semaine / toutes — le filtre
/// principal de la capture 3), statut (en cours / terminées / toutes), projet
/// ou entité, collaborateur assigné, échéance, plus une recherche plein-texte
/// sur le titre.
struct ActionsListView: View {
    @Query(sort: \ActionTask.dueDate) private var allTasks: [ActionTask]
    @Query private var projects: [Project]
    @Query private var entities: [Entity]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .pending
    /// Filtre principal de la capture 3 : trois pilules (en retard / cette
    /// semaine / toutes). Distinct du filtre de statut, qui reste disponible
    /// — déplacé par la tâche 2 dans le menu « Filtres » de la barre d'outils
    /// — voir `Portee` pour la règle de date, à ne pas confondre avec
    /// `Urgence` (règle de couleur).
    @State private var portee: Portee = .enRetard
    @State private var filterProject: Project?
    @State private var filterEntity: Entity?
    @State private var filterCollaborator: Collaborator?
    @State private var filterDueDate: DueDateFilter = .any
    @State private var viewMode: ActionsViewMode = .liste
    /// Défaut `.echeance` (maquette de référence) : en liste comme en kanban,
    /// c'est le premier regroupement qu'on voit à l'ouverture de l'écran.
    @State private var kanbanGrouping: ActionGrouping = .echeance
    /// Même clé, même réglage que `CollaboratorPickerOptions` : lu ici pour
    /// que le sous-menu « Assigné à » de `filtresMenu` applique la même
    /// partition (pastilles en tête) que les `Picker` ailleurs dans
    /// l'application, via `CollaboratorPreference.partition`.
    @AppStorage(CollaboratorPreference.appStorageKey) private var collabsFilter: String = "both"

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
    /// et une portée donnés (statut, puis portée d'échéance, puis
    /// projet/entité, collaborateur, échéance, recherche). `statut` et
    /// `portee` sont paramétrables indépendamment de `filterStatus` et de
    /// `portee` (l'état) pour que `nombreDActions(pour:)` puisse simuler
    /// chaque valeur sans dupliquer la chaîne de filtres — `filteredTasks`
    /// et les compteurs des deux jeux de pilules partagent ainsi la même
    /// logique et ne peuvent plus diverger. L'ordre de tri par échéance vient
    /// de la `@Query` ; le filtrage ne le modifie pas.
    ///
    /// **La portée ne s'applique jamais aux actions terminées.** Les trois
    /// pilules filtrent par conception « parmi les actions non terminées »
    /// (voir le commentaire de `portee`) ; l'accès aux terminées passe par le
    /// filtre de statut. Sans cette exception, une terminée sans échéance ou
    /// à échéance future devenait invisible dès que la portée par défaut
    /// (`.enRetard`) était active — et le compteur « Terminées » du sous-menu
    /// Statut affirmait alors qu'il n'y en avait aucune.
    ///
    /// Cas `statut == .all` (ambigu, choix assumé ici) : il mélange
    /// terminées et non-terminées. On applique la portée seulement au
    /// sous-ensemble non terminé et on laisse passer toutes les terminées
    /// sans condition — chaque sous-ensemble garde exactement la règle qu'il
    /// aurait s'il était seul sélectionné (`.pending` filtré par portée,
    /// `.completed` jamais filtré). L'alternative — appliquer la portée à
    /// l'ensemble mélangé — reproduirait le bug corrigé ci-dessus pour
    /// « Toutes », juste caché derrière un statut différent.
    private func actionsFiltrees(statut: FilterStatus, portee: Portee) -> [ActionTask] {
        var tasks = allTasks

        switch statut {
        case .pending:
            tasks = tasks.filter { !$0.isCompleted }
        case .completed:
            tasks = tasks.filter { $0.isCompleted }
        case .all:
            break
        }

        // Un seul instant pour toute la fonction : consommé ici et par le
        // cas `filterDueDate == .overdue` plus bas, pour ne jamais raisonner
        // sur deux « maintenant » légèrement différents au sein d'un même
        // calcul.
        let maintenant = Date()

        if statut != .completed {
            tasks = tasks.filter { $0.isCompleted || Portee.contient($0.dueDate, portee: portee, maintenant: maintenant) }
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
            let startOfToday = Calendar.current.startOfDay(for: maintenant)
            tasks = tasks.filter { ($0.dueDate ?? .distantFuture) < startOfToday }
        }

        if !searchText.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        return tasks
    }

    /// Liste réellement affichée : la chaîne de filtres actifs appliquée au
    /// statut et à la portée actuellement sélectionnés.
    private var filteredTasks: [ActionTask] {
        actionsFiltrees(statut: filterStatus, portee: portee)
    }

    /// Nombre d'actions que donnerait un statut — pour le sous-menu
    /// « Statut ». Compte volontairement avec la portée `.toutes`, **jamais**
    /// avec la portée actuellement sélectionnée : sinon ce compteur mentirait
    /// exactement comme avant ce correctif (« Terminées (0) » alors que la
    /// portée par défaut est `.enRetard`), puisque la portée ne filtre plus
    /// les terminées mais continuerait de faire varier le total affiché ici
    /// selon la pilule du moment. Réutilise `actionsFiltrees(statut:portee:)`
    /// — jamais de second endroit qui recalcule la même chaîne de filtres.
    private func nombreDActions(pour statut: FilterStatus) -> Int {
        actionsFiltrees(statut: statut, portee: .toutes).count
    }

    /// Nombre d'actions que donnerait une portée, **les autres filtres
    /// (statut compris) restant appliqués** — même contrat que la surcharge
    /// ci-dessus pour `FilterStatus`, pour le même motif : c'est ce qu'on
    /// obtient en cliquant une pilule de portée, jamais un total abstrait.
    /// Réutilise la même chaîne unique `actionsFiltrees(statut:portee:)`.
    private func nombreDActions(pour portee: Portee) -> Int {
        actionsFiltrees(statut: filterStatus, portee: portee).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters bar
            HStack(spacing: 12) {
                // Filtre principal de la capture 3 : trois pilules de portée
                // d'échéance (En retard / Cette semaine / Toutes).
                SegmentedFilter(options: Portee.allCases,
                                selection: $portee,
                                libelle: { $0.libelle },
                                compteur: { nombreDActions(pour: $0) })

                Spacer()

                // « Grouper par : <valeur> », comme la capture 3 le montre,
                // toujours visible en barre principale (pas seulement en
                // kanban/sticky comme avant). En vue liste, ce réglage
                // détermine désormais les sections affichées — même
                // `KanbanBoard.columns(for:tasks:)` que le kanban et le
                // mode sticky, voir la vue liste plus bas.
                //
                // Tâche 2 : le sélecteur de statut, le filtre projet/entité,
                // le filtre collaborateur, le filtre échéance, le sélecteur
                // de vue et « Nouvelle action » ont quitté cette barre —
                // ils sont désormais dans la barre d'outils de la fenêtre
                // (voir `.toolbar` plus bas). La barre principale ne garde
                // que la capture : les trois pilules de portée et ce menu.
                grouperParMenu
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
                // Mêmes colonnes que le kanban et le mode sticky — une seule
                // règle de groupement (`KanbanBoard.columns(for:tasks:)`),
                // rendue ici en sections plutôt qu'en colonnes. Les colonnes
                // vides ne produisent pas de section (une colonne kanban vide
                // est légitime — on y dépose — une section de liste vide
                // serait du bruit).
                let colonnes = KanbanBoard.columns(for: kanbanGrouping, tasks: filteredTasks)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(colonnes) { colonne in
                            let items = filteredTasks.filter(colonne.contains)
                            if !items.isEmpty {
                                sectionHeader(colonne, count: items.count)
                                ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, task in
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
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher une action...")
        .navigationTitle("Actions")
        // Tâche 2 : les cinq contrôles chassés de la barre principale par la
        // maquette (capture 3) atterrissent ici, dans la barre d'outils de
        // la fenêtre. Le sélecteur de vue et « Nouvelle action » restent des
        // éléments de premier niveau ; les trois filtres secondaires
        // (statut, projet/entité, collaborateur) — plus le filtre échéance,
        // qui n'est pas l'un des cinq contrôles mais devait tout de même
        // quitter la barre principale — sont regroupés sous un seul menu
        // « Filtres » pour ne pas la saturer.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filtresMenu

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
            }
        }
    }

    private func saveContext() {
        do { try context.save() } catch { print("Save error: \(error)") }
    }

    /// En-tête d'une section de liste groupée : titre de la colonne (langage
    /// visuel des intitulés de section — petites capitales grises) et, en
    /// discret, le nombre d'actions du groupe.
    private func sectionHeader(_ colonne: KanbanColumn, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(colonne.title)
                .font(AppTheme.intituleSection)
                .foregroundStyle(AppTheme.texteSecondaire)
            Text("\(count)")
                .font(AppTheme.intituleSection)
                .foregroundStyle(AppTheme.texteSecondaire.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Grouper par : <valeur> » — expose `kanbanGrouping` (`ActionGrouping`,
    /// existant, utilisé par le kanban) en barre principale, comme la
    /// capture 3 le montre. Remplace l'ancien picker qui n'apparaissait qu'en
    /// vue kanban/sticky : même état lié (`kanbanGrouping`), donc aucun
    /// comportement de regroupement du kanban n'est perdu, et le réglage est
    /// désormais visible dans tous les modes de vue, comme sur la capture.
    /// Consommé aussi par la vue liste (voir plus bas), avec exactement la
    /// même fonction `KanbanBoard.columns(for:tasks:)` — une seule règle de
    /// groupement, deux rendus.
    private var grouperParMenu: some View {
        Menu("Grouper par : \(kanbanGrouping.label)") {
            ForEach(ActionGrouping.allCases, id: \.self) { g in
                Button(g.label) { kanbanGrouping = g }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        // Tooltip porté par l'ancien sélecteur de regroupement ; à conserver
        // (règle du chantier : rien n'est supprimé) même si ce menu l'a remplacé.
        .help("Regrouper par…")
    }

    /// Menu « Filtres » de la barre d'outils (tâche 2) : regroupe les trois
    /// filtres secondaires chassés de la barre principale — statut, projet/
    /// entité, collaborateur — plus le filtre échéance (pas un des cinq
    /// contrôles du brief, mais qui devait tout de même déménager). Chaque
    /// sous-menu affiche la sélection courante dans son titre et coche
    /// l'option active.
    ///
    /// Écart documenté : à l'intérieur d'un `Menu`, un `Picker` imbriqué est
    /// connu pour se comporter de façon peu fiable sous AppKit (le sous-menu
    /// ne s'ouvre pas toujours, ou la sélection ne se répercute pas). Comme
    /// on ne peut pas vérifier à l'écran ici, ces trois filtres (statut,
    /// collaborateur, échéance) sont exposés en `Button` + coche plutôt qu'en
    /// `Picker`, conformément à la consigne de repli. Seul `projectFilterMenu`
    /// reste un `Menu` imbriqué (il l'était déjà nativement, sans `Picker`).
    private var filtresMenu: some View {
        Menu {
            Menu("Statut : \(filterStatus.rawValue)") {
                ForEach(FilterStatus.allCases, id: \.self) { statut in
                    Button {
                        filterStatus = statut
                    } label: {
                        let libelle = "\(statut.rawValue) (\(nombreDActions(pour: statut)))"
                        if filterStatus == statut {
                            Label(libelle, systemImage: "checkmark")
                        } else {
                            Text(libelle)
                        }
                    }
                }
            }

            projectFilterMenu

            // Même partition que le Picker « Assigné à » ailleurs dans
            // l'application (ActionTaskRow, QuickActionPopover) : pastilles
            // épinglées/favorites en tête, puis le reste — pas un simple
            // tri A→Z. Règle unique : `CollaboratorPreference.partition`.
            Menu("Assigné à : \(filterCollaborator?.name ?? "Tous")") {
                Button {
                    filterCollaborator = nil
                } label: {
                    if filterCollaborator == nil {
                        Label("Tous", systemImage: "checkmark")
                    } else {
                        Text("Tous")
                    }
                }
                Divider()
                let groupes = CollaboratorPreference.partition(collaborators, preference: collabsFilter)
                ForEach(groupes.top) { c in
                    collaborateurMenuButton(c, pastille: true)
                }
                if !groupes.top.isEmpty && !groupes.rest.isEmpty {
                    Divider()
                }
                ForEach(groupes.rest) { c in
                    collaborateurMenuButton(c, pastille: false)
                }
            }

            Menu("Échéance : \(filterDueDate.rawValue)") {
                ForEach(DueDateFilter.allCases) { f in
                    Button {
                        filterDueDate = f
                    } label: {
                        if filterDueDate == f {
                            Label(f.rawValue, systemImage: "checkmark")
                        } else {
                            Text(f.rawValue)
                        }
                    }
                }
            }
        } label: {
            Label("Filtres", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    /// Un `Button` du sous-menu « Assigné à » : coche si c'est la sélection
    /// courante, sinon pastille (pin/étoile/silhouette via
    /// `CollaboratorPreference.pillIcon`) pour le groupe en tête, texte nu
    /// pour le reste — même signal visuel que `CollaboratorPickerOptions`,
    /// juste porté en `Button` puisqu'on est dans un `Menu`, pas un `Picker`.
    @ViewBuilder
    private func collaborateurMenuButton(_ c: Collaborator, pastille: Bool) -> some View {
        Button {
            filterCollaborator = c
        } label: {
            if filterCollaborator?.persistentModelID == c.persistentModelID {
                Label(c.name, systemImage: "checkmark")
            } else if pastille {
                Label(c.name, systemImage: CollaboratorPreference.pillIcon(for: c))
            } else {
                Text(c.name)
            }
        }
    }

    /// Hierarchical project filter: Entities at the top level, each opens
    /// a submenu of its projects. "Sans entité" groups orphan projects.
    /// Vit désormais comme sous-menu imbriqué dans `filtresMenu` (tâche 2) —
    /// le libellé est un simple `String` (plus l'icône/chevron/fond du pilule
    /// autonome d'avant) pour un rendu fiable en sous-menu AppKit.
    private var projectFilterMenu: some View {
        Menu(currentProjectFilterLabel) {
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
        }
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

/// Renders Collaborator picker options groupés selon `CollaboratorPreference`.
/// Rendu inchangé depuis avant l'extraction (même `Label`/`Text`/`tag`/
/// `Divider`) — seul le calcul de la partition a été délégué. Utilisé dans
/// des `Picker` ailleurs dans l'application (`ActionTaskRow.expandedDetails`,
/// `QuickActionPopover`) : ne pas modifier son rendu.
struct CollaboratorPickerOptions: View {
    let collaborators: [Collaborator]
    @AppStorage(CollaboratorPreference.appStorageKey) private var collabsFilter: String = "both"

    var body: some View {
        let groups = CollaboratorPreference.partition(collaborators, preference: collabsFilter)
        Group {
            ForEach(groups.top) { c in
                Label(c.name, systemImage: CollaboratorPreference.pillIcon(for: c)).tag(c as Collaborator?)
            }
            if !groups.top.isEmpty && !groups.rest.isEmpty {
                Divider()
            }
            ForEach(groups.rest) { c in
                Text(c.name).tag(c as Collaborator?)
            }
        }
    }
}

/// Ligne d'action façon liste GitHub.
/// - Ouverte : case à cocher (la *forme* de l'icône vient de `taskStatus` — en
///   retard / aujourd'hui / sous 48 h / à venir / sans date ; sa *couleur* vient
///   de la règle d'urgence partagée `Urgence.pour` / `AppTheme.couleur`, seuil de
///   7 jours, la même que celle de l'échéance affichée à droite) + titre éditable
///   en double-clic + métadonnées alignées à droite (code projet, avatar du
///   porteur, échéance colorée par l'urgence) + menu `⋮` (visible au survol,
///   voir `ligneMenu`) donnant accès à Modifier / Commentaires / Supprimer.
///   Le sous-titre (date de création) et les contrôles permanents de
///   dépliage/suppression de la maquette d'origine ont quitté la ligne au
///   repos (voir `ligneMenu` pour où leurs actions vivent désormais).
/// - Terminée : rendue en bloc façon note (porteur, dates, commentaires, projet).
/// - Le dépliage (tap sur la ligne, ou « Commentaires » depuis le menu `⋮`)
///   affiche le fil de commentaires, le champ d'ajout, et les sélecteurs
///   projet / assigné / échéance modifiables en place.
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
                }

                Spacer(minLength: 8)

                metadonneesADroite

                ligneMenu
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

    /// Métadonnées alignées à droite, dans l'ordre de la capture 3 :
    /// code projet, avatar du porteur, échéance colorée par l'urgence.
    private var metadonneesADroite: some View {
        HStack(spacing: 12) {
            Text(libelleCodeProjet)
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

    /// Code projet affiché dans la colonne : couvre le projet absent **et**
    /// le projet présent avec un code vide — un tiret cadratin dans les deux
    /// cas, jamais une case vide.
    private var libelleCodeProjet: String {
        guard let code = task.project?.code, !code.isEmpty else { return "—" }
        return code
    }

    /// Menu `⋮` de fin de ligne — regroupe les trois gestes retirés de la
    /// ligne au repos (Modifier, Commentaires, Supprimer). Visible
    /// uniquement au survol (`isHovering`, déjà porté par `rowBackground`),
    /// mais toujours monté : seule son opacité (et son interactivité) varie,
    /// pour que sa largeur reste réservée en permanence et que les colonnes
    /// de `metadonneesADroite` ne sautent pas quand la souris entre/sort.
    ///
    /// `.onTapGesture {}` (no-op) est posé sur le menu lui-même : sans lui,
    /// le clic qui ouvre le `Menu` remonte aussi au `.onTapGesture` du
    /// `HStack` parent (celui qui déplie/replie la ligne) et déclenche les
    /// deux à la fois — un `Button` ne fuit pas comme ça, un `Menu` si.
    ///
    /// L'ordre des modificateurs compte : posé *avant* `.opacity`/
    /// `.allowsHitTesting`, le no-op fait partie de la sous-vue dont
    /// `.allowsHitTesting(isHovering)` désactive le hit-testing — il devient
    /// donc inerte exactement quand le menu l'est (souris pas au survol), au
    /// lieu de rester vivant en permanence et d'avaler le clic destiné au
    /// dépliage de la ligne.
    ///
    /// ⚠️ Non vérifié à l'écran (impossible de lancer l'app dans ce
    /// contexte) : on ne sait pas si ce no-op est réellement nécessaire,
    /// inoffensif, ou s'il empêche le `Menu` de s'ouvrir au clic. Symptôme à
    /// surveiller lors d'un premier essai manuel : le menu `⋮` ne s'ouvre pas
    /// au clic (au survol, une fois `isHovering` vrai). Si c'est le cas,
    /// commencer par retirer `.onTapGesture {}` et vérifier si le dépliage
    /// intempestif de la ligne revient.
    private var ligneMenu: some View {
        Menu {
            Button("Modifier") { isEditingTitle = true }
            Button(task.comments.isEmpty ? "Commentaires" : "Commentaires (\(task.comments.count))") {
                expanded = true
            }
            Button("Supprimer") { onDelete() }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(AppTheme.texteSecondaire)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onTapGesture {}
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
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
