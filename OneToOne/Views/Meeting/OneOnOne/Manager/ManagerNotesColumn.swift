import SwiftUI
import SwiftData

/// La colonne centrale de l'écran de séance 1:1 (capture 2a) :
/// `Notes de l'entretien · liées à l'audio`, la bascule de visibilité par
/// défaut, puis les trois temps `①②③` et le composeur.
///
/// Il n'y a **pas** de colonne de transcription ici : la spec §3.1 retire du
/// type 1:1 tout ce qui regarde ailleurs que la personne, et la capture montre
/// une colonne de notes pleine largeur. La transcription reste accessible en
/// mode Relire.
struct ManagerNotesColumn: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    let screen: MeetingScreenModel

    @Environment(\.modelContext) private var context

    /// La carte de `③` où la prochaine ligne `/feedback` sera écrite.
    @State private var feedbackSection: NoteCommandParser.FeedbackSection = .given
    /// La visibilité par défaut des lignes saisies dans cette séance.
    ///
    /// Un `@State` et non une colonne : c'est un réglage de séance (spec §3.2
    /// « par défaut au niveau de la réunion »), et le persister ferait
    /// apparaître dans un backup la trace d'un choix d'interface. Le défaut
    /// vient du rôle du fil.
    @State private var defautDeVisibilite: Visibility?

    private var visibilite: Visibility {
        defautDeVisibilite ?? OneOnOneConfidentiality.defaultVisibility(for: thread.myRole)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        MoodScale(meeting: meeting, thread: thread)
                        // `MoodScale` porte déjà le libellé `① COMMENT ÇA VA` :
                        // les notes de ce temps-là viennent **sous** l'échelle,
                        // dans la même section (capture 2a).
                        OneOnOneNotesSection(meeting: meeting, section: .howAreYou,
                                             screen: screen,
                                             montreLeLibelle: false)
                    }
                    separateur
                    OneOnOneNotesSection(meeting: meeting, section: .topics, screen: screen)
                    separateur
                    FeedbackCards(meeting: meeting, section: $feedbackSection)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            composeur
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard))
        .task(id: meeting.timedNotes.count) { rafraichirMarqueurs() }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 8) {
            Text("Notes de l'entretien")
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Text("liées à l'audio")
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.inkMuted)
            Spacer(minLength: 8)
            bascule(.shared, libelle: "Partagé")
            bascule(.private, libelle: "Privé")
        }
        .padding(.horizontal, 12)
        .frame(height: MeetingLiveSpace.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// Les deux pilules de visibilité par défaut. Elles ne changent **pas** les
    /// lignes déjà écrites : la confidentialité se règle par ligne, et un
    /// changement de défaut qui repeindrait l'historique rendrait publique une
    /// note écrite en privé.
    private func bascule(_ niveau: Visibility, libelle: String) -> some View {
        let actif = visibilite == niveau
        return Button {
            defautDeVisibilite = niveau
        } label: {
            Pill(libelle, ton: actif ? .oneOnOne : .neutre, bordee: actif)
        }
        .buttonStyle(.plain)
        .help(niveau == .private
              ? "Les prochaines lignes seront privées — jamais dans un récap ni un rapport"
              : "Les prochaines lignes seront visibles par les deux personnes du fil")
    }

    private var separateur: some View {
        Rectangle().fill(One2OneToken.hair).frame(height: 1)
    }

    // MARK: - Composeur

    private var composeur: some View {
        let contexte = OneOnOneComposerContext(thread: thread,
                                               role: thread.myRole,
                                               section: feedbackSection,
                                               defaultVisibility: visibilite)
        return NoteComposer(meeting: meeting,
                            screen: screen,
                            commands: contexte.commands,
                            oneOnOne: contexte,
                            placeholder: "Écrire…")
    }

    private func rafraichirMarqueurs() {
        screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
        if screen.playhead.duration <= 0 {
            screen.playhead.duration = Double(meeting.durationSeconds)
        }
    }
}
