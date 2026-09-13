import Foundation
import SwiftData

/// Les trois compteurs de la section « Projets » de la barre latérale — les
/// badges « 62 », « 7 » et « 23 » de la capture
/// `2b-sidebar-variante-arbre-replie.png`.
///
/// **Une fonction pure, pas un calcul dans `body`** (décision **D11**) : la
/// barre latérale voit tous les projets, toutes les réunions et toutes les
/// actions ; le comptage se teste sur le semis du portefeuille sans monter
/// d'écran, et une règle qui bouge fait tomber un test au lieu de changer un
/// chiffre en silence.
///
/// ## « À risque » : la règle est ailleurs
///
/// Les trois motifs — jalon dépassé, aucune réunion tenue depuis trente
/// jours, fiche incomplète — étaient écrits ici au lot 1, faute d'un autre
/// endroit. Ils vivent depuis le lot 5 dans `AtRiskBuilder`, qui les groupe
/// pour la capture `1f-vue-a-risque.png` : ce compteur **l'appelle**, il ne
/// le répète pas. Les chiffres du semis (2 jalons + 3 sans réunion + 2
/// fiches = 7) sont donc les mêmes des deux côtés par construction.
struct SidebarProjectCounts: Equatable, Sendable {

    /// Projets non archivés — le badge de « Portfolio ».
    var active: Int

    /// Projets répondant à au moins un des trois motifs, comptés **une fois**
    /// même s'ils en cumulent deux — le badge de « À risque ».
    var atRisk: Int

    /// Actions `status == .open` portées par un projet — le badge de
    /// « Actions projets ».
    var openProjectActions: Int

    /// Aucun projet, aucune action : ce que rend un store vide.
    static let zero = SidebarProjectCounts(active: 0, atRisk: 0, openProjectActions: 0)

    // MARK: - Le comptage

    /// Compte les trois badges.
    ///
    /// - Parameters:
    ///   - projects: **tous** les projets, archivés compris — c'est ici qu'on
    ///     les écarte, pas dans l'appelant.
    ///   - meetings: les réunions ; les notes sont retirées par
    ///     `MeetingStatsScope.held`, et les réunions à venir ne comptent pas
    ///     comme tenues.
    ///   - tasks: les actions, toutes destinations confondues.
    ///   - today: le jour de référence, injecté pour que les tests ne dépendent
    ///     pas de l'horloge.
    static func compute(projects: [Project],
                        meetings: [Meeting],
                        tasks: [ActionTask],
                        today: Date) -> SidebarProjectCounts {
        SidebarProjectCounts(
            active: projects.filter { !$0.isArchived }.count,
            atRisk: AtRiskBuilder.count(projects: projects, meetings: meetings, today: today),
            openProjectActions: tasks.filter { $0.status == .open && $0.project != nil }.count
        )
    }
}
