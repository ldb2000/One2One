import Foundation
import SwiftData

/// Les groupes du rail d'actions et son historique (spec §2.5) : « Groupes
/// ordonnés : `À ASSIGNER` (barre gauche `accent/report`) → `MES ACTIONS` →
/// `REPORTÉES DU <date>` (compact, une ligne par action) ».
///
/// Fonctions pures, hors de toute vue : l'ordre des groupes, l'exclusion des
/// actions closes et le regroupement par date d'origine sont des règles
/// métier, et une règle métier rendue directement dans un `ForEach` n'est
/// vérifiable qu'à l'œil.
///
/// Une action n'apparaît **jamais deux fois** : les prédicats sont évalués dans
/// l'ordre et le premier qui accepte l'emporte. C'est le report qui passe
/// d'abord — une action reportée et sans porteur se lit comme une dette de la
/// séance précédente, pas comme une nouveauté à distribuer.
@MainActor
enum ActionsRailGrouping {

    /// Identité d'un groupe. `reportees` porte la date de la réunion d'origine,
    /// `nil` quand l'action ne dit que son nombre de reports.
    enum Identite: Hashable, Sendable {
        case aAssigner
        case mesActions
        case deleguees
        case reportees(Date?)
    }

    /// Comment le groupe se rend : en cartes (`ActionCard`) ou en lignes
    /// compactes à puce ronde (les reportées, capture 1a).
    enum Rendu: Sendable {
        case cartes
        case lignes
    }

    struct Groupe: Identifiable {
        let identite: Identite
        /// « À assigner — 9 ». `SectionLabel` met en capitales, donc le libellé
        /// est écrit en casse normale et l'ordinal « 1er » y survit.
        let libelle: String
        let actions: [ActionTask]
        let rendu: Rendu
        var id: Identite { identite }
    }

    /// Une entrée de l'onglet Historique : une action close, abandonnée ou
    /// reportée, avec la date qui explique sa présence.
    struct Entree: Identifiable {
        enum Motif: Sendable {
            case close
            case reportee
        }
        let id: PersistentIdentifier
        let titre: String
        let date: Date?
        let motif: Motif
    }

    // MARK: - Groupes

    /// Les groupes ouverts du rail, dans l'ordre d'affichage. Un groupe vide
    /// n'est pas rendu — la spec veut une invite, pas un en-tête suivi de rien,
    /// et l'invite est le composeur en pied.
    static func groupes(for tasks: [ActionTask], calendar: Calendar = .current) -> [Groupe] {
        // `MeetingActionCounts.ouvertes` et non un filtre local : c'est la même
        // définition que les compteurs de l'onglet, du bandeau et de la nav du
        // mode Relire, et elle écarte aussi les lignes en attente de
        // suppression.
        let ouvertes = MeetingActionCounts.ouvertes(tasks)

        let reportees = ouvertes.filter(estReportee)
        let reste = ouvertes.filter { !estReportee($0) }
        let aAssigner = reste.filter { $0.destinataire != .moi && !aUnPorteur($0) }
        let miennes = reste.filter { $0.destinataire == .moi }
        let deleguees = reste.filter { $0.destinataire != .moi && aUnPorteur($0) }

        var resultat: [Groupe] = []
        if !aAssigner.isEmpty {
            resultat.append(Groupe(identite: .aAssigner,
                                   libelle: "À assigner — \(aAssigner.count)",
                                   actions: triees(aAssigner),
                                   rendu: .cartes))
        }
        if !miennes.isEmpty {
            resultat.append(Groupe(identite: .mesActions,
                                   libelle: "Mes actions — \(miennes.count)",
                                   actions: triees(miennes),
                                   rendu: .cartes))
        }
        if !deleguees.isEmpty {
            resultat.append(Groupe(identite: .deleguees,
                                   libelle: "Déléguées — \(deleguees.count)",
                                   actions: triees(deleguees),
                                   rendu: .cartes))
        }
        resultat.append(contentsOf: groupesReportes(reportees, calendar: calendar))
        return resultat
    }

