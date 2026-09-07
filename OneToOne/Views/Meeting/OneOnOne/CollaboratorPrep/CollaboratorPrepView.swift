import SwiftUI
import SwiftData

/// L'écran de **préparation en deux minutes** d'un tête-à-tête subi
/// (`5b-1to1-collaborateur-preparation.png`, spec §6.3).
///
/// « L'écran qui s'ouvre la veille : ce qui est resté sans réponse, ce que j'ai
/// livré, ce que je dois demander. Un bouton pour transformer la liste en ordre
/// du jour. » C'est le mode `Préparer` du type `.manager`, et le mode
/// d'ouverture par défaut d'un entretien subi sans enregistrement
/// (`MeetingSpaceRouting.initialMode`).
///
/// **Une carte étroite, centrée, et rien d'autre** : ni rail d'actions de
/// 330 px, ni bandeau d'indicateurs (rien n'a encore été dit), ni barre
/// d'assistant. Deux minutes veut dire dix lignes qu'on lit d'un coup d'œil ;
/// une colonne de plus, et l'écran devient un tableau de bord qu'on remet à
/// plus tard.
///
/// La vue **n'assemble que des modèles purs** : `CollabPrepModel`,
/// `UnansweredItemsBuilder`, `WantedItemsBuilder`, `DeliveredItemsBuilder`,
/// `PrepToAgenda`. Chacun est testé sans écran, et c'est là que vit le critère
/// chantier 5 n° 4 — une promesse du manager non tenue remonte
/// automatiquement.
struct CollaboratorPrepView: View {

    /// La largeur de la carte (capture 5b : ~940 px). Au-delà, les lignes
    /// deviennent des lignes de texte de 120 caractères qu'on ne lit plus en
    /// deux minutes.
    static let cardMaxWidth: CGFloat = 940

    let meeting: Meeting
    let screen: MeetingScreenModel
    /// Réunions connues, pour `CE QUE J'AI LIVRÉ DEPUIS`.
    let historique: [Meeting]

    @Environment(\.modelContext) private var context

    /// Le fil, résolu **hors du rendu** : `OneOnOneThreadStore.thread(for:in:)`
    /// crée le fil paresseusement (D3), donc écrit en base. L'appeler depuis
    /// `body` insérerait pendant un cycle d'affichage.
    @State private var thread: OneOnOneThread?
    /// L'instant de référence, figé à l'apparition : un `Date()` lu dans `body`
    /// ferait basculer « demain 14:00 » en « aujourd'hui 14:00 » au milieu d'un
    /// rendu.
    @State private var now = Date()
    /// Rejoué à chaque écriture : les modèles sont purs, ils ne s'invalident
    /// pas seuls.
    @State private var revision = 0
    @State private var demandeConfirmationDePartage = false

    var body: some View {
        ScrollView {
            if let fil = thread {
                carte(fil)
                    .frame(maxWidth: Self.cardMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            } else {
                MeetingEmptyInvite(titre: CollabPrepModel.noThreadTitle,
                                   invite: CollabPrepModel.noThreadInvite)
                    .padding(.top, 40)
            }
        }
        .background(One2OneToken.bgCanvas)
        .onAppear {
            now = Date()
            thread = OneOnOneThreadStore.thread(for: meeting, in: context)
        }
    }

    // MARK: - La carte

    private func carte(_ fil: OneOnOneThread) -> some View {
        let suspens = UnansweredItemsBuilder.build(fil, now: now)
        let voulus = WantedItemsBuilder.build(fil, excluding: suspens)
        let plan = planCourant(suspens: suspens, voulus: voulus)

        return VStack(spacing: 0) {
            CollabPrepHeader(model: CollabPrepModel.header(meeting: meeting,
                                                           thread: fil, now: now))
            VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
                UnansweredCard(items: suspens,
                               checked: screen.oneOnOne.collabPrepCheckedUnanswered,
                               onToggle: basculerSuspens)
                DeliveredSinceCard(meeting: meeting, thread: fil,
                                   historique: historique, now: now)
                WantedCard(items: voulus,
                           dropped: screen.oneOnOne.collabPrepDroppedWanted,
                           onToggle: basculerVoulu,
                           onAdd: { ajouter($0, dans: fil) })
                actions(fil, plan: plan)
                Text(CollabPrepModel.provenance)
                    .font(.plexSans(11))
                    .foregroundStyle(One2OneToken.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .fill(One2OneToken.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous)
                .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
        )
        // Le bandeau d'en-tête est plein bord : sans découpe, son violet
        // dépasserait des quatre coins arrondis de la carte.
        .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusCard, style: .continuous))
        // Un seul jeton de rafraîchissement pour toute la carte : une écriture
        // SwiftData faite depuis une closure n'invalide pas toujours la vue qui
        // l'a déclenchée.
        .id(revision)
    }

