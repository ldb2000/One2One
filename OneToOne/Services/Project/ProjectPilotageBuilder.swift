import Foundation
import SwiftData

/// Tout ce que l'onglet « Pilotage » de l'écran projet affiche, calculé **une
/// fois** depuis le modèle (capture `1d-ecran-projet-pilotage.png`, décision
/// **D11**).
///
/// Aucune vue de l'onglet ne relit `Project` pour compter, trier ou formater :
/// elle lirait des relations dont SwiftData ne garantit pas l'ordre, et le
/// rendu changerait d'une ouverture à l'autre. Même motif que `PortfolioRow` /
/// `PortfolioBuilder` au lot 2 et que `ProjectCardState` sur la fiche de
/// réunion.
///
/// La structure est `Equatable` pour que la vue puisse ignorer un
/// rechargement qui ne change rien — d'où les sous-structures nommées plutôt
/// que les tuples de l'esquisse : un tuple ne conforme à aucun protocole.
struct ProjectPilotageState: Equatable, Sendable {

    // MARK: - Les quatre tuiles

    /// La tuile « DERNIÈRE RÉUNION » : « hier » et « COPIL · 45 min ».
    struct LastMeeting: Equatable, Sendable {
        var date: Date
        /// Libellé relatif — « aujourd'hui », « hier », « il y a 3 j »…
        /// (`PortfolioBuilder.relativeLabel`, une seule règle dans le dépôt).
        var label: String
        /// « COPIL · 45 min ». Sans durée connue, le type seul.
        var kindLine: String
    }

    /// La tuile « CHARGE » : « 48 / 60 j » et sa barre de 4 pt.
    struct Charge: Equatable, Sendable {
        var spent: Double?
        var planned: Double?
        /// « 48 », ou `nil` quand rien n'est consommé.
        var spentLabel: String?
        /// « / 60 j », ou `nil` quand le nombre de jours n'est pas connu.
        var plannedLabel: String?
        /// Part remplie de la barre, bornée 0…1. `nil` = pas de barre : un
        /// dépassement se lit au chiffre, il ne déborde pas du cadre.
        var ratio: Double?
        /// Ni consommé ni prévu : la tuile affiche un tiret.
        var estVide: Bool { spentLabel == nil && plannedLabel == nil }
    }

    // MARK: - Les cartes

    /// Une ligne de « ACTIONS EN COURS ».
    struct ActionRow: Identifiable, Equatable, Sendable {
        /// La teinte de l'échéance, à droite de la ligne.
        enum Echeance: Equatable, Sendable {
            /// « retard 3 j ».
            case retard(Int)
            /// « 14/09 ».
            case date(String)
            /// « — ».
            case aucune
        }

        var id: PersistentIdentifier
        var title: String
        /// « RIGAUT Manuel », ou « Non affecté » (décision **D3**).
        var porteur: String
        /// « issue du COPIL du 08/09 », ou `nil` quand la réunion d'origine
        /// n'est pas identifiable.
        var origine: String?
        var echeance: Echeance

        /// « RIGAUT Manuel · issue du COPIL du 08/09 ».
        var sousLigne: String {
            [porteur, origine].compactMap { $0 }.joined(separator: " · ")
        }

        /// « retard 3 j » · « 14/09 » · « — ».
        var echeanceLabel: String {
            switch echeance {
            case .retard(let jours): return "retard \(jours) j"
            case .date(let texte):   return texte
            case .aucune:            return ProjectPilotageBuilder.tiret
            }
        }

        var enRetard: Bool {
            if case .retard = echeance { return true }
            return false
        }
    }

    /// Une ligne de « DERNIÈRES RÉUNIONS ».
    struct MeetingRow: Identifiable, Equatable, Sendable {
        var id: PersistentIdentifier
        var stableID: UUID?
        var date: Date
        /// « 08/09 », en mono sur 44 pt.
        var dateLabel: String
        var badge: MeetingTypeBadge?
        var titre: String
        /// Le résumé de décision, vide quand la réunion n'en porte aucun.
        var resume: String
    }

    /// Une ligne de « MAILS LIÉS ».
    struct MailRow: Identifiable, Equatable, Sendable {
        var id: PersistentIdentifier
        var sujet: String
        /// « ALP · hier », « THEDREZ W. · 04/09 ».
        var sousLigne: String
    }

