import Foundation
import SwiftData

/// Le jeu de démonstration des **quatre captures 1:1** :
/// `2a-1to1-manager-seance.png`, `2b-1to1-manager-preparation.png`,
/// `5a-1to1-collaborateur-seance.png`, `5b-1to1-collaborateur-preparation.png`.
///
/// Deux fils, un par rôle, comme les captures : je manage **Laurent NOMINÉ**
/// (2a, 2b) et **Yann PENVEN** me manage (5a, 5b). Les deux vivent en même
/// temps dans la base — c'est la situation d'un manager intermédiaire, et c'est
/// ce que les lots 11 à 14 doivent afficher côte à côte.
///
/// Extension et non modification de `RefonteDemoSeed.swift` : ce fichier
/// appartient au lot 1 et sert la recette de tous les lots.
///
/// **L'arithmétique des captures est tenue exactement** — 14ᵉ entretien,
/// 8 tenus sur 11 (taux 73 %), tendance « en baisse », `Charge de travail · 5`,
/// 56 jours de demande sans réponse (donc `warn`, pas `report`). Un jeu
/// approximatif rendrait la comparaison à la maquette impossible à trancher.
@MainActor
extension RefonteDemoSeed {

    // MARK: - Constantes des captures

    static let managerThreadCollaborator = "Laurent NOMINÉ"
    static let managerThreadRole = "Ingénieur CI/CD"
    static let collaboratorThreadManager = "Yann PENVEN"

    /// 4 septembre 2026, 9:15 à Paris — la date des quatre captures.
    static var oneOnOneSeedDate: Date { Date(timeIntervalSince1970: 1_788_506_100) }
    private static var jour: TimeInterval { 86_400 }

    /// Nombre d'entretiens du fil manager : la capture 2b dit « 14ᵉ 1:1 ».
    static let managerThreadSessionCount = 14

    /// Les six crans de l'histogramme de la capture 2b, du plus ancien au plus
    /// récent : `12/06 26/06 10/07 24/07 21/08 04/09`.
    ///
    /// Moyenne des deux derniers 3,0 contre 4,33 pour les trois précédents :
    /// la tendance est « en baisse », et la dernière barre est `Sous tension`,
    /// ce que la capture 2a confirme (`↓ vs 21 août (Bien)`).
    static let managerThreadMoods: [Int] = [3, 4, 5, 4, 4, 2]

    // MARK: - Point d'entrée

    /// Sème les deux fils 1:1 et les rend.
    ///
    /// Idempotent : semer deux fois ne duplique ni les fils, ni les
    /// entretiens, ni les engagements. Une commande de menu se clique deux
    /// fois, et un doublon de recette serait pire qu'inutile.
    @discardableResult
    static func seedOneOnOneThreads(in context: ModelContext)
        -> (manager: OneOnOneThread, collaborator: OneOnOneThread) {
        (seedManagerThread(in: context), seedCollaboratorThread(in: context))
    }

    // MARK: - Fil manager (captures 2a, 2b)

    @discardableResult
    private static func seedManagerThread(in context: ModelContext) -> OneOnOneThread {
        let laurent = oneOnOnePerson(named: managerThreadCollaborator,
                                     role: managerThreadRole,
                                     email: "laurent.nomine@example.com",
                                     in: context)
        laurent.oneToOneCadence = .bimensuelle

        let seances = seedSessions(for: laurent, kind: .oneToOne,
                                   count: managerThreadSessionCount, in: context)
        guard let fil = OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context) else {
            fatalError("le fil d'un .oneToOne existe toujours")
        }

        // Humeurs : les six dernières séances, une par séance (remplacement
        // garanti par `MoodTrend.record`, donc idempotent).
        for (decalage, valeur) in managerThreadMoods.enumerated() {
            let index = seances.count - managerThreadMoods.count + decalage
            guard seances.indices.contains(index) else { continue }
            MoodTrend.record(valeur, for: seances[index], in: fil, in: context)
        }

        seedObjectives(fil, in: context)
        seedManagerCommitments(fil, seances.last, in: context)
        seedManagerAgenda(fil, seances.last, in: context)
        seedManagerNotes(seances, in: context)
        seedManagerHistoryNotes(seances, in: context)
        seedManagerClosedActions(laurent, in: context)

