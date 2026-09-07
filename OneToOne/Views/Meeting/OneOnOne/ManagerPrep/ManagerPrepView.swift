import SwiftUI
import SwiftData

/// L'écran de **préparation** d'un tête-à-tête côté manager
/// (`2b-1to1-manager-preparation.png`, spec §3.4).
///
/// « La même séance vue comme une trajectoire : moral dans le temps, objectifs,
/// promesses tenues ou non. » C'est le mode `Préparer` du type `.oneToOne`, et
/// il **remplace** la colonne principale du mode Préparer générique : ni
/// bandeau d'indicateurs (rien n'a encore été dit), ni rail d'actions de 330 px
/// (un 1:1 n'a pas de tableau d'actions multi-projets — spec §3.1 retire les
/// projets affectés et les vues Kanban).
///
/// La vue **n'assemble que des modèles purs** : `PrepHeaderModel`,
/// `MoodHistogramModel`, `ObjectivesCardModel`, `PrepRemindersModel`,
/// `CommitmentsTableModel`, `RecurringTopicsCardModel`, `ThreadHistoryModel`.
/// Chacun est testé sans écran, et c'est là que vivent les critères
/// d'acceptation — en particulier le n° 3 du chantier 2 (le moral saisi en
/// séance alimente immédiatement l'histogramme).
struct ManagerPrepView: View {

    /// Largeur de la colonne de droite (sujets récurrents, historique,
    /// assistant) : le rail 1:1 de la spec §1.2.
    static let sideColumnWidth: CGFloat = One2OneToken.oneOnOneRailNarrow

    /// La suggestion de la barre d'assistant, au mot de la capture.
    static let assistantSuggestion = "« Qu'a-t-il demandé sans réponse depuis juin ? »"

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    /// Réunions connues, pour la barre d'assistant.
    let historique: [Meeting]
    /// Les actions de la réunion : `Démarrer l'entretien` passe par
    /// `startRecording`, la source de vérité déjà partagée par le menu `⋯` et
    /// les menus natifs. La vue ne parle pas à `AudioRecorderService`.
    let menuActions: MeetingMenuActions
    @Binding var isAssistantOpen: Bool
    /// Ouvre une séance de l'historique.
    let onOpenMeeting: (PersistentIdentifier) -> Void

    @Environment(\.modelContext) private var context

    /// Le fil, résolu **hors du rendu** : `OneOnOneThreadStore.thread(for:in:)`
    /// crée le fil paresseusement (D3), donc écrit en base. L'appeler depuis
    /// `body` insérerait pendant un cycle d'affichage.
    @State private var thread: OneOnOneThread?
    /// Rejoué à chaque apparition et à chaque écriture, pour que les cartes se
    /// recalculent : les modèles sont purs, ils ne s'invalident pas seuls.
    @State private var revision = 0

