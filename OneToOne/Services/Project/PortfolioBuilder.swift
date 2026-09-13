import Foundation
import SwiftData

/// Les cinq facettes du Portfolio, dans l'ordre où la barre de filtres les
/// propose (capture `1a-portfolio.png`).
///
/// La chip active « Risque ≥ Modéré » n'est pas une liste de valeurs mais un
/// **seuil de gravité** : c'est la seule facette dont le libellé porte un
/// opérateur, et `PortfolioFilters.riskAtLeast` la stocke à part.
enum PortfolioFacet: String, CaseIterable, Sendable {
    case entity
    case risk
    case phase
    case status
    case manager

    /// Le libellé de la chip, tel que la capture l'écrit.
    var libelle: String {
        switch self {
        case .entity:  return "Entité"
        case .risk:    return "Risque"
        case .phase:   return "Phase"
        case .status:  return "Statut"
        case .manager: return "Chef de projet"
        }
    }

    /// Le libellé complet d'une chip active : « Entité : ASP », mais
    /// « Risque ≥ Modéré » — le seuil ne s'écrit pas avec deux points.
    func libelleActif(_ valeurs: [String]) -> String {
        let valeur = valeurs.count <= 1
            ? (valeurs.first ?? "")
            : "\(valeurs.count) valeurs"
        return self == .risk ? "\(libelle) ≥ \(valeur)" : "\(libelle) : \(valeur)"
    }
}

/// Le tableau du Portfolio, calculé **avant** d'être affiché (décision
/// **D11**) : les lignes, les facettes, le tri, les libellés relatifs et le
/// sous-titre de l'en-tête.
///
/// **Quatre fonctions pures, et rien d'autre.** `rows` transforme des projets
/// en valeurs, `apply` filtre, `sort` ordonne, `relativeLabel` et `summary`
/// écrivent les deux textes que la capture montre. Aucune ne touche au store,
/// aucune ne connaît SwiftUI : elles se testent sur le semis de démonstration
/// (`RefonteDemoSeed+Portfolio`) sans monter d'écran, et c'est ce qui permet de
/// figer « il y a 2 sem. » ou « J−4 » au caractère près.
///
/// **Le tableau ne montre que les projets actifs.** Le pied de la capture dit
/// « 8 lignes sur 62 », et 62 est le nombre de projets non archivés. Les
/// archivés ont leur section dans la barre latérale ; les rendre filtrables
/// ici demanderait une sixième facette que la maquette n'a pas.
enum PortfolioBuilder {

    // MARK: - Les lignes

    /// Construit une ligne par projet **actif**, dans l'ordre d'entrée.
    ///
    /// - Parameters:
    ///   - projects: tous les projets, archivés compris — ils sont écartés ici
    ///     et non par l'appelant.
    ///   - meetings: toutes les réunions ; seules les tenues et passées
    ///     alimentent la colonne « Dernière réu. »
    ///     (`MeetingStatsScope.lastHeldByProject`).
    ///   - today: le jour de référence, injecté pour que les tests ne dépendent
    ///     pas de l'horloge.
    static func rows(projects: [Project], meetings: [Meeting], today: Date) -> [PortfolioRow] {
        let dernieres = MeetingStatsScope.lastHeldByProject(meetings, today: today)
        return projects.filter { !$0.isArchived }.map { projet in
            let derniere = dernieres[projet.persistentModelID]
            return PortfolioRow(
                id: projet.persistentModelID,
                stableID: projet.stableID,
                name: projet.name,
                code: projet.code,
                type: projet.projectType,
                entity: entite(de: projet),
                sponsor: projet.sponsor,
                phase: ProjectPhase(raw: projet.phase),
                phaseRaw: projet.phase,
                status: ProjectStatus(raw: projet.status),
                risk: projet.riskLevel.flatMap { RiskLevel(raw: $0) },
                manager: ProjectPeople.manager(of: projet),
                nextMilestone: milestoneCell(of: projet, today: today),
                lastMeeting: derniere,
                lastMeetingLabel: relativeLabel(from: derniere, today: today),
                pinned: projet.pinned
            )
        }
    }

