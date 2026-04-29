import SwiftUI
import SwiftData

struct MeetingDetailsBlock: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let allCollaborators: [Collaborator]
    let availableCollaborators: [Collaborator]
    let projects: [Project]

    @Binding var expanded: Bool
    @Binding var showCustomPrompt: Bool
    @Binding var newAdhocName: String
    @Binding var calendarImportError: String?

    let addParticipant: (Collaborator) -> Void
    let removeParticipant: (Collaborator) -> Void
    let setParticipantStatus: (MeetingAttendanceStatus, Collaborator) -> Void
    let participantStatus: (Collaborator) -> MeetingAttendanceStatus
    let addAdhoc: () -> Void
    let saveContext: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showCreateProjectSheet = false
    @State private var showProjectSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Détails de la réunion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    typeProjectRow
                    participantsBlock
                    if !availableCollaborators.isEmpty { collaboratorsBlock }
                    adhocRow
                    if showCustomPrompt {
                        TextEditor(text: $meeting.customPrompt)
                            .font(.body)
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(MeetingTheme.hairline, lineWidth: 1)
                            )
                    }
                    if let calendarImportError, !calendarImportError.isEmpty {
                        Text(calendarImportError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
        }
        .background(MeetingTheme.canvasCream)
    }

    private var typeProjectRow: some View {
        HStack(spacing: 16) {
            labeled("TYPE") {
                Picker("", selection: Binding(
                    get: { meeting.kind },
                    set: { meeting.kind = $0; saveContext() }
                )) {
                    ForEach(MeetingKind.allCases) { k in
                        Label(k.label, systemImage: k.sfSymbol).tag(k)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
            }
            if meeting.kind == .project {
                labeled("PROJET") {
                    HStack(spacing: 8) {
                        Button {
                            showProjectSearch.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                if let project = meeting.project {
                                    Text(project.code).font(.caption.monospaced()).foregroundColor(.secondary)
                                    Text(project.name).lineLimit(1).truncationMode(.tail)
                                } else {
                                    Text("Aucun projet — rechercher…").foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .frame(maxWidth: 320, alignment: .leading)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(MeetingTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showProjectSearch, arrowEdge: .bottom) {
                            ProjectSearchPicker(
                                projects: projects,
                                selected: meeting.project,
                                onSelect: { project in
                                    meeting.project = project
                                    saveContext()
                                    showProjectSearch = false
                                }
                            )
                        }

                        Button {
                            showCreateProjectSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Créer un nouveau projet")
                    }
                }
            }
            Spacer()
        }
        .sheet(isPresented: $showCreateProjectSheet) {
            CreateProjectSheet(
                existingProjects: projects,
                onCreate: { newProject in
                    context.insert(newProject)
                    meeting.project = newProject
                    saveContext()
                    showCreateProjectSheet = false
                },
                onCancel: { showCreateProjectSheet = false }
            )
        }
    }

    private var participantsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARTICIPANTS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            if !meeting.calendarEventTitle.isEmpty {
                Label(
                    "\(meeting.calendarEventTitle) • \(meeting.date.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(meeting.participants, id: \.persistentModelID) { p in
                    Menu {
                        ForEach(MeetingAttendanceStatus.allCases) { status in
                            Button(action: { setParticipantStatus(status, p) }) {
                                Label(status.label, systemImage: status.sfSymbol)
                            }
                        }
                        Divider()
                        Button(role: .destructive, action: { removeParticipant(p) }) {
                            Label("Retirer", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AvatarMini(collaborator: p, tint: settings.meetingParticipantColor)
                            Text(p.name)
                                .font(.caption)
                                .foregroundColor(.primary)
                            if participantStatus(p) == .absent {
                                Image(systemName: MeetingAttendanceStatus.absent.sfSymbol)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(participantChipColor(for: p))
                        .cornerRadius(12)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }

                Menu {
                    ForEach(availableCollaborators) { c in
                        Button(c.name) { addParticipant(c) }
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus.circle").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 100)
            }
        }
    }

    private var collaboratorsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLLABORATEURS")
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(availableCollaborators, id: \.persistentModelID) { c in
                    Button(action: { addParticipant(c) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill").font(.caption2)
                            Text(c.name).font(.caption)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(settings.meetingCollaboratorColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var adhocRow: some View {
        HStack(spacing: 6) {
            TextField("Ad-hoc : nom…", text: $newAdhocName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit { addAdhoc() }
            Button(action: addAdhoc) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(newAdhocName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(MeetingTheme.sectionLabel)
                .tracking(1.2)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func participantChipColor(for c: Collaborator) -> Color {
        switch participantStatus(c) {
        case .participant: return settings.meetingParticipantColor
        case .absent:      return settings.meetingAbsentColor
        }
    }
}

// MARK: - Recherche projet

/// Popover de sélection de projet avec champ de recherche en haut.
/// Filtre par code, nom, domaine, CP, AT (case-insensitive).
private struct ProjectSearchPicker: View {
    let projects: [Project]
    let selected: Project?
    let onSelect: (Project?) -> Void

    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    private var filtered: [Project] {
        let active = projects.filter { !$0.isArchived }
        let sorted = active.sorted { lhs, rhs in
            lhs.code.localizedCaseInsensitiveCompare(rhs.code) == .orderedAscending
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { p in
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
                            Text("Aucun projet").foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if filtered.isEmpty {
                        Text("Aucun résultat").font(.caption).foregroundColor(.secondary)
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

// MARK: - Création de projet inline

private struct CreateProjectSheet: View {
    let existingProjects: [Project]
    let onCreate: (Project) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var domain: String = ""
    @State private var phase: String = "Build"
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canCreate: Bool {
        !trimmedName.isEmpty && !trimmedCode.isEmpty
    }

    private static let phases = ["Idéation", "Cadrage", "Build", "Run", "Clos"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nouveau projet")
                .font(.title2.weight(.semibold))

            Form {
                TextField("Code (ex. PXX_042)", text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField("Nom du projet", text: $name)
                    .textFieldStyle(.roundedBorder)
                TextField("Domaine (optionnel)", text: $domain)
                    .textFieldStyle(.roundedBorder)
                Picker("Phase", selection: $phase) {
                    ForEach(Self.phases, id: \.self) { Text($0).tag($0) }
                }
            }

            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Annuler", action: onCancel)
                Button("Créer") {
                    if existingProjects.contains(where: { $0.code == trimmedCode }) {
                        error = "Ce code projet existe déjà."
                        return
                    }
                    let project = Project(
                        code: trimmedCode,
                        name: trimmedName,
                        domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
                        phase: phase
                    )
                    onCreate(project)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }
}
