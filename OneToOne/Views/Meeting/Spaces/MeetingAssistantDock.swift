import SwiftUI
import SwiftData

/// La barre d'invocation de l'assistant, en pied de l'espace Réunion
/// (spec §1.1, capture `1a-cockpit.png`).
///
/// « L'assistant est une surface, pas un onglet : barre d'invocation
/// persistante + `⌘K` partout. » L'onglet Chat a disparu de la navigation ;
/// `MeetingChatView` est réemployé **tel quel** dans le panneau qui s'ouvre —
/// son mode outillage et son pré-fetch RAG sont inchangés.
struct MeetingAssistantDock: View {

    /// Hauteur de la barre.
    static let height: CGFloat = 34

    /// Le placeholder de la capture, au mot près.
    static let placeholder = "Demander à l'assistant sur cette réunion, l'historique, les documents…"

    /// Les deux suggestions de la barre.
    ///
    /// La première porte sur la séance en cours, la seconde sur la réunion
    /// **précédente du même projet** — la capture montre `Actions du 1er sept. ?`.
    /// Une suggestion datée est actionnable ; une suggestion générique ne
    /// l'est pas, et n'aurait pas mérité sa place.
    @MainActor
    static func suggestions(for meeting: Meeting, historique: [Meeting]) -> [String] {
        var propositions = ["Où en est le chiffrage ?"]
        if let precedente = precedenteDuProjet(meeting, dans: historique) {
            propositions.append("Actions du \(dateCourte(precedente.date)) ?")
        } else {
            propositions.append("Qu'est-ce qui reste sans réponse ?")
        }
        return propositions
    }

    /// La réunion du même projet immédiatement antérieure, s'il y en a une.
    @MainActor
    private static func precedenteDuProjet(_ meeting: Meeting,
                                            dans historique: [Meeting]) -> Meeting? {
        guard let projet = meeting.project else { return nil }
        return historique
            .filter { autre in
                autre.persistentModelID != meeting.persistentModelID
                    && autre.project?.persistentModelID == projet.persistentModelID
                    && autre.date < meeting.date
            }
            .max(by: { $0.date < $1.date })
    }

    /// `1er sept.` — la forme de la capture.
    static func dateCourte(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.locale = Locale(identifier: "fr_FR")
        return date.formatted(style)
    }

    let meeting: Meeting
    /// Réunions connues, pour dater la seconde suggestion.
    let historique: [Meeting]
    /// Le panneau d'assistant est ouvert. Piloté aussi par `⌘K`
    /// (`MeetingMenuActions.openAssistant`).
    @Binding var isOpen: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundStyle(One2OneToken.action)
                    Text(Self.placeholder)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Self.suggestions(for: meeting, historique: historique), id: \.self) { suggestion in
                Button { isOpen = true } label: {
                    Pill(suggestion, ton: .neutre)
                }
                .buttonStyle(.plain)
                .help("Poser cette question à l'assistant")
            }

            Text("⌘K")
                .font(.plexMono(10))
                .foregroundStyle(One2OneToken.ink4)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
    }
}

/// Le panneau d'assistant, ouvert par la barre d'invocation ou par `⌘K`.
///
/// Ne réécrit rien : il héberge `MeetingChatView` telle quelle. Le lot 4 en
/// fera un panneau ancré en pied de la colonne droite du mode séance (spec
/// §2.6) ; d'ici là, une feuille suffit et ne coûte rien.
struct MeetingAssistantPanel: View {
    @Bindable var meeting: Meeting
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ASSISTANT").sectionLabel()
                Spacer()
                Text(meeting.title.isEmpty ? "Réunion" : meeting.title)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink4)
                    .lineLimit(1)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(One2OneToken.ink3)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .frame(height: MeetingTopChromeBar.height)
            .background(One2OneToken.bgApp)
            .overlay(alignment: .bottom) {
                Rectangle().fill(One2OneToken.cardBorder).frame(height: 1)
            }

            MeetingChatView(meeting: meeting)
        }
        .frame(minWidth: 560, minHeight: 480)
    }
}
