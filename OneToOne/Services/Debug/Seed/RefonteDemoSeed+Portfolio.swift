import Foundation
import SwiftData

/// Le portefeuille de démonstration de la refonte de la gestion des projets
/// (décision **D6**) : soixante-deux projets actifs sur huit entités, quatorze
/// archivés, avec les réunions, les jalons, les actions et les mails qu'il faut
/// pour photographier les captures `1a-portfolio.png`,
/// `1d-ecran-projet-pilotage.png` et `1f-vue-a-risque.png`.
///
/// **Une extension, comme les autres semis.** `seedPortfolio` ne réécrit rien
/// de `RefonteDemoSeed` ; il ne dépend pas non plus de `seed(in:)`, parce que
/// le portefeuille n'a rien à voir avec la réunion de `1a-cockpit.png` — les
/// deux jeux cohabitent dans le même store sans se connaître.
///
/// **Idempotent par `Project.code`, et jamais destructif.** Un projet dont le
/// code existe déjà est rendu tel quel : ni budget, ni jalon, ni interlocuteur
/// de démonstration ne lui sont plaqués, et aucun doublon n'est créé. Même
/// règle que `seedProject` du semis de réunion — un code du portefeuille de
/// démonstration peut très bien être celui d'un vrai projet.
///
/// **Les dates sont relatives au jour du semis.** La capture 1a affiche
/// « hier », « il y a 3 j », « il y a 2 sem. » ; la capture 1d « Deadline
/// design 09/09/2026 — J−0 » et un COPIL « du 08/09 » qui est la veille. Une
/// date absolue rendrait la recette juste un seul jour. Les décalages sont donc
/// comptés depuis `Date()`, ce qui reproduit exactement les captures un
/// 9 septembre 2026 et reste lisible tous les autres jours.
///
/// **Trois écarts assumés aux maquettes**, parce que les captures se
/// contredisent entre elles et que les décisions de la spec tranchent :
///
/// 1. La ligne `P25_193` de 1a affiche « Non affecté » et un risque « — »,
///    alors que 1d lui donne RIGAUT Manuel comme chef de projet et un risque
///    « Modéré ». 1d gagne : c'est la fiche détaillée, et la capture 1f dit que
///    ce projet est incomplet **par son sponsor**, pas par son chef de projet.
/// 2. La ligne `P25_099` de 1a affiche « NOMINE Laurent » et une pastille
///    orange, alors que 1f la range dans « fiche incomplète » avec « Pas de
///    chef de projet · statut inconnu ». 1f gagne, et la décision **D3** dit
///    pourquoi : la **relation** fait foi. Le projet garde donc le nom importé
///    du xlsx dans `chefDeProjet` — c'est lui qui préremplira le sélecteur de
///    l'action « Compléter » — mais `projectManager` reste `nil` et le statut
///    `Unknown`. La colonne de 1a affichera « Non affecté » : c'est le rendu
///    juste, pas un écart de semis.
/// 3. La ligne `P25_155` de 1a affiche une pastille neutre (statut inconnu) et
///    « jamais » de dernière réunion, et 1f la range dans « sans réunion depuis
///    30 j » (en écrivant « il y a 41 j », ce qui contredit « jamais »). Les
///    **comptes** de 1f font foi — 2 + 3 + 2 = 7, le nombre que porte aussi le
///    badge « À risque 7 » de 1a. Le projet est donc sans réunion et son statut
///    est connu, sinon il ferait un huitième motif.
@MainActor
extension RefonteDemoSeed {

    // MARK: - Ce que l'en-tête de la capture 1a annonce

    /// « 62 projets actifs · 8 entités ».
    static let portfolioActiveCount = 62
    /// La section « Projets Archivés » de la barre latérale.
    static let portfolioArchivedCount = 14
    /// Les huit entités, dans l'ordre d'apparition du menu de facettes.
    static let portfolioEntityNames = ["ASP", "RH", "FIN", "SI", "LOG", "COM", "JUR", "DSI"]

    /// Le code du projet de la capture `1d-ecran-projet-pilotage.png`.
    static let portfolioFocusProjectCode = "P25_193"