    /// L'entité affichée : la relation, à défaut le domaine, `nil` si les deux
    /// sont vides. Le domaine sert de repli parce que l'import xlsx y écrit le
    /// nom de l'entité avant que la relation soit posée.
    private static func entite(de projet: Project) -> String? {
        for candidat in [projet.entity?.name, projet.domain] {
            guard let net = candidat?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !net.isEmpty else { continue }
            return net
        }
        return nil
    }

    /// La cellule « JALON » : un retard l'emporte sur une échéance à venir.
    ///
    /// « Prochain jalon non fait » (`MilestoneState != .done`) : un jalon
    /// échu et non fait, ou déclaré `.late`, rend `retard` ; sinon la plus
    /// proche échéance à venir rend `J−n` ; sinon un tiret. Comparaison au
    /// **début du jour**, comme `SidebarProjectCounts.jalonDepasse` — un jalon
    /// dû aujourd'hui à midi n'est pas en retard à quinze heures, il est
    /// « J−0 ».
    static func milestoneCell(of projet: Project, today: Date) -> MilestoneCell {
        let debut = Calendar.current.startOfDay(for: today)
        let restants = projet.milestones.filter { $0.state != .done }
        if restants.contains(where: { jalon in
            if jalon.state == .late { return true }
            guard let echeance = jalon.dueAt else { return false }
            return echeance < debut
        }) { return .late }

        let joursRestants = restants.compactMap { jalon -> Int? in
            guard let echeance = jalon.dueAt else { return nil }
            return Calendar.current.dateComponents([.day],
                                                   from: debut,
                                                   to: Calendar.current.startOfDay(for: echeance)).day
        }
        guard let plusProche = joursRestants.filter({ $0 >= 0 }).min() else { return .none }
        return .days(plusProche)
    }

    // MARK: - Les facettes

