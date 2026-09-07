import Foundation

/// Le statut de la fiche projet, en trois valeurs (spec §4.3 : « menu à
/// 3 valeurs avec point coloré »).
///
/// `Project.status` en porte quatre (`Green`, `Yellow`, `Red`, `Unknown`) parce
/// qu'il est alimenté par l'import du portfolio externe, qui admet l'absence
/// d'information. `Unknown` n'ouvre pas une quatrième entrée de menu : il se
/// replie sur `watch` et s'affiche « À qualifier » tant que personne n'a
/// tranché. Choisir pour l'utilisateur (« sain » par défaut) serait un
/// mensonge, et l'afficher « en risque » une fausse alerte.
enum ProjectCardStatus: String, CaseIterable, Sendable, Identifiable {
    case ok
    case watch
    case risk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ok:    return "Sous contrôle"
        case .watch: return "À surveiller"
        case .risk:  return "En risque"
        }
    }

    /// Valeur brute à réécrire dans `Project.status`. Les trois libellés du
    /// portfolio externe sont conservés : la fiche n'invente pas un vocabulaire
    /// que l'import écraserait au prochain xlsx.
    var projectStatusRaw: String {
        switch self {
        case .ok:    return "Green"
        case .watch: return "Yellow"
        case .risk:  return "Red"
        }
    }

    init(projectStatus: String) {
        switch projectStatus {
        case "Green": self = .ok
        case "Red":   self = .risk
        default:      self = .watch
        }
    }
}

/// Teinte de la barre de budget, par ratio consommé (spec §4.3 : « < 70 % ok,
/// < 90 % warn, ≥ 90 % report »).
enum BudgetTone: String, Sendable {
    case ok
    case warn
    case report
}

/// Tout ce que le panneau de fiche projet affiche, calculé une fois depuis le
/// modèle. Aucune vue ne relit `Project` : elle lirait des relations dont
/// SwiftData ne garantit pas l'ordre, et le rendu changerait d'une ouverture à
/// l'autre.
struct ProjectCardState: Equatable, Sendable {

    struct Budget: Equatable, Sendable {
        var spent: Double
        var total: Double
        /// Borné 0…1 : c'est la largeur de la barre, pas le taux réel. Un
        /// dépassement se lit dans `text` et dans `tone`.
        var ratio: Double
        var tone: BudgetTone
        /// « 40 000 € / 61 000 € ».
        var text: String
    }

    struct Milestone: Equatable, Sendable, Identifiable {
        var id: UUID
        var label: String
        var state: MilestoneState
        /// Date courte (« 30 sept. »), ou « bloqué » pour un jalon en retard,
        /// ou vide si le jalon n'a pas de date.
        var trailingText: String
        var isBlocked: Bool
        /// L'échéance brute. Portée en plus du texte parce que le mode Préparer
        /// filtre sur une fenêtre de trente jours : relire une date depuis son
        /// libellé français serait une analyse à l'envers.
        var dueAt: Date?
    }

    struct Risk: Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var level: MeetingKPI.Level
    }

    struct Contact: Equatable, Sendable, Identifiable {
        var id: UUID
        var name: String
        var role: String
        /// « Olivier Freund — partenaire, décideur », ou le nom seul sans rôle.
        var text: String
    }

    var name: String = ""
    /// Le code projet (`P25_110`), affiché tel quel en tête.
    var reference: String = ""
    var status: ProjectCardStatus = .watch
    /// Libellé affiché : celui du statut, sauf pour un projet non qualifié.
    var statusLabel: String = ProjectCardStatus.watch.label
    /// Faux quand `Project.status` ne dit rien (`Unknown` ou vide).
    var statusIsQualified: Bool = true
    var meetingCount: Int = 0
    /// « dernière mise à jour aujourd'hui par vous ».
    var lastUpdateText: String = ""
    /// `nil` quand aucun budget total n'est connu : il n'y a alors pas de barre
    /// à dessiner, seulement une invite.
    var budget: Budget?
    var milestones: [Milestone] = []
    var scopeText: String = ""
    var tags: [String] = []
    var risks: [Risk] = []
    var contacts: [Contact] = []
}

