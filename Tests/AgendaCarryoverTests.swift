import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **Critère d'acceptation du chantier 2, n° 4** : « un item d'ordre du jour
/// non traité migre automatiquement vers le 1:1 suivant du même fil ».
///
/// La migration est **idempotente** : elle se déclenche à la clôture, et une
/// clôture se rejoue (fermeture de fenêtre, rouverture, re-clôture). Un report
/// qui duplique produit un ordre du jour en double à chaque essai.
@Suite("Ordre du jour — report vers le 1:1 suivant (critère chantier 2 n° 4)")
@MainActor
struct AgendaCarryoverTests {

    private static let jour: TimeInterval = 86_400
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)

    private func makeFil() throws -> (OneOnOneThread, ModelContext, Collaborator) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)
        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        return (fil, context, laurent)
    }

    @discardableResult
    private func seance(_ context: ModelContext, _ collab: Collaborator, _ date: Date) -> Meeting {
        let reunion = Meeting(title: "1:1 Laurent", date: date, notes: "")
        reunion.kind = .oneToOne
        context.insert(reunion)
        reunion.participants.append(collab)
        return reunion
    }

    @discardableResult
    private func sujet(_ fil: OneOnOneThread,
                       _ context: ModelContext,
                       _ texte: String,
                       state: AgendaItemState = .todo,
                       order: Int = 0,
                       meeting: Meeting? = nil,
                       side: OneOnOneSide = .manager) -> OneOnOneAgendaItem {
        let item = OneOnOneAgendaItem(text: texte, addedBySide: side, order: order, state: state)
        context.insert(item)
        item.thread = fil
        item.meeting = meeting
        return item
    }

    // MARK: - Report

    @Test("Un item non traité migre vers le 1:1 suivant")
    func itemNonTraiteMigre() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        let item = sujet(fil, context, "Point objectifs S2", order: 3, meeting: close)

        let copies = AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context)

        #expect(item.state == .deferred)
        #expect(item.deferredToMeeting?.persistentModelID == suivante.persistentModelID)
        #expect(copies.count == 1)
        let copie = try #require(copies.first)
        #expect(copie.text == "Point objectifs S2")
        #expect(copie.state == .todo)
        #expect(copie.order == 3)
        #expect(copie.addedBySide == .manager)
        #expect(copie.meeting?.persistentModelID == suivante.persistentModelID)
        #expect(copie.deferredToMeeting == nil)
        #expect(copie.thread?.persistentModelID == fil.persistentModelID)
    }

    @Test("Rejouer le report ne duplique rien")
    func reportIdempotent() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        sujet(fil, context, "Point objectifs S2", meeting: close)

        #expect(AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context).count == 1)
        #expect(AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context).isEmpty)
        #expect(AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context).isEmpty)
        #expect(fil.agendaItems.count == 2)
    }

    @Test("Un item traité ne migre pas")
    func itemTraiteNeMigrePas() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        let traite = sujet(fil, context, "Charge de travail", state: .done, meeting: close)

        #expect(AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context).isEmpty)
        #expect(traite.state == .done)
        #expect(fil.agendaItems.count == 1)
    }

    @Test("Sans séance suivante, l'item est reporté sans cible")
    func sansSeanceSuivante() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let item = sujet(fil, context, "Formation Admin", meeting: close)

        #expect(AgendaCarryover.carryOver(from: close, to: nil, in: fil, in: context).isEmpty)
        #expect(item.state == .deferred)
        #expect(item.deferredToMeeting == nil)

        // La séance suivante finit par être planifiée : le report se termine.
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        let copies = AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context)
        #expect(copies.count == 1)
        #expect(item.deferredToMeeting?.persistentModelID == suivante.persistentModelID)
    }

    @Test("Une demande reportée garde son statut et son ancienneté")
    func demandeReportee() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        let demande = OneOnOneAgendaItem(text: "Mobilité vers l'architecture",
                                          addedBySide: .collaborator,
                                          visibility: .private,
                                          kind: .request,
                                          requestStatus: .waiting,
                                          requestedAt: Self.quatreSeptembre.addingTimeInterval(-56 * Self.jour))
        demande.remindedCount = 2
        context.insert(demande)
        demande.thread = fil
        demande.meeting = close

        let copie = try #require(AgendaCarryover.carryOver(from: close, to: suivante,
                                                            in: fil, in: context).first)
        #expect(copie.kind == .request)
        #expect(copie.requestStatus == .waiting)
        #expect(copie.requestedAt == demande.requestedAt)
        #expect(copie.remindedCount == 2)
        #expect(copie.visibility == .private)
        #expect(copie.addedBySide == .collaborator)
    }

    @Test("L'item reporté affiche la date de sa cible")
    func libelleDeReport() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        // 18 septembre 2026, la date de la capture 2a (« → 18/09 »).
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        let item = sujet(fil, context, "Point objectifs S2", meeting: close)
        AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context)

        #expect(AgendaCarryover.deferredLabel(item) == "→ 18/09")
        #expect(AgendaCarryover.deferredLabel(sujet(fil, context, "Autre")) == nil)
    }

    // MARK: - Resté en suspens

    @Test("Resté en suspens mêle les items reportés et les sujets récurrents non tranchés")
    func resteEnSuspens() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        sujet(fil, context, "Astreintes week-end : compensation à clarifier", meeting: close)
        AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context)

        let entrees = AgendaCarryover.stillOpen(
            fil,
            recurringTopics: [(label: "Souhait de mobilité vers l'archi", count: 2)]
        )

        #expect(entrees.count == 2)
        #expect(entrees.contains { $0.text == "Astreintes week-end : compensation à clarifier"
                                    && $0.occurrences == 1 && !$0.isRecurringTopic })
        #expect(entrees.contains { $0.text == "Souhait de mobilité vers l'archi"
                                    && $0.occurrences == 2 && $0.isRecurringTopic })
    }

    @Test("Un sujet récurrent déjà à l'ordre du jour ne compte pas deux fois")
    func pasDeDoublonEnSuspens() throws {
        let (fil, context, collab) = try makeFil()
        let close = seance(context, collab, Self.quatreSeptembre)
        let suivante = seance(context, collab, Self.quatreSeptembre.addingTimeInterval(14 * Self.jour))
        sujet(fil, context, "Mobilité archi", meeting: close)
        AgendaCarryover.carryOver(from: close, to: suivante, in: fil, in: context)

        let entrees = AgendaCarryover.stillOpen(fil,
                                                 recurringTopics: [(label: "Mobilité archi", count: 3)])
        #expect(entrees.count == 1)
        #expect(entrees.first?.isRecurringTopic == false)
    }

    // MARK: - Demandes

    @Test("Une demande sans réponse depuis plus de 60 jours passe en report")
    func demandeTropVieille() throws {
        let (fil, context, _) = try makeFil()
        let vieille = OneOnOneAgendaItem(text: "Vieille demande", kind: .request,
                                          requestStatus: .pending,
                                          requestedAt: Self.quatreSeptembre.addingTimeInterval(-65 * Self.jour))
        context.insert(vieille)
        vieille.thread = fil
        // 10 juillet → 4 septembre = 56 jours : la capture 5a la montre en
        // `warn`, pas en `report`. Le seuil est bien à 60, pas à 55.
        let recente = OneOnOneAgendaItem(text: "Mobilité vers l'architecture", kind: .request,
                                          requestStatus: .pending,
                                          requestedAt: Self.quatreSeptembre.addingTimeInterval(-56 * Self.jour))
        context.insert(recente)
        recente.thread = fil

        #expect(AgendaCarryover.requestLevel(vieille, now: Self.quatreSeptembre) == .report)
        #expect(AgendaCarryover.requestLevel(recente, now: Self.quatreSeptembre) == .warn)
    }

    @Test("Une demande refusée est en report, une demande accordée est neutre")
    func niveauParStatut() throws {
        let (fil, context, _) = try makeFil()
        func demande(_ statut: RequestStatus) -> OneOnOneAgendaItem {
            let item = OneOnOneAgendaItem(text: "Demande", kind: .request,
                                          requestStatus: statut,
                                          requestedAt: Self.quatreSeptembre)
            context.insert(item)
            item.thread = fil
            return item
        }

        #expect(AgendaCarryover.requestLevel(demande(.granted), now: Self.quatreSeptembre) == .ok)
        #expect(AgendaCarryover.requestLevel(demande(.refused), now: Self.quatreSeptembre) == .report)
        #expect(AgendaCarryover.requestLevel(demande(.waiting), now: Self.quatreSeptembre) == .warn)
        #expect(AgendaCarryover.requestLevel(demande(.pending), now: Self.quatreSeptembre) == .warn)
    }

    @Test("Un sujet ordinaire n'a pas de niveau de demande")
    func sujetSansNiveau() throws {
        let (fil, context, _) = try makeFil()
        let item = sujet(fil, context, "Charge de travail")
        #expect(AgendaCarryover.requestLevel(item, now: Self.quatreSeptembre) == .ok)
    }

    @Test("L'historique d'une demande dit sa date et ses relances")
    func historiqueDeDemande() throws {
        let (fil, context, _) = try makeFil()
        let item = OneOnOneAgendaItem(text: "Mobilité vers l'architecture", kind: .request,
                                       requestStatus: .pending,
                                       requestedAt: Self.quatreSeptembre.addingTimeInterval(-56 * Self.jour))
        item.remindedCount = 2
        context.insert(item)
        item.thread = fil

        #expect(AgendaCarryover.requestHistoryLabel(item) == "Demandé le 10 juil. · relancé 2 fois")

        item.remindedCount = 0
        #expect(AgendaCarryover.requestHistoryLabel(item) == "Demandé le 10 juil.")

        item.remindedCount = 1
        #expect(AgendaCarryover.requestHistoryLabel(item) == "Demandé le 10 juil. · relancé 1 fois")
    }

    @Test("Relancer une demande incrémente son compteur")
    func relancer() throws {
        let (fil, context, _) = try makeFil()
        let item = OneOnOneAgendaItem(text: "Demande", kind: .request, requestedAt: Self.quatreSeptembre)
        context.insert(item)
        item.thread = fil

        #expect(AgendaCarryover.remind(item) == 1)
        #expect(AgendaCarryover.remind(item) == 2)
        #expect(item.remindedCount == 2)
    }

    // MARK: - Tri

    @Test("Les sujets sortent dans l'ordre manuel, puis par date de création")
    func tri() throws {
        let (fil, context, _) = try makeFil()
        let troisieme = sujet(fil, context, "Troisième", order: 2)
        let premier = sujet(fil, context, "Premier", order: 0)
        let deuxieme = sujet(fil, context, "Deuxième", order: 1)

        #expect(AgendaCarryover.sorted([troisieme, premier, deuxieme]).map(\.text)
                == ["Premier", "Deuxième", "Troisième"])
    }
}
