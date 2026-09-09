import SwiftUI

/// L'onglet « Pilotage » de l'écran projet (capture
/// `1d-ecran-projet-pilotage.png`) : deux colonnes, `1fr` et 330 pt, écart 16,
/// marges 16 / 22 / 22.
///
/// **Il n'assemble que des cartes.** Rien n'est calculé ici : tout vient de
/// `ProjectPilotageState`, construit une fois par `ProjectScreen` (D11), et
/// chaque geste remonte à `ProjectScreen`, qui tient le brouillon et la
/// bannière d'annulation.
struct PilotageTab: View {

    // MARK: - Mesures du handoff §1d

    static let ecartColonnes: CGFloat = 16
    static let margeH: CGFloat = 22
    static let margeHaute: CGFloat = 16
    static let margeBasse: CGFloat = 22

    let etat: ProjectPilotageState
    let collaborateurs: [Collaborator]
    let suggestions: [String: Collaborator]

    let onToutVoir: () -> Void
    let onHistorique: () -> Void
    let onCocher: (ProjectPilotageState.ActionRow) -> Void
    let onOuvrirReunion: (ProjectPilotageState.MeetingRow) -> Void
    let onPerimetre: (String) -> Void
    let onOuvrirCollaborateur: (UUID) -> Void
    let onAffecter: (String, Collaborator?) -> Void
    let onSponsor: (String) -> Void
    let onRisque: (String) -> Void
    let onDescriptionDeRisque: (String) -> Void
    let onRattacherLesMails: () -> Void
    let onFicheComplete: () -> Void

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Self.ecartColonnes) {
                colonnePrincipale
                SideColumn(etat: etat,
                           collaborateurs: collaborateurs,
                           suggestions: suggestions,
                           onOuvrirCollaborateur: onOuvrirCollaborateur,
                           onAffecter: onAffecter,
                           onSponsor: onSponsor,
                           onRisque: onRisque,
                           onDescriptionDeRisque: onDescriptionDeRisque,
                           onRattacherLesMails: onRattacherLesMails,
                           onFicheComplete: onFicheComplete)
            }
            .padding(.horizontal, Self.margeH)
            .padding(.top, Self.margeHaute)
            .padding(.bottom, Self.margeBasse)
        }
    }

    private var colonnePrincipale: some View {
        VStack(alignment: .leading, spacing: PilotageMetrics.ecartCartes) {
            KPITiles(etat: etat)
            OpenActionsCard(actions: etat.actions,
                            onToutVoir: onToutVoir,
                            onCocher: onCocher)
            RecentMeetingsCard(meetings: etat.meetings,
                               onHistorique: onHistorique,
                               onOuvrir: onOuvrirReunion)
            ScopeCard(scopeText: etat.scopeText,
                      pied: etat.scopeFooter,
                      onValider: onPerimetre)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
