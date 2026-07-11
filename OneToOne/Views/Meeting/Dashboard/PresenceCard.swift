import SwiftUI

/// Carte « Présence » du dashboard : donut de taux de présence, compteurs par
/// statut, pile d'avatars, bouton « Gérer les participants ».
struct PresenceCard: View {
    @Bindable var meeting: Meeting
    let settings: AppSettings
    var isEditing: Bool = false
    /// Ouvre la modale de gestion des participants.
    let onManage: () -> Void

    private var stats: PresenceStats {
        PresenceStats.compute(statuses: meeting.participants.map { meeting.participantStatus(for: $0) })
    }

    var body: some View {
        DashboardCard(title: "Présence", systemImage: "person.3.fill",
                      badge: "\(stats.total)", isEditing: isEditing) {
            EmptyView()
        } content: {
            let s = stats
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    donut(present: s.present, refused: s.refused, pending: s.pending,
                          total: s.total, percent: s.percent)
                        .frame(width: 108, height: 108)
                    VStack(alignment: .leading, spacing: 8) {
                        legendRow(color: .green, count: s.present, label: "présents")
                        legendRow(color: MeetingTheme.accentOrange, count: s.refused, label: "ont refusé")
                        if s.pending > 0 {
                            legendRow(color: .orange, count: s.pending, label: "en attente")
                        }
                    }
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                if !meeting.participants.isEmpty {
                    MeetingAvatarStack(participants: meeting.participants,
                                       tint: { _ in settings.meetingParticipantColor })
                }
                Button(action: onManage) {
                    Text("Gérer les participants")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(MeetingTheme.hairline))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func legendRow(color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)").font(.body)
        }
    }

    /// Donut : arc vert (présents) + arc rouge (refusés) + reste neutre (en attente),
    /// pourcentage centré.
    private func donut(present: Int, refused: Int, pending: Int, total: Int, percent: Int) -> some View {
        let denom = max(total, 1)
        let presentFrac = Double(present) / Double(denom)
        let refusedFrac = Double(refused) / Double(denom)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: presentFrac)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: presentFrac, to: presentFrac + refusedFrac)
                .stroke(MeetingTheme.accentOrange, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)").font(.system(size: 30, weight: .bold)) + Text("%").font(.callout.bold())
                Text("de présence").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