    /// Les groupes `REPORTÉES DU <date>`, du plus récent au plus ancien, les
    /// actions sans réunion d'origine en dernier.
    private static func groupesReportes(_ reportees: [ActionTask],
                                        calendar: Calendar) -> [Groupe] {
        guard !reportees.isEmpty else { return [] }
        var parDate: [Date?: [ActionTask]] = [:]
        for action in reportees {
            parDate[action.carriedFromMeeting?.date, default: []].append(action)
        }
        // Tri sur `Date?` : les dates connues d'abord, décroissantes.
        let cles = parDate.keys.sorted { gauche, droite in
            switch (gauche, droite) {
            case let (g?, d?): return g > d
            case (nil, _?):    return false
            case (_?, nil):    return true
            case (nil, nil):   return false
            }
        }
        return cles.map { cle in
            let actions = triees(parDate[cle] ?? [])
            let libelle = cle.map { "Reportées du \(dateOrdinale($0, calendar: calendar)) — \(actions.count)" }
                ?? "Reportées — \(actions.count)"
            return Groupe(identite: .reportees(cle),
                          libelle: libelle,
                          actions: actions,
                          rendu: .lignes)
        }
    }

    // MARK: - Prédicats

    /// Reportée d'une réunion à la suivante : la trace de provenance ou le
    /// compteur suffit — un report peut avoir été fait avant que la colonne
    /// `carriedFromMeeting` existe.
    static func estReportee(_ task: ActionTask) -> Bool {
        task.carriedFromMeeting != nil || task.deferralCount > 0
    }

    /// Quelqu'un porte cette action. Un nom non résolu par l'extraction LLM
    /// (`unresolvedAssigneeName`) **compte** : l'action a un porteur, il n'est
    /// simplement pas encore relié à une fiche. Même règle que
    /// `MeetingKPIBuilder`, sinon le rail et la carte ACTIONS du bandeau
    /// afficheraient deux nombres différents pour la même réunion.
    static func aUnPorteur(_ task: ActionTask) -> Bool {
        if task.collaborator != nil { return true }
        guard let nom = task.unresolvedAssigneeName else { return false }
        return !nom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Tri

    /// Tri d'un groupe : `sortOrder` croissant, puis échéance (sans échéance en
    /// dernier), puis titre.
    ///
    /// `sortOrder` passe **avant** l'échéance, contrairement à l'ancien
    /// `ActionsPanel` : c'est ce qui permet au composeur de placer une action
    /// neuve en tête de son groupe (spec §2.5 « l'action apparaît en tête »)
    /// sans lui inventer une échéance, et c'est ce qui reproduit l'ordre de la
    /// capture de référence.
    static func triees(_ tasks: [ActionTask]) -> [ActionTask] {
        tasks.sorted { gauche, droite in
            if gauche.sortOrder != droite.sortOrder { return gauche.sortOrder < droite.sortOrder }
            let dg = gauche.dueDate ?? .distantFuture
            let dd = droite.dueDate ?? .distantFuture
            if dg != dd { return dg < dd }
            return gauche.title.localizedCaseInsensitiveCompare(droite.title) == .orderedAscending
        }
    }

    // MARK: - Historique

    /// Les actions closes, abandonnées et reportées de la réunion, les plus
    /// récentes d'abord. C'est l'onglet `Historique` de la spec §2.5.
    static func historique(for tasks: [ActionTask]) -> [Entree] {
        tasks.compactMap { action -> Entree? in
            switch action.status {
            case .done, .dropped:
                return Entree(id: action.persistentModelID,
                              titre: action.title,
                              date: action.completedAt,
                              motif: .close)
            case .open:
                guard estReportee(action) else { return nil }
                return Entree(id: action.persistentModelID,
                              titre: action.title,
                              date: action.carriedFromMeeting?.date,
                              motif: .reportee)
            }
        }
        .sorted { gauche, droite in
            let dg = gauche.date ?? .distantPast
            let dd = droite.date ?? .distantPast
            if dg != dd { return dg > dd }
            return gauche.titre.localizedCaseInsensitiveCompare(droite.titre) == .orderedAscending
        }
    }

    // MARK: - Date

    /// `1er sept.`, `11 sept.`, `31 août` — la forme du libellé de la capture
    /// (`REPORTÉES DU 1ER SEPT.`).
    ///
    /// Le premier du mois prend son ordinal : `Date.FormatStyle` ne le fait pas
    /// en français, et « Reportées du 1 sept. » se lit comme une faute.
    static func dateOrdinale(_ date: Date, calendar: Calendar = .current) -> String {
        let jour = calendar.component(.day, from: date)
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.locale = Locale(identifier: "fr_FR")
        style.timeZone = calendar.timeZone
        let mois = date.formatted(style)
        return jour == 1 ? "1er \(mois)" : "\(jour) \(mois)"
    }
}
