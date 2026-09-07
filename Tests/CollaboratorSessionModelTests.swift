import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les intitulés, les tons et les listes de l'écran de séance du 1:1 subi
/// (spec §6.2, capture 5a) — tous **hors de la vue**, pour que la capture soit
/// vérifiable autrement qu'à l'œil.
@Suite("Écran 5a — intitulés, tons et listes (spec §6.2)")
@MainActor
struct CollaboratorSessionModelTests {

    /// Vendredi 4 septembre 2026, 9 h 15 — la séance de la capture.
    static let seance = Date(timeIntervalSince1970: 1_788_506_100)

    private static func jours(_ n: Double) -> Date {
        seance.addingTimeInterval(n * 86_400)
    }

    /// Le fil de la capture : Yann PENVEN me manage.
    private func makeFil() throws -> (context: ModelContext,
                                      fil: OneOnOneThread,
                                      seance: Meeting) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let yann = Collaborator(name: "Yann PENVEN", role: "Manager")
        context.insert(yann)
        let seance = Meeting(title: "1:1 avec Yann · 4", date: Self.seance, notes: "")
        seance.kind = .manager
        context.insert(seance)
        seance.participants.append(yann)
        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        try context.save()
        return (context, fil, seance)
    }

    // MARK: - Intitulés de la capture, au mot près

    @Test("Les titres et la mention de confidentialité sont ceux de la capture")
    func intitules() {
        #expect(CollaboratorSessionModel.myTopicsTitle == "CE QUE JE VEUX DIRE")
        #expect(CollaboratorSessionModel.privacyPill == "● privé")
        #expect(CollaboratorSessionModel.myTopicsMention
                == "Visible de vous seul. Vous choisissez à la fin ce qui part dans le récap partagé.")
        #expect(CollaboratorSessionModel.myTopicsComposerPlaceholder == "Ajouter un sujet…")
        #expect(CollaboratorSessionModel.dragHint == "glisser pour classer")
        #expect(CollaboratorSessionModel.dragHandle == "⠿")
        #expect(CollaboratorSessionModel.requestsTitle == "MES DEMANDES EN COURS")
        #expect(CollaboratorSessionModel.notesTitle == "Notes de l'entretien")
        #expect(CollaboratorSessionModel.defaultPrivacyPill == "● Privé par défaut")
        #expect(CollaboratorSessionModel.shareLinePill == "Partager la ligne")
        #expect(CollaboratorSessionModel.heardTitle == "CE QU'IL M'A DIT")
        #expect(CollaboratorSessionModel.saidTitle == "CE QUE J'AI DIT")
        #expect(CollaboratorSessionModel.privateBlockLabel == "● POUR MOI SEUL")
        #expect(CollaboratorSessionModel.promisesTitle == "CE QU'IL M'A PROMIS")
        #expect(CollaboratorSessionModel.remindButtonLabel == "Relancer")
        #expect(CollaboratorSessionModel.closingTitle == "EN SORTANT")
        #expect(CollaboratorSessionModel.annualFolderButtonLabel
                == "Verser dans mon dossier annuel")
    }

    @Test("Aucune zone de l'écran n'est vide sans invite")
    func invites() {
        for invite in [CollaboratorSessionModel.myTopicsEmptyInvite,
                       CollaboratorSessionModel.requestsEmptyInvite,
                       CollaboratorSessionModel.heardEmptyInvite,
                       CollaboratorSessionModel.saidEmptyInvite,
                       CollaboratorSessionModel.promisesEmptyInvite,
                       DeliveredItemsBuilder.emptyInvite] {
            #expect(!invite.isEmpty)
        }
    }

    @Test("Les sujets sont numérotés à partir de 1")
    func numerotation() {
        #expect(CollaboratorSessionModel.topicNumber(0) == "1")
        #expect(CollaboratorSessionModel.topicNumber(2) == "3")
    }

    // MARK: - Mes sujets et mes demandes

    @Test("Mes sujets sont les `topic` de la séance, dans l'ordre manuel, sans les demandes")
    func mesSujets() throws {
        let (context, fil, seance) = try makeFil()
        for (rang, texte) in ["Charge : deux migrations + astreinte",
                              "Mobilité archi : je veux une réponse ferme",
                              "Porter la formation Admin"].enumerated().reversed() {
            let sujet = OneOnOneAgendaItem(text: texte, addedBySide: .collaborator,
                                           order: rang, visibility: .private)
            context.insert(sujet)
            sujet.thread = fil
            sujet.meeting = seance
        }
        let demande = OneOnOneAgendaItem(text: "Mobilité vers l'architecture",
                                         addedBySide: .collaborator, order: 9,
                                         visibility: .private, kind: .request)
        context.insert(demande)
        demande.thread = fil
        demande.meeting = seance
        try context.save()

        let sujets = CollaboratorSessionModel.myTopics(fil, for: seance)
        #expect(sujets.map(\.text) == ["Charge : deux migrations + astreinte",
                                        "Mobilité archi : je veux une réponse ferme",
                                        "Porter la formation Admin"])
        // Une demande n'est pas un sujet de brouillon : elle a sa propre carte.
        #expect(!sujets.contains { $0.kind == .request })
        #expect(CollaboratorSessionModel.requests(fil).map(\.text)
                == ["Mobilité vers l'architecture"])
    }

    @Test("Le ton d'une demande suit son statut, et l'ancienneté prime sur `Sans réponse`")
    func tonsDesDemandes() throws {
        let (context, fil, seance) = try makeFil()

        func demande(_ texte: String, _ statut: RequestStatus, jours: Double) -> OneOnOneAgendaItem {
            let item = OneOnOneAgendaItem(text: texte, addedBySide: .collaborator,
                                          visibility: .private, kind: .request,
                                          requestStatus: statut,
                                          requestedAt: Self.jours(jours))
            context.insert(item)
            item.thread = fil
            item.meeting = seance
            return item
        }

        let recente = demande("Mobilité vers l'architecture", .pending, jours: -56)
        let attente = demande("Compensation des astreintes", .waiting, jours: -42)
        let accordee = demande("Budget formation Terraform", .granted, jours: -70)
        let refusee = demande("Télétravail quatre jours", .refused, jours: -10)
        // Plus de 60 jours sans réponse : la spec la fait passer en
        // `accent/report`, même si son statut reste `Sans réponse`.
        let oubliee = demande("Revalorisation", .pending, jours: -90)
        try context.save()

        #expect(CollaboratorSessionModel.requestTone(recente, now: Self.seance) == .warn)
        #expect(CollaboratorSessionModel.requestTone(attente, now: Self.seance) == .warn)
        #expect(CollaboratorSessionModel.requestTone(accordee, now: Self.seance) == .ok)
        #expect(CollaboratorSessionModel.requestTone(refusee, now: Self.seance) == .report)
        #expect(CollaboratorSessionModel.requestTone(oubliee, now: Self.seance) == .report)

        // L'historique court de la capture.
        recente.remindedCount = 2
        #expect(AgendaCarryover.requestHistoryLabel(recente)
                == "Demandé le 10 juil. · relancé 2 fois")
    }

    // MARK: - Ce qu'il m'a promis

    @Test("Les promesses du manager sont triées par retard décroissant")
    func promessesTrieesParRetard() throws {
        let (context, fil, _) = try makeFil()

        func promesse(_ texte: String, echeance: Double?, pris: Double,
                      reports: Int = 0) -> Commitment {
            let engagement = Commitment(text: texte, ownerSide: .manager,
                                        dueAt: echeance.map { Self.jours($0) },
                                        promisedAt: Self.jours(pris),
                                        visibility: .private)
            engagement.deferralCount = reports
            context.insert(engagement)
            engagement.thread = fil
            return engagement
        }

        _ = promesse("Grille de compensation des astreintes", echeance: -42, pris: -42,
                     reports: 2)
        _ = promesse("Arbitrage renfort / décalage Webcast", echeance: 1, pris: 0)
        _ = promesse("Point mobilité avec Claire-Amélie", echeance: 119, pris: -56, reports: 3)
        // Un engagement que **je** porte n'est pas une promesse de mon manager.
        let mienne = promesse("Chiffrer la reprise AP", echeance: 5, pris: 0)
        mienne.ownerSide = .collaborator
        try context.save()

        let promesses = CollaboratorSessionModel.promises(fil, now: Self.seance)
        #expect(promesses.map(\.text) == ["Grille de compensation des astreintes",
                                          "Arbitrage renfort / décalage Webcast",
                                          "Point mobilité avec Claire-Amélie"])
        #expect(CollaboratorSessionModel.lateBadge(fil, now: Self.seance) == "1 en retard")

        let enRetard = try #require(promesses.first)
        #expect(CollaboratorSessionModel.promisedAtPill(enRetard) == "Promise le 24 juil.")
        #expect(CollaboratorSessionModel.deferralPill(enRetard) == "2 reports")
        #expect(CollaboratorSessionModel.isLate(enRetard, now: Self.seance))

        let arbitrage = promesses[1]
        #expect(CollaboratorSessionModel.deferralPill(arbitrage) == nil)
        #expect(!CollaboratorSessionModel.isLate(arbitrage, now: Self.seance))
    }

    @Test("Une promesse tenue quitte la carte : elle n'est plus quelque chose à obtenir")
    func promesseTenueRetiree() throws {
        let (context, fil, _) = try makeFil()
        let tenue = Commitment(text: "Ouverture des comptes GitLab", ownerSide: .manager,
                               state: .kept, promisedAt: Self.jours(-30))
        context.insert(tenue)
        tenue.thread = fil
        try context.save()

        #expect(CollaboratorSessionModel.promises(fil, now: Self.seance).isEmpty)
        #expect(CollaboratorSessionModel.lateBadge(fil, now: Self.seance) == nil)
    }

    @Test("Un seul report s'écrit au singulier")
    func reportAuSingulier() throws {
        let (context, fil, _) = try makeFil()
        let promesse = Commitment(text: "Grille", ownerSide: .manager,
                                  promisedAt: Self.jours(-10))
        promesse.deferralCount = 1
        context.insert(promesse)
        promesse.thread = fil
        try context.save()

        #expect(CollaboratorSessionModel.deferralPill(promesse) == "1 report")
    }

    // MARK: - Les deux sections de notes

    @Test("`CE QU'IL M'A DIT` et `CE QUE J'AI DIT` se partagent selon l'auteur de la ligne")
    func deuxSectionsDeNotes() throws {
        let (context, _, seance) = try makeFil()
        let lignes: [(Double, String, MeetingSide)] = [
            (200, "Retour positif sur le COSUI du 1er sept.", .manager),
            (400, "Posé les 3 j-h de reprise non prévus", .me),
            (545, "Sur la charge : il arbitre vendredi", .manager),
            (1_070, "3ᵉ report sur la mobilité", .me),
            (1_200, "   ", .manager)
        ]
        for (rang, ligne) in lignes.enumerated() {
            let note = MeetingNote(t: ligne.0, text: ligne.1, visibility: .private,
                                   authorSide: ligne.2, orderIndex: rang)
            context.insert(note)
            note.meeting = seance
        }
        try context.save()

        #expect(CollaboratorSessionModel.heardSectionNotes(seance).map(\.t) == [200, 545])
        #expect(CollaboratorSessionModel.saidSectionNotes(seance).map(\.t) == [400, 1_070])
        // Une ligne vide est un marqueur d'axe temps (⌘M), pas une phrase :
        // elle n'apparaît dans aucune des deux sections.
        #expect(CollaboratorSessionModel.heardSectionNotes(seance).count == 2)
    }

    // MARK: - En sortant

    @Test("`Envoyer mon récap à Yann` porte le prénom de mon manager")
    func libelleDuRecap() throws {
        let (_, fil, _) = try makeFil()
        #expect(CollaboratorSessionModel.recapButtonLabel(for: fil)
                == "Envoyer mon récap à Yann")
    }

    @Test("Le compte des lignes exclues additionne notes, engagements et sujets")
    func lignesExclues() throws {
        let (context, fil, seance) = try makeFil()

        let note = MeetingNote(t: 10, text: "Je regarde ailleurs", visibility: .private)
        context.insert(note)
        note.meeting = seance

        let engagement = Commitment(text: "Ouvrir le sujet mobilité", ownerSide: .collaborator,
                                    promisedAt: Self.seance, visibility: .private)
        context.insert(engagement)
        engagement.thread = fil

        let sujet = OneOnOneAgendaItem(text: "Charge de travail", addedBySide: .collaborator,
                                       visibility: .private)
        context.insert(sujet)
        sujet.thread = fil
        sujet.meeting = seance

        // Une ligne partagée sort, donc ne compte pas.
        let partagee = MeetingNote(t: 20, text: "Ce que j'assume devant lui",
                                   visibility: .shared)
        context.insert(partagee)
        partagee.meeting = seance
        try context.save()

        #expect(CollaboratorSessionModel.excludedLinesLabel(for: seance, in: fil)
                == "3 lignes privées seront exclues.")
    }

    @Test("Sans rien à exclure, aucune mention n'attire l'œil pour rien")
    func aucuneLigneExclue() throws {
        let (context, fil, seance) = try makeFil()
        let partagee = MeetingNote(t: 20, text: "Assumé", visibility: .shared)
        context.insert(partagee)
        partagee.meeting = seance
        try context.save()

        #expect(CollaboratorSessionModel.excludedLinesLabel(for: seance, in: fil) == nil)
    }

    @Test("Le récap du collaborateur part vers son manager, jamais vers l'autre côté")
    func audienceDuRecap() {
        #expect(OneOnOneConfidentiality.recapAudience(for: .collaborator) == .manager)
    }

    // MARK: - Barre assistant

    @Test("La suggestion de l'assistant nomme le mois du dernier point")
    func suggestionDeLAssistant() throws {
        let (context, fil, seance) = try makeFil()
        // Sans séance précédente, la question reste posable mais sans mois.
        #expect(CollaboratorSessionModel.assistantSuggestion(fil, for: seance)
                == "« Qu'ai-je livré depuis le dernier point ? »")

        let precedente = Meeting(title: "1:1 avec Yann · 3",
                                 date: Self.jours(-45), notes: "")
        precedente.kind = .manager
        context.insert(precedente)
        precedente.participants.append(try #require(fil.collaborator))
        try context.save()

        #expect(CollaboratorSessionModel.assistantSuggestion(fil, for: seance)
                == "« Qu'ai-je livré depuis juillet ? »")
    }
}