    /// Une ligne de « INTERLOCUTEURS ».
    struct PersonRow: Identifiable, Equatable, Sendable {
        /// Le rôle sert d'identité : il y a au plus une ligne par rôle.
        var id: String { role }
        var nom: String
        var role: String
        /// `stableID` du collaborateur lié, quand la relation existe : c'est
        /// lui qui rend le raccourci « 1:1 ▸ » cliquable.
        var collaboratorID: UUID?
        /// Rôle non pourvu : ligne en pointillés, « Sponsor à renseigner ».
        var aRenseigner: Bool
    }

    /// Une ligne de « IDENTITÉ ».
    struct IdentityRow: Identifiable, Equatable, Sendable {
        var id: String { libelle }
        var libelle: String
        var valeur: String
        /// Le code projet est en Plex Mono ; le reste en Plex Sans.
        var mono: Bool = false
        /// « — / — » se lit en `inkMuted`, une valeur renseignée en `ink2`.
        var absente: Bool = false
    }

    // MARK: - Tuiles

    var openActions: Int = 0
    var lateActions: Int = 0
    var lastMeeting: LastMeeting?
    /// Huit barres, une par semaine et demie sur douze semaines.
    var rhythm: [Int] = []
    /// « 9 réunions / 12 sem. ».
    var rhythmLabel: String = ""
    var charge: Charge = Charge()

    // MARK: - Cartes

    var actions: [ActionRow] = []
    var meetings: [MeetingRow] = []
    var mails: [MailRow] = []
    var pendingMailSuggestions: Int = 0
    /// « 3 mails à rattacher à ce projet », ou `nil` quand il n'y en a aucun.
    var pendingMailLabel: String?
    /// Le nombre total de mails du projet — le badge de l'onglet « Mails ».
    var mailCount: Int = 0
    var scopeText: String = ""
    /// « Cliquer pour éditer · dernière mise à jour hier ».
    var scopeFooter: String = ""

    // MARK: - Colonne latérale

    var people: [PersonRow] = []
    var risk: RiskLevel?
    /// La valeur persistée, affichée telle quelle hors table (décision **D14**).
    var riskRaw: String = ""
    var riskDescription: String = ""
    var identity: [IdentityRow] = []

    // MARK: - En-tête

    /// « Deadline design 09/09/2026 — J−0 », posé seulement à sept jours ou
    /// moins de l'échéance.
    var deadlineAlert: String?
}

/// Le constructeur de `ProjectPilotageState` : une fonction pure, testée sur
/// le semis de démonstration avant que la moindre vue n'existe.
///
/// Les règles qu'il porte — et qu'aucune vue ne refera :
///
/// - **En retard** = action ouverte dont l'échéance est passée (décision
///   **D11**), comparée au **début du jour** : une action due aujourd'hui à
///   midi n'est pas en retard à quinze heures.
/// - **Les actions en retard d'abord**, de la plus vieille échéance à la plus
///   récente ; les autres dans l'ordre manuel de la liste d'actions
///   (`ActionTask.sortOrder`), qui est l'ordre que la capture montre.
/// - **Les réunions tenues seulement** (`MeetingStatsScope.held`) et passées :
///   une note n'est pas une réunion, une réunion planifiée n'est pas la
///   dernière.
enum ProjectPilotageBuilder {

    // MARK: - Constantes de la capture 1d

    /// Nombre d'actions montrées sur la carte « ACTIONS EN COURS ».
    static let maxActions = 4
    /// Nombre de réunions montrées sur la carte « DERNIÈRES RÉUNIONS ».
    static let maxMeetings = 3
    /// Nombre de mails montrés dans la carte « MAILS LIÉS ».
    static let maxMails = 3
    /// Fenêtre de la tuile « RYTHME », en semaines.
    static let rhythmWeeks = 12
    /// Nombre de barres de la tuile « RYTHME ».
    static let rhythmBars = 8
    /// Seuil de l'alerte de deadline de l'en-tête, en jours.
    static let deadlineAlertDays = 7
    /// Le tiret d'une valeur absente — cadratin, comme partout ailleurs.
    static let tiret = "—"
    /// Le signe moins **typographique** de « J−0 » (U+2212), celui de
    /// `MilestoneCell.libelle`.
    static let moins = "\u{2212}"

    // MARK: - Construction

