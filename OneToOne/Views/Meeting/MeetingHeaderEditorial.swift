import SwiftUI

struct MeetingHeaderEditorial: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Binding var detailsExpanded: Bool

    @State private var showDatePopover = false

    /// Libellé du bandeau supérieur dérivé de `meeting.kind`. Pour les 1:1 (et manager),
    /// suffixe le nom du premier participant en majuscules s'il existe.
    private var kindLabel: String {
        switch meeting.kind {
        case .project:   return "COPIL · PROJET"
        case .oneToOne:
            let name = meeting.participants.first?.name.uppercased() ?? ""
            return name.isEmpty ? "1:1" : "1:1 · \(name)"
        case .work:      return "RÉUNION DE TRAVAIL"
        case .global:    return "RÉUNION"
        case .manager:
            let name = meeting.participants.first?.name.uppercased() ?? ""
            return name.isEmpty ? "1:1 MANAGER" : "1:1 MANAGER · \(name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row 1: badge + kind label
            HStack(spacing: 10) {
                if let project = meeting.project {
                    Text(project.code)
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(MeetingTheme.badgeBlack)
                        .clipShape(Capsule())
                }
                Text(kindLabel)
                    .font(MeetingTheme.sectionLabel)
                    .tracking(1.4)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Row 2: editable title
            EditableTextField(placeholder: "Titre de la réunion…", text: $meeting.title)
                .font(MeetingTheme.titleSerif)
                .frame(minHeight: 44, alignment: .leading)

            // Row 3: date · avatars · count
            HStack(spacing: 14) {
                Button { showDatePopover.toggle() } label: {
                    Text(dateLabel)
                        .font(MeetingTheme.meta)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePopover) {
                    DatePicker("", selection: $meeting.date, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .padding()
                }

                if !meeting.participants.isEmpty {
                    MeetingAvatarStack(
                        participants: meeting.participants,
                        tint: { _ in settings.meetingParticipantColor }
                    )

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            detailsExpanded.toggle()
                        }
                    } label: {
                        Text("\(meeting.participants.count) participants")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(MeetingTheme.canvasCream)
    }

    /// Date de la réunion formatée en locale fr_FR au format « dd/MM/yyyy · HH:mm ».
    private var dateLabel: String {
        Self.dateFormatter.string(from: meeting.date)
    }

    /// Formateur de date mis en cache (évite une réallocation à chaque accès).
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.timeZone = .current
        df.dateFormat = "dd/MM/yyyy · HH:mm"
        return df
    }()
}