        try? context.save()
        return fil
    }

    /// Les deux mentions **antérieures** de charge, qui portent le comptage à
    /// `Charge de travail · 5` (chip de la capture 2b) et justifient la phrase
    /// « Cause citée deux fois : charge sur la migration AP ».
    ///
    /// Elles vivent sur les séances du 24 juillet et du 21 août, ce que dit
    /// l'`HISTORIQUE` de la capture 2b (« Charge signalée une 1re fois »).
    private static func seedManagerHistoryNotes(_ seances: [Meeting],
                                                in context: ModelContext) {
        let mentions: [(depuisLaFin: Int, texte: String)] = [
            (1, "Charge signalée une première fois : la migration AP déborde."),
            (2, "Il ne tient plus le rythme sur les deux migrations en parallèle.")
        ]
        for mention in mentions {
            let index = seances.count - 1 - mention.depuisLaFin
            guard seances.indices.contains(index) else { continue }
            let seance = seances[index]
            guard seance.timedNotes.isEmpty else { continue }
            seance.notesMigrated = true
            let note = MeetingNote(t: 0, text: mention.texte, kind: .note, visibility: .shared)
            context.insert(note)
            note.meeting = seance
        }
    }

    /// Les actions closes de Laurent — la matière de la règle 3 « réussite
    /// récente non reconnue ».
    ///
    /// Celle du 1er septembre est **déjà citée** dans le feedback de la séance
    /// du 4 septembre : la règle 3 ne la fait donc pas remonter, et c'est le
    /// bon comportement. La capture 2b est l'écran de *préparation*, tenu avant
    /// que ce feedback n'existe ; une fois le feedback donné, le rappel doit
    /// disparaître.
    private static func seedManagerClosedActions(_ laurent: Collaborator,
                                                 in context: ModelContext) {
        guard laurent.assignedTasks.isEmpty else { return }
        let livrables: [(String, Double)] = [
            ("la reprise du périmètre Nexus", -6),
            ("la présentation COSUI", -3)
        ]
        for livrable in livrables {
            let action = ActionTask(title: livrable.0)
            action.collaborator = laurent
            action.isCompleted = true
            action.completedAt = oneOnOneSeedDate.addingTimeInterval(livrable.1 * jour)
            action.createdAt = oneOnOneSeedDate.addingTimeInterval((livrable.1 - 20) * jour)
            context.insert(action)
        }
    }

    /// Les trois objectifs S2 de la capture 2b, revue le 18 septembre.
    private static func seedObjectives(_ fil: OneOnOneThread, in context: ModelContext) {
        guard fil.objectives.isEmpty else { return }
        let revue = oneOnOneSeedDate.addingTimeInterval(14 * jour)
        let objectifs: [(String, Int)] = [
            ("Industrialiser la CI/CD", 70),
            ("Monter en compétence archi", 25),
            ("Transmettre (formation Admin)", 10)
        ]
        for (rang, objectif) in objectifs.enumerated() {
            let entree = OneOnOneObjective(label: objectif.0, progress: objectif.1,
                                           reviewAt: revue, order: rang)
            context.insert(entree)
            entree.thread = fil
        }
    }

    /// Les onze engagements de la capture 2b : huit tenus, trois non tenus,
    /// dont celui du manager reporté deux fois. `8 / 11 = 73 %`.
    private static func seedManagerCommitments(_ fil: OneOnOneThread,
                                               _ derniere: Meeting?,
                                               in context: ModelContext) {
        guard fil.commitments.isEmpty else { return }

        /// Les quatre lignes visibles du tableau, aux dates de la capture.
        let visibles: [(texte: String, cote: OneOnOneSide, etat: CommitmentState,
                        echeance: Double?, pris: Double, reports: Int)] = [
            ("Arbitrer renfort ou décalage du Webcast", .manager, .open, 1, 0, 0),
            // « En retard » sur la capture : échéance du 24 juillet, deux
            // reports. C'est la ligne qui fait la pilule « 1 en retard côté
            // manager » et le premier rappel « À ne pas oublier ».
            ("Retour sur la grille d'astreinte", .manager, .open, -42, -42, 2),
            ("Cadrer la formation Admin (plan + 2 dates)", .collaborator, .open, 7, 0, 0),
            ("Reprise du périmètre Nexus", .collaborator, .kept, nil, -14, 0)
        ]
        for (rang, ligne) in visibles.enumerated() {
            let engagement = Commitment(
                text: ligne.texte,
                ownerSide: ligne.cote,
                dueAt: ligne.echeance.map { oneOnOneSeedDate.addingTimeInterval($0 * jour) },
                state: ligne.etat,
                promisedAt: oneOnOneSeedDate.addingTimeInterval(ligne.pris * jour)
            )
            engagement.deferralCount = ligne.reports
            if ligne.etat != .open {
                engagement.settledAt = oneOnOneSeedDate.addingTimeInterval(-13 * jour)
            }
            engagement.promisedInMeeting = derniere
            context.insert(engagement)
            engagement.thread = fil
            _ = rang
        }

        // Le reste de l'historique, pour tenir « 8 tenus sur 11 · taux 73 % » :
        // sept tenus de plus (le huitième est dans les lignes visibles) et
        // trois manqués. `8 / (8 + 3) = 73 %` ; les trois engagements encore
        // ouverts ne comptent pas dans le taux, comme sur la capture.
        //
        // Les trois manqués sont **côté collaborateur** : la capture 2b
        // n'affiche qu'un seul rappel de règle 1 (« Vous lui devez un retour
        // sur la grille d'astreinte »), et un manqué côté manager en
        // ajouterait un second.
        let historique: [(String, CommitmentState, OneOnOneSide)] = [
            ("Accès environnement recette", .kept, .collaborator),
            ("Chiffrage de la reprise AP v1", .kept, .collaborator),
            ("Revue du pipeline Jenkins", .kept, .manager),
            ("Point avec Claire-Amélie sur l'archi", .kept, .manager),
            ("Cadrage du webcast développeurs", .kept, .collaborator),
            ("Ouverture des comptes GitLab", .kept, .manager),
            ("Rétrospective de la migration AP", .kept, .collaborator),
            ("Relecture du dossier d'architecture", .missed, .collaborator),
            ("Compte rendu du COSUI de juin", .missed, .collaborator),
            ("Estimation du lot 2 de la migration", .missed, .collaborator)
        ]
        for (rang, ligne) in historique.enumerated() {
            let quand = oneOnOneSeedDate.addingTimeInterval(Double(-70 + rang * 5) * jour)
            let engagement = Commitment(text: ligne.0, ownerSide: ligne.2,
                                        state: ligne.1, promisedAt: quand)
            engagement.settledAt = quand.addingTimeInterval(7 * jour)
            context.insert(engagement)
            engagement.thread = fil
        }
    }

    /// Les quatre sujets de l'ordre du jour de la capture 2a, dont le dernier
    /// est reporté (`→ 18/09`).
    private static func seedManagerAgenda(_ fil: OneOnOneThread,
                                          _ derniere: Meeting?,
                                          in context: ModelContext) {
        guard fil.agendaItems.isEmpty else { return }
        let sujets: [(String, OneOnOneSide, AgendaItemState)] = [
            ("Charge de travail sur la migration AP — je sature", .collaborator, .todo),
            ("Retour sur la présentation COSUI du 1er sept.", .manager, .todo),
            ("Formation Admin : est-ce que je peux la porter ?", .collaborator, .todo),
            ("Point objectifs S2", .manager, .deferred)
        ]
        for (rang, sujet) in sujets.enumerated() {
            let item = OneOnOneAgendaItem(text: sujet.0, addedBySide: sujet.1,
                                          order: rang, state: sujet.2,
                                          visibility: .shared)
            context.insert(item)
            item.thread = fil
            item.meeting = derniere
        }
    }

    /// Les notes horodatées de la capture 2a, dont la note privée isolée et les
    /// deux cartes de feedback.
    private static func seedManagerNotes(_ seances: [Meeting], in context: ModelContext) {
        guard let derniere = seances.last, derniere.timedNotes.isEmpty else { return }
        derniere.notesMigrated = true

        let lignes: [(t: Double, texte: String, nature: MeetingNoteKind,
                      visibilite: Visibility, auteur: MeetingSide)] = [
            (160, "Deux migrations en parallèle + astreinte. Dit « tenir » mais ne prend plus de recul. À surveiller.",
             .note, .shared, .me),
            (375, "Charge AP — estime 3 j-h de reprise non prévus ; demande soit un renfort, soit de décaler le Webcast.",
             .note, .shared, .collaborator),
            (782, "Formation Admin — veut la porter et l'animer. Motivé, c'est cohérent avec son envie d'archi.",
             .note, .shared, .collaborator),
            (1_050, "Risque de départ si la mobilité archi n'avance pas d'ici la fin d'année. En parler à Claire-Amélie.",
             .note, .private, .me),
            (1_680, "Présentation COSUI très claire — le passage sur les risques Jenkins a débloqué la décision. À refaire au COPIL.",
             .feedback, .shared, .me),
            (1_700, "Les arbitrages budget arrivent trop tard : il apprend les décisions en séance projet. Demande un point amont.",
             .feedback, .shared, .collaborator)
        ]
        for (rang, ligne) in lignes.enumerated() {
            let note = MeetingNote(t: ligne.t, text: ligne.texte, kind: ligne.nature,
                                   visibility: ligne.visibilite, authorSide: ligne.auteur,
                                   orderIndex: rang)
            context.insert(note)
            note.meeting = derniere
        }

        // Trois thèmes, qui alimentent le comptage des sujets récurrents.
        for nom in ["Charge de travail", "Mobilité archi", "Astreintes"] {
            let theme = existingTag(named: nom, in: context) ?? {
                let nouveau = MeetingTag(name: nom)
                context.insert(nouveau)
                return nouveau
            }()
            if !derniere.tags.contains(where: { $0.name == nom }) {
                derniere.tags.append(theme)
            }
        }
    }

    // MARK: - Fil collaborateur (captures 5a, 5b)

    @discardableResult
    private static func seedCollaboratorThread(in context: ModelContext) -> OneOnOneThread {
        let yann = oneOnOnePerson(named: collaboratorThreadManager,
                                  role: "Manager",
                                  email: "yann.penven@example.com",
                                  in: context)
        yann.oneToOneCadence = .bimensuelle

        let seances = seedSessions(for: yann, kind: .manager, count: 4, in: context)
        guard let fil = OneOnOneThreadStore.thread(for: yann, kind: .manager, in: context) else {
            fatalError("le fil d'un .manager existe toujours")
        }

        seedCollaboratorRequests(fil, seances.last, in: context)
        seedManagerPromises(fil, seances.last, in: context)
        seedCollaboratorNotes(seances.last, in: context)

        try? context.save()
        return fil
    }

    /// Les trois demandes de la capture 5a.
    ///
    /// La première est datée du **10 juillet** : 56 jours au 4 septembre, donc
    /// `Sans réponse` en `warn` — la capture ne la montre pas en `report`, et
    /// le seuil est bien à 60 jours.
    private static func seedCollaboratorRequests(_ fil: OneOnOneThread,
                                                 _ derniere: Meeting?,
                                                 in context: ModelContext) {
        guard fil.agendaItems.isEmpty else { return }
        let demandes: [(String, RequestStatus, Double, Int)] = [
            ("Mobilité vers l'architecture", .pending, -56, 2),
            ("Compensation des astreintes", .waiting, -42, 0),
            ("Budget formation Terraform", .granted, -70, 0)
        ]
        for (rang, demande) in demandes.enumerated() {
            let item = OneOnOneAgendaItem(
                text: demande.0,
                addedBySide: .collaborator,
                order: rang,
                state: demande.1 == .granted ? .done : .todo,
                visibility: .private,
                kind: .request,
                requestStatus: demande.1,
                requestedAt: oneOnOneSeedDate.addingTimeInterval(demande.2 * jour)
            )
            item.remindedCount = demande.3
            context.insert(item)
            item.thread = fil
            item.meeting = derniere
        }

        // Les trois sujets privés de « CE QUE JE VEUX DIRE » (capture 5a).
        let miens = [
            "Charge : deux migrations + astreinte, je ne tiens pas le rythme",
            "Mobilité archi : je veux une réponse ferme cette fois",
            "Porter la formation Admin"
        ]
        for (rang, texte) in miens.enumerated() {
            let item = OneOnOneAgendaItem(text: texte, addedBySide: .collaborator,
                                          order: demandes.count + rang,
                                          visibility: .private)
            context.insert(item)
            item.thread = fil
            item.meeting = derniere
        }
    }

    /// Les trois promesses du manager de la capture 5a, dont une en retard de
    /// deux reports et une reportée trois fois.
    private static func seedManagerPromises(_ fil: OneOnOneThread,
                                            _ derniere: Meeting?,
                                            in context: ModelContext) {
        guard fil.commitments.isEmpty else { return }
        let promesses: [(texte: String, echeance: Double?, pris: Double, reports: Int)] = [
            ("Grille de compensation des astreintes", -42, -42, 2),
            ("Arbitrage renfort / décalage Webcast", 1, 0, 0),
            // « Janvier », soit environ quatre mois : la carte est loin, mais
            // le compteur de reports est le signal.
            ("Point mobilité avec Claire-Amélie", 119, -56, 3)
        ]
        for promesse in promesses {
            let engagement = Commitment(
                text: promesse.texte,
                // Toujours côté manager : c'est *lui* qui a promis (spec §6.2).
                ownerSide: .manager,
                dueAt: promesse.echeance.map { oneOnOneSeedDate.addingTimeInterval($0 * jour) },
                promisedAt: oneOnOneSeedDate.addingTimeInterval(promesse.pris * jour),
                visibility: .private
            )
            engagement.deferralCount = promesse.reports
            engagement.promisedInMeeting = derniere
            context.insert(engagement)
            engagement.thread = fil
        }
    }

    /// Les notes de la capture 5a : deux sections et le bloc `POUR MOI SEUL`.
    private static func seedCollaboratorNotes(_ derniere: Meeting?, in context: ModelContext) {
        guard let derniere, derniere.timedNotes.isEmpty else { return }
        derniere.notesMigrated = true

        let lignes: [(t: Double, texte: String, nature: MeetingNoteKind,
                      visibilite: Visibility, auteur: MeetingSide)] = [
            (200, "Retour positif sur le COSUI du 1er sept. — veut que je le refasse au COPIL du 25.",
             .feedback, .private, .manager),
            (545, "Sur la charge : il arbitre vendredi entre un renfort et le décalage du Webcast. Pas d'engagement chiffré.",
             .note, .private, .manager),
            (990, "Mobilité archi : « pas avant la fin de la migration ». À reposer en janvier avec Claire-Amélie.",
             .promise, .private, .manager),
            (400, "Posé les 3 j-h de reprise non prévus, chiffres à l'appui (capture du chiffrage v3).",
             .proof, .private, .me),
            (1_070, "3ᵉ report sur la mobilité. Si rien en janvier, je regarde ailleurs — à garder en tête pour l'entretien annuel.",
             .note, .private, .me)
        ]
        for (rang, ligne) in lignes.enumerated() {
            let note = MeetingNote(t: ligne.t, text: ligne.texte, kind: ligne.nature,
                                   visibility: ligne.visibilite, authorSide: ligne.auteur,
                                   orderIndex: rang)
            context.insert(note)
            note.meeting = derniere
        }
    }

    // MARK: - Fabriques idempotentes

    /// La personne du fil, réutilisée si l'annuaire la connaît déjà : semer ne
    /// doit pas créer un second « Laurent NOMINÉ » dans une base réelle.
    private static func oneOnOnePerson(named nom: String,
                                       role: String,
                                       email: String,
                                       in context: ModelContext) -> Collaborator {
        let existants = (try? context.fetch(FetchDescriptor<Collaborator>())) ?? []
        if let trouve = existants.first(where: {
            $0.name.localizedCaseInsensitiveCompare(nom) == .orderedSame
        }) {
            if trouve.email.isEmpty { trouve.email = email }
            return trouve
        }
        let personne = Collaborator(name: nom, role: role)
        personne.email = email
        context.insert(personne)
        return personne
    }

    /// Les `count` derniers entretiens du fil, à la cadence de quinze jours, le
    /// dernier tombant le 4 septembre 2026.
    ///
    /// Idempotent par le **titre** : chaque séance porte son rang, donc semer
    /// deux fois retrouve les mêmes réunions au lieu d'en créer 14 de plus.
    private static func seedSessions(for personne: Collaborator,
                                     kind: MeetingKind,
                                     count: Int,
                                     in context: ModelContext) -> [Meeting] {
        let prefixe = kind == .oneToOne
            ? "1:1 — \(personne.name.split(separator: " ").first.map(String.init) ?? personne.name)"
            : "1:1 avec \(personne.name.split(separator: " ").first.map(String.init) ?? personne.name)"

        var seances: [Meeting] = []
        for rang in 1...count {
            let titre = "\(prefixe) · \(rang)"
            if let existante = (try? context.fetch(
                FetchDescriptor<Meeting>(predicate: #Predicate { $0.title == titre })
            ))?.first {
                seances.append(existante)
                continue
            }
            let decalage = Double(rang - count) * 14 * jour
            let seance = Meeting(title: titre,
                                 date: oneOnOneSeedDate.addingTimeInterval(decalage),
                                 notes: "")
            seance.kind = kind
            seance.durationSeconds = kind == .oneToOne ? 1_867 : 1_695
            seance.meetingDurationSeconds = seance.durationSeconds
            context.insert(seance)
            seance.participants.append(personne)
            seance.setParticipantStatus(.present, for: personne)
            seances.append(seance)
        }
        return seances
    }

    private static func existingTag(named nom: String, in context: ModelContext) -> MeetingTag? {
        let tous = (try? context.fetch(FetchDescriptor<MeetingTag>())) ?? []
        return tous.first { $0.name.localizedCaseInsensitiveCompare(nom) == .orderedSame }
    }
}