/// Assemble `ProjectCardState` depuis un `Project`. Fonctions pures : aucune
/// écriture, aucun appel réseau, aucune dépendance à la locale du poste.
enum ProjectCardBuilder {

    /// Seuils de la spec §4.3, en clair pour qu'ils soient relisibles depuis
    /// le test.
    static let warnRatio = 0.70
    static let reportRatio = 0.90

    @MainActor
    static func build(project: Project,
                      meetings: [Meeting],
                      now: Date = Date()) -> ProjectCardState {
        let statut = ProjectCardStatus(projectStatus: project.status)
        let qualifie = !["", "Unknown"].contains(project.status)

        let duProjet = meetings.filter {
            $0.project?.persistentModelID == project.persistentModelID
        }

        return ProjectCardState(
            name: project.name,
            reference: project.code,
            status: statut,
            statusLabel: qualifie ? statut.label : "À qualifier",
            statusIsQualified: qualifie,
            meetingCount: duProjet.count,
            lastUpdateText: lastUpdateText(project: project, meetings: duProjet, now: now),
            budget: budget(project: project),
            milestones: sortedMilestones(project.milestones).map { jalon in
                ProjectCardState.Milestone(
                    id: jalon.ensuredStableID,
                    label: jalon.label,
                    state: jalon.state,
                    trailingText: trailingText(for: jalon),
                    isBlocked: jalon.state == .late,
                    dueAt: jalon.dueAt
                )
            },
            scopeText: project.scopeText,
            tags: project.tags,
            risks: risks(project: project),
            contacts: sortedContacts(project.contacts).map { contact in
                ProjectCardState.Contact(
                    id: contact.ensuredStableID,
                    name: contact.name,
                    role: contact.role,
                    text: contact.role.isEmpty ? contact.name : "\(contact.name) — \(contact.role)"
                )
            }
        )
    }

    // MARK: - Budget

    static func tone(ratio: Double) -> BudgetTone {
        if ratio >= reportRatio { return .report }
        if ratio >= warnRatio { return .warn }
        return .ok
    }

    /// Budget consommé sur budget total, le total étant le budget **révisé**
    /// s'il existe : c'est celui sur lequel le projet est piloté après
    /// arbitrage. Un total absent ou nul rend `nil` — une barre de progression
    /// sur un total inconnu ne veut rien dire, et diviser par zéro donnerait
    /// une largeur `nan`, donc une barre invisible sans le dire.
    @MainActor
    static func budget(project: Project) -> ProjectCardState.Budget? {
        guard let total = project.budgetRev ?? project.budgetInit, total > 0 else { return nil }
        let consomme = project.budgetCons ?? 0
        let brut = consomme / total
        return ProjectCardState.Budget(
            spent: consomme,
            total: total,
            ratio: min(max(brut, 0), 1),
            tone: tone(ratio: brut),
            text: "\(amountText(consomme)) / \(amountText(total))"
        )
    }

    /// Montant en euros, arrondi à l'unité, groupé par milliers avec une
    /// **espace fine insécable** (U+202F) et suivi d'une espace insécable avant
    /// le symbole — la convention typographique française.
    ///
    /// Écrit à la main plutôt que délégué à `NumberFormatter` : la locale du
    /// poste ne doit pas décider de la présentation d'une fiche française, et
    /// un test qui dépend de la locale de la machine ne prouve rien.
    static func amountText(_ montant: Double) -> String {
        let entier = Int(montant.rounded())
        let signe = entier < 0 ? "−" : ""
        var chiffres = Array(String(abs(entier)))
        var groupes: [String] = []
        while chiffres.count > 3 {
            groupes.insert(String(chiffres.suffix(3)), at: 0)
            chiffres.removeLast(3)
        }
        groupes.insert(String(chiffres), at: 0)
        return signe + groupes.joined(separator: "\u{202F}") + "\u{00A0}€"
    }

