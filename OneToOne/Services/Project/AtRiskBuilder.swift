import Foundation
import SwiftData

/// Les trois motifs de la vue « À risque » (capture `1f-vue-a-risque.png`),
/// et rien d'autre.
///
/// **Une fonction pure, pas un calcul dans `body`** (décision **D11**). C'est
/// la règle unique du dépôt : le badge « 7 » de la barre latérale
/// (`SidebarProjectCounts.atRisk`) l'appelle aussi, au lieu de répéter les
/// trois motifs comme il le faisait depuis le lot 1.
///
/// **Un projet peut figurer dans plusieurs groupes** — le handoff groupe par
/// motif, pas par projet — mais `projectCount` compte les projets **distincts** :
/// c'est le chiffre du sous-titre et celui du badge, et il vaut 7 sur le semis
/// du portefeuille (2 jalons dépassés + 3 sans réunion + 2 fiches incomplètes,
/// sans recoupement).
///
/// Les **archivés sont exclus** : un projet rangé n'attend aucune décision.
enum AtRiskBuilder {

    /// Le nombre de jours sans réunion **tenue** au-delà duquel un projet
    /// entre dans le deuxième groupe.
    static let sansReunionDepuis = 30

    /// Le délai que « Planifier » propose : la réunion créée est datée
    /// d'aujourd'hui + sept jours.
    static let planifierDansNJours = 7

    /// Le séparateur des fragments d'un détail de ligne.
    static let separateur = " · "

    // MARK: - Le rapport

    /// Construit les trois groupes de la capture 1f.
    ///
    /// - Parameters:
    ///   - projects: **tous** les projets, archivés compris — ils sont écartés
    ///     ici, pas dans l'appelant.
    ///   - meetings: toutes les réunions ; seules les **tenues**
    ///     (`MeetingStatsScope.held`, donc pas les notes) et passées comptent.
    ///   - today: le jour de référence, injecté pour que les tests ne
    ///     dépendent pas de l'horloge.
    static func build(projects: [Project],
                      meetings: [Meeting],
                      today: Date) -> AtRiskReport {
        let actifs = projects.filter { !$0.isArchived }
        let derniereReunion = MeetingStatsScope.lastHeldByProject(meetings, today: today)

        var jalons: [(item: AtRiskItem, retard: Int, nom: String)] = []
        var silences: [(item: AtRiskItem, silence: Int, nom: String)] = []
        var fiches: [(item: AtRiskItem, nom: String)] = []
        var projetsCitees = Set<PersistentIdentifier>()

        for projet in actifs {
            let identite = projet.persistentModelID

            if let jalon = jalonLePlusEnRetard(of: projet, today: today) {
                let retard = retardDuJalon(jalon, today: today)
                jalons.append((item: AtRiskItem(id: identifiantDeLigne("jalon", projet),
                                                project: identite,
                                                stableID: projet.stableID,
                                                title: nomAffiche(projet),
                                                detail: detailDeJalon(jalon,
                                                                      porteur: porteur(of: projet),
                                                                      today: today),
                                                action: .replan(milestone: jalon.persistentModelID)),
                               retard: retard,
                               nom: nomAffiche(projet)))
                projetsCitees.insert(identite)
            }

            let derniere = derniereReunion[identite]
            if sansReunionRecente(derniere, today: today) {
                silences.append((item: AtRiskItem(id: identifiantDeLigne("silence", projet),
                                                  project: identite,
                                                  stableID: projet.stableID,
                                                  title: nomAffiche(projet),
                                                  detail: detailDeSilence(derniere, today: today),
                                                  action: .schedule),
                                 silence: silence(derniere, today: today),
                                 nom: nomAffiche(projet)))
                projetsCitees.insert(identite)
            }

            let manquants = champsManquants(projet)
            if let premier = manquants.first {
                fiches.append((item: AtRiskItem(id: identifiantDeLigne("fiche", projet),
                                                project: identite,
                                                stableID: projet.stableID,
                                                title: nomAffiche(projet),
                                                detail: detailDeFiche(manquants),
                                                action: .complete(field: premier)),
                               nom: nomAffiche(projet)))
                projetsCitees.insert(identite)
            }
        }

        // Le plus urgent en tête, puis l'ordre alphabétique — la capture
        // classe le jalon échu depuis 6 j avant celui de 2 j.
        let groupeJalons = jalons
            .sorted { $0.retard != $1.retard ? $0.retard > $1.retard : avant($0.nom, $1.nom) }
            .map(\.item)
        let groupeSilences = silences
            .sorted { $0.silence != $1.silence ? $0.silence > $1.silence : avant($0.nom, $1.nom) }
            .map(\.item)
        let groupeFiches = fiches
            .sorted { avant($0.nom, $1.nom) }
            .map(\.item)

        return AtRiskReport(overdueMilestones: groupeJalons,
                            silent30Days: groupeSilences,
                            incomplete: groupeFiches,
                            projectCount: projetsCitees.count,
                            subtitle: sousTitre(projets: projetsCitees.count, at: today))
    }

