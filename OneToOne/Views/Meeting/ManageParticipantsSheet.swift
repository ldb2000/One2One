import SwiftUI

/// Modale de gestion des participants : recherche, filtres par statut, resync,
/// changement de statut, retrait, ajout ad-hoc. Toute la logique métier est
/// fournie par `MeetingView` via closures (réutilisation de l'existant).
struct ManageParticipantsSheet: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    let availableCollaborators: [Collaborator]
    let collaboratorsCount: Int
    @Binding var newAdhocName: String
    let addParticipant: (Collaborator) -> Void
    let removeParticipant: (Collaborator) -> Void
    let removeAllParticipants: () -> Void
    let setParticipantStatus: (MeetingAttendanceStatus, Collaborator) -> Void
    let participantStatus: (Collaborator) -> MeetingAttendanceStatus
    let addAdhoc: () -> Void
    let onResync: () -> Void
    let onClose: () -> Void

    /// Filtre de statut actif (nil = Tous).
    @State private var filter: MeetingAttendanceStatus? = nil
    @State private var query: String = ""

    private var counts: PresenceStats {
        PresenceStats.compute(statuses: meeting.participants.map { participantStatus($0) })
    }

    private var filteredParticipants: [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return meeting.participants.filter { c in
            (filter == nil || participantStatus(c) == filter)
            && (q.isEmpty || c.name.localizedCaseInsensitiveContains(q))
        }
    }

    /// Résultats annuaire (collaborateurs non-participants) quand on recherche.
    private var directoryMatches: [Collaborator] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return availableCollaborators.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 640, height: 720)
        .background(MeetingTheme.canvasCream)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gérer les participants").font(.title2.bold())
                Text("\(meeting.title) · \(meeting.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Rechercher un participant ou un collaborateur…", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
                Button { onResync() } label: { Label("Resync", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.bordered)
            }
            HStack(spacing: 8) {
                filterChip(nil, "Tous", counts.total)
                filterChip(.present, "Présents", counts.present)
                filterChip(.refused, "Ont refusé", counts.refused)
                filterChip(.pending, "En attente", counts.pending)
                Spacer()
                Text("Collaborateurs \(collaboratorsCount)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func filterChip(_ status: MeetingAttendanceStatus?, _ label: String, _ count: Int) -> some View {
        let active = filter == status
        return Button { filter = status } label: {
            HStack(spacing: 6) {
                if let status { Circle().fill(color(for: status)).frame(width: 7, height: 7) }
                Text("\(label) \(count)").font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(active ? MeetingTheme.badgeBlack : Color.secondary.opacity(0.08)))
            .foregroundColor(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func color(for status: MeetingAttendanceStatus) -> Color {
        switch status {
        case .present: return .green
        case .refused: return MeetingTheme.accentOrange
        case .pending: return .orange
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredParticipants, id: \.persistentModelID) { c in
                    participantRow(c); Divider()
                }
                if !directoryMatches.isEmpty {
                    Text("AJOUTER DEPUIS L'ANNUAIRE").font(MeetingTheme.sectionLabel)
                        .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 12)
                    ForEach(directoryMatches, id: \.persistentModelID) { c in
                        Button { addParticipant(c) } label: {
                            HStack(spacing: 12) {
                                AvatarMini(collaborator: c, tint: settings.meetingCollaboratorColor)
                                Text(c.name); Spacer()
                                Image(systemName: "plus.circle").foregroundColor(.secondary)
                            }.padding(.horizontal, 20).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private func participantRow(_ c: Collaborator) -> some View {
        HStack(spacing: 12) {
            AvatarCircle(collaborator: c, size: 34, tint: settings.meetingParticipantColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.body)
                Text(c.isAdhoc ? "Invité" : "Collaborateur").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                ForEach(MeetingAttendanceStatus.allCases) { s in
                    Button { setParticipantStatus(s, c) } label: { Label(s.label, systemImage: s.sfSymbol) }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(color(for: participantStatus(c))).frame(width: 7, height: 7)
                    Text(participantStatus(c).label).font(.caption)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
            }
            .menuStyle(.button).buttonStyle(.plain).fixedSize()
            Button { removeParticipant(c) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    TextField("Ajouter un participant ad-hoc (nom)…", text: $newAdhocName)
                        .textFieldStyle(.plain).onSubmit { addAdhoc() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
                Button("Ajouter") { addAdhoc() }
                    .disabled(newAdhocName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            HStack {
                Button(role: .destructive) { removeAllParticipants() } label: {
                    Label("Tout retirer", systemImage: "trash").foregroundColor(MeetingTheme.accentOrange)
                }.buttonStyle(.plain)
                Spacer()
                Button("Annuler") { onClose() }
                Button("Terminé") { onClose() }.buttonStyle(.borderedProminent).tint(MeetingTheme.accentOrange)
            }
            .padding(20)
        }
    }
}
