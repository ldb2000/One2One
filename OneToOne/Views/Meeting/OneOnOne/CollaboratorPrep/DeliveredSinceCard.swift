import SwiftUI
import SwiftData

/// `CE QUE J'AI LIVRÉ DEPUIS` (capture 5b, deuxième bloc) : les lignes que
/// personne n'a saisies.
///
/// La même liste que la carte de séance du lot 13, le même
/// `DeliveredItemsBuilder`, la même borne — **sans le bouton `Citer`**. Une
/// préparation n'a pas de notes où insérer une preuve : la séance n'a pas
/// commencé, et un bouton qui écrirait dans les notes de l'entretien à venir
/// horodaterait une preuve avant l'entretien.
///
/// Sans case à cocher non plus : ces lignes ne se portent pas à l'ordre du
/// jour. Elles sont ce que j'ai à répondre quand on me demandera où j'en suis.
struct DeliveredSinceCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    /// Réunions connues — celles où j'ai eu un rôle actif entrent dans la
    /// liste.
    let historique: [Meeting]
    /// L'instant de référence : l'ouverture de l'écran. La fenêtre va du
    /// dernier point à **maintenant**, et non à la date de la séance : on
    /// prépare avant, et ce qui est clos ce matin compte.
    let now: Date

    /// Toutes les actions : le filtre « les miennes »
    /// (`destinataire == .moi && collaborator == nil`) est fait par le
    /// constructeur, pour qu'aucun appelant ne puisse l'oublier.
    @Query private var toutesLesActions: [ActionTask]

    private var lignes: [DeliveredItemsBuilder.Item] {
        DeliveredItemsBuilder.build(actions: toutesLesActions,
                                    meetings: historique,
                                    since: CollabPrepModel.deliveredSince(meeting, in: thread),
                                    now: now)
    }

    var body: some View {
        RefonteCard {
            VStack(alignment: .leading, spacing: 9) {
                Text(CollabPrepModel.deliveredTitle)
                    .sectionLabel()
                    // Le vert de la capture : c'est la seule carte de l'écran
                    // qui porte de bonnes nouvelles.
                    .foregroundStyle(One2OneToken.okDeep)
                    .help("Reprise de vos actions closes et de vos réunions — "
                          + "personne ne l'a saisie")

                let lignes = lignes
                if lignes.isEmpty {
                    Text(CollabPrepModel.deliveredEmptyInvite)
                        .font(.plexSans(11.5))
                        .foregroundStyle(One2OneToken.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(lignes) { ligne in
                            self.ligne(ligne)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `✓ Nexus repris · 29 août`, `◐ Clustering en recette · bloqué par les
    /// comptes GitLab`. Le détail suit le libellé sur la **même ligne**, comme
    /// la capture : la carte de préparation tient en deux minutes, et un détail
    /// sur deux lignes doublerait sa hauteur.
    private func ligne(_ item: DeliveredItemsBuilder.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(item.symbol)
                .font(.plexSans(12, .semibold))
                .foregroundStyle(item.status == .blocked ? One2OneToken.warn : One2OneToken.ok)
            Text(item.text)
                .font(.plexSans(12.5))
                .foregroundStyle(One2OneToken.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text("· \(item.detail)")
                .font(.plexSans(11.5))
                .foregroundStyle(item.status == .blocked
                                 ? One2OneToken.warnInk
                                 : One2OneToken.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
