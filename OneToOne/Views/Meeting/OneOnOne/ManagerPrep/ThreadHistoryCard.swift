import SwiftUI
import SwiftData

/// La carte `HISTORIQUE` de la capture 2b : les quatre dernières séances du
/// fil, une ligne chacune, cliquables vers la réunion.
struct ThreadHistoryModel: Equatable, Sendable {

    struct Row: Equatable, Sendable, Identifiable {
        var id: PersistentIdentifier
        /// `21 août` — la date en mono.
        var dateLabel: String
        /// Le résumé d'une ligne.
        var summary: String
        /// Vrai quand la séance n'a rien laissé : la ligne devient une invite,
        /// jamais un vide (spec §1.1, critère chantier 1 n° 1).
        var isPlaceholder: Bool
    }

    var rows: [Row]

    var isEmpty: Bool { rows.isEmpty }

    /// Le nombre de lignes de la capture.
    static let visibleCount = 4

    /// Ce que la ligne dit d'une séance dont il ne reste rien.
    static let placeholder = "Séance sans note — rien n'a été retenu"

    /// Longueur au-delà de laquelle un sujet est coupé : la carte fait 320 px,
    /// une ligne de plus de soixante caractères y passerait sur deux lignes et
    /// la capture n'en montre qu'une.
    static let summaryLimit = 60

    @MainActor
    static func build(_ thread: OneOnOneThread,
                      current: Meeting?,
                      now: Date,
                      limit: Int = visibleCount) -> ThreadHistoryModel {
        let courante = current?.persistentModelID
        let anterieures = OneOnOneThreadStore.meetings(of: thread, now: now)
            .filter { $0.persistentModelID != courante }
            .sorted { $0.date > $1.date }
            .prefix(max(0, limit))

        return ThreadHistoryModel(rows: anterieures.map { seance in
            let resume = summary(of: seance, in: thread)
            return Row(id: seance.persistentModelID,
                       dateLabel: OneOnOneDateFormat.dayMonth(seance.date),
                       summary: resume ?? placeholder,
                       isPlaceholder: resume == nil)
        })
    }

    /// Le résumé d'une ligne : le `shortSummary` du rapport quand il existe,
    /// sinon ce que la séance a effectivement retenu — le cran de moral et le
    /// premier sujet.
    ///
    /// Dans cet ordre, et pas l'inverse : quand un rapport a été généré, sa
    /// phrase est écrite pour être relue ; la reconstruction n'est qu'un repli.
    @MainActor
    static func summary(of meeting: Meeting, in thread: OneOnOneThread) -> String? {
        let court = firstLine(meeting.shortSummary)
        if !court.isEmpty { return truncated(court) }

        var parts: [String] = []
        if let humeur = MoodTrend.entry(for: meeting, in: thread) {
            parts.append("moral « \(MoodLevel.clamped(humeur.clampedValue).label) »")
        }
        if let sujet = firstTopic(of: meeting) { parts.append(sujet) }
        return parts.isEmpty ? nil : truncated(parts.joined(separator: " · "))
    }

    /// Le premier sujet de la séance : un thème s'il y en a — c'est déjà un
    /// libellé court — sinon la première note horodatée.
    @MainActor
    private static func firstTopic(of meeting: Meeting) -> String? {
        if let theme = meeting.tags.first?.name, !theme.isEmpty { return theme }
        let notes = meeting.timedNotes.sorted { $0.t < $1.t }
        guard let premiere = notes.first(where: { !$0.text.isEmpty }) else { return nil }
        return firstLine(premiere.text)
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > summaryLimit else { return text }
        return String(text.prefix(summaryLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// La carte `HISTORIQUE` (capture 2b). Dépliée, elle montre tout le fil : c'est
/// ce que le bouton `Historique` de l'en-tête demande.
struct ThreadHistoryCard: View {

    /// Largeur de la colonne de dates. Fixe, en mono : des dates qui ne
    /// s'alignent pas rendent une liste de quatre lignes illisible.
    static let dateColumn: CGFloat = 62

    let model: ThreadHistoryModel
    /// Vrai quand l'en-tête a demandé l'historique complet.
    let isExpanded: Bool
    let onOpenMeeting: (PersistentIdentifier) -> Void

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Historique").sectionLabel()
                    Spacer(minLength: 8)
                    if isExpanded {
                        MonoMeta("\(model.rows.count) séances")
                    }
                }

                if model.isEmpty {
                    MeetingEmptyInvite(
                        titre: "Premier entretien du fil",
                        invite: "Les séances passées s'empileront ici, une ligne chacune, "
                              + "cliquables vers la réunion."
                    )
                } else {
                    ForEach(model.rows) { ligne in
                        Button { onOpenMeeting(ligne.id) } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Text(ligne.dateLabel)
                                    .font(.plexMono(11, .medium))
                                    .foregroundStyle(One2OneToken.ink4)
                                    .frame(width: Self.dateColumn, alignment: .leading)
                                Text(ligne.summary)
                                    .font(.plexSans(12))
                                    .foregroundStyle(ligne.isPlaceholder
                                                     ? One2OneToken.inkMuted
                                                     : One2OneToken.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Ouvrir cette séance")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
