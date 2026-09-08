import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le rail des engagements de la capture 2a (spec §3.3, colonne droite) —
/// **modèle de vue pur**, pour que le critère d'acceptation chantier 2 n° 2
/// (« un engagement manqué côté manager est visible dans 2a, avec son compteur
/// de reports ») soit vérifiable sans monter un écran.
@Suite("Rail des engagements 1:1 — groupes, pilules et ledger")
@MainActor
struct CommitmentsRailModelTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static var jour: TimeInterval { 86_400 }

    private struct Fixture {
        var thread: OneOnOneThread
        var meeting: Meeting
        var previous: Meeting
        var context: ModelContext
    }

    /// Un fil minimal : deux séances (celle-ci et la précédente, quinze jours
    /// avant) et aucun engagement. Chaque test ajoute ce qu'il observe.
    private func fixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let laurent = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)

        let precedente = Meeting(title: "1:1 — Laurent · 13",
                                 date: Self.maintenant.addingTimeInterval(-14 * Self.jour),
                                 notes: "")
        precedente.kind = .oneToOne
        context.insert(precedente)
        precedente.participants.append(laurent)

        let seance = Meeting(title: "1:1 — Laurent · 14", date: Self.maintenant, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(laurent)

        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        try context.save()
        return Fixture(thread: fil, meeting: seance, previous: precedente, context: context)
    }

    @discardableResult
    private func engagement(_ texte: String,
                            side: OneOnOneSide,
                            in f: Fixture,
                            meeting: Meeting?? = nil,
                            due: Double? = nil,
                            state: CommitmentState = .open,
                            settled: Double? = nil,
                            reports: Int = 0,
                            visibility: Visibility = .shared,
                            blocks: Bool = false) -> Commitment {
        let ligne = Commitment(text: texte,
                               ownerSide: side,
                               dueAt: due.map { Self.maintenant.addingTimeInterval($0 * Self.jour) },
                               state: state,
                               promisedAt: Self.maintenant,
                               visibility: visibility)
        ligne.deferralCount = reports
        ligne.blocksOther = blocks
        ligne.settledAt = settled.map { Self.maintenant.addingTimeInterval($0 * Self.jour) }
        f.context.insert(ligne)
        ligne.thread = f.thread
        // `meeting` explicite pour rattacher l'engagement à une autre séance ;
        // par défaut, celle qui est ouverte.
        ligne.promisedInMeeting = meeting ?? f.meeting
        try? f.context.save()
        return ligne
    }

    // MARK: - Groupes « Moi · n » / « <Prénom> · n »

    @Test("Les deux groupes de la capture, le manager d'abord")
    func groupesDeLaCapture() throws {
        let f = try fixture()
        engagement("Arbitrer renfort ou décalage du Webcast", side: .manager, in: f, due: 0)
        engagement("Ouvrir le sujet mobilité archi avec Claire-Amélie", side: .manager, in: f,
                   due: 26, visibility: .private)
        engagement("Cadrer la formation Admin (plan + 2 dates)", side: .collaborator, in: f, due: 7)
        engagement("Chiffrer la reprise AP restante", side: .collaborator, in: f, due: 5)

        let groupes = CommitmentsRailModel.groups(for: f.meeting, in: f.thread,
                                                  ownerName: "Yann PENVEN",
                                                  now: Self.maintenant)
        #expect(groupes.count == 2)
        // « Moi » avant « Laurent » : c'est l'ordre de la capture, et c'est ce
        // que le manager doit lire en premier — ses propres engagements.
        #expect(groupes[0].side == .manager)
        #expect(groupes[0].title == "Moi · 2")
        #expect(groupes[0].initials == "YP")
        #expect(groupes[1].side == .collaborator)
        #expect(groupes[1].title == "Laurent · 2")
        #expect(groupes[1].initials == "LN")
        #expect(groupes[0].commitments.count == 2)
        #expect(groupes[1].commitments.count == 2)
    }

    @Test("Un engagement d'une autre séance ne figure pas dans « cette séance »")
    func engagementDUneAutreSeance() throws {
        let f = try fixture()
        engagement("Pris à la séance précédente", side: .manager, in: f, meeting: f.previous)
        engagement("Pris aujourd'hui", side: .manager, in: f)

        let groupes = CommitmentsRailModel.groups(for: f.meeting, in: f.thread,
                                                  ownerName: "", now: Self.maintenant)
        let textes = groupes.flatMap(\.commitments).map(\.text)
        #expect(textes == ["Pris aujourd'hui"])
    }

    @Test("Les deux groupes restent présents même vides, avec leur invite")
    func groupesVidesGardentLeurInvite() throws {
        let f = try fixture()
        let groupes = CommitmentsRailModel.groups(for: f.meeting, in: f.thread,
                                                  ownerName: "", now: Self.maintenant)
        // « Aucune zone vide sans invite » (chantier 1, critère n° 1) : le rail
        // d'un entretien qui commence est vide par nature, et un cadre muet ne
        // dirait pas comment le remplir.
        #expect(groupes.count == 2)
        #expect(groupes.allSatisfy { $0.commitments.isEmpty })
        #expect(groupes[0].title == "Moi · 0")
        let invite = CommitmentsRailModel.emptyInvite(for: .manager, in: f.thread)
        #expect(invite.contains("/engagement"))
        #expect(!CommitmentsRailModel.emptyInvite(for: .collaborator, in: f.thread).isEmpty)
    }

    // MARK: - Pilules de la carte

    @Test("L'échéance imminente s'écrit en jour de la semaine, les autres en date")
    func pilulesDEcheance() throws {
        let f = try fixture()
        // Vendredi 4 septembre : la séance. `Vendredi` — jour même.
        let vendredi = engagement("Arbitrer", side: .manager, in: f, due: 0)
        #expect(CommitmentsRailModel.duePill(vendredi, now: Self.maintenant) == "Vendredi")
        // Mercredi 9 septembre : dans la fenêtre de sept jours, donc le jour.
        //
        // La règle a changé à l'intégration de la vague 5 : ce modèle
        // comparait les **semaines calendaires** et écrivait « 9 sept. » ;
        // le tableau de la préparation (2b) et la carte d'action du lot 3
        // appliquaient déjà la fenêtre de sept jours. Le critère du chantier 2
        // veut qu'un engagement se lise pareil dans 2a et dans 2b : c'est donc
        // `OneOnOneDateFormat.dueDate` pour les deux.
        let mercredi = engagement("Chiffrer", side: .collaborator, in: f, due: 5)
        #expect(CommitmentsRailModel.duePill(mercredi, now: Self.maintenant) == "Mercredi")
        #expect(CommitmentsRailModel.duePill(mercredi, now: Self.maintenant)
                == OneOnOneDateFormat.dueDate(mercredi.dueAt ?? Self.maintenant,
                                              now: Self.maintenant))
        // Vendredi 11 septembre : au septième jour, un « Vendredi » y serait
        // ambigu — deux vendredis porteraient le même nom.
        let vendrediProchain = engagement("Cadrer", side: .collaborator, in: f, due: 7)
        #expect(CommitmentsRailModel.duePill(vendrediProchain, now: Self.maintenant) == "11 sept.")
        let finDuMois = engagement("Mobilité", side: .manager, in: f, due: 26)
        #expect(CommitmentsRailModel.duePill(finDuMois, now: Self.maintenant) == "30 sept.")
        // Sans échéance, pas de pilule : « aucune date » n'est pas une date.
        let sansDate = engagement("Sans échéance", side: .manager, in: f)
        #expect(CommitmentsRailModel.duePill(sansDate, now: Self.maintenant) == nil)
    }

    @Test("La criticité se dit du point de vue de celui qui lit")
    func piluleDeCriticite() throws {
        let f = try fixture()
        let mien = engagement("Arbitrer", side: .manager, in: f, blocks: true)
        #expect(CommitmentsRailModel.criticalityPill(mien) == "Bloquant pour lui")
        let sien = engagement("Chiffrer", side: .collaborator, in: f, blocks: true)
        #expect(CommitmentsRailModel.criticalityPill(sien) == "Bloquant pour moi")
        let ordinaire = engagement("Ordinaire", side: .manager, in: f)
        #expect(CommitmentsRailModel.criticalityPill(ordinaire) == nil)
    }

    @Test("La confidentialité n'est marquée que sur une ligne qui n'est pas partagée")
    func piluleDeConfidentialite() throws {
        let f = try fixture()
        let prive = engagement("Mobilité", side: .manager, in: f, visibility: .private)
        #expect(CommitmentsRailModel.privacyPill(prive) == "● privé")
        let partage = engagement("Arbitrer", side: .manager, in: f, visibility: .shared)
        #expect(CommitmentsRailModel.privacyPill(partage) == nil)
        let escalade = engagement("Escalade", side: .manager, in: f, visibility: .escalated)
        #expect(CommitmentsRailModel.privacyPill(escalade) == "● escaladé")
    }

    @Test("La charge vient de l'action liée, jamais d'une estimation inventée")
    func piluleDeCharge() throws {
        let f = try fixture()
        let ligne = engagement("Cadrer la formation Admin (plan + 2 dates)",
                               side: .collaborator, in: f, due: 7)
        #expect(CommitmentsRailModel.effortPill(ligne) == nil)

        let action = ActionTask(title: "Cadrer la formation Admin (plan + 2 dates)")
        action.effortMinutes = 240
        f.context.insert(action)
        ligne.linkedAction = action
        try f.context.save()
        #expect(CommitmentsRailModel.effortPill(ligne) == "4h")

        action.effortMinutes = 45
        #expect(CommitmentsRailModel.effortPill(ligne) == "45min")
        action.effortMinutes = 90
        #expect(CommitmentsRailModel.effortPill(ligne) == "1h30")
    }

    // MARK: - Tenus depuis le dernier 1:1 (critère chantier 2 n° 2)

    @Test("Un engagement manqué du manager est visible avec son compteur de reports")
    func engagementManqueDuManager() throws {
        let f = try fixture()
        // La ligne rouge de la capture : « ✗ Retour sur la grille d'astreinte
        // — YP · 2× reporté ». Elle est encore `open` : son échéance est
        // passée de six semaines et personne ne l'a soldée. C'est **le** cas
        // que le critère n° 2 exige de voir, « y compris pour le manager, sans
        // exception ».
        engagement("Retour sur la grille d'astreinte", side: .manager, in: f,
                   due: -42, reports: 2)
        engagement("Reprise du périmètre Nexus", side: .collaborator, in: f,
                   state: .kept, settled: -13)

        let lignes = CommitmentsRailModel.ledgerLines(for: f.meeting, in: f.thread,
                                                      ownerName: "Yann PENVEN",
                                                      now: Self.maintenant)
        let manquee = try #require(lignes.first { $0.text == "Retour sur la grille d'astreinte" })
        #expect(manquee.isMissed)
        #expect(manquee.symbol == "✗")
        #expect(manquee.deferralLabel == "2× reporté")
        #expect(manquee.initials == "YP")

        let tenue = try #require(lignes.first { $0.text == "Reprise du périmètre Nexus" })
        #expect(!tenue.isMissed)
        #expect(tenue.symbol == "✓")
        #expect(tenue.deferralLabel == nil)
        #expect(tenue.initials == "LN")
    }

    @Test("Les manqués passent en tête, les tenus suivent")
    func ordreDuLedger() throws {
        let f = try fixture()
        engagement("Tenu récent", side: .collaborator, in: f, state: .kept, settled: -1)
        engagement("Manqué soldé", side: .manager, in: f, state: .missed, settled: -2)

        let lignes = CommitmentsRailModel.ledgerLines(for: f.meeting, in: f.thread,
                                                      ownerName: "", now: Self.maintenant)
        // Un manqué est ce qu'on doit voir en premier : c'est la dette du fil.
        #expect(lignes.map(\.isMissed) == [true, false])
    }

    @Test("Ce qui a été soldé avant la séance précédente ne remonte pas")
    func horsFenetre() throws {
        let f = try fixture()
        engagement("Vieux tenu", side: .collaborator, in: f, state: .kept, settled: -60)
        engagement("Tenu depuis", side: .collaborator, in: f, state: .kept, settled: -10)

        let lignes = CommitmentsRailModel.ledgerLines(for: f.meeting, in: f.thread,
                                                      ownerName: "", now: Self.maintenant)
        #expect(lignes.map(\.text) == ["Tenu depuis"])
    }

    @Test("Un ledger vide porte son invite")
    func ledgerVide() throws {
        let f = try fixture()
        let lignes = CommitmentsRailModel.ledgerLines(for: f.meeting, in: f.thread,
                                                      ownerName: "", now: Self.maintenant)
        #expect(lignes.isEmpty)
        #expect(!CommitmentsRailModel.ledgerEmptyInvite.isEmpty)
    }

    // MARK: - Clôture

    @Test("Les libellés de clôture nomment la personne et la date du prochain")
    func libellesDeCloture() throws {
        let f = try fixture()
        #expect(CommitmentsRailModel.recapButtonLabel(for: f.thread) == "Envoyer le récap à Laurent")
        #expect(CommitmentsRailModel.planNextButtonLabel(for: f.thread, now: Self.maintenant)
                == "Planifier le prochain — 18 sept.")
        #expect(CommitmentsRailModel.privacyFootnote == "Les notes privées ne sont jamais incluses")
    }

    @Test("Sans cadence, le bouton de planification le dit au lieu d'inventer une date")
    func sansCadence() throws {
        let f = try fixture()
        f.thread.collaborator?.oneToOneCadence = .aucune
        f.thread.cadenceDays = 0
        #expect(CommitmentsRailModel.planNextButtonLabel(for: f.thread, now: Self.maintenant)
                == "Planifier le prochain")
    }
}
