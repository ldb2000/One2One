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

    /// Le contexte que l'assistant interroge, quand ce n'est **pas** la seule
    /// réunion ouverte (lots 11 et 12, spec §3.3 : « barre assistant en pied,
    /// contexte = fil (`threadId`), pas seulement la réunion »).
    ///
    /// En 1:1, la question porte sur le **fil** : « Interroger l'historique
    /// des 1:1 de Laurent » en séance (capture 2a), « Qu'a-t-il demandé sans
    /// réponse depuis juin ? » en préparation (capture 2b). Le `threadID`
    /// voyage avec le placeholder pour que la surface sache de quoi elle
    /// parle ; le panneau lui-même reste celui de la réunion (lot 15 câblera
    /// la portée côté chatbot).
    ///
    /// **Un seul type pour les deux écrans** : les lots 11 et 12 en avaient
    /// écrit un chacun (`Contexte` et `ThreadContext`), pour la même barre au
    /// même endroit. Le champ `suggestions` du lot 12 a disparu avec eux — la
    /// barre de contexte n'en affiche pas : sur 2a comme sur 2b, la question
    /// tient toute la largeur.
    struct ThreadContext: Equatable, Sendable {
        /// La question affichée, guillemets compris quand la capture en met.
        var placeholder: String
        /// Le prénom de la personne du fil, pour le libellé d'aide.
        var threadName: String = ""
        var threadID: UUID?

        /// Le contexte d'un fil 1:1.
        @MainActor
        static func fil(of thread: OneOnOneThread) -> ThreadContext {
            let prenom = OneOnOneThreadStore.firstName(of: thread)
            return ThreadContext(
                placeholder: prenom.isEmpty
                    ? "Interroger l'historique de ce fil"
                    : "Interroger l'historique des 1:1 de \(prenom)",
                threadName: prenom,
                threadID: thread.ensuredStableID
            )
        }
    }
    }

    let meeting: Meeting
    /// Réunions connues, pour dater la seconde suggestion.
    let historique: [Meeting]
    /// Le panneau d'assistant est ouvert. Piloté aussi par `⌘K`
    /// (`MeetingMenuActions.openAssistant`).
    @Binding var isOpen: Bool
    /// `nil` = la barre de la capture 1a, inchangée : placeholder de réunion et
    /// deux suggestions datées. Renseigné, la barre se réduit au placeholder du
    /// contexte et à `⌘K` — les colonnes latérales du 1:1 font 300 px, deux
    /// pilules de suggestion n'y tiennent pas.
    var threadContext: ThreadContext?

    var body: some View {
        if let threadContext {
            barreDeContexte(threadContext)
        } else {
            barreDeReunion
        }
    }

    /// La barre étroite d'un contexte nommé (capture 2a, pied de colonne
    /// gauche) : l'étincelle, la question, `⌘K`.
    private func barreDeContexte(_ contexte: ThreadContext) -> some View {
        Button {
            isOpen = true
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(One2OneToken.oneOnOne)
                Text(contexte.placeholder)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.ink3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text("⌘K")
                    .font(.plexMono(10))
                    .foregroundStyle(One2OneToken.ink4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.oneOnOneBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .help(contexte.threadName.isEmpty
              ? "Poser une question sur tout l'historique de ce fil (⌘K)"
              : "Poser une question sur tout l'historique des 1:1 de \(contexte.threadName) (⌘K)")
    }

    private var barreDeReunion: some View {
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

            ForEach(Self.suggestions(for: meeting, historique: historique),
                    id: \.self) { suggestion in
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