    /// L'identifiant stable de ce projet, **constant**.
    ///
    /// `RecetteScreen.p1d` route sur `.project(id, .pilotage)` : la table des
    /// écrans est statique, elle ne peut pas lire un identifiant tiré au sort
    /// au moment du semis. `nonisolated` parce que `RecetteScreen.cible` la lit
    /// hors de l'acteur principal — une constante immuable et `Sendable` s'y
    /// prête.
    nonisolated static let portfolioFocusProjectStableID =
        UUID(uuidString: "9E1D0A5C-1D4B-4E9A-9C7F-25193ABCDEF0")!

    /// Le terme que la palette de la capture `1c-palette-cmdk.png` porte.
    /// Ici parce que c'est le semis qui garantit qu'il trouve quelque chose :
    /// « Installation nouvelle GED » (actif) et « Migration GED documentaire »
    /// (archivé). `nonisolated` pour la même raison que l'identifiant ci-dessus :
    /// `RecetteScreen.termeDePalette` la lit hors de l'acteur principal.
    nonisolated static let portfolioPaletteQuery = "ged"

    /// Les trois projets que la sous-section « RÉCENTS » de la capture
    /// `2b-sidebar-variante-arbre-replie.png` liste, **dans l'ordre de la
    /// capture** (du plus récemment ouvert au plus ancien).
    ///
    /// Ici et non dans le semis lui-même : les récents sont un état de session
    /// (`@AppStorage`, décision **D4**), pas une donnée du store. Le semis ne
    /// les pose pas ; l'écran de recette `p2b` les inscrit par ces codes.
    /// `nonisolated` pour la même raison que `portfolioPaletteQuery` :
    /// `RecetteScreen` les lit hors de l'acteur principal.
    nonisolated static let portfolioRecentProjectCodes = ["P25_140", "P25_099", "P25_204"]

    // MARK: - Les gens de la maquette

    /// Les sept collaborateurs que les captures nomment.
    ///
    /// Réutilisés s'ils existent déjà, par comparaison de nom insensible à la
    /// casse — motif de `seedCollaborators` : semer ne doit pas créer un second
    /// « RIGAUT Manuel » dans une base réelle, et ne doit pas réécrire son rôle.
    static let portfolioPeople: [(nom: String, role: String)] = [
        ("RIGAUT Manuel", "Chef de projet"),
        ("PENVEN Yann", "Chef de projet"),
        ("THEDREZ Wilfried", "Architecte technique"),
        ("ORSET Jean-Baptiste", "Chef de projet"),
        ("PAOLI Nicolas", "Architecte technique"),
        ("NOMINE Laurent", "Manager"),
        ("ZANNETTINI François-Louis", "Architecte technique")
    ]

    // MARK: - Point d'entrée

    /// Sème le portefeuille et rend le projet de la capture 1d.
    ///
    /// - Returns: le projet `P25_193`, existant ou nouvellement créé. `nil` ne
    ///   se produit pas dans un store sain — seulement si l'insertion échoue.
    @discardableResult
    static func seedPortfolio(in context: ModelContext) -> Project? {
        let entites = seedPortfolioEntities(in: context)
        let gens = seedPortfolioPeople(in: context)

        var parCode: [String: Project] = [:]
        for gabarit in portfolioGabarits {
            parCode[gabarit.code] = seedPortfolioProject(gabarit,
                                                          entites: entites,
                                                          gens: gens,
                                                          in: context)
        }

        semerPortfolioFocus(parCode[portfolioFocusProjectCode], gens: gens, in: context)
        semerPortfolioActionsDeRemplissage(parCode, gens: gens, in: context)

        try? context.save()
        return parCode[portfolioFocusProjectCode]
    }

    // MARK: - Entités et collaborateurs

    private static func seedPortfolioEntities(in context: ModelContext) -> [String: Entity] {
        let existantes = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        var resultat: [String: Entity] = [:]
        for nom in portfolioEntityNames {
            if let trouvee = existantes.first(where: { $0.name == nom }) {
                resultat[nom] = trouvee
                continue
            }
            let entite = Entity(name: nom)
            context.insert(entite)
            resultat[nom] = entite
        }
        return resultat
    }

