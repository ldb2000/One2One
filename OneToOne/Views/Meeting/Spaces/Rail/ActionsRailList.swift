import SwiftUI
import SwiftData

/// L'onglet `Actions` du rail en vue **Liste** (spec §2.5) : les groupes
/// ordonnés de `ActionsRailGrouping`, en cartes ou en lignes compactes selon
/// le groupe.
///
/// Extraite de `ActionsRail` parce que le mode **Relire** l'affiche aussi, dans
/// sa colonne principale (capture `1c-poste-de-pilotage.png`) où il n'y a pas
/// de rail : le tableau dense à sept colonnes de ce mode arrive au lot 5, et
/// d'ici là c'est la même liste éditable qui sert — pas un second rendu à
/// maintenir en parallèle.
struct ActionsRailList: View {

    @Bindable var meeting: Meeting
    let allCollaborators: [Collaborator]
    /// Replace la tête de lecture sur la source d'une action. `nil` = pas
    /// d'axe temps disponible.
    let onSeek: ((Double) -> Void)?
    let onToggle: (ActionTask) -> Void
    let onSave: () -> Void

    private var groupes: [ActionsRailGrouping.Groupe] {
        ActionsRailGrouping.groupes(for: meeting.tasks)
    }

    /// Les actions du projet, pour la règle du préfixe de titre de
    /// `OwnerSuggestion`. Repli sur celles de la réunion quand elle n'est
    /// rattachée à aucun projet.
    private var actionsDuProjet: [ActionTask] {
        meeting.project?.tasks ?? meeting.tasks
    }

    var body: some View {
        if groupes.isEmpty {
            MeetingEmptyInvite(
                titre: "Aucune action ouverte",
                invite: "Tapez l'action dans le champ ci-dessous, ou créez-la depuis une phrase de la transcription."
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groupes) { groupe in
                    section(groupe)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            // L'animation d'insertion de la spec §2.4 et §2.5 : « l'action
            // apparaît immédiatement en tête du rail avec une animation de
            // 150 ms ». Déclenchée par le nombre d'actions ouvertes, la seule
            // grandeur qui change à la création.
            .animation(.easeOut(duration: 0.15), value: meeting.tasks.count)
        }
    }

    @ViewBuilder
    private func section(_ groupe: ActionsRailGrouping.Groupe) -> some View {
        VStack(alignment: .leading, spacing: groupe.rendu == .cartes ? 7 : 2) {
            HStack(spacing: 0) {
                SectionLabel(groupe.libelle)
                    .foregroundStyle(couleurDuLibelle(groupe.identite))
                Spacer(minLength: 0)
            }
            ForEach(groupe.actions) { action in
                switch groupe.rendu {
                case .cartes:
                    ActionCard(task: action,
                               allCollaborators: allCollaborators,
                               suggestion: OwnerSuggestion.suggestion(for: action,
                                                                      in: meeting,
                                                                      projectTasks: actionsDuProjet),
                               onSeek: onSeek,
                               onToggle: { onToggle(action) },
                               onSave: onSave)
                case .lignes:
                    ActionCompactRow(task: action, onToggle: { onToggle(action) })
                }
            }
        }
    }

    /// `À ASSIGNER` et les groupes reportés portent le rouge brique du rapport
    /// (capture 1a) : ce sont les deux dettes de la séance. Les autres gardent
    /// l'encre de libellé du thème.
    private func couleurDuLibelle(_ identite: ActionsRailGrouping.Identite) -> Color {
        switch identite {
        case .aAssigner:  return One2OneToken.report
        case .reportees:  return One2OneToken.report
        case .mesActions, .deleguees: return One2OneToken.ink4
        }
    }
}