    /// Le nombre de projets distincts à risque — le badge « 7 » de la barre
    /// latérale (`SidebarProjectCounts.atRisk`).
    static func count(projects: [Project], meetings: [Meeting], today: Date) -> Int {
        build(projects: projects, meetings: meetings, today: today).projectCount
    }

    /// L'identifiant d'une ligne : le motif et le code du projet.
    ///
    /// Le **code** et non le `PersistentIdentifier` : `hashValue` change d'un
    /// lancement à l'autre, et un `ForEach` qui change d'identité à chaque
    /// reconstruction refait toute l'animation.
    static func identifiantDeLigne(_ motif: String, _ project: Project) -> String {
        let code = project.code.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(motif)-\(code.isEmpty ? String(project.persistentModelID.hashValue) : code)"
    }

    private static func avant(_ gauche: String, _ droite: String) -> Bool {
        gauche.localizedCaseInsensitiveCompare(droite) == .orderedAscending
    }

    /// Le nom affiché d'un projet — jamais vide, pour qu'une ligne cliquable
    /// ne soit pas invisible.
    static func nomAffiche(_ project: Project) -> String {
        let net = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return net.isEmpty ? (project.code.isEmpty ? "Projet sans nom" : project.code) : net
    }

    // MARK: - Motif 1 : jalon dépassé

    /// Le jalon est-il dépassé ? Échu et non fait, **ou** saisi « en retard »
    /// quelle que soit son échéance.
    ///
    /// La comparaison se fait au **début du jour** : un jalon dû aujourd'hui à
    /// midi n'est pas dépassé à quinze heures.
    static func estDepasse(dueAt: Date?, state: MilestoneState, today: Date) -> Bool {
        if state == .late { return true }
        guard state != .done, let echeance = dueAt else { return false }
        return echeance < Calendar.current.startOfDay(for: today)
    }

    /// Le projet porte-t-il au moins un jalon dépassé ?
    ///
    /// Prend des tuples et non des `ProjectMilestone` : la règle ne lit que
    /// deux champs, et un tuple se fabrique dans un test sans store.
    static func jalonDepasse(jalons: [(dueAt: Date?, state: MilestoneState)],
                             today: Date) -> Bool {
        jalons.contains { estDepasse(dueAt: $0.dueAt, state: $0.state, today: today) }
    }

    /// Le jalon dépassé le **plus ancien** — celui que la ligne nomme. Un
    /// projet ne produit qu'une ligne par groupe.
    static func jalonLePlusEnRetard(of project: Project, today: Date) -> ProjectMilestone? {
        project.milestones
            .filter { estDepasse(dueAt: $0.dueAt, state: $0.state, today: today) }
            .min { gauche, droite in
                switch (gauche.dueAt, droite.dueAt) {
                case let (g?, d?): return g < d
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return gauche.order < droite.order
                }
            }
    }

    /// Le retard d'un jalon, en jours pleins. Un jalon saisi « en retard »
    /// sans échéance passée compte pour zéro : il est urgent, pas ancien.
    static func retardDuJalon(_ jalon: ProjectMilestone, today: Date) -> Int {
        guard let echeance = jalon.dueAt else { return 0 }
        return max(0, joursEcoules(de: echeance, a: today))
    }