    private static func seedPortfolioPeople(in context: ModelContext) -> [String: Collaborator] {
        let existants = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
        var resultat: [String: Collaborator] = [:]
        for personne in portfolioPeople {
            if let trouve = existants.first(where: {
                $0.name.localizedCaseInsensitiveCompare(personne.nom) == .orderedSame
            }) {
                resultat[personne.nom] = trouve
                continue
            }
            let collaborateur = Collaborator(name: personne.nom, role: personne.role)
            context.insert(collaborateur)
            resultat[personne.nom] = collaborateur
        }
        return resultat
    }

    // MARK: - Un projet du portefeuille

    /// Crée le projet du gabarit, ou rend celui qui porte déjà ce code sans y
    /// toucher.
    private static func seedPortfolioProject(_ gabarit: PortfolioGabarit,
                                             entites: [String: Entity],
                                             gens: [String: Collaborator],
                                             in context: ModelContext) -> Project {
        let code = gabarit.code
        if let existant = (try? context.fetch(
            FetchDescriptor<Project>(predicate: #Predicate { $0.code == code })
        ))?.first {
            // Un projet réel peut porter ce code. Le semis ne lui plaque ni
            // jalon, ni réunion, ni action de démonstration.
            return existant
        }

        let projet = Project(code: gabarit.code,
                             name: gabarit.nom,
                             domain: gabarit.entite,
                             sponsor: gabarit.sponsor,
                             projectType: gabarit.type,
                             phase: gabarit.phase,
                             status: gabarit.statut)
        projet.entity = entites[gabarit.entite]
        projet.isArchived = gabarit.archive
        projet.pinned = gabarit.epingle
        projet.riskLevel = gabarit.risque
        projet.chefDeProjet = gabarit.chefDeProjet
        projet.architecte = gabarit.architecte
        // D3 : la **relation** fait foi. Un gabarit peut porter le nom sans la
        // relation — c'est le cas « fiche incomplète » de la capture 1f.
        if gabarit.chefLie { projet.projectManager = gens[gabarit.chefDeProjet] }
        projet.technicalArchitect = gens[gabarit.architecte]
        if gabarit.code == portfolioFocusProjectCode {
            projet.stableID = portfolioFocusProjectStableID
        }
        context.insert(projet)

        if let jalon = gabarit.jalon {
            let milestone = ProjectMilestone(label: jalon.libelle,
                                             dueAt: jour(decale: jalon.jours),
                                             state: .planned,
                                             order: 0)
            context.insert(milestone)
            milestone.project = projet
        }

        if let jours = gabarit.derniereReunion {
            let reunion = Meeting(title: "Point projet \(gabarit.code)",
                                  date: jour(decale: -jours),
                                  notes: "")
            reunion.kind = .project
            reunion.project = projet
            context.insert(reunion)
        }

        return projet
    }

    // MARK: - Le projet de la capture 1d

    /// Complète `P25_193` : périmètre, risque, charge, interlocuteurs, ses neuf
    /// réunions, ses six actions ouvertes, ses deux mails et ses trois
    /// suggestions de rattachement.
    ///
    /// Ne fait rien si le projet portait déjà des jalons ou des interlocuteurs :
    /// c'est le signe qu'il est réel (ou déjà semé), et la garde d'idempotence
    /// de cette moitié du semis.
    private static func semerPortfolioFocus(_ projet: Project?,
                                            gens: [String: Collaborator],
                                            in context: ModelContext) {
        guard let projet, projet.contacts.isEmpty, projet.mails.isEmpty else { return }
        // Un projet réel ne se laisse pas garnir : la garde ci-dessus suffit
        // dans le store de recette, mais un vrai `P25_193` sans interlocuteur
        // existerait. On vérifie donc aussi que c'est bien notre projet.
        guard projet.stableID == portfolioFocusProjectStableID else { return }

        projet.scopeText = """
        Reprise des services IO historiquement hébergés chez l’association ALP : \
        annuaire, échanges de fichiers, supervision. Le lot annuaire est sorti du \
        périmètre v1 (COPIL 08/09). Dépendance forte au chantier « Sécurisation \
        des flux inter-sites ».
        """
        projet.riskDescription = """
        Disponibilité de l’équipe ALP en octobre non confirmée — impact possible \
        sur la fin de design.
        """
        // « CHARGE · 48 / 60 j » et « Deadline design … — J−0 » de la capture 1d.
        projet.plannedDays = 60
        projet.budgetCons = 48
        projet.designEndDeadline = jour(decale: 0)

        for (index, contact) in [("RIGAUT Manuel", "Chef de projet"),
                                 ("THEDREZ Wilfried", "Architecte technique")].enumerated() {
            let ligne = ProjectContact(name: contact.0, role: contact.1, order: index)
            context.insert(ligne)
            ligne.project = projet
        }

        let reunions = semerPortfolioFocusReunions(projet, in: context)
        semerPortfolioFocusActions(projet, copil: reunions.copil, gens: gens, in: context)
        semerPortfolioFocusMails(projet, in: context)
    }

    /// Les trois réunions nommées de la carte « DERNIÈRES RÉUNIONS », plus six
    /// plus anciennes : la tuile RYTHME annonce « 9 réunions / 12 sem. ».
    private static func semerPortfolioFocusReunions(
        _ projet: Project,
        in context: ModelContext
    ) -> (copil: Meeting, atelier: Meeting, unAUn: Meeting) {
        // « hier » — la tuile DERNIÈRE RÉUNION, et le « COPIL du 08/09 » que
        // cite la première action.
        let copil = Meeting(title: "Arbitrage périmètre IO", date: jour(decale: -1), notes: "")
        copil.kind = .project
        copil.project = projet
        copil.meetingDurationSeconds = 45 * 60
        copil.decisions = ["Le lot « annuaire » sort du périmètre v1"]
        copil.shortSummary = """
        Décision : le lot « annuaire » sort du périmètre v1. 3 actions créées, \
        CR envoyé au sponsor.
        """
        context.insert(copil)
        // Décision **D10** : « COPIL » se lit dans les thèmes ou le titre —
        // `MeetingKind` n'a pas de cas COPIL, et n'en aura pas.
        if let theme = MeetingTag.findOrCreate(name: "COPIL", in: context) {
            copil.tags.append(theme)
        }

        let atelier = Meeting(title: "Cadrage technique avec l’ALP",
                              date: jour(decale: -8), notes: "")
        atelier.kind = .workshop
        atelier.project = projet
        atelier.shortSummary = "Choix d’architecture retenu : passerelle IO mutualisée."
        context.insert(atelier)

        let unAUn = Meeting(title: "Point d’avancement — PENVEN Yann",
                            date: jour(decale: -19), notes: "")
        unAUn.kind = .oneToOne
        unAUn.project = projet
        context.insert(unAUn)

        // Les six autres réunions des douze dernières semaines : elles ne
        // portent que leur date, c'est tout ce que la tuile RYTHME compte.
        for (index, jours) in [26, 33, 40, 54, 61, 75].enumerated() {
            let reunion = Meeting(title: "Point hebdomadaire IO \(index + 1)",
                                  date: jour(decale: -jours), notes: "")
            reunion.kind = .project
            reunion.project = projet
            context.insert(reunion)
        }

        return (copil, atelier, unAUn)
    }

    /// Les six actions ouvertes de la carte « ACTIONS EN COURS » : deux en
    /// retard, une non affectée.
    private static func semerPortfolioFocusActions(_ projet: Project,
                                                   copil: Meeting,
                                                   gens: [String: Collaborator],
                                                   in context: ModelContext) {
        let gabarits: [(titre: String, porteur: String?, echeance: Int?, issueDuCopil: Bool)] = [
            ("Valider le périmètre IO avec l’ALP", "RIGAUT Manuel", -3, true),
            ("Chiffrer la reprise de données", "PENVEN Yann", -1, false),
            ("Rédiger le DAT", "THEDREZ Wilfried", 5, false),
            ("Planifier l’atelier sécurité", nil, nil, false),
            ("Préparer la reprise de l’annuaire en v2", "PENVEN Yann", 12, false),
            ("Recetter les échanges de fichiers", "THEDREZ Wilfried", 19, false)
        ]
        for (index, gabarit) in gabarits.enumerated() {
            let action = ActionTask(title: gabarit.titre)
            action.sortOrder = index
            action.project = projet
            action.destinataire = .collaborateur
            if let porteur = gabarit.porteur { action.collaborator = gens[porteur] }
            if let jours = gabarit.echeance { action.dueDate = jour(decale: jours) }
            if gabarit.issueDuCopil { action.meeting = copil }
            context.insert(action)
        }
    }

    /// Les deux mails de la carte « MAILS LIÉS » et les trois suggestions de
    /// l'invite « 3 mails à rattacher à ce projet ».
    ///
    /// `MailBrowserView` et `MailSuggestionService` étaient classés « code mort
    /// à arbitrer » dans `architecture.md` §13 : ils ne le sont plus dès ce
    /// chantier, et il faut donc de quoi les regarder.
    private static func semerPortfolioFocusMails(_ projet: Project,
                                                 in context: ModelContext) {
        // Les identifiants sont **écrits**, pas dérivés d'un `hashValue` : le
        // hachage des chaînes de Swift est semé par processus, deux exécutions
        // ne donneraient pas la même clé de déduplication.
        let mails: [(id: String, sujet: String, expediteur: String, jours: Int)] = [
            ("demo-portfolio-mail-1", "RE : périmètre v1 — annuaire", "contact@alp.example", 1),
            ("demo-portfolio-mail-2", "Planning atelier sécurité", "THEDREZ Wilfried", 5)
        ]
        for gabarit in mails {
            let mail = ProjectMail(messageId: gabarit.id,
                                   accountName: "APRIL",
                                   mailbox: "Réception",
                                   subject: gabarit.sujet,
                                   sender: gabarit.expediteur,
                                   dateReceived: jour(decale: -gabarit.jours))
            context.insert(mail)
            mail.project = projet
        }

        let suggestions: [(id: String, sujet: String, expediteur: String,
                           jours: Int, score: Double)] = [
            ("demo-portfolio-suggestion-1", "Devis passerelle IO — v2",
             "commercial@alp.example", 2, 0.72),
            ("demo-portfolio-suggestion-2", "Comptes de service à créer",
             "exploitation@april.example", 3, 0.64),
            ("demo-portfolio-suggestion-3", "CR atelier sécurité du mois dernier",
             "THEDREZ Wilfried", 6, 0.58)
        ]
        for gabarit in suggestions {
            let suggestion = MailIndexSuggestion(
                messageId: gabarit.id,
                accountName: "APRIL",
                mailbox: "Réception",
                subject: gabarit.sujet,
                sender: gabarit.expediteur,
                dateReceived: jour(decale: -gabarit.jours),
                preview: "…",
                confidence: gabarit.score
            )
            context.insert(suggestion)
            suggestion.suggestedProject = projet
        }
    }

    // MARK: - Les autres actions ouvertes

    /// Les dix-sept projets qui portent une action ouverte de remplissage.
    ///
    /// La barre latérale de la capture 1a annonce « Actions 23 » : six sont
    /// celles de `P25_193`, les dix-sept autres sont ici. La liste est
    /// **déterministe et nommée** — les dix-sept premiers projets actifs autres
    /// que celui de la capture 1d — et non le résultat d'un compteur parcourant
    /// la table : un compteur qui n'avance qu'en posant une action ferait
    /// glisser le semis sur dix-sept **autres** projets à la seconde exécution,
    /// et l'idempotence tomberait.
    static var portfolioFillerActionCodes: [String] {
        portfolioGabarits
            .filter { !$0.archive && $0.code != portfolioFocusProjectCode }
            .prefix(17)
            .map(\.code)
    }

    private static func semerPortfolioActionsDeRemplissage(
        _ parCode: [String: Project],
        gens: [String: Collaborator],
        in context: ModelContext
    ) {
        let libelles = [
            "Relancer l’éditeur sur le devis",
            "Valider la maquette avec le métier",
            "Compléter le dossier d’architecture",
            "Planifier la recette utilisateurs",
            "Chiffrer la reprise de l’historique",
            "Obtenir l’accord du sponsor",
            "Vérifier les prérequis d’exploitation"
        ]
        let porteurs = portfolioPeople.map(\.nom)
        for (rang, code) in portfolioFillerActionCodes.enumerated() {
            guard let projet = parCode[code] else { continue }
            let titre = libelles[rang % libelles.count]
            // Un projet réel porte déjà ses actions : on n'y ajoute rien.
            guard projet.tasks.isEmpty else { continue }
            let action = ActionTask(title: titre)
            action.project = projet
            action.destinataire = .collaborateur
            action.collaborator = gens[porteurs[rang % porteurs.count]]
            // Jamais échue : « en retard » est réservé aux deux actions de la
            // capture 1d.
            action.dueDate = jour(decale: 7 + rang)
            context.insert(action)
        }
    }

    // MARK: - Dates

    /// Le jour décalé de `jours` par rapport à aujourd'hui, à midi.
    ///
    /// Midi et non minuit : une échéance comparée à `startOfDay` ne doit pas
    /// basculer d'un jour selon le fuseau ou l'heure d'été.
    private static func jour(decale jours: Int) -> Date {
        let calendrier = Calendar.current
        let midiAujourdHui = calendrier.date(bySettingHour: 12, minute: 0, second: 0,
                                             of: Date()) ?? Date()
        return calendrier.date(byAdding: .day, value: jours, to: midiAujourdHui) ?? midiAujourdHui
    }

    // MARK: - La table des projets

    /// Les onze projets nommés par les captures, puis les soixante-cinq qui
    /// remplissent le portefeuille.
    ///
    /// Les nommés gardent le code de leur capture (`P25_112`, `P25_193`…), hors
    /// de la plage des autres : c'est ce code que la maquette affiche, et le
    /// renuméroter rendrait la comparaison au pixel impossible. Les deux que
    /// la capture 1f nomme sans code (`RH – TIME & APPLI`,
    /// `FIN – Refonte facturation fournisseurs`) en reçoivent un du même
    /// millésime.
    static var portfolioGabarits: [PortfolioGabarit] {
        portfolioNamedGabarits + portfolioFillerGabarits
    }

    private static var portfolioNamedGabarits: [PortfolioGabarit] {
        [
            // Les huit lignes du tableau de la capture 1a, dans l'ordre.
            PortfolioGabarit(
                code: "P25_112", nom: "ASP – BLOOM", entite: "ASP", type: "Métier",
                phase: "Build", statut: "Red", sponsor: "Direction ASP",
                chefDeProjet: "RIGAUT Manuel", chefLie: true,
                architecte: "THEDREZ Wilfried", risque: "Modéré",
                epingle: true, archive: false,
                jalon: (libelle: "Livraison du lot 2", jours: 4),
                derniereReunion: 3),
            PortfolioGabarit(
                code: "P25_193", nom: "AE – Gestion des services IO pour l’association ALP",
                entite: "ASP", type: "Métier",
                phase: "Design", statut: "Green",
                // Capture 1f : « Sponsor non renseigné ». C'est ce vide qui
                // range le projet dans « fiche incomplète ».
                sponsor: "",
                chefDeProjet: "RIGAUT Manuel", chefLie: true,
                architecte: "THEDREZ Wilfried", risque: "Modéré",
                epingle: true, archive: false,
                jalon: (libelle: "Fin de design", jours: 21),
                // Les neuf réunions du projet sont semées à part
                // (`semerPortfolioFocusReunions`) : la dernière est « hier ».
                derniereReunion: nil),
            PortfolioGabarit(
                code: "P25_087", nom: "ASP – Installation nouvelle GED", entite: "ASP",
                type: "Métier", phase: "Build", statut: "Yellow",
                sponsor: "Direction ASP",
                chefDeProjet: "PENVEN Yann", chefLie: true,
                architecte: "PAOLI Nicolas", risque: "Élevé",
                epingle: true, archive: false,
                // Capture 1f : « Recette utilisateurs · échue depuis 6 j ».
                jalon: (libelle: "Recette utilisateurs", jours: -6),
                derniereReunion: 8),
            PortfolioGabarit(
                code: "P25_140", nom: "ASP – Sécurisation des flux inter-sites",
                entite: "ASP", type: "Technique", phase: "Cadrage", statut: "Green",
                sponsor: "Direction technique",
                chefDeProjet: "THEDREZ Wilfried", chefLie: true,
                architecte: "PAOLI Nicolas", risque: "Modéré",
                epingle: false, archive: false,
                jalon: (libelle: "Validation du cadrage", jours: 35),
                derniereReunion: 14),
            PortfolioGabarit(
                code: "P25_155", nom: "ASP – Intégration « NEVIDIS » Filiale",
                entite: "ASP", type: "Métier", phase: "Design",
                // Écart n° 3 : 1a montre une pastille neutre, mais un statut
                // inconnu ferait un huitième motif « à risque ».
                statut: "Green",
                sponsor: "Direction filiale",
                chefDeProjet: "ORSET Jean-Baptiste", chefLie: true,
                architecte: "PAOLI Nicolas", risque: nil,
                epingle: false, archive: false,
                jalon: nil,
                // « jamais » — motif « sans réunion depuis 30 j » de la 1f.
                derniereReunion: nil),
            PortfolioGabarit(
                code: "P25_061", nom: "ASP – Mise en place d’une infrastructure de sauvegarde",
                entite: "ASP", type: "Technique", phase: "Run", statut: "Green",
                sponsor: "Direction technique",
                chefDeProjet: "PAOLI Nicolas", chefLie: true,
                architecte: "ZANNETTINI François-Louis", risque: nil,
                epingle: false, archive: false,
                jalon: (libelle: "Bascule du dernier site", jours: 60),
                derniereReunion: 5),
            PortfolioGabarit(
                code: "P25_099", nom: "ASP – Obsolescence de la VM applicative",
                entite: "ASP", type: "Technique", phase: "Build",
                // Capture 1f : « Pas de chef de projet · statut inconnu ».
                statut: "Unknown",
                sponsor: "Direction technique",
                chefDeProjet: "NOMINE Laurent",
                // Écart n° 2, décision D3 : le nom vient du xlsx, la relation
                // manque — c'est ce qui rend la fiche incomplète.
                chefLie: false,
                architecte: "ZANNETTINI François-Louis", risque: "Modéré",
                epingle: false, archive: false,
                jalon: (libelle: "Décommissionnement", jours: 12),
                derniereReunion: 4),
            PortfolioGabarit(
                code: "P25_121", nom: "ASP – Sécurisation IBMi Netserver", entite: "ASP",
                type: "Technique", phase: "Run", statut: "Green",
                sponsor: "Direction technique",
                chefDeProjet: "ZANNETTINI François-Louis", chefLie: true,
                architecte: "PAOLI Nicolas", risque: nil,
                epingle: false, archive: false,
                jalon: (libelle: "Audit de conformité", jours: 90),
                // « il y a 1 mois » en 1a, « il y a 34 j » en 1f.
                derniereReunion: 34),

            // Les deux autres projets que la capture 1f nomme.
            PortfolioGabarit(
                code: "P25_204", nom: "RH – TIME & APPLI", entite: "RH",
                type: "Métier", phase: "Build", statut: "Yellow",
                sponsor: "Direction RH",
                chefDeProjet: "NOMINE Laurent", chefLie: true,
                architecte: "THEDREZ Wilfried", risque: "Élevé",
                epingle: false, archive: false,
                // Capture 1f : « Livraison prod · échue depuis 2 j ».
                jalon: (libelle: "Livraison prod", jours: -2),
                derniereReunion: 2),
            PortfolioGabarit(
                code: "P25_178", nom: "FIN – Refonte facturation fournisseurs",
                entite: "FIN", type: "Métier", phase: "Cadrage", statut: "Green",
                sponsor: "Direction financière",
                chefDeProjet: "ORSET Jean-Baptiste", chefLie: true,
                architecte: "PAOLI Nicolas", risque: "Modéré",
                epingle: false, archive: false,
                jalon: (libelle: "Choix de la solution", jours: 45),
                // Capture 1f : « Aucune réunion enregistrée ».
                derniereReunion: nil),

            // L'archivé que la palette de la capture 1c fait remonter sur « ged ».
            PortfolioGabarit(
                code: "P24_211", nom: "RH – Migration GED documentaire", entite: "RH",
                type: "Métier", phase: "Run", statut: "Green",
                sponsor: "Direction RH",
                chefDeProjet: "PENVEN Yann", chefLie: true,
                architecte: "THEDREZ Wilfried", risque: nil,
                epingle: false, archive: true,
                jalon: nil,
                derniereReunion: 20),
        ]
    }

    /// Les soixante-cinq projets qui font le volume : cinquante-deux actifs et
    /// treize archivés, répartis sur les huit entités.
    ///
    /// Entièrement **déterministes** : le nom, la phase, le statut, le risque et
    /// les dates découlent de l'indice. Un semis au hasard rendrait deux
    /// captures de recette incomparables.
    ///
    /// Aucun ne peut tomber dans un motif « à risque » : le jalon est toujours
    /// à venir, la dernière réunion toujours à moins de trente jours, le
    /// sponsor renseigné, le chef de projet lié et le statut connu. Les sept
    /// projets de la capture 1f sont nommés, et ils sont les seuls.
    private static var portfolioFillerGabarits: [PortfolioGabarit] {
        let libelles = [
            "Refonte du portail", "Migration de la base de données",
            "Socle d’authentification", "Dématérialisation des dossiers",
            "Pilotage budgétaire", "Reprise de l’historique",
            "Automatisation des relances", "Tableau de bord décisionnel",
            "Sécurisation des accès distants", "Modernisation des postes",
            "Interfaçage avec l’éditeur", "Archivage légal",
            "Consolidation des référentiels", "Passage en infrastructure hébergée",
            "Refonte des états réglementaires", "Portail fournisseurs",
            "Traçabilité des échanges", "Supervision applicative",
            "Reprise du plan de secours", "Gestion des habilitations",
            "Optimisation des sauvegardes", "Industrialisation des déploiements",
            "Refonte de la facturation interne", "Cartographie des flux",
            "Reprise de l’annuaire technique", "Portail des collaborateurs"
        ]
        let statuts = ["Green", "Yellow", "Green", "Green"]
        let risques: [String?] = [nil, "Faible", "Modéré", "Faible"]
        let porteurs = portfolioPeople.map(\.nom)
        // Ce que les projets nommés ne fournissent pas.
        let nommes = portfolioNamedGabarits
        let actifs = portfolioActiveCount - nommes.filter { !$0.archive }.count
        let archives = portfolioArchivedCount - nommes.filter(\.archive).count

        // Les codes des projets nommés sont **réservés** : `P25_061` tombe dans
        // la plage de remplissage, et le réutiliser faisait un projet de moins
        // que les soixante-seize annoncés.
        let reserves = Set(nommes.map(\.code))
        var codes: [String] = []
        var numero = 1
        while codes.count < actifs + archives {
            let code = String(format: "P25_%03d", numero)
            if !reserves.contains(code) { codes.append(code) }
            numero += 1
        }

        return codes.enumerated().map { (index, code) in
            let entite = portfolioEntityNames[index % portfolioEntityNames.count]
            let libelle = libelles[(index / portfolioEntityNames.count) % libelles.count]
            return PortfolioGabarit(
                code: code,
                nom: "\(entite) – \(libelle)",
                entite: entite,
                type: ProjectType.allLabels[index % ProjectType.allLabels.count],
                phase: ProjectPhase.allLabels[index % ProjectPhase.allLabels.count],
                statut: statuts[index % statuts.count],
                sponsor: "Direction \(entite)",
                chefDeProjet: porteurs[index % porteurs.count], chefLie: true,
                architecte: porteurs[(index + 2) % porteurs.count],
                risque: risques[index % risques.count],
                epingle: false,
                archive: index >= actifs,
                jalon: (libelle: "Jalon suivant", jours: 10 + index % 50),
                derniereReunion: 2 + index % 25)
        }
    }
}

/// Un projet du portefeuille de démonstration, tel que les captures le
/// décrivent. Les dates sont des **décalages en jours** par rapport au jour du
/// semis, jamais des dates absolues.
struct PortfolioGabarit {
    let code: String
    let nom: String
    let entite: String
    let type: String
    let phase: String
    let statut: String
    let sponsor: String
    /// Le nom libre, tel que l'import xlsx l'écrit dans `Project.chefDeProjet`.
    let chefDeProjet: String
    /// La relation `Project.projectManager` est-elle posée ? Décision **D3** :
    /// c'est elle qui fait foi, et son absence rend la fiche incomplète.
    let chefLie: Bool
    let architecte: String
    let risque: String?
    let epingle: Bool
    let archive: Bool
    /// Jalon unique : son libellé et son échéance, en jours relatifs.
    let jalon: (libelle: String, jours: Int)?
    /// Jours écoulés depuis la dernière réunion. `nil` = jamais de réunion.
    let derniereReunion: Int?
}
