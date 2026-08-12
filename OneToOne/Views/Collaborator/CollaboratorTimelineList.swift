import SwiftUI
import SwiftData

/// Le fil chronologique : une ligne par événement, un séparateur par mois.
///
/// `[puce] [date 46] [pastille 56] [titre / sous-titre] [méta]`. La graisse du
/// titre **est** la hiérarchie : un 1:1 et une décision sont en demi-gras, une
/// note et une réunion en romain.
struct CollaboratorTimelineList: View {
    let items: [TimelineItem]
    /// La réunion d'où vient la ligne, à ouvrir au clic.
    let meetingFor: (TimelineItem) -> Meeting?

    @State private var hovered: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if items.isEmpty {
                    empty
                } else {
                    ForEach(groupedByMonth, id: \.key) { mois, lignes in
                        Text(mois)
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(FicheTokens.ink.opacity(0.30))
                            .textCase(.uppercase)
                            .padding(.leading, 46).padding(.top, 9).padding(.bottom, 3)
                        ForEach(lignes) { item in
                            // `NavigationLink`, pas un `onTapGesture` qui
                            // pousse une destination : c'est le patron que la
                            // fiche precedente utilisait, et un double-clic n'y
                            // pousse qu'une fois.
                            if let meeting = meetingFor(item) {
                                NavigationLink { MeetingView(meeting: meeting, isPushed: true) } label: {
                                    ligneSurvolee(item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                ligneSurvolee(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// « Aucun échange enregistré » plutôt qu'une liste vide : l'absence
    /// d'historique est un état, pas une erreur.
    private var empty: some View {
        VStack(spacing: 10) {
            Text("Aucun échange enregistré")
                .font(.system(size: 12.5))
                .foregroundStyle(FicheTokens.inkSecondary)
            Button("Créer le premier 1:1") {}
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var groupedByMonth: [(key: String, value: [TimelineItem])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "LLLL"
        var ordre: [String] = []
        var paquets: [String: [TimelineItem]] = [:]
        for item in items {
            let mois = formatter.string(from: item.date)
            if paquets[mois] == nil { ordre.append(mois) }
            paquets[mois, default: []].append(item)
        }
        return ordre.map { ($0, paquets[$0] ?? []) }
    }

    private func ligneSurvolee(_ item: TimelineItem) -> some View {
        row(item)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(hovered == item.id ? FicheTokens.rowHover : Color.clear))
            .onHover { hovered = $0 ? item.id : nil }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Circle()
                .fill(pastilleTint(item.kind))
                .frame(width: 5, height: 5)
                .padding(.top, 15).padding(.trailing, 6)
            Text(item.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FicheTokens.ink.opacity(0.38))
                .frame(width: FicheTokens.dateWidth, alignment: .leading)
                .padding(.top, 11)
            pill(item.kind)
                .padding(.top, 10).padding(.trailing, 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: emphasised(item.kind) ? .semibold : .regular))
                    .foregroundStyle(FicheTokens.ink)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(FicheTokens.inkSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.vertical, 7)
            Spacer(minLength: 8)
            // Le badge compte les actions produites — la seule métrique qui
            // justifie de rouvrir une réunion.
            if item.actionCount > 0 {
                Text("\(item.actionCount) action\(item.actionCount > 1 ? "s" : "")")
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(FicheTokens.inkSecondary)
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// La graisse porte la hiérarchie : ce qui engage est en demi-gras.
    private func emphasised(_ kind: TimelineKind) -> Bool {
        kind == .oneToOne || kind == .decision
    }

    private func pill(_ kind: TimelineKind) -> some View {
        Text(kind.pill)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .frame(width: FicheTokens.pillWidth, height: FicheTokens.pillHeight)
            .background(RoundedRectangle(cornerRadius: 4).fill(pastilleFond(kind)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(pastilleBord(kind)))
            .foregroundStyle(pastilleTexte(kind))
    }

    private func pastilleFond(_ k: TimelineKind) -> Color {
        switch k {
        case .oneToOne: return Color(red: 0.910, green: 0.933, blue: 0.976)
        case .decision: return Color(red: 0.910, green: 0.953, blue: 0.925)
        case .note:     return Color(red: 0.949, green: 0.941, blue: 0.922)
        case .meeting:  return Color(red: 0.980, green: 0.973, blue: 0.957)
        }
    }
    private func pastilleTexte(_ k: TimelineKind) -> Color {
        switch k {
        case .oneToOne: return Color(red: 0.227, green: 0.361, blue: 0.573)
        case .decision: return Color(red: 0.184, green: 0.427, blue: 0.298)
        case .note:     return FicheTokens.ink.opacity(0.45)
        case .meeting:  return FicheTokens.ink.opacity(0.40)
        }
    }
    private func pastilleBord(_ k: TimelineKind) -> Color {
        switch k {
        case .oneToOne: return Color(red: 0.827, green: 0.875, blue: 0.949)
        case .decision: return Color(red: 0.812, green: 0.902, blue: 0.847)
        default:        return Color(red: 0.902, green: 0.886, blue: 0.859)
        }
    }
    private func pastilleTint(_ k: TimelineKind) -> Color {
        switch k {
        case .oneToOne: return Color(red: 0.227, green: 0.361, blue: 0.573)
        case .decision: return FicheTokens.ok
        default:        return FicheTokens.ink.opacity(0.25)
        }
    }
}