    /// « Recette utilisateurs · échue depuis 6 j · PENVEN Yann ».
    ///
    /// Sans échéance passée — un jalon simplement saisi « en retard » — le
    /// fragment devient « en retard », qui est ce que la donnée dit.
    static func detailDeJalon(_ jalon: ProjectMilestone,
                              porteur: String?,
                              today: Date) -> String {
        var fragments: [String] = []
        let libelle = jalon.label.trimmingCharacters(in: .whitespacesAndNewlines)
        fragments.append(libelle.isEmpty ? "Jalon sans nom" : libelle)

        let retard = retardDuJalon(jalon, today: today)
        if let echeance = jalon.dueAt, echeance < Calendar.current.startOfDay(for: today) {
            fragments.append("échue depuis \(retard) j")
        } else {
            fragments.append("en retard")
        }

        if let porteur, !porteur.isEmpty { fragments.append(porteur) }
        return fragments.joined(separator: separateur)
    }

    /// Le responsable nommé par la ligne : le chef de projet **lié** (décision
    /// **D3**), à défaut le nom libre du xlsx, à défaut rien.
    static func porteur(of project: Project) -> String? {
        if let chef = ProjectPeople.manager(of: project) { return chef }
        let libre = project.chefDeProjet.trimmingCharacters(in: .whitespacesAndNewlines)
        return libre.isEmpty ? nil : libre
    }

    // MARK: - Motif 2 : sans réunion depuis 30 jours

    /// Aucune réunion tenue depuis trente jours, ou aucune du tout.
    static func sansReunionRecente(_ derniereReunion: Date?, today: Date) -> Bool {
        guard let derniereReunion else { return true }
        let calendrier = Calendar.current
        guard let limite = calendrier.date(byAdding: .day,
                                           value: -sansReunionDepuis,
                                           to: calendrier.startOfDay(for: today))
        else { return false }
        return derniereReunion < limite
    }

    /// L'ancienneté du silence, en jours. `Int.max` quand aucune réunion n'a
    /// jamais été tenue : c'est le plus long silence possible, et il passe en
    /// tête du groupe.
    static func silence(_ derniereReunion: Date?, today: Date) -> Int {
        guard let derniereReunion else { return Int.max }
        return max(0, joursEcoules(de: derniereReunion, a: today))
    }

    /// « Dernière réunion il y a 34 j » ou « Aucune réunion enregistrée ».
    static func detailDeSilence(_ derniereReunion: Date?, today: Date) -> String {
        guard let derniereReunion else { return "Aucune réunion enregistrée" }
        return "Dernière réunion il y a \(silence(derniereReunion, today: today)) j"
    }

    // MARK: - Motif 3 : fiche incomplète

    /// Les champs manquants, dans l'ordre où la ligne les énumère.
    ///
    /// **La relation fait foi** pour le chef de projet (décision **D3**) : le
    /// nom importé du xlsx ne comble pas le vide. Un statut vide compte comme
    /// inconnu ; une valeur hors table (« Réalisation ») ne rend pas la fiche
    /// incomplète — D14 dit seulement qu'elle s'affiche en neutre.
    static func champsManquants(_ project: Project) -> [IncompleteField] {
        var manquants: [IncompleteField] = []
        if project.sponsor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manquants.append(.sponsor)
        }
        if ProjectPeople.manager(of: project) == nil {
            manquants.append(.manager)
        }
        let statut = project.status.trimmingCharacters(in: .whitespacesAndNewlines)
        if statut.isEmpty || ProjectStatus(raw: statut) == .unknown {
            manquants.append(.status)
        }
        return manquants
    }

    /// La fiche est-elle incomplète ?
    static func ficheIncomplete(_ project: Project) -> Bool {
        !champsManquants(project).isEmpty
    }

    /// « Pas de chef de projet · statut inconnu ».
    ///
    /// Seul le **premier** fragment porte la majuscule : les suivants sont la
    /// suite de la même phrase, et c'est ce que la capture écrit.
    static func detailDeFiche(_ champs: [IncompleteField]) -> String {
        champs.enumerated()
            .map { index, champ in index == 0 ? champ.detail : enMinuscule(champ.detail) }
            .joined(separator: separateur)
    }

    private static func enMinuscule(_ texte: String) -> String {
        guard let premiere = texte.first else { return texte }
        return premiere.lowercased() + texte.dropFirst()
    }

    // MARK: - Le projet est-il à risque ? (badge de la barre latérale)

    /// Au moins un des trois motifs. Un `ou` — d'où le « compté une fois » du
    /// badge.
    static func estARisque(_ project: Project,
                           derniereReunion: Date?,
                           today: Date) -> Bool {
        jalonDepasse(jalons: project.milestones.map { (dueAt: $0.dueAt, state: $0.state) },
                     today: today)
            || sansReunionRecente(derniereReunion, today: today)
            || ficheIncomplete(project)
    }

    // MARK: - Libellés d'en-tête

    /// « 7 projets demandent une décision · mis à jour ce matin ».
    static func sousTitre(projets: Int, at date: Date) -> String {
        let accord = projets == 1 ? "1 projet demande une décision"
                                  : "\(projets) projets demandent une décision"
        return accord + separateur + "mis à jour \(libelleDeMiseAJour(date))"
    }

    /// Le moment de la journée, tel que la capture l'écrit (« ce matin »).
    static func libelleDeMiseAJour(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case ..<12:  return "ce matin"
        case 12..<18: return "cet après-midi"
        default:      return "ce soir"
        }
    }

    // MARK: - « Planifier »

    /// La date de la réunion que « Planifier » crée : aujourd'hui + sept
    /// jours, à la même heure.
    static func dateDePlanification(from today: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: planifierDansNJours, to: today) ?? today
    }

    // MARK: - Outils

    /// Le nombre de jours pleins entre deux instants, comptés de début de jour
    /// à début de jour — « échue depuis 6 j » ne doit pas dépendre de l'heure.
    static func joursEcoules(de debut: Date, a fin: Date) -> Int {
        let calendrier = Calendar.current
        return calendrier.dateComponents([.day],
                                         from: calendrier.startOfDay(for: debut),
                                         to: calendrier.startOfDay(for: fin)).day ?? 0
    }
}

