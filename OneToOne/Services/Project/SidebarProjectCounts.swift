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
/// ## « À risque » est un stub, et il le reste jusqu'au lot 5
///
/// Les trois motifs du handoff sont écrits ici — jalon dépassé, aucune réunion
/// tenue depuis trente jours, fiche incomplète — parce que le badge en a besoin
/// dès ce lot. Le **lot 5** livre `AtRiskBuilder`, qui groupe les projets par
/// motif pour la capture `1f-vue-a-risque.png` : c'est lui qui portera alors la
/// règle, et `atRisk` devra l'appeler au lieu de la répéter. Les tests de ce
/// fichier vérifient chaque motif séparément **pour que la bascule se prouve** :
/// les chiffres du semis (2 jalons + 3 sans réunion + 2 fiches = 7) sont les
/// mêmes des deux côtés.
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

    /// Le nombre de jours sans réunion tenue au-delà duquel un projet est à
    /// risque (motif 2 du handoff).
    static let sansReunionDepuis = 30

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
        let actifs = projects.filter { !$0.isArchived }
        let derniereReunion = MeetingStatsScope.lastHeldByProject(meetings, today: today)

        let aRisque = actifs.filter { projet in
            estARisque(projet,
                       derniereReunion: derniereReunion[projet.persistentModelID],
                       today: today)
        }

        return SidebarProjectCounts(
            active: actifs.count,
            atRisk: aRisque.count,
            openProjectActions: tasks.filter { $0.status == .open && $0.project != nil }.count
        )
    }

    // MARK: - « À risque » : les trois motifs

    /// Le projet répond-il à au moins un motif ? Un `ou` — d'où le « compté une
    /// fois » du badge.
    static func estARisque(_ project: Project,
                           derniereReunion: Date?,
                           today: Date) -> Bool {
        jalonDepasse(jalons: project.milestones.map { (dueAt: $0.dueAt, state: $0.state) },
                     today: today)
            || sansReunionRecente(derniereReunion, today: today)
            || ficheIncomplete(project)
    }

    /// Motif 1 — un jalon échu et non fait, ou déclaré en retard.
    ///
    /// La comparaison se fait au **début du jour** : un jalon dû aujourd'hui à
    /// midi n'est pas dépassé à quinze heures. Les échéances du semis sont
    /// posées à midi pour la même raison.
    ///
    /// Prend des tuples et non des `ProjectMilestone` : la règle ne lit que
    /// deux champs, et un tuple se fabrique dans un test sans store.
    static func jalonDepasse(jalons: [(dueAt: Date?, state: MilestoneState)],
                             today: Date) -> Bool {
        let debutDeJournee = Calendar.current.startOfDay(for: today)
        return jalons.contains { jalon in
            if jalon.state == .late { return true }
            guard jalon.state != .done, let echeance = jalon.dueAt else { return false }
            return echeance < debutDeJournee
        }
    }

    /// Motif 2 — aucune réunion tenue depuis trente jours, ou aucune du tout.
    static func sansReunionRecente(_ derniereReunion: Date?, today: Date) -> Bool {
        guard let derniereReunion else { return true }
        let calendrier = Calendar.current
        guard let limite = calendrier.date(byAdding: .day,
                                           value: -sansReunionDepuis,
                                           to: calendrier.startOfDay(for: today))
        else { return false }
        return derniereReunion < limite
    }

    /// Motif 3 — fiche incomplète : sponsor vide, chef de projet non **lié**
    /// (décision **D3** : la relation fait foi, le nom du xlsx ne suffit pas)
    /// ou statut inconnu.
    ///
    /// Un statut vide compte comme inconnu : c'est le même vide que celui du
    /// sponsor. Une valeur hors table (« Réalisation »), elle, ne rend pas la
    /// fiche incomplète — elle s'affiche en badge neutre, et c'est tout ce que
    /// D14 en dit.
    static func ficheIncomplete(_ project: Project) -> Bool {
        if project.sponsor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if ProjectPeople.manager(of: project) == nil { return true }
        let statut = project.status.trimmingCharacters(in: .whitespacesAndNewlines)
        return statut.isEmpty || ProjectStatus(raw: statut) == .unknown
    }
}
