import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La colonne gauche de la capture 2a : carte personne, `ORDRE DU JOUR ·
/// co-construit`, `RESTÉ EN SUSPENS` et la barre d'assistant contextuelle
/// (spec §3.3, colonne gauche).
@Suite("Colonne gauche du 1:1 — personne, ordre du jour, suspens")
@MainActor
struct OneOnOneAgendaCardTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static var jour: TimeInterval { 86_400 }

    private struct Fixture {
        var thread: OneOnOneThread
        var meeting: Meeting
        var context: ModelContext
    }

    private func fixture(cadence: OneToOneCadence = .bimensuelle) throws -> Fixture {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let laurent = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        laurent.oneToOneCadence = cadence
        laurent.joinedAt = Self.maintenant.addingTimeInterval(-3.2 * 365.25 * Self.jour)
        context.insert(laurent)

        // Le 1:1 précédent : 21 août, quinze jours avant celui de la capture.
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
        return Fixture(thread: fil, meeting: seance, context: context)
    }

    @discardableResult
    private func sujet(_ texte: String,
                       side: OneOnOneSide = .collaborator,
                       order: Int,
                       state: AgendaItemState = .todo,
                       in f: Fixture,
                       deferredTo: Meeting? = nil) -> OneOnOneAgendaItem {
        let item = OneOnOneAgendaItem(text: texte, addedBySide: side, order: order, state: state)
        f.context.insert(item)
        item.thread = f.thread
        item.meeting = f.meeting
        item.deferredToMeeting = deferredTo
        try? f.context.save()
        return item
    }

    // MARK: - Carte personne

    @Test("Les deux métriques de la carte personne sont celles de la capture")
    func metriquesDeLaCartePersonne() throws {
        let f = try fixture()
        #expect(PersonCardModel.lastMeetingLabel(of: f.thread, now: Self.maintenant)
                == "21 août · il y a 2 sem.")
        #expect(PersonCardModel.rhythmLabel(of: f.thread) == "Toutes les 2 sem.")
        #expect(PersonCardModel.roleLine(of: f.thread, now: Self.maintenant)
                == "Ingénieur CI/CD · dans l'équipe depuis 3 ans")
        #expect(PersonCardModel.initials(of: f.thread) == "LN")
    }

    @Test("Sans rythme convenu, la métrique le dit au lieu d'afficher un chiffre")
    func sansRythme() throws {
        let f = try fixture(cadence: .aucune)
        #expect(PersonCardModel.rhythmLabel(of: f.thread) == "Aucun rythme convenu")
    }

    @Test("Le premier entretien d'un fil n'a pas de « dernier 1:1 »")
    func premierEntretien() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let personne = Collaborator(name: "Nouvelle ARRIVÉE")
        context.insert(personne)
        let seance = Meeting(title: "1:1 — Nouvelle · 1", date: Self.maintenant, notes: "")
        seance.kind = .oneToOne
        context.insert(seance)
        seance.participants.append(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))

        // La seule séance du fil est celle qui est ouverte : « dernier 1:1 »
        // n'a pas de réponse, et afficher la date du jour serait un mensonge.
        #expect(PersonCardModel.lastMeetingLabel(of: fil, now: Self.maintenant)
                == "Premier entretien")
    }

    // MARK: - Ordre du jour

    @Test("L'ordre du jour suit l'ordre manuel et marque son auteur")
    func ordreEtAuteur() throws {
        let f = try fixture()
        sujet("Charge de travail sur la migration AP — je sature", side: .collaborator, order: 0, in: f)
        sujet("Retour sur la présentation COSUI du 1er sept.", side: .manager, order: 1, in: f)
        sujet("Formation Admin : est-ce que je peux la porter ?", side: .collaborator, order: 2, in: f)

        let lignes = ManagerAgendaModel.rows(for: f.meeting, in: f.thread, ownerName: "Yann PENVEN")
        #expect(lignes.count == 3)
        #expect(lignes.map(\.initials) == ["LN", "YP", "LN"])
        #expect(lignes.allSatisfy { !$0.isStruck })
        #expect(lignes.allSatisfy { $0.deferredLabel == nil })
    }

    @Test("Un sujet traité est barré, un sujet reporté porte sa cible")
    func barreEtReport() throws {
        let f = try fixture()
        let suivante = Meeting(title: "1:1 — Laurent · 15",
                               date: Self.maintenant.addingTimeInterval(14 * Self.jour),
                               notes: "")
        suivante.kind = .oneToOne
        f.context.insert(suivante)
        suivante.participants.append(f.thread.collaborator!)

        sujet("Sujet traité", order: 0, state: .done, in: f)
        sujet("Point objectifs S2", side: .manager, order: 1, state: .deferred, in: f,
              deferredTo: suivante)
        try f.context.save()

        let lignes = ManagerAgendaModel.rows(for: f.meeting, in: f.thread, ownerName: "")
        #expect(lignes[0].isStruck)
        #expect(lignes[0].deferredLabel == nil)
        // Un reporté est barré lui aussi : il ne sera pas traité ici.
        #expect(lignes[1].isStruck)
        #expect(lignes[1].deferredLabel == "→ 18/09")
    }

    @Test("Réordonner réécrit les rangs de 0 à n−1")
    func reordonner() throws {
        let f = try fixture()
        sujet("Un", order: 0, in: f)
        sujet("Deux", order: 1, in: f)
        sujet("Trois", order: 2, in: f)

        // Le troisième remonte en tête.
        ManagerAgendaModel.move(for: f.meeting, in: f.thread,
                                from: IndexSet(integer: 2), to: 0, in: f.context)
        let apres = ManagerAgendaModel.rows(for: f.meeting, in: f.thread, ownerName: "")
        #expect(apres.map(\.item.text) == ["Trois", "Un", "Deux"])
        // Les rangs sont **compactés** : sans cela, deux réordonnancements de
        // suite finissent par des rangs égaux et l'ordre devient celui de la
        // date de création.
        #expect(apres.map(\.item.order) == [0, 1, 2])
    }

    @Test("Un ordre du jour vide porte son invite et son composeur")
    func ordreDuJourVide() throws {
        let f = try fixture()
        #expect(ManagerAgendaModel.rows(for: f.meeting, in: f.thread, ownerName: "").isEmpty)
        #expect(!ManagerAgendaModel.emptyInvite.isEmpty)
        #expect(ManagerAgendaModel.composerPlaceholder == "Ajouter un sujet…")
        #expect(ManagerAgendaModel.title == "ORDRE DU JOUR")
        #expect(ManagerAgendaModel.badge == "co-construit")
    }

    @Test("Ajouter un sujet le place en fin de liste, du côté du manager")
    func ajouterUnSujet() throws {
        let f = try fixture()
        sujet("Déjà là", order: 0, in: f)
        let ajoute = try #require(ManagerAgendaModel.add("Point sur les astreintes",
                                                          for: f.meeting, in: f.thread,
                                                          role: .manager, in: f.context))
        #expect(ajoute.order == 1)
        #expect(ajoute.addedBySide == .manager)
        #expect(ajoute.meeting?.persistentModelID == f.meeting.persistentModelID)
        // Une ligne blanche n'est pas un sujet.
        #expect(ManagerAgendaModel.add("   ", for: f.meeting, in: f.thread,
                                        role: .manager, in: f.context) == nil)
    }

    // MARK: - Resté en suspens

    @Test("Le suspens ne répète pas ce que l'ordre du jour montre déjà")
    func suspensSansDoublon() throws {
        let f = try fixture()
        sujet("Charge de travail sur la migration AP — je sature", order: 0, in: f)
        sujet("Point objectifs S2", side: .manager, order: 1, state: .deferred, in: f)

        let suspens = ManagerAgendaModel.pendingEntries(f.thread, for: f.meeting,
                                                        now: Self.maintenant)
        // « Point objectifs S2 » est déjà visible, barré, dans l'ordre du jour
        // de cette séance : le montrer une seconde fois juste en dessous
        // ferait croire à deux sujets.
        #expect(!suspens.contains { $0.text.contains("Point objectifs S2") })
        // La charge est à l'ordre du jour : elle n'est pas « restée » en
        // suspens, elle est en train d'être traitée.
        #expect(!suspens.contains { $0.text == "Charge de travail" })
    }

    @Test("Un sujet récurrent jamais tranché remonte avec son compte")
    func sujetRecurrent() throws {
        let f = try fixture()
        // Trois mentions de mobilité archi dans les notes de la séance
        // précédente : le comptage est celui de `RecurringTopicsBuilder`.
        let precedente = try #require(
            OneOnOneThreadStore.previousMeeting(before: f.meeting, in: f.thread))
        for texte in ["Mobilité archi évoquée", "encore la mobilité", "poste d'archi"] {
            let note = MeetingNote(t: 0, text: texte)
            f.context.insert(note)
            note.meeting = precedente
        }
        try f.context.save()

        let suspens = ManagerAgendaModel.pendingEntries(f.thread, for: f.meeting,
                                                        now: Self.maintenant)
        let mobilite = try #require(suspens.first { $0.text.contains("Mobilité archi") })
        #expect(mobilite.occurrences == 3)
        #expect(mobilite.isRecurringTopic)
        #expect(ManagerAgendaModel.pendingLabel(mobilite)
                == "Mobilité archi — évoqué 3 fois, jamais tranché")
    }

    @Test("Un suspens vide porte son invite")
    func suspensVide() throws {
        let f = try fixture()
        #expect(ManagerAgendaModel.pendingEntries(f.thread, for: f.meeting,
                                                  now: Self.maintenant).isEmpty)
        #expect(!ManagerAgendaModel.pendingEmptyInvite.isEmpty)
        #expect(ManagerAgendaModel.pendingTitle == "RESTÉ EN SUSPENS")
    }

    // MARK: - Barre d'assistant

    @Test("L'assistant du 1:1 interroge le fil, pas seulement la réunion")
    func contexteDeLAssistant() throws {
        let f = try fixture()
        let contexte = MeetingAssistantDock.ThreadContext.fil(of: f.thread)
        #expect(contexte.placeholder == "Interroger l'historique des 1:1 de Laurent")
        #expect(contexte.threadName == "Laurent")
        #expect(contexte.threadID == f.thread.ensuredStableID)
    }
}
