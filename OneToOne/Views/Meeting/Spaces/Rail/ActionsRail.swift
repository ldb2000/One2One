import SwiftUI
import SwiftData

/// Le rail d'actions **permanent** de 330 px (spec §2.5, capture
/// `1a-cockpit.png`, colonne de droite).
///
/// « Trois onglets : `Actions n` / `Risques n` / `Historique`. » Le composeur
/// du pied est **toujours** visible, y compris sur les onglets Risques et
/// Historique : c'est la seule surface qui promette qu'une intention dite en
/// séance ne se perd pas, et la faire disparaître à chaque changement d'onglet
/// en ferait une surface conditionnelle.
///
/// **Le rail n'affiche que la liste** — retour d'usage du 2026-09-08, qui
/// **amende la décision D10**. La rangée `Liste / Calendrier / Eisenhower` que
/// montre la capture `1a-cockpit.png` a été retirée : en séance, on lit une
/// liste et on assigne, on ne consulte pas une matrice d'Eisenhower dans 330 px.
/// Ce qui a servi à la construire reste en place et sert ailleurs :
/// `ActionsViewMode.railCases` et la persistance `MeetingScreenModel.railViewMode`
/// (les cinq vues de `ActionsListView`), et le rendu compact de `CalendarBoard`
/// et `EisenhowerBoard` (le mode Relire les affiche en colonne principale).
///
/// Le rail ne connaît ni sa largeur ni sa place : `MeetingSpaceView` la lui
/// donne, calculée par `MeetingSpaceLayout.columns` — c'est le seul endroit qui
/// sait si la fenêtre peut tenir 330 px sans rogner la colonne fluide sous son
/// plancher (critère d'acceptation n° 5).
///
/// Remplace `ActionsPanel` dans l'espace Réunion. L'ancien panneau, que seul
/// le dashboard montait encore, a été retiré du dépôt au lot 19 (décision D8).
struct ActionsRail: View {

    /// Le libellé d'un onglet : titre de carte de §1.2 (600 · 11,5 → 12 px).
    static let tabLabelSize: CGFloat = 11.5
    /// Le compteur qui le suit : pilule de §1.2 (500 · 10 → 10,5 px).
    static let tabCountSize: CGFloat = 10.5

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let allCollaborators: [Collaborator]
    /// Replace la tête de lecture sur la source d'une action.
    let onSeek: ((Double) -> Void)?

    @Environment(\.modelContext) private var context

    /// Le nombre d'actions **ouvertes** : c'est celui de l'onglet, et c'est
    /// exactement ce que la liste en dessous affiche. La définition vient de
    /// `MeetingActionCounts` — une action en attente de suppression n'est plus
    /// comptée, même avant le `save()`.
    private var nombreDActions: Int {
        MeetingActionCounts.compute(meeting: meeting).ouvertes
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
                    .font(.plexSans(Self.tabLabelSize, actif ? .semibold : .regular))
                    .foregroundStyle(actif ? One2OneToken.ink1 : One2OneToken.ink4)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let compte = compteur(onglet), compte > 0 {
                    Text("\(compte)")
                        .font(.plexSans(Self.tabCountSize, .medium))
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

    // MARK: - Corps

    @ViewBuilder
    private var corps: some View {
        switch screen.railTab {
        case .actions:
            // Une seule vue, sans sélecteur : le rail est une liste (D10
            // amendée le 2026-09-08).
            ActionsRailList(meeting: meeting,
                            allCollaborators: allCollaborators,
                            onSeek: onSeek,
                            onToggle: basculer,
                            onSave: enregistrer)
        case .risques:
            ActionsRailRisks(meeting: meeting, onSave: enregistrer)
        case .historique:
            ActionsRailHistory(meeting: meeting)
        }
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

    /// L'action neuve doit être visible : si le rail était sur l'onglet Risques
    /// ou Historique, on revient sur Actions. Sans cela, `⌘⏎` donnerait
    /// l'impression de n'avoir rien fait.
    ///
    /// Ne touche plus à `screen.railViewMode` : le rail ne s'en sert pas, et le
    /// remettre sur Liste depuis ici changerait la vue mémorisée d'un écran
    /// qu'on ne regarde même pas.
    private func apresCreation(_ task: ActionTask) {
        if screen.railTab != .actions { screen.railTab = .actions }
    }
}