    /// Filtre les lignes par le jeu de facettes, **en ET** : chaque facette
    /// renseignée retire des lignes, jamais n'en ajoute (handoff, §Interactions
    /// : « les filtres se cumulent (ET) »).
    ///
    /// Dans une même facette, les valeurs sont en **OU** : « Phase : Build,
    /// Run » garde les deux phases. C'est ce qu'un menu à cocher laisse
    /// attendre, et le seul cumul utile.
    ///
    /// Le terme du champ de recherche passe par `ProjectSearch` (décision
    /// **D7** : une seule recherche dans l'application) — sur les champs que
    /// la ligne porte, donc sans les notes, qu'une valeur ne transporte pas.
    /// Fouiller les comptes rendus est le travail de la palette (lot 3).
    static func apply(_ filters: PortfolioFilters, to rows: [PortfolioRow]) -> [PortfolioRow] {
        rows.filter { ligne in
            if !filters.entities.isEmpty {
                guard let entite = ligne.entity, contient(filters.entities, entite) else { return false }
            }
            if !filters.phases.isEmpty {
                guard contient(filters.phases, ligne.phaseRaw) else { return false }
            }
            if !filters.statuses.isEmpty {
                guard let statut = ligne.status, contient(filters.statuses, statut.label) else { return false }
            }
            if let seuil = filters.riskAtLeast.flatMap({ RiskLevel(raw: $0) }) {
                guard let risque = ligne.risk, risque.severity >= seuil.severity else { return false }
            }
            if !filters.managers.isEmpty {
                let valeur = ligne.manager ?? ProjectPeople.nonAffecte
                guard contient(filters.managers, valeur) else { return false }
            }
            if !filters.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard ProjectSearch.matches(fields: champsCherchables(de: ligne),
                                            query: filters.text) else { return false }
            }
            return true
        }
    }

    /// Les valeurs qu'un menu de facette doit proposer, pour ces lignes.
    ///
    /// **Celles qui sont présentes, pas celles de la table.** Proposer
    /// « Critique » quand aucun projet ne l'est donne un filtre qui vide le
    /// tableau ; proposer « Réalisation » quand le store en contient est au
    /// contraire indispensable (décision **D14** : une valeur hors table reste
    /// filtrable).
    ///
    /// Exception : le **risque** est un seuil, et ses quatre crans se
    /// proposent toujours dans l'ordre de gravité — un seuil dont la liste
    /// change selon le contenu du tableau serait illisible.
    static func values(of facet: PortfolioFacet, in rows: [PortfolioRow]) -> [String] {
        switch facet {
        case .risk:
            return RiskLevel.allLabels
        case .entity:
            return triees(rows.compactMap(\.entity))
        case .phase:
            return connuesDAbord(rows.map(\.phaseRaw), table: ProjectPhase.allLabels)
        case .status:
            return connuesDAbord(rows.compactMap { $0.status?.label },
                                 table: ProjectStatus.allLabels)
        case .manager:
            let noms = triees(rows.compactMap(\.manager))
            // « Non affecté » en dernier : c'est un vide, pas un nom, et D3 en
            // fait une valeur qu'on doit pouvoir isoler.
            return rows.contains { $0.manager == nil } ? noms + [ProjectPeople.nonAffecte] : noms
        }
    }

    // MARK: - Le tri

    /// Ordonne les lignes selon la colonne et le sens demandés.
    ///
    /// Le **nom** départage toujours, en croissant, quel que soit le sens du
    /// tri principal : sans lui, deux projets de la même phase changeraient de
    /// place d'un recalcul à l'autre.
    ///
    /// Les vides ne sont pas « avant A » : un projet sans chef de projet, sans
    /// jalon ou sans entité passe **après** les autres en tri croissant. Seule
    /// la dernière réunion fait exception — « jamais » est le plus ancien des
    /// passés, et se place en tête d'un tri croissant, là où l'utilisateur
    /// cherche ce qu'il a négligé.
    static func sort(_ rows: [PortfolioRow], by sort: PortfolioSort) -> [PortfolioRow] {
        rows.sorted { a, b in
            let ordre = compare(a, b, on: sort.column)
            if ordre != .orderedSame {
                let croissant = ordre == .orderedAscending
                return sort.ascending ? croissant : !croissant
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func compare(_ a: PortfolioRow,
                                _ b: PortfolioRow,
                                on colonne: PortfolioSort.Column) -> ComparisonResult {
        switch colonne {
        case .name:
            return a.name.localizedStandardCompare(b.name)
        case .entity:
            return compareTexte(a.entity, b.entity)
        case .phase:
            return compareRang(rangDePhase(a), rangDePhase(b))
        case .risk:
            // Sans risque = moins grave que « Faible » : la colonne affiche un
            // tiret, et un tri croissant met les tirets en tête.
            return compareRang(a.risk.map { $0.severity + 1 } ?? 0,
                               b.risk.map { $0.severity + 1 } ?? 0)
        case .manager:
            return compareTexte(a.manager, b.manager)
        case .milestone:
            return compareRang(a.nextMilestone.rangDeTri, b.nextMilestone.rangDeTri)
        case .lastMeeting:
            // `jamais` est infiniment ancien : `Date.distantPast`.
            let da = a.lastMeeting ?? .distantPast
            let db = b.lastMeeting ?? .distantPast
            if da == db { return .orderedSame }
            return da < db ? .orderedAscending : .orderedDescending
        }
    }

    /// L'ordre de la table pour une phase connue, la fin de la liste pour une
    /// valeur hors table (décision **D14**).
    private static func rangDePhase(_ ligne: PortfolioRow) -> Int {
        guard let phase = ligne.phase else { return ProjectPhase.allCases.count }
        return ProjectPhase.allCases.firstIndex(of: phase) ?? ProjectPhase.allCases.count
    }

    private static func compareRang(_ a: Int, _ b: Int) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    /// Deux textes optionnels : le vide en dernier, quel que soit le sens.
    private static func compareTexte(_ a: String?, _ b: String?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil):   return .orderedSame
        case (nil, _):     return .orderedDescending
        case (_, nil):     return .orderedAscending
        case (let a?, let b?): return a.localizedStandardCompare(b)
        }
    }

    // MARK: - Les libellés

    /// La colonne « Dernière réu. », telle que la capture 1a l'écrit :
    /// « hier », « il y a 3 j », « il y a 2 sem. », « il y a 1 mois »,
    /// « jamais ».
    ///
    /// Les paliers sont ceux de la capture, qui affiche « il y a 8 j » (donc
    /// pas de semaines avant deux) et « il y a 2 sem. » à quatorze jours :
    /// jours jusqu'à treize, semaines jusqu'à vingt-neuf, mois ensuite, années
    /// au-delà d'un an. Comparaison au **début du jour** : une réunion d'hier
    /// à 23 h reste « hier » ce matin à 8 h.
    static func relativeLabel(from date: Date?, today: Date) -> String {
        guard let date else { return "jamais" }
        let calendrier = Calendar.current
        let jours = calendrier.dateComponents([.day],
                                              from: calendrier.startOfDay(for: date),
                                              to: calendrier.startOfDay(for: today)).day ?? 0
        switch jours {
        case ..<1:      return "aujourd'hui"
        case 1:         return "hier"
        case 2...13:    return "il y a \(jours) j"
        case 14...29:   return "il y a \(jours / 7) sem."
        case 30...364:  return "il y a \(jours / 30) mois"
        default:
            let ans = jours / 365
            return "il y a \(ans) an\(ans > 1 ? "s" : "")"
        }
    }

    /// Le sous-titre de l'en-tête : « 62 actifs · 8 entités · 14 archivés ».
    ///
    /// Les entités comptées sont celles des projets **actifs** : une entité
    /// dont tous les projets sont archivés n'apparaît dans aucune facette, et
    /// l'annoncer serait mentir sur ce que le tableau permet de filtrer.
    static func summary(projects: [Project]) -> String {
        let actifs = projects.filter { !$0.isArchived }
        let entites = Set(actifs.compactMap { entite(de: $0) }).count
        let archives = projects.count - actifs.count
        return [accord(actifs.count, "actif", "actifs"),
                accord(entites, "entité", "entités"),
                accord(archives, "archivé", "archivés")].joined(separator: " · ")
    }

    /// Le pied du tableau : « 8 lignes sur 62 · sélection multiple ⇧-clic pour
    /// changer phase, statut ou entité en lot ».
    static func footer(affichees: Int, total: Int) -> String {
        "\(accord(affichees, "ligne", "lignes")) sur \(total) · sélection multiple"
            + " ⇧-clic pour changer phase, statut ou entité en lot"
    }

    /// Le groupement du segment « Groupé par entité » : les mêmes lignes, sous
    /// un en-tête d'entité, par ordre alphabétique — les projets sans entité
    /// en dernier groupe.
    static func groups(_ rows: [PortfolioRow]) -> [(entite: String, lignes: [PortfolioRow])] {
        let paquets = Dictionary(grouping: rows) { $0.entity }
        return paquets.keys
            .sorted { compareTexte($0, $1) == .orderedAscending }
            .map { clef in
                (entite: clef ?? "Sans entité", lignes: paquets[clef] ?? [])
            }
    }

    // MARK: - Mécanique

    /// Les champs qu'une ligne offre au champ de recherche — « Nom, code,
    /// sponsor… », plus l'entité, le chef de projet et le type, que la ligne
    /// affiche et qu'on tape donc naturellement.
    private static func champsCherchables(de ligne: PortfolioRow) -> [String] {
        [ligne.name, ligne.code, ligne.entity ?? "", ligne.sponsor,
         ligne.manager ?? "", ligne.type]
    }

    /// L'ensemble contient-il cette valeur, casse et accents pliés ? Les
    /// valeurs d'une facette viennent d'un menu, mais une vue enregistrée peut
    /// avoir été écrite à une époque où la casse différait.
    private static func contient(_ valeurs: Set<String>, _ valeur: String) -> Bool {
        let clef = plie(valeur)
        return valeurs.contains { plie($0) == clef }
    }

    private static func plie(_ valeur: String) -> String {
        valeur.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Les valeurs distinctes, non vides, par ordre alphabétique local.
    private static func triees(_ valeurs: [String]) -> [String] {
        var vues = Set<String>()
        var resultat: [String] = []
        for valeur in valeurs {
            let net = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !net.isEmpty, vues.insert(plie(net)).inserted else { continue }
            resultat.append(net)
        }
        return resultat.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Les valeurs présentes, dans l'ordre de la table pour celles qu'elle
    /// connaît, puis les autres par ordre alphabétique.
    private static func connuesDAbord(_ valeurs: [String], table: [String]) -> [String] {
        let presentes = triees(valeurs)
        let connues = table.filter { attendue in presentes.contains { plie($0) == plie(attendue) } }
        let inconnues = presentes.filter { valeur in
            !table.contains { plie($0) == plie(valeur) }
        }
        return connues + inconnues
    }

    private static func accord(_ nombre: Int, _ singulier: String, _ pluriel: String) -> String {
        "\(nombre) \(nombre <= 1 ? singulier : pluriel)"
    }
}