    static func build(project: Project,
                      meetings: [Meeting],
                      suggestions: [MailIndexSuggestion],
                      today: Date) -> ProjectPilotageState {
        var etat = ProjectPilotageState()

        let debutDuJour = Calendar.current.startOfDay(for: today)
        let siennes = reunionsDuProjet(project, parmi: meetings, today: today)
        let ouvertes = project.tasks.filter { $0.status == .open }

        // Tuiles.
        etat.openActions = ouvertes.count
        etat.lateActions = ouvertes.filter { estEnRetard($0, debutDuJour: debutDuJour) }.count
        etat.lastMeeting = derniereReunion(siennes, today: today)
        etat.rhythm = rythme(siennes, today: today)
        etat.rhythmLabel = libelleDuRythme(etat.rhythm.reduce(0, +))
        etat.charge = charge(of: project)

        // Cartes de la colonne principale.
        etat.actions = lignesDActions(ouvertes, debutDuJour: debutDuJour)
        etat.meetings = lignesDeReunions(siennes)
        etat.scopeText = project.scopeText
        etat.scopeFooter = piedDuPerimetre(project, today: today)

        // Mails.
        let tries = project.mails.sorted { $0.dateReceived > $1.dateReceived }
        etat.mailCount = tries.count
        etat.mails = tries.prefix(maxMails).map { mail in
            ProjectPilotageState.MailRow(
                id: mail.persistentModelID,
                sujet: mail.subject,
                sousLigne: [expediteurAbrege(mail.sender),
                            dateDeMail(mail.dateReceived, today: today)].joined(separator: " · ")
            )
        }
        etat.pendingMailSuggestions = suggestions.filter {
            $0.suggestedProject?.persistentModelID == project.persistentModelID
        }.count
        etat.pendingMailLabel = libelleDesSuggestions(etat.pendingMailSuggestions)

        // Colonne latérale.
        etat.people = interlocuteurs(of: project)
        etat.riskRaw = project.riskLevel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        etat.risk = RiskLevel(raw: etat.riskRaw)
        etat.riskDescription = project.riskDescription ?? ""
        etat.identity = identite(of: project)

        // En-tête.
        etat.deadlineAlert = alerteDeDeadline(project, debutDuJour: debutDuJour)

        return etat
    }

    // MARK: - Réunions

    /// Les réunions **tenues et passées** du projet, de la plus récente à la
    /// plus ancienne.
    static func reunionsDuProjet(_ project: Project,
                                 parmi meetings: [Meeting],
                                 today: Date) -> [Meeting] {
        MeetingStatsScope.held(meetings)
            .filter { $0.project?.persistentModelID == project.persistentModelID }
            .filter { $0.date <= today }
            .sorted { $0.date > $1.date }
    }

    private static func derniereReunion(_ siennes: [Meeting],
                                        today: Date) -> ProjectPilotageState.LastMeeting? {
        guard let derniere = siennes.first else { return nil }
        return ProjectPilotageState.LastMeeting(
            date: derniere.date,
            label: PortfolioBuilder.relativeLabel(from: derniere.date, today: today),
            kindLine: ligneDeType(derniere)
        )
    }

    /// « COPIL · 45 min ». Sans durée connue, le type seul — jamais
    /// « · 0 min », qui ferait croire à une réunion vide.
    static func ligneDeType(_ meeting: Meeting) -> String {
        let type = MeetingTypeBadge.from(meeting)?.libelle ?? meeting.kind.label
        let minutes = Int((meeting.effectiveDuration / 60).rounded())
        return minutes > 0 ? "\(type) · \(minutes) min" : type
    }

    private static func lignesDeReunions(_ siennes: [Meeting]) -> [ProjectPilotageState.MeetingRow] {
        siennes.prefix(maxMeetings).map { reunion in
            ProjectPilotageState.MeetingRow(
                id: reunion.persistentModelID,
                stableID: reunion.stableID,
                date: reunion.date,
                dateLabel: jourEtMois(reunion.date),
                badge: MeetingTypeBadge.from(reunion),
                titre: reunion.title,
                resume: resumeDeDecision(reunion)
            )
        }
    }