    // MARK: - Les deux boutons

    @ViewBuilder
    private func actions(_ fil: OneOnOneThread, plan: [PrepToAgenda.Line]) -> some View {
        let verse = PrepToAgenda.isApplied(plan, in: fil)
        let partage = PrepToAgenda.isShared(plan, in: fil)

        HStack(spacing: 9) {
            boutonPrimaire(verse
                           ? PrepToAgenda.doneLabel(plan.count)
                           : PrepToAgenda.agendaButtonLabel) {
                PrepToAgenda.apply(plan, for: meeting, in: fil, in: context)
                revision += 1
            }
            .disabled(verse)
            .opacity(verse ? 0.55 : 1)
            .help(verse
                  ? "Ces sujets sont déjà à l'ordre du jour de l'entretien"
                  : "Créer les sujets privés correspondants, dans cet ordre")

            boutonSecondaire(partage
                             ? PrepToAgenda.sharedLabel(plan.count)
                             : PrepToAgenda.shareButtonLabel(for: fil)) {
                demandeConfirmationDePartage = true
            }
            .disabled(plan.isEmpty || partage)
            .opacity(plan.isEmpty || partage ? 0.55 : 1)
            .help("Rendre ces sujets visibles de votre manager — un geste explicite, "
                  + "ligne par ligne sinon")

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        // La confirmation légère de la spec : le **compte** des sujets, la
        // seule chose qu'on veut relire avant de rendre visible ce qu'on avait
        // écrit pour soi (critère chantier 5 n° 2).
        .confirmationDialog(PrepToAgenda.shareConfirmation(plan.count),
                            isPresented: $demandeConfirmationDePartage,
                            titleVisibility: .visible) {
            Button(PrepToAgenda.shareConfirmButton) {
                PrepToAgenda.share(plan, for: meeting, in: fil, in: context)
                revision += 1
            }
            Button(PrepToAgenda.shareCancelButton, role: .cancel) {}
        } message: {
            Text(CollabPrepModel.provenance)
        }
    }

    private func boutonPrimaire(_ titre: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(12, .semibold))
                .foregroundStyle(One2OneToken.onFilledButton)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                     style: .continuous)
                        .fill(One2OneToken.oneOnOne)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func boutonSecondaire(_ titre: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.plexSans(12, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                     style: .continuous)
                        .fill(One2OneToken.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: One2OneToken.radiusButton,
                                     style: .continuous)
                        .strokeBorder(One2OneToken.strongBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - État des cases

    /// Le plan que les cases décrivent à cet instant : les lignes sans réponse
    /// **cochées**, puis les sujets voulus qui n'ont pas été décochés.
    private func planCourant(suspens: [UnansweredItemsBuilder.Item],
                             voulus: [OneOnOneAgendaItem]) -> [PrepToAgenda.Line] {
        let coches = screen.oneOnOne.collabPrepCheckedUnanswered
        let refuses = screen.oneOnOne.collabPrepDroppedWanted
        return PrepToAgenda.plan(
            unanswered: suspens.filter { coches.contains($0.id) },
            wanted: voulus.filter { !refuses.contains($0.persistentModelID) })
    }

    private func basculerSuspens(_ id: String) {
        if screen.oneOnOne.collabPrepCheckedUnanswered.contains(id) {
            screen.oneOnOne.collabPrepCheckedUnanswered.remove(id)
        } else {
            screen.oneOnOne.collabPrepCheckedUnanswered.insert(id)
        }
    }

    private func basculerVoulu(_ id: PersistentIdentifier) {
        if screen.oneOnOne.collabPrepDroppedWanted.contains(id) {
            screen.oneOnOne.collabPrepDroppedWanted.remove(id)
        } else {
            screen.oneOnOne.collabPrepDroppedWanted.insert(id)
        }
    }

    /// Le composeur `Ajouter…`. Le sujet naît **coché** : l'ensemble d'état ne
    /// retient que les refus, donc il n'y a rien à y écrire.
    private func ajouter(_ texte: String, dans fil: OneOnOneThread) -> Bool {
        guard CollaboratorPrepStore.addWantedTopic(text: texte, for: meeting,
                                                   in: fil, in: context) != nil
        else { return false }
        revision += 1
        return true
    }
}
