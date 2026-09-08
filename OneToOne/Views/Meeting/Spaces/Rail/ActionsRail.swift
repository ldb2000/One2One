import SwiftUI
import SwiftData

/// Le rail d'actions **permanent** de 330 px (spec §2.5, capture
/// `1a-cockpit.png`, colonne de droite).
///
/// « Trois onglets : `Actions n` / `Risques n` / `Historique`. Vues d'actions :
/// **Liste** · **Calendrier** · **Eisenhower** (Kanban et Post-it supprimés du
/// contexte réunion). » Le composeur du pied est **toujours** visible, y
/// compris sur les onglets Risques et Historique : c'est la seule surface qui
/// promette qu'une intention dite en séance ne se perd pas, et la faire
/// disparaître à chaque changement d'onglet en ferait une surface
/// conditionnelle.
///
/// Le rail ne connaît ni sa largeur ni sa place : `MeetingSpaceView` la lui
/// donne, calculée par `MeetingSpaceLayout.columns` — c'est le seul endroit qui
/// sait si la fenêtre peut tenir 330 px sans rogner la colonne fluide sous son
/// plancher (critère d'acceptation n° 5).
///
/// Remplace `ActionsPanel` dans l'espace Réunion. L'ancien panneau reste dans
/// le dépôt pour `OverviewDashboard`, retiré au lot 19 (décision D8).
struct ActionsRail: View {

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let allCollaborators: [Collaborator]
    /// Replace la tête de lecture sur la source d'une action.
    let onSeek: ((Double) -> Void)?
    /// Rail « réduit » du mode Préparer (spec §2.2) : le sélecteur de vue
    /// disparaît, on ne prépare pas une séance en matrice d'Eisenhower.
    var reduit: Bool = false

    @Environment(\.modelContext) private var context

    /// Le nombre d'actions **ouvertes** : c'est celui de l'onglet.
    private var nombreDActions: Int {
        meeting.tasks.filter { $0.status == .open }.count
    }

    /// Le nombre de risques ouverts, réunion et projet confondus, sans
    /// doublon — le même que la carte RISQUES du bandeau.
    private var nombreDeRisques: Int {
        let deLaReunion = meeting.meetingAlerts.filter { !$0.isResolved }
        let dejaListes = Set(deLaReunion.map(\.persistentModelID))
        let duProjet = (meeting.project?.alerts ?? [])
            .filter { !$0.isResolved && !dejaListes.contains($0.persistentModelID) }
        return deLaReunion.count + duProjet.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            onglets
            if screen.railTab == .actions && !reduit {
                selecteurDeVue
            }
            Divider().overlay(One2OneToken.hair)
            ScrollView {
                corps
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            ActionComposer(meeting: meeting, screen: screen, onCreated: apresCreation)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(One2OneToken.surface)
    }

    // MARK: - Onglets

    private var onglets: some View {
        HStack(spacing: 4) {
            ForEach(MeetingScreenModel.RailTab.allCases, id: \.self) { onglet in
                ongletBouton(onglet)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    /// L'onglet actif est un fond gris clair arrondi (capture 1a), pas un
    /// soulignement : le soulignement `accent/report` est réservé à la barre
    /// d'espaces, et deux soulignements sur le même écran ne se hiérarchisent
    /// plus.
    @ViewBuilder
    private func ongletBouton(_ onglet: MeetingScreenModel.RailTab) -> some View {
        let actif = screen.railTab == onglet
        Button {
            screen.railTab = onglet
        } label: {
            HStack(spacing: 5) {
                Text(onglet.label)
                    .font(.plexSans(11.5, actif ? .semibold : .regular))
                    .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink4)
                if let compte = compteur(onglet), compte > 0 {
                    Text("\(compte)")
                        .font(.plexSans(10.5, .medium))
                        .foregroundStyle(onglet == .risques ? One2OneToken.report : One2OneToken.ink4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: One2OneToken.radiusButton, style: .continuous)
                    .fill(actif ? One2OneToken.bgApp : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(actif ? [.isSelected] : [])
    }

    /// Le compteur d'un onglet, `nil` pour l'Historique : un nombre d'entrées
    /// passées ne réclame rien, et un badge qui ne réclame rien est du bruit.
    private func compteur(_ onglet: MeetingScreenModel.RailTab) -> Int? {
        switch onglet {
        case .actions:    return nombreDActions
        case .risques:    return nombreDeRisques
        case .historique: return nil
        }
    }

    // MARK: - Sélecteur de vue

    private var selecteurDeVue: some View {
        HStack(spacing: 0) {
            SegmentedMode(selection: Binding(get: { screen.railViewMode },
                                             set: { screen.railViewMode = $0 }),
                          options: ActionsViewMode.railCases,
                          libelle: { $0.label })
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Corps

    @ViewBuilder
    private var corps: some View {
        switch screen.railTab {
        case .actions:
            switch reduit ? .liste : screen.railViewMode {
            case .liste, .kanban, .sticky:
                // Kanban et Post-it n'existent pas dans le rail (spec §2.5) ;
                // une valeur mémorisée d'un ancien réglage retombe sur Liste
                // plutôt que sur un écran vide.
                ActionsRailList(meeting: meeting,
                                allCollaborators: allCollaborators,
                                onSeek: onSeek,
                                onToggle: basculer,
                                onSave: enregistrer)
            case .calendar:
                CalendarBoard(tasks: actionsOuvertes, onToggle: basculer, compact: true)
                    .padding(10)
            case .eisenhower:
                EisenhowerBoard(tasks: actionsOuvertes, onToggle: basculer, compact: true)
                    .padding(10)
            }
        case .risques:
            ActionsRailRisks(meeting: meeting, onSave: enregistrer)
        case .historique:
            ActionsRailHistory(meeting: meeting)
        }
    }

    private var actionsOuvertes: [ActionTask] {
        meeting.tasks.filter { $0.status == .open }
    }

    // MARK: - Actions

    private func basculer(_ task: ActionTask) {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil
        enregistrer()
    }

    private func enregistrer() {
        try? context.save()
    }

    /// L'action neuve doit être visible : si le rail était sur un autre onglet
    /// ou une autre vue, on revient là où elle apparaît. Sans cela, `⌘⏎`
    /// donnerait l'impression de n'avoir rien fait.
    private func apresCreation(_ task: ActionTask) {
        if screen.railTab != .actions { screen.railTab = .actions }
        if screen.railViewMode != .liste { screen.railViewMode = .liste }
    }
}
