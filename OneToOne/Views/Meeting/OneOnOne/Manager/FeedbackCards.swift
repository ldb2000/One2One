import SwiftUI

/// `③ FEEDBACK — DANS LES DEUX SENS` : deux cartes côte à côte,
/// `CE QUE JE LUI DIS` et `CE QU'IL ME DIT` (capture 2a, spec §3.3).
///
/// Les deux sont **obligatoires pour marquer le 1:1 « complet »**, et
/// l'indicateur n'est pas bloquant : rien n'empêche de clore un entretien sans
/// feedback, l'écran le signale simplement quand les deux y sont.
///
/// Une carte vide porte son invite : c'est la section la plus souvent oubliée,
/// et un cadre muet ne rappelle rien.
struct FeedbackCards: View {

    let meeting: Meeting
    /// Bascule la carte où le composeur écrira la prochaine ligne
    /// `/feedback` — c'est la section, et non la commande, qui dit qui parle.
    @Binding var section: NoteCommandParser.FeedbackSection

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SectionLabel(OneOnOneNoteSections.Section.feedback.label)
                if let complet = OneOnOneNoteSections.completenessLabel(meeting) {
                    Pill(complet, ton: .ok)
                        .help("Les deux sens sont renseignés")
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: One2OneToken.cardGap) {
                carte(.given)
                carte(.received)
            }
        }
    }

    private func carte(_ carte: NoteCommandParser.FeedbackSection) -> some View {
        let notes = OneOnOneNoteSections.feedback(meeting, carte)
        let active = section == carte
        return Button {
            section = carte
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(OneOnOneNoteSections.cardLabel(carte))
                if notes.isEmpty {
                    Text(OneOnOneNoteSections.feedbackEmptyInvite(for: carte))
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(notes, id: \.persistentModelID) { note in
                        Text(note.text)
                            .font(.plexSans(12))
                            .foregroundStyle(One2OneToken.ink2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(One2OneToken.cardPaddingMax)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    .fill(One2OneToken.surfaceAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                    // La carte active est bordée : c'est là que la prochaine
                    // ligne `/feedback` ira, et il faut le voir avant de taper.
                    .strokeBorder(active ? One2OneToken.oneOnOne : One2OneToken.cardBorder,
                                  lineWidth: active ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(active
              ? "Le composeur écrit dans cette carte"
              : "Écrire le prochain /feedback dans cette carte")
    }
}
