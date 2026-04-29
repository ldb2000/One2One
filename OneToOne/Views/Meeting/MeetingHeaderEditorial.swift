import SwiftUI

struct MeetingHeaderEditorial: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    @Binding var detailsExpanded: Bool

    @State private var showDatePopover = false

    private var kindLabel: String {
        switch meeting.kind {
        case .project:   return "COPIL · PROJET"
        case .oneToOne:
            let name = meeting.participants.first?.name.uppercased() ?? ""
            return name.isEmpty ? "1:1" : "1:1 · \(name)"
        case .work:      return "RÉUNION DE TRAVAIL"
        case .global:    return "RÉUNION"
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

    private var dateLabel: String {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy · HH:mm"
        return df.string(from: meeting.date)
    }
}
