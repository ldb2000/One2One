import SwiftUI
import SwiftData

/// `CE QUE J'AI LIVRÉ · auto · depuis le 21 août` (capture 5a, colonne droite).
///
/// La carte que le côté manager n'a pas, et le critère chantier 5 n° 3 : la
/// liste se remplit **sans saisie** et chaque ligne se cite en un clic. Un
/// entretien où l'on doit se souvenir de ce qu'on a fait est un entretien qu'on
/// perd.
///
/// Tout le calcul est dans `DeliveredItemsBuilder`, qui est pur et testé : la
/// carte ne fait que rendre et écrire la note de preuve.
struct DeliveredCard: View {

    let meeting: Meeting
    let thread: OneOnOneThread
    /// Réunions connues — celles où j'ai eu un rôle actif entrent dans la liste.
    let historique: [Meeting]
    var now: Date = Date()

    @Environment(\.modelContext) private var context
    /// Toutes les actions : le filtre `destinataire == .moi` est fait par le
    /// constructeur, pour qu'aucun appelant ne puisse l'oublier.
    @Query private var toutesLesActions: [ActionTask]

    /// La borne de la liste : la séance précédente du fil.
    private var depuis: Date? {
        OneOnOneThreadStore.previousMeeting(before: meeting, in: thread)?.date
    }

    private var lignes: [DeliveredItemsBuilder.Item] {
        DeliveredItemsBuilder.build(actions: toutesLesActions,
                                    meetings: historique,
                                    since: depuis,
                                    now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            entete
            let lignes = lignes
            if lignes.isEmpty {
                Text(DeliveredItemsBuilder.emptyInvite)
                    .font(.plexSans(11.5))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(lignes) { ligne in
                    carte(ligne)
                }
            }
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 6) {
            SectionLabel(DeliveredItemsBuilder.title)
            Spacer(minLength: 0)
            Pill("\(DeliveredItemsBuilder.autoBadge) · \(DeliveredItemsBuilder.sinceLabel(depuis))",
                 ton: .ok)
                .help("Reprise de vos actions closes et de vos réunions — personne ne l'a saisie")
        }
    }

    // MARK: - Carte d'une ligne

    private func carte(_ ligne: DeliveredItemsBuilder.Item) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(ligne.symbol)
                .font(.plexSans(11.5, .semibold))
                .foregroundStyle(ligne.status == .blocked
                                 ? One2OneToken.warn
                                 : One2OneToken.ok)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(ligne.text)
                    .font(.plexSans(12))
                    .foregroundStyle(One2OneToken.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ligne.detail)
                    .font(.plexSans(11))
                    .foregroundStyle(ligne.status == .blocked
                                     ? One2OneToken.warnInk
                                     : One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            boutonCiter(ligne)
        }
        .padding(One2OneToken.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                .strokeBorder(ligne.status == .blocked
                              ? One2OneToken.warn.opacity(0.45)
                              : One2OneToken.cardBorder,
                              lineWidth: 1)
        )
    }

    /// `Citer` — insère la ligne dans les notes en `kind: .proof`.
    private func boutonCiter(_ ligne: DeliveredItemsBuilder.Item) -> some View {
        Button {
            citer(ligne)
        } label: {
            Pill(DeliveredItemsBuilder.quoteButtonLabel, ton: .oneOnOne)
        }
        .buttonStyle(.plain)
        .help("Insérer cette preuve dans vos notes, au timecode courant")
    }

    // MARK: - Écriture de la preuve

    /// La note de preuve, au timecode courant.
    ///
    /// `authorSide: .me` : une preuve est ce que **j'ai** posé sur la table, et
    /// elle doit s'afficher sous `CE QUE J'AI DIT` quelle que soit la section
    /// que le composeur avait armée. Écrite directement et non par le
    /// composeur, pour cette raison précise.
    ///
    /// `private`, comme toute ligne de cet écran : c'est à moi de décider, à la
    /// fin, ce qui part dans le récap (critère chantier 5 n° 2).
    ///
    /// `t = 0`, et c'est voulu : une preuve ne cite pas un instant de
    /// l'entretien, elle cite un fait **antérieur** à lui. La replacer au
    /// timecode courant ferait croire que le livrable a été produit là.
    private func citer(_ ligne: DeliveredItemsBuilder.Item) {
        let t: Double = 0
        let note = MeetingNote(t: t,
                               text: DeliveredItemsBuilder.quoteText(ligne),
                               kind: .proof,
                               visibility: CollaboratorNotePrivacy.defaultVisibility,
                               authorSide: .me,
                               orderIndex: MeetingNoteStore.nextOrderIndex(at: t,
                                                                           in: meeting))
        note.sourceRef = ligne.reference
        context.insert(note)
        note.meeting = meeting
        try? context.save()
        NoteIndexingCoordinator.shared.scheduleReindex(meeting: meeting, context: context)
    }
}
