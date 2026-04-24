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
                    Picker("", selection: Binding(
                        get: { meeting.project },
                        set: { meeting.project = $0; saveContext() }
                    )) {
                        Text("Aucun projet").tag(nil as Project?)
                        ForEach(projects.sorted(by: { $0.name < $1.name })) { p in
                            Text(p.name).tag(p as Project?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)
                }
            }
            Spacer()
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
                            Text(p.name).font(.caption)
                            if participantStatus(p) == .absent {
                                Image(systemName: MeetingAttendanceStatus.absent.sfSymbol)
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(participantChipColor(for: p))
                        .cornerRadius(12)
                    }
                    .menuStyle(.borderlessButton)
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
