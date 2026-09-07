import SwiftUI
import SwiftData

/// La colonne centrale de l'écran de séance du 1:1 subi (capture 5a) :
/// `Notes de l'entretien`, les deux pilules de confidentialité, les deux
/// sections `CE QU'IL M'A DIT` / `CE QUE J'AI DIT`, puis le composeur.
///
/// Deux pilules, et **une seule est un bouton**. `● Privé par défaut` est un
/// état : côté collaborateur, le défaut n'est pas négociable (spec §6.1), et en
/// faire une bascule de séance — comme au lot 11 — ouvrirait la porte à un
/// « tout partager » d'un clic, qui est exactement ce que le critère n° 2
/// interdit. `Partager la ligne` agit sur **la ligne désignée**, et sur aucune
/// autre.
///
/// Il n'y a pas de colonne de transcription ici : la spec §3.1 retire du type
/// 1:1 tout ce qui regarde ailleurs que la personne. La transcription reste
/// accessible en mode Relire.
struct CollaboratorNotesColumn: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    let screen: MeetingScreenModel

    @Environment(\.modelContext) private var context

    /// La section où la prochaine ligne sera écrite.
    ///
    /// `.received` par défaut — dans un entretien qu'on subit, ce qu'on note le
    /// plus est ce que l'autre dit, et c'est ce que montre la capture (trois
    /// lignes sous `CE QU'IL M'A DIT`, deux sous `CE QUE J'AI DIT`). Un `@State`
    /// et non une colonne : c'est un réglage de saisie, pas un fait de
    /// l'entretien.
    @State private var section: NoteCommandParser.FeedbackSection = .received

    /// La ligne désignée, quand elle appartient encore à la séance.
    private var ligneCourante: MeetingNote? {
        guard let id = screen.oneOnOne.collabSelectedNoteID else { return nil }
        return meeting.timedNotes.first { $0.persistentModelID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            entete
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CollaboratorNotesSection(
                        meeting: meeting, screen: screen,
                        titre: CollaboratorSessionModel.heardTitle,
                        notes: CollaboratorSessionModel.heardSectionNotes(meeting),
                        invite: CollaboratorSessionModel.heardEmptyInvite,
                        cible: .received, section: $section)
                    separateur
                    CollaboratorNotesSection(
                        meeting: meeting, screen: screen,
                        titre: CollaboratorSessionModel.saidTitle,
                        notes: CollaboratorSessionModel.saidSectionNotes(meeting),
                        invite: CollaboratorSessionModel.saidEmptyInvite,
                        cible: .given, section: $section)
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
            Text(CollaboratorSessionModel.notesTitle)
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.ink1)
            Spacer(minLength: 8)
            Pill(CollaboratorSessionModel.defaultPrivacyPill, ton: .oneOnOne, bordee: true)
                .help("Tout ce que vous écrivez ici reste privé — le partage se fait ligne par ligne")
            boutonDePartage
        }
        .padding(.horizontal, 12)
        .frame(height: MeetingLiveSpace.headerHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(One2OneToken.hair).frame(height: 1)
        }
    }

    /// `Partager la ligne` — inerte tant qu'aucune ligne n'est désignée :
    /// partager « la » ligne quand il n'y en a pas reviendrait à en choisir une
    /// au hasard.
    private var boutonDePartage: some View {
        let note = ligneCourante
        let partageable = note?.visibility == .private
        return Button {
            if let note { CollaboratorNotePrivacy.shareLine(note, in: context) }
        } label: {
            Pill(CollaboratorSessionModel.shareLinePill,
                 ton: partageable ? .oneOnOne : .neutre,
                 bordee: true)
        }
        .buttonStyle(.plain)
        .disabled(!partageable)
        .help(aideDuPartage(note))
    }

    private func aideDuPartage(_ note: MeetingNote?) -> String {
        guard let note else {
            return "Cliquez une ligne ci-dessous pour la désigner, puis partagez-la"
        }
        switch note.visibility {
        case .private:
            return "Rendre cette ligne — et elle seule — visible de votre manager"
        case .shared:
            return "Cette ligne est déjà partagée"
        case .escalated:
            return "Une ligne escaladée ne redescend pas vers votre manager"
        }
    }

    private var separateur: some View {
        Rectangle().fill(One2OneToken.hair).frame(height: 1)
    }

    // MARK: - Composeur

    /// `Écrire… /promesse /demande /preuve` (capture 5a).
    ///
    /// La section vient du titre cliqué : c'est elle qui décide de l'auteur de
    /// la ligne (`NoteCommandParser.parseOneOnOne`), donc de la section où elle
    /// s'affichera. `/promesse` reste côté manager quoi qu'il arrive — c'est
    /// *lui* qui a promis (spec §6.2), et le parseur le fige.
    private var composeur: some View {
        let contexte = OneOnOneComposerContext(thread: thread,
                                               role: .collaborator,
                                               section: section,
                                               defaultVisibility: CollaboratorNotePrivacy
                                                   .defaultVisibility)
        return NoteComposer(meeting: meeting,
                            screen: screen,
                            commands: contexte.commands,
                            oneOnOne: contexte,
                            placeholder: CollaboratorSessionModel.composerPlaceholder)
    }

    private func rafraichirMarqueurs() {
        screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
        if screen.playhead.duration <= 0 {
            screen.playhead.duration = Double(meeting.durationSeconds)
        }
    }
}