    // MARK: - Jalons

    /// Tri explicite : `order` (l'ordre manuel de la fiche), puis la date
    /// d'échéance, puis la date de création. SwiftData ne garantit pas l'ordre
    /// d'une relation ; sans ce tri la liste se réordonne d'un rendu à l'autre.
    @MainActor
    static func sortedMilestones(_ jalons: [ProjectMilestone]) -> [ProjectMilestone] {
        jalons.sorted { gauche, droite in
            if gauche.order != droite.order { return gauche.order < droite.order }
            switch (gauche.dueAt, droite.dueAt) {
            case let (g?, d?) where g != d: return g < d
            case (nil, .some):              return true
            case (.some, nil):              return false
            default:                        return gauche.createdAt < droite.createdAt
            }
        }
    }

    @MainActor
    static func sortedContacts(_ contacts: [ProjectContact]) -> [ProjectContact] {
        contacts.sorted { gauche, droite in
            if gauche.order != droite.order { return gauche.order < droite.order }
            return gauche.createdAt < droite.createdAt
        }
    }

    /// Ce qui s'affiche à droite d'un jalon. Un jalon en retard montre
    /// « bloqué » et **pas** sa date : la date passée est un constat, le
    /// blocage est l'information (capture 3b).
    @MainActor
    static func trailingText(for jalon: ProjectMilestone) -> String {
        if jalon.state == .late { return "bloqué" }
        guard let echeance = jalon.dueAt else { return "" }
        return dateCourte(echeance)
    }

    /// Date courte à la française (« 30 sept. »). Même style que
    /// `MeetingAssistantDock.dateCourte`, locale figée.
    static func dateCourte(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.locale = Locale(identifier: "fr_FR")
        return date.formatted(style)
    }

    // MARK: - Risques

    /// Les risques du projet **non résolus**, du plus grave au plus faible.
    /// Ce sont les `ProjectAlert` existants : le lot 0B n'a pas créé de modèle
    /// de risque, `ProjectAlert` portant déjà sévérité, détail et réunion
    /// d'origine.
    @MainActor
    static func risks(project: Project) -> [ProjectCardState.Risk] {
        project.alerts
            .filter { !$0.isResolved }
            .sorted { gauche, droite in
                let ng = MeetingKPIBuilder.level(fromSeverity: gauche.severity)
                let nd = MeetingKPIBuilder.level(fromSeverity: droite.severity)
                if ng != nd { return ng < nd }
                return gauche.date > droite.date
            }
            .map { alerte in
                ProjectCardState.Risk(
                    id: "\(alerte.persistentModelID.hashValue)",
                    title: alerte.title,
                    level: MeetingKPIBuilder.level(fromSeverity: alerte.severity)
                )
            }
    }

    // MARK: - En-tête

    /// « dernière mise à jour <quand> par <qui> » (spec §4.3). Le « quand »
    /// vient de la plus récente des traces datées du dossier : la dernière
    /// réunion du projet et l'horodatage des sujets permanents. Le « qui » est
    /// toujours « vous » — l'app est mono-utilisateur, et inventer un auteur
    /// serait pire que de ne rien dire.
    @MainActor
    static func lastUpdateText(project: Project,
                               meetings: [Meeting],
                               now: Date) -> String {
        let candidats = meetings.map(\.date) + [project.standingPrepUpdatedAt].compactMap { $0 }
        guard let derniere = candidats.max() else { return "jamais mis à jour" }
        return "dernière mise à jour \(quand(derniere, now: now)) par vous"
    }

    /// « aujourd'hui », « hier », ou la date courte.
    static func quand(_ date: Date, now: Date) -> String {
        let calendrier = Calendar(identifier: .gregorian)
        if calendrier.isDate(date, inSameDayAs: now) { return "aujourd'hui" }
        if let veille = calendrier.date(byAdding: .day, value: -1, to: now),
           calendrier.isDate(date, inSameDayAs: veille) {
            return "hier"
        }
        return "le \(dateCourte(date))"
    }
}
