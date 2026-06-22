import SwiftUI
import SwiftData
import AVFoundation

/// Liste principale des réunions : filtres (type, projet, collaborateur via
/// le routeur), recherche plein texte, création, agenda du jour et import
/// groupé de WAVs orphelins.
struct MeetingsListView: View {
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: QuickLaunchRouter

    @State private var searchText = ""
    @State private var filterProject: Project?
    @State private var filterKind: MeetingKind? = nil
    @State private var filterCollaborator: Collaborator?
    @State private var bulkImportReport: String?
    @State private var isBulkImporting = false
    @State private var showProjectFilterPicker = false
    @State private var showCollaboratorFilterPicker = false
    @State private var agendaInspectorOpen: Bool = false
    @Query private var allAppSettings: [AppSettings]

    /// Projets ayant au moins une réunion en base. C'est la liste qu'on
    /// propose dans le filtre "Projet" : pas de bruit avec les projets
    /// importés mais sans réunion attachée.
    private var projectsWithMeetings: [Project] {
        let withMeetings = Dictionary(grouping: meetings, by: { $0.project?.persistentModelID })
            .compactMap { $0.key }
        let ids = Set(withMeetings)
        return projects
            .filter { ids.contains($0.persistentModelID) && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Nombre de réunions par collaborateur participant (pour le picker du filtre).
    private var collaboratorMeetingCounts: [PersistentIdentifier: Int] {
        var counts: [PersistentIdentifier: Int] = [:]
        for meeting in meetings {
            for p in meeting.participants {
                counts[p.persistentModelID, default: 0] += 1
            }
        }
        return counts
    }

    /// Collaborateurs participant à au moins une réunion — même logique que
    /// `projectsWithMeetings` : pas de bruit dans le filtre.
    private var collaboratorsWithMeetings: [Collaborator] {
        let counts = collaboratorMeetingCounts
        return collaborators
            .filter { (counts[$0.persistentModelID] ?? 0) > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredMeetings: [Meeting] {
        var result = meetings

        if let kind = filterKind {
            result = result.filter { $0.kind == kind }
        }

        if let collab = router.listFilterCollaborator {
            result = result.filter { meeting in
                meeting.kind == .oneToOne &&
                meeting.participants.contains(where: { $0.ensuredStableID == collab.ensuredStableID })
            }
        }

        if let collab = filterCollaborator {
            result = result.filter { meeting in
                meeting.participants.contains(where: { $0.persistentModelID == collab.persistentModelID })
            }
        }

        if let project = filterProject {
            result = result.filter { $0.project?.persistentModelID == project.persistentModelID }
        }

        if !searchText.isEmpty {
            let q = searchText
            result = result.filter { m in
                m.title.localizedCaseInsensitiveContains(q) ||
                m.notes.localizedCaseInsensitiveContains(q) ||
                m.liveNotes.localizedCaseInsensitiveContains(q) ||
                m.summary.localizedCaseInsensitiveContains(q) ||
                m.rawTranscript.localizedCaseInsensitiveContains(q) ||
                m.mergedTranscript.localizedCaseInsensitiveContains(q) ||
                m.keyPointsJSON.localizedCaseInsensitiveContains(q) ||
                m.decisionsJSON.localizedCaseInsensitiveContains(q) ||
                m.openQuestionsJSON.localizedCaseInsensitiveContains(q) ||
                m.customPrompt.localizedCaseInsensitiveContains(q) ||
                m.calendarEventTitle.localizedCaseInsensitiveContains(q) ||
                m.participants.contains { $0.name.localizedCaseInsensitiveContains(q) }
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters — chips harmonisées : Type (menu), Projet et Collaborateur
            // (popovers avec recherche). Une chip active est teintée accent.
            HStack(spacing: 8) {
                Menu {
                    Button {
                        filterKind = nil
                    } label: {
                        Label("Tous types", systemImage: filterKind == nil ? "checkmark" : "circle")
                    }
                    Divider()
                    ForEach(MeetingKind.allCases) { kind in
                        Button {
                            filterKind = kind
                        } label: {
                            Label(kind.label, systemImage: filterKind == kind ? "checkmark" : kind.sfSymbol)
                        }
                    }
                } label: {
                    filterChip(icon: filterKind?.sfSymbol ?? "line.3.horizontal.decrease",
                               text: filterKind?.label ?? "Type",
                               isActive: filterKind != nil)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Filtrer par type de réunion")

                Button {
                    showProjectFilterPicker.toggle()
                } label: {
                    filterChip(icon: "folder",
                               text: filterProject?.name ?? "Projet",
                               isActive: filterProject != nil,
                               maxWidth: 240)
                }
                .buttonStyle(.plain)
                .help("Filtrer par projet")
                .popover(isPresented: $showProjectFilterPicker, arrowEdge: .bottom) {
                    MeetingsProjectFilterPicker(
                        projects: projectsWithMeetings,
                        selected: filterProject,
                        meetingCounts: Dictionary(
                            grouping: meetings,
                            by: { $0.project?.persistentModelID }
                        ).mapValues { $0.count },
                        onSelect: { p in
                            filterProject = p
                            showProjectFilterPicker = false
                        }
                    )
                }

                Button {
                    showCollaboratorFilterPicker.toggle()
                } label: {
                    filterChip(icon: "person.2",
                               text: filterCollaborator?.name ?? "Collaborateur",
                               isActive: filterCollaborator != nil,
                               maxWidth: 220,
                               avatar: filterCollaborator)
                }
                .buttonStyle(.plain)
                .help("Filtrer par collaborateur participant")
                .popover(isPresented: $showCollaboratorFilterPicker, arrowEdge: .bottom) {
                    MeetingsCollaboratorFilterPicker(
                        collaborators: collaboratorsWithMeetings,
                        selected: filterCollaborator,
                        meetingCounts: collaboratorMeetingCounts,
                        onSelect: { c in
                            filterCollaborator = c
                            showCollaboratorFilterPicker = false
                        }
                    )
                }

                if filterKind != nil || filterProject != nil || filterCollaborator != nil {
                    Button {
                        filterKind = nil
                        filterProject = nil
                        filterCollaborator = nil
                    } label: {
                        Label("Réinitialiser", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Effacer tous les filtres")
                }

                Spacer()

                Text("\(filteredMeetings.count) réunion(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: addMeeting) {
                    Label("Nouvelle réunion", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    agendaInspectorOpen.toggle()
                } label: {
                    Image(systemName: "calendar")
                }
                .help("Afficher l'agenda du jour")

                Menu {
                    Button {
                        Task { await importOrphanWAVs(targetProject: filterProject) }
                    } label: {
                        if let project = filterProject {
                            Label("Importer WAVs orphelins → \(project.name)", systemImage: "waveform.badge.plus")
                        } else {
                            Label("Importer WAVs orphelins (sans projet)", systemImage: "waveform.badge.plus")
                        }
                    }
                    .disabled(isBulkImporting)
                } label: {
                    if isBulkImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Outils d'import groupé")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            if let collab = router.listFilterCollaborator {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill").foregroundColor(.accentColor)
                    Text("1:1 avec \(collab.name)")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        router.listFilterCollaborator = nil
                    } label: {
                        Label("Retirer le filtre", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.10))
            }

            if let report = bulkImportReport {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.accentColor)
                    Text(report).font(.caption)
                    Spacer()
                    Button {
                        bulkImportReport = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.08))
            }

            Divider()

            if filteredMeetings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Aucune réunion")
                        .foregroundColor(.secondary)
                    Button(action: addMeeting) {
                        Label("Créer une réunion", systemImage: "plus")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredMeetings) { meeting in
                        NavigationLink {
                            MeetingView(meeting: meeting)
                        } label: {
                            MeetingRowView(meeting: meeting)
                        }
                    }
                    .onDelete(perform: deleteMeetings)
                }
            }
        }
        .inspector(isPresented: $agendaInspectorOpen) {
            AgendaInspectorPanel()
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .onAppear {
            if let s = allAppSettings.first, s.agendaInspectorOpenByDefault {
                agendaInspectorOpen = true
            }
        }
        .searchable(text: $searchText, prompt: "Rechercher (titre, rapport, transcription, notes…)")
        .navigationTitle("Réunions")
    }

    /// Capsule de filtre : avatar (si fourni) ou icône, libellé, chevron.
    /// Active → teintée accent ; inactive → neutre discrète.
    @ViewBuilder
    private func filterChip(icon: String,
                            text: String,
                            isActive: Bool,
                            maxWidth: CGFloat? = nil,
                            avatar: Collaborator? = nil) -> some View {
        HStack(spacing: 6) {
            if let avatar {
                AvatarCircle(collaborator: avatar, size: 16, tint: .accentColor)
            } else {
                Image(systemName: icon)
                    .font(.caption)
            }
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .opacity(0.6)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: maxWidth)
        .fixedSize(horizontal: maxWidth == nil, vertical: false)
        .background(
            Capsule().fill(isActive ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07))
        )
        .overlay(
            Capsule().stroke(isActive ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .foregroundColor(isActive ? .accentColor : .primary)
        .contentShape(Capsule())
    }

    /// Crée une réunion vide (titre vide, date du jour, sans notes), l'insère
    /// dans le contexte et sauvegarde.
    private func addMeeting() {
        let meeting = Meeting(title: "", date: Date(), notes: "")
        context.insert(meeting)
        saveContext()
    }

    private func deleteMeetings(offsets: IndexSet) {
        let sorted = filteredMeetings
        for index in offsets {
            context.delete(sorted[index])
        }
        saveContext()
    }

    private func saveContext() {
        do { try context.save() } catch { print("[MeetingsListView] save FAILED: \(error)") }
    }

    /// Crée un Meeting pour chaque WAV/audio présent dans
    /// `~/Library/Application Support/OneToOne/recordings/` qui n'est pas
    /// déjà rattaché à un meeting. Date = mtime du fichier, titre = nom de
    /// fichier, durée lue via AVAudioFile.
    private func importOrphanWAVs(targetProject: Project?) async {
        isBulkImporting = true
        defer { isBulkImporting = false }
        bulkImportReport = nil

        let fm = FileManager.default
        let recordingsDir = URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "recordings", directoryHint: .isDirectory)

        guard let entries = try? fm.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else {
            bulkImportReport = "Dossier recordings/ inaccessible."
            return
        }

        let audioExt: Set<String> = ["wav", "mp3", "m4a", "aac", "aiff", "caf"]
        let referenced = Set(meetings.compactMap { $0.wavFilePath })

        let candidates = entries
            .filter { audioExt.contains($0.pathExtension.lowercased()) }
            .filter { !referenced.contains($0.path) }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }

        guard !candidates.isEmpty else {
            bulkImportReport = "Aucun WAV orphelin trouvé."
            return
        }

        var created = 0
        var failed: [String] = []
        for url in candidates {
            do {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let file = try AVAudioFile(forReading: url)
                let durationSec = Double(file.length) / file.processingFormat.sampleRate
                let title = url.deletingPathExtension().lastPathComponent

                let meeting = Meeting(title: title, date: mtime, notes: "")
                meeting.wavFilePath = url.path
                meeting.durationSeconds = Int(durationSec.rounded())
                if let project = targetProject {
                    meeting.project = project
                }
                context.insert(meeting)
                created += 1
            } catch {
                failed.append("\(url.lastPathComponent) (\(error.localizedDescription))")
            }
        }

        do {
            try context.save()
        } catch {
            bulkImportReport = "Echec save : \(error.localizedDescription)"
            return
        }

        var msg = "\(created) meeting(s) créé(s) depuis WAVs orphelins."
        if !failed.isEmpty {
            msg += " Echecs: \(failed.joined(separator: ", "))."
        }
        bulkImportReport = msg
    }
}

// MARK: - Filtre projet avec recherche

/// Popover de sélection de projet pour le filtre de la liste réunions :
/// ne propose QUE les projets ayant au moins une réunion ; recherche
/// case-insensitive sur code, nom, domaine, CP, AT.
private struct MeetingsProjectFilterPicker: View {
    let projects: [Project]
    let selected: Project?
    let meetingCounts: [PersistentIdentifier?: Int]
    let onSelect: (Project?) -> Void

    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    private var filtered: [Project] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects }
        return projects.filter { p in
            p.code.localizedCaseInsensitiveContains(q) ||
            p.name.localizedCaseInsensitiveContains(q) ||
            p.domain.localizedCaseInsensitiveContains(q) ||
            p.chefDeProjet.localizedCaseInsensitiveContains(q) ||
            p.architecte.localizedCaseInsensitiveContains(q) ||
            (p.entity?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Code, nom, domaine, CP, AT…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            Image(systemName: selected == nil ? "checkmark" : "circle.dotted")
                                .foregroundColor(selected == nil ? .accentColor : .secondary)
                                .frame(width: 18)
                            Text("Tous les projets")
                            Spacer()
                            let total = meetingCounts.values.reduce(0, +)
                            Text("\(total)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()

                    if filtered.isEmpty {
                        Text("Aucun projet correspondant")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 12)
                    } else {
                        ForEach(filtered) { project in
                            Button {
                                onSelect(project)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: project == selected ? "checkmark" : "circle")
                                        .foregroundColor(project == selected ? .accentColor : .secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(project.code).font(.caption.monospaced()).foregroundColor(.secondary)
                                            Text(project.name).lineLimit(1)
                                        }
                                        let meta = projectMetaLine(project)
                                        if !meta.isEmpty {
                                            Text(meta).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    let count = meetingCounts[project.persistentModelID] ?? 0
                                    Text("\(count)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(project == selected ? Color.accentColor.opacity(0.08) : Color.clear)
                            Divider()
                        }
                    }
                }
            }
            .frame(width: 380, height: 320)
        }
        .onAppear { queryFocused = true }
    }

    private func projectMetaLine(_ project: Project) -> String {
        var parts: [String] = []
        if !project.domain.isEmpty { parts.append(project.domain) }
        if !project.phase.isEmpty { parts.append(project.phase) }
        if !project.chefDeProjet.isEmpty { parts.append("CP: \(project.chefDeProjet)") }
        if !project.architecte.isEmpty { parts.append("AT: \(project.architecte)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filtre collaborateur avec recherche

/// Popover de sélection de collaborateur pour le filtre de la liste réunions :
/// ne propose QUE les collaborateurs participant à au moins une réunion ;
/// recherche case-insensitive sur nom et email, avatar et compteur par ligne.
private struct MeetingsCollaboratorFilterPicker: View {
    let collaborators: [Collaborator]
    let selected: Collaborator?
    let meetingCounts: [PersistentIdentifier: Int]
    let onSelect: (Collaborator?) -> Void

    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    private var filtered: [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return collaborators }
        return collaborators.filter { c in
            c.name.localizedCaseInsensitiveContains(q) ||
            c.email.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Nom, email…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Button {
                        onSelect(nil)
                    } label: {
                        HStack {
                            Image(systemName: selected == nil ? "checkmark" : "circle.dotted")
                                .foregroundColor(selected == nil ? .accentColor : .secondary)
                                .frame(width: 18)
                            Text("Tous les collaborateurs")
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()

                    if filtered.isEmpty {
                        Text("Aucun collaborateur correspondant")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 12)
                    } else {
                        ForEach(filtered) { collab in
                            Button {
                                onSelect(collab)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: collab == selected ? "checkmark" : "circle")
                                        .foregroundColor(collab == selected ? .accentColor : .secondary)
                                        .frame(width: 18)
                                    AvatarCircle(collaborator: collab, size: 22, tint: .accentColor)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(collab.name).lineLimit(1)
                                        if !collab.email.isEmpty {
                                            Text(collab.email)
                                                .font(.caption2).foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    let count = meetingCounts[collab.persistentModelID] ?? 0
                                    Text("\(count)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(collab == selected ? Color.accentColor.opacity(0.08) : Color.clear)
                            Divider()
                        }
                    }
                }
            }
            .frame(width: 340, height: 320)
        }
        .onAppear { queryFocused = true }
    }
}

/// Ligne d'une réunion dans la liste : titre, badges rapport/transcription,
/// date, projet, participants et compteur d'actions en attente.
struct MeetingRowView: View {
    let meeting: Meeting

    private var hasReport: Bool {
        !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !meeting.keyPoints.isEmpty ||
        !meeting.decisions.isEmpty ||
        !meeting.openQuestions.isEmpty
    }

    private var hasTranscript: Bool {
        !meeting.mergedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !meeting.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(meeting.title.isEmpty ? "Réunion sans titre" : meeting.title)
                        .font(.headline)
                    if hasReport {
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .help("Rapport disponible")
                    }
                    if hasTranscript {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help("Transcription disponible")
                    }
                }

                HStack(spacing: 8) {
                    Label(meeting.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let project = meeting.project {
                        Label(project.name, systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if !meeting.participants.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(meeting.participants.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            let pendingCount = meeting.tasks.filter { !$0.isCompleted }.count
            if pendingCount > 0 {
                VStack {
                    Text("\(pendingCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    Text("actions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
