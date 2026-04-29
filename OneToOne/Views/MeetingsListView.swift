import SwiftUI
import SwiftData
import AVFoundation

struct MeetingsListView: View {
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]
    @Query private var projects: [Project]
    @Query(filter: #Predicate<Collaborator> { !$0.isArchived }) private var collaborators: [Collaborator]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: QuickLaunchRouter

    @State private var searchText = ""
    @State private var filterProject: Project?
    @State private var filterKind: MeetingKind? = nil
    @State private var bulkImportReport: String?
    @State private var isBulkImporting = false
    @State private var showProjectFilterPicker = false

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

    private var filteredMeetings: [Meeting] {
        var result = meetings

        if let kind = filterKind {
            result = result.filter { $0.kind == kind }
        }

        if let collab = router.listFilterCollaborator {
            result = result.filter { meeting in
                meeting.kind == .oneToOne &&
                meeting.participants.contains(where: { $0.stableID == collab.stableID })
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
            // Filters
            HStack(spacing: 12) {
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
                    HStack(spacing: 6) {
                        Image(systemName: filterKind?.sfSymbol ?? "line.3.horizontal.decrease.circle")
                            .foregroundColor(.secondary)
                        Text(filterKind?.label ?? "Tous types")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filtrer par type de réunion")

                Button {
                    showProjectFilterPicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        if let p = filterProject {
                            Text(p.code).font(.caption.monospaced()).foregroundColor(.secondary)
                            Text(p.name).lineLimit(1).truncationMode(.tail)
                        } else {
                            Text("Tous les projets").foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: 280, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
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

                Spacer()

                Text("\(filteredMeetings.count) réunion(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: addMeeting) {
                    Label("Nouvelle réunion", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

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
        .searchable(text: $searchText, prompt: "Rechercher une réunion...")
        .navigationTitle("Réunions")
    }

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

struct MeetingRowView: View {
    let meeting: Meeting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title.isEmpty ? "Réunion sans titre" : meeting.title)
                    .font(.headline)

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
