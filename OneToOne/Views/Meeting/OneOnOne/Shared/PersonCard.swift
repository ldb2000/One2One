import SwiftUI

/// La carte personne en tête de la colonne gauche du 1:1 (capture 2a) :
/// avatar 34 px, nom, rôle · ancienneté, puis les deux métriques
/// `DERNIER 1:1` et `RYTHME`.
///
/// Tous les libellés viennent de `PersonCardModel`, qui est pur et testé : la
/// vue ne calcule rien. Partagée (`Shared/`) — la capture 2b porte le même
/// en-tête, en plus large.
struct PersonCard: View {

    let thread: OneOnOneThread
    /// L'instant de référence des deux métriques. Injecté : les tests et le
    /// jeu de démonstration se placent au 4 septembre 2026.
    var now: Date = Date()

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AvatarSide(initials: PersonCardModel.initials(of: thread),
                               identity: PersonCardModel.name(of: thread),
                               diametre: AvatarSide.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PersonCardModel.name(of: thread))
                            .font(.plexSans(13.5, .semibold))
                            .foregroundStyle(One2OneToken.ink1)
                            .lineLimit(1)
                        Text(PersonCardModel.roleLine(of: thread, now: now))
                            .font(.plexSans(11.5))
                            .foregroundStyle(One2OneToken.ink4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 12) {
                    metrique(PersonCardModel.lastMeetingTitle,
                             PersonCardModel.lastMeetingLabel(of: thread, now: now))
                    metrique(PersonCardModel.rhythmTitle,
                             PersonCardModel.rhythmLabel(of: thread))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func metrique(_ titre: String, _ valeur: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(titre)
            Text(valeur)
                .font(.plexSans(11.5))
                .foregroundStyle(One2OneToken.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