    /// Le résumé montré sous le titre d'une réunion : **la première décision**,
    /// à défaut le résumé court.
    ///
    /// Dans cet ordre parce que la carte s'appelle « résumé de **décision** »
    /// (handoff §1d) : ce qui a été tranché prime sur ce qui a été raconté.
    /// La maquette, elle, écrit le résumé court des deux réunions qui en
    /// portent un — écart assumé et signalé dans le rapport du lot.
    static func resumeDeDecision(_ meeting: Meeting) -> String {
        if let premiere = meeting.decisionEntries.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !premiere.isEmpty {
            return premiere
        }
        return meeting.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rythme

    /// Le nombre de réunions par barre, de la plus ancienne à la plus récente.
    ///
    /// Douze semaines réparties en huit barres : chaque barre couvre dix jours
    /// et demi. Une réunion plus vieille que la fenêtre n'est comptée nulle
    /// part — la tuile dit « / 12 sem. », elle doit le tenir.
    static func rythme(_ siennes: [Meeting], today: Date) -> [Int] {
        var barres = [Int](repeating: 0, count: rhythmBars)
        let calendrier = Calendar.current
        let fin = calendrier.startOfDay(for: today)
        let joursParBarre = Double(rhythmWeeks * 7) / Double(rhythmBars)
        for reunion in siennes {
            let jours = calendrier.dateComponents([.day],
                                                  from: calendrier.startOfDay(for: reunion.date),
                                                  to: fin).day ?? 0
            guard jours >= 0 else { continue }
            let recul = Int(Double(jours) / joursParBarre)
            let index = rhythmBars - 1 - recul
            guard index >= 0 else { continue }
            barres[index] += 1
        }
        return barres
    }

    /// « 9 réunions / 12 sem. » — et « 1 réunion » au singulier.
    static func libelleDuRythme(_ total: Int) -> String {
        "\(total) \(total == 1 ? "réunion" : "réunions") / \(rhythmWeeks) sem."
    }

    // MARK: - Charge

    static func charge(of project: Project) -> ProjectPilotageState.Charge {
        let consomme = project.budgetCons
        let prevu = project.plannedDays
        var ratio: Double?
        if let consomme, let prevu, prevu > 0 {
            ratio = min(max(consomme / prevu, 0), 1)
        }
        return ProjectPilotageState.Charge(
            spent: consomme,
            planned: prevu,
            spentLabel: consomme.map(nombre(_:)),
            plannedLabel: prevu.map { "/ \(nombre($0)) j" },
            ratio: ratio
        )
    }

    /// « 48 » et non « 48,0 » : un nombre de jours entier s'écrit sans
    /// décimale, un demi-jour la garde.
    static func nombre(_ valeur: Double) -> String {
        valeur == valeur.rounded()
            ? String(Int(valeur.rounded()))
            : String(format: "%.1f", valeur).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Actions

    static func estEnRetard(_ task: ActionTask, debutDuJour: Date) -> Bool {
        guard task.status == .open, let echeance = task.dueDate else { return false }
        return Calendar.current.startOfDay(for: echeance) < debutDuJour
    }

    /// Les quatre lignes de la carte : les retards d'abord, du plus ancien au
    /// plus récent ; puis les autres dans l'ordre manuel de la liste.
    ///
    /// **Pas par échéance croissante** pour la seconde moitié : la capture 1d
    /// montre « Planifier l'atelier sécurité », sans échéance, en quatrième
    /// ligne — devant deux actions datées de la semaine suivante. C'est
    /// l'ordre de la liste d'actions du projet, `sortOrder`, que le lecteur a
    /// posé lui-même.
    static func lignesDActions(_ ouvertes: [ActionTask],
                               debutDuJour: Date,
                               limite: Int = maxActions) -> [ProjectPilotageState.ActionRow] {
        let retards = ouvertes.filter { estEnRetard($0, debutDuJour: debutDuJour) }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let reste = ouvertes.filter { !estEnRetard($0, debutDuJour: debutDuJour) }
            .sorted { gauche, droite in
                if gauche.sortOrder != droite.sortOrder { return gauche.sortOrder < droite.sortOrder }
                return gauche.title.localizedStandardCompare(droite.title) == .orderedAscending
            }
        return (retards + reste).prefix(max(limite, 0)).map { tache in
            ProjectPilotageState.ActionRow(
                id: tache.persistentModelID,
                title: tache.title,
                porteur: tache.collaborator?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilSiVide ?? ProjectPeople.nonAffecte,
                origine: origine(de: tache),
                echeance: echeance(de: tache, debutDuJour: debutDuJour)
            )
        }
    }

    /// « issue du COPIL du 08/09 ».
    ///
    /// Seulement quand la réunion d'origine porte un **badge** : « issue de la
    /// réunion projet du 08/09 » n'apprend rien sur un écran qui ne montre que
    /// les réunions de ce projet.
    static func origine(de task: ActionTask) -> String? {
        guard let reunion = task.meeting, let badge = MeetingTypeBadge.from(reunion) else { return nil }
        return "issue du \(badge.libelle) du \(jourEtMois(reunion.date))"
    }

    static func echeance(de task: ActionTask,
                         debutDuJour: Date) -> ProjectPilotageState.ActionRow.Echeance {
        guard let due = task.dueDate else { return .aucune }
        let jours = Calendar.current.dateComponents([.day],
                                                    from: Calendar.current.startOfDay(for: due),
                                                    to: debutDuJour).day ?? 0
        return jours > 0 ? .retard(jours) : .date(jourEtMois(due))
    }

    // MARK: - Périmètre

    /// « Cliquer pour éditer · dernière mise à jour hier ».
    ///
    /// La maquette écrit « par RIGAUT Manuel, hier » ; le modèle ne garde pas
    /// **qui** a touché le périmètre, et l'inventer serait pire que de le
    /// taire (rapport du lot). Sans date d'édition, le pied se réduit à
    /// l'invitation.
    static func piedDuPerimetre(_ project: Project, today: Date) -> String {
        let invitation = "Cliquer pour éditer"
        guard let maj = project.scopeUpdatedAt else { return invitation }
        return "\(invitation) · dernière mise à jour \(PortfolioBuilder.relativeLabel(from: maj, today: today))"
    }

    // MARK: - Mails

    /// « ALP », « THEDREZ W. ».
    ///
    /// Une adresse rend le premier morceau de son domaine en majuscules (c'est
    /// l'organisation qui écrit, pas la boîte aux lettres) ; un nom de
    /// personne garde son premier mot et abrège les suivants.
    static func expediteurAbrege(_ sender: String) -> String {
        let net = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !net.isEmpty else { return tiret }
        if let arobase = net.firstIndex(of: "@") {
            let domaine = net[net.index(after: arobase)...]
            if let premier = domaine.split(separator: ".").first, !premier.isEmpty {
                return premier.uppercased()
            }
            return String(domaine).uppercased()
        }
        let mots = net.split(separator: " ")
        guard mots.count > 1 else { return net }
        let suite = mots.dropFirst().compactMap { $0.first.map { "\($0)." } }
        return ([String(mots[0])] + suite).joined(separator: " ")
    }

    /// « hier » tant que c'est hier ou aujourd'hui, « 04/09 » au-delà : un
    /// mail vieux d'une semaine se repère par sa date, pas par un décompte.
    static func dateDeMail(_ date: Date, today: Date) -> String {
        let jours = Calendar.current.dateComponents([.day],
                                                    from: Calendar.current.startOfDay(for: date),
                                                    to: Calendar.current.startOfDay(for: today)).day ?? 0
        return jours <= 1 ? PortfolioBuilder.relativeLabel(from: date, today: today)
                          : jourEtMois(date)
    }

    /// « 3 mails à rattacher à ce projet », `nil` à zéro.
    static func libelleDesSuggestions(_ nombre: Int) -> String? {
        guard nombre > 0 else { return nil }
        return "\(nombre) mail\(nombre == 1 ? "" : "s") à rattacher à ce projet"
    }

    // MARK: - Colonne latérale

    /// Les trois rôles de la capture, dans l'ordre : chef de projet,
    /// architecte technique, sponsor.
    ///
    /// **La relation fait foi** (décision **D3**) : un rôle sans
    /// `Collaborator` lié est « à renseigner », même si la colonne libre
    /// importée du xlsx porte un nom — et c'est cette ligne en pointillés qui
    /// dit à quoi la fiche est incomplète.
    static func interlocuteurs(of project: Project) -> [ProjectPilotageState.PersonRow] {
        [
            ligneDePersonne(nom: ProjectPeople.manager(of: project),
                            role: "Chef de projet",
                            collaborateur: project.projectManager),
            ligneDePersonne(nom: ProjectPeople.architect(of: project),
                            role: "Architecte technique",
                            collaborateur: project.technicalArchitect),
            ligneDePersonne(nom: project.sponsor.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVide,
                            role: "Sponsor",
                            collaborateur: nil)
        ]
    }

    private static func ligneDePersonne(nom: String?,
                                        role: String,
                                        collaborateur: Collaborator?) -> ProjectPilotageState.PersonRow {
        ProjectPilotageState.PersonRow(
            nom: nom ?? "\(role) à renseigner",
            role: role,
            collaboratorID: nom == nil ? nil : collaborateur?.stableID,
            aRenseigner: nom == nil
        )
    }

    /// Les cinq lignes de la carte « IDENTITÉ ».
    static func identite(of project: Project) -> [ProjectPilotageState.IdentityRow] {
        let domaine = [project.entity?.name, project.domain]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVide }
            .first
        let finDesign = project.designEndDeadline.map(jourMoisAnnee(_:))
        return [
            .init(libelle: "Code", valeur: project.code.nilSiVide ?? tiret,
                  mono: true, absente: project.code.isEmpty),
            .init(libelle: "Domaine", valeur: domaine ?? tiret, absente: domaine == nil),
            .init(libelle: "Jours", valeur: project.plannedDays.map(nombre(_:)) ?? tiret,
                  absente: project.plannedDays == nil),
            .init(libelle: "Fin design", valeur: finDesign ?? tiret, absente: finDesign == nil),
            .init(libelle: "DAT / DIT", valeur: documents(of: project),
                  absente: !project.hasDAT && !project.hasDIT)
        ]
    }

    /// « ✓ / — » : la coche pour un document déposé, le tiret sinon.
    static func documents(of project: Project) -> String {
        "\(project.hasDAT ? "✓" : tiret) / \(project.hasDIT ? "✓" : tiret)"
    }

    // MARK: - Alerte de deadline

    /// « Deadline design 09/09/2026 — J−0 », posée à sept jours ou moins.
    ///
    /// Une échéance **dépassée** la porte aussi, et dit son retard : la faire
    /// disparaître le jour où elle compte le plus serait le pire moment.
    static func alerteDeDeadline(_ project: Project, debutDuJour: Date) -> String? {
        guard let echeance = project.designEndDeadline else { return nil }
        let jours = Calendar.current.dateComponents([.day],
                                                    from: debutDuJour,
                                                    to: Calendar.current.startOfDay(for: echeance)).day ?? 0
        guard jours <= deadlineAlertDays else { return nil }
        let reste = jours >= 0 ? "J\(moins)\(jours)" : "retard \(-jours) j"
        return "Deadline design \(jourMoisAnnee(echeance)) — \(reste)"
    }

    // MARK: - Dates

    /// « 08/09 ».
    static func jourEtMois(_ date: Date) -> String {
        formateur(jourEtMoisFormat).string(from: date)
    }

    /// « 09/09/2026 ».
    static func jourMoisAnnee(_ date: Date) -> String {
        formateur(jourMoisAnneeFormat).string(from: date)
    }

    private static let jourEtMoisFormat = "dd/MM"
    private static let jourMoisAnneeFormat = "dd/MM/yyyy"

    /// Les formateurs sont mis en cache : en construire un par ligne de carte
    /// coûterait plus cher que tout le reste du calcul.
    private static let cache = FormatterCache()

    private static func formateur(_ format: String) -> DateFormatter {
        cache.formatter(format)
    }

    /// Cache verrouillé : `build` n'est pas isolé à un acteur, et un
    /// `DateFormatter` partagé sans verrou n'est pas sûr.
    private final class FormatterCache: @unchecked Sendable {
        private let verrou = NSLock()
        private var formateurs: [String: DateFormatter] = [:]

        func formatter(_ format: String) -> DateFormatter {
            verrou.lock()
            defer { verrou.unlock() }
            if let connu = formateurs[format] { return connu }
            let neuf = DateFormatter()
            neuf.locale = Locale(identifier: "fr_FR")
            neuf.dateFormat = format
            formateurs[format] = neuf
            return neuf
        }
    }
}

private extension String {
    /// La chaîne, ou `nil` si elle est vide — pour enchaîner les replis d'un
    /// champ facultatif sans multiplier les `if`.
    var nilSiVide: String? { isEmpty ? nil : self }
}