// MARK: - Le vocabulaire de la vue

/// Le champ que « Compléter » vient renseigner.
enum IncompleteField: String, CaseIterable, Hashable, Sendable {
    case sponsor
    case manager
    case status

    /// Le fragment de détail, en tête de phrase.
    var detail: String {
        switch self {
        case .sponsor: return "Sponsor non renseigné"
        case .manager: return "Pas de chef de projet"
        case .status:  return "Statut inconnu"
        }
    }

}

/// Ce que la ligne propose de faire, à droite.
enum AtRiskAction: Hashable, Sendable {
    /// Rouvrir le jalon dépassé (`Replanifier`).
    case replan(milestone: PersistentIdentifier)
    /// Créer une réunion projet (`Planifier`).
    case schedule
    /// Renseigner le champ manquant (`Compléter`).
    case complete(field: IncompleteField)

    /// L'intitulé du lien, tel que la capture 1f l'écrit.
    var libelle: String {
        switch self {
        case .replan:   return "Replanifier"
        case .schedule: return "Planifier"
        case .complete: return "Compléter"
        }
    }
}

/// Une ligne de la vue « À risque ».
struct AtRiskItem: Identifiable, Hashable, Sendable {
    /// Unique **par groupe** : un projet qui cumule deux motifs produit deux
    /// lignes, et un `ForEach` refuse deux identifiants égaux.
    let id: String
    let project: PersistentIdentifier
    /// Le jeton de route du projet. Optionnel comme `PortfolioRow.stableID` :
    /// `Project.stableID` l'est, et le combler écrirait dans le store — ce
    /// qu'un constructeur pur ne fait pas. La vue route par `project`.
    let stableID: UUID?
    let title: String
    let detail: String
    let action: AtRiskAction
}

/// Les trois groupes de la capture 1f, et le chiffre du sous-titre.
struct AtRiskReport: Hashable, Sendable {
    var overdueMilestones: [AtRiskItem] = []
    var silent30Days: [AtRiskItem] = []
    var incomplete: [AtRiskItem] = []
    /// Les projets **distincts** cités par au moins un groupe.
    var projectCount: Int = 0
    /// « 7 projets demandent une décision · mis à jour ce matin ».
    ///
    /// Dans le rapport et non dans la vue : c'est une phrase qui s'accorde et
    /// qui date, donc une règle, et D11 interdit de la calculer dans `body`.
    var subtitle: String = ""

    /// Aucun groupe n'a de ligne.
    var estVide: Bool {
        overdueMilestones.isEmpty && silent30Days.isEmpty && incomplete.isEmpty
    }
}