    /// L'instant de référence des calculs. Figé à l'apparition : un `Date()`
    /// lu dans `body` ferait basculer une échéance « Vendredi » en
    /// « En retard » au milieu d'un rendu.
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let fil = thread {
                    PrepHeader(model: PrepHeaderModel.build(meeting: meeting, thread: fil),
                               onShowHistory: { screen.oneOnOne.prepHistoryExpanded.toggle() },
                               onStart: demarrerLEntretien,
                               isStartDisabled: !menuActions.isEnabled(.startStopRecording))
                    contenu(fil)
                        .padding(14)
                } else {
                    MeetingEmptyInvite(
                        titre: "Aucun interlocuteur",
                        invite: "Ajoutez la personne du tête-à-tête aux participants : "
                              + "le fil, les engagements et le moral se rattachent à elle."
                    )
                    .padding(.top, 40)
                }
            }
        }
        .background(One2OneToken.bgCanvas)
        .onAppear {
            now = Date()
            thread = OneOnOneThreadStore.thread(for: meeting, in: context)
        }
    }

    // MARK: - Disposition

    @ViewBuilder
    private func contenu(_ fil: OneOnOneThread) -> some View {
        VStack(alignment: .leading, spacing: One2OneToken.cardGap) {
            // Rangée 1 : trois cartes de largeur égale (capture 2b).
            HStack(alignment: .top, spacing: One2OneToken.cardGap) {
                MoodHistogram(model: MoodHistogramModel.build(fil, now: now))
                    .frame(maxWidth: .infinity)
                ObjectivesCard(model: ObjectivesCardModel.build(fil),
                               onAdd: { libelle, pourcentage in
                                   OneOnOnePrepStore.addObjective(label: libelle,
                                                                  progress: pourcentage,
                                                                  in: fil, in: context)
                                   revision += 1
                               },
                               onUpdateProgress: { id, pourcentage in
                                   guard let objectif = objectif(id, in: fil) else { return }
                                   OneOnOnePrepStore.update(objectif, progress: pourcentage,
                                                            in: context)
                                   revision += 1
                               },
                               onUpdateLabel: { id, libelle in
                                   guard let objectif = objectif(id, in: fil) else { return }
                                   OneOnOnePrepStore.update(objectif, label: libelle,
                                                            in: context)
                                   revision += 1
                               })
                    .frame(maxWidth: .infinity)
                RemindersCard(model: PrepRemindersModel.build(fil, now: now),
                              onFillAgenda: { mettreALOrdreDuJour(fil) })
                    .frame(maxWidth: .infinity)
            }
            .id(revision)

            // Rangée 2 : le tableau des engagements, puis la colonne de droite.
            HStack(alignment: .top, spacing: One2OneToken.cardGap) {
                CommitmentsTable(model: CommitmentsTableModel.build(fil,
                                                                    current: meeting,
                                                                    filter: filtre.wrappedValue,
                                                                    now: now),
                                 filter: filtre,
                                 onToggleState: { id in
                                     guard let engagement = engagement(id, in: fil) else { return }
                                     OneOnOnePrepStore.toggleKept(engagement, in: context)
                                     revision += 1
                                 },
                                 onCreate: { texte in
                                     OneOnOnePrepStore.addCommitment(text: texte,
                                                                     ownerSide: .manager,
                                                                     in: fil, in: context)
                                     revision += 1
                                 })
                    .frame(maxWidth: .infinity, alignment: .top)
                    .id(revision)

                VStack(spacing: One2OneToken.cardGap) {
                    RecurringTopicsCard(model: RecurringTopicsCardModel.build(fil, now: now))
                    ThreadHistoryCard(
                        model: ThreadHistoryModel.build(
                            fil,
                            current: meeting,
                            now: now,
                            limit: screen.oneOnOne.prepHistoryExpanded
                                ? Int.max
                                : ThreadHistoryModel.visibleCount),
                        isExpanded: screen.oneOnOne.prepHistoryExpanded,
                        onOpenMeeting: onOpenMeeting)
                    MeetingAssistantDock(meeting: meeting,
                                         historique: historique,
                                         isOpen: $isAssistantOpen,
                                         threadContext: contexteAssistant(fil))
                }
                .frame(width: Self.sideColumnWidth)
                .id(revision)
            }
        }
    }

    // MARK: - Actions

    /// Le filtre du tableau, adossé à l'état d'écran du lot 10
    /// (`OneOnOneScreenState.commitmentSideFilter`) : le segment choisi survit
    /// à un aller-retour vers la séance, mais pas à la fermeture de l'écran.
    private var filtre: Binding<PrepCommitmentFilter> {
        Binding(
            get: {
                switch screen.oneOnOne.commitmentSideFilter {
                case .none:               return .both
                case .some(.manager):     return .mine
                case .some(.collaborator): return .theirs
                }
            },
            set: { screen.oneOnOne.commitmentSideFilter = $0.side }
        )
    }

    /// `Démarrer l'entretien` : passe en séance **et** lance l'enregistrement.
    ///
    /// Les deux, parce que c'est ce que le bouton promet. Le mode d'abord :
    /// l'écran de séance doit être en place quand la première seconde
    /// d'audio est horodatée, sinon la note posée dans les instants qui
    /// suivent l'est à zéro.
    private func demarrerLEntretien() {
        screen.mode = .live
        guard !menuActions.isRecording else { return }
        menuActions.startRecording()
    }

    private func mettreALOrdreDuJour(_ fil: OneOnOneThread) {
        let rappels = ReminderRules.reminders(for: fil, now: now)
        ReminderRules.toAgendaItems(rappels, for: fil, role: fil.myRole, in: context)
        revision += 1
    }

    /// Le contexte du fil pour la barre d'assistant. Même type que la séance
    /// (capture 2a) depuis l'intégration de la vague 5 : seule la question
    /// change, et le `threadID` accompagne les deux.
    private func contexteAssistant(_ fil: OneOnOneThread) -> MeetingAssistantDock.ThreadContext {
        MeetingAssistantDock.ThreadContext(
            placeholder: Self.assistantSuggestion,
            threadName: OneOnOneThreadStore.firstName(of: fil),
            threadID: fil.ensuredStableID
        )
    }

    private func objectif(_ id: PersistentIdentifier,
                          in fil: OneOnOneThread) -> OneOnOneObjective? {
        fil.objectives.first { $0.persistentModelID == id }
    }

    private func engagement(_ id: PersistentIdentifier,
                            in fil: OneOnOneThread) -> Commitment? {
        fil.commitments.first { $0.persistentModelID == id }
    }
}
