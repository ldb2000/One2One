import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **Critère d'acceptation du chantier 5, n° 4** : « une promesse du manager
/// non tenue remonte automatiquement à la préparation suivante ».
///
/// L'ordre des trois règles est celui de la spec §3.4 et il n'est pas
/// indifférent : la première chose que doit lire un manager qui prépare son
/// entretien, c'est ce qu'il doit lui-même à la personne.
@Suite("À ne pas oublier — les trois règles dans l'ordre (critère chantier 5 n° 4)")
@MainActor
struct ReminderRulesTests {

    private static let jour: TimeInterval = 86_400
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)
    private static let vingtEtUnAout = quatreSeptembre.addingTimeInterval(-14 * jour)

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

    private func note(_ reunion: Meeting, _ context: ModelContext,
                      _ texte: String, kind: MeetingNoteKind) {
        let ligne = MeetingNote(t: 0, text: texte, kind: kind)
        context.insert(ligne)
        ligne.meeting = reunion
    }

    // MARK: - Règle 1

    @Test("Une promesse du manager non tenue est en position 1")
    func promesseNonTenueEnPremier() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)

        let engagement = Commitment(text: "un retour sur la grille d'astreinte",
                                     ownerSide: .manager,
                                     dueAt: Self.quatreSeptembre.addingTimeInterval(-42 * Self.jour),
                                     promisedAt: Self.quatreSeptembre.addingTimeInterval(-42 * Self.jour))
        engagement.deferralCount = 2
        context.insert(engagement)
        engagement.thread = fil

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        let premier = try #require(rappels.first)
        #expect(premier.rule == .managerCommitmentLate)
        #expect(premier.text == "Vous lui devez un retour sur la grille d'astreinte — reporté 2 fois.")
        // Point rouge sur la capture 2b : c'est ma parole qui n'a pas été
        // tenue, pas un simple point de vigilance.
        #expect(premier.tone == .report)
    }

    @Test("Sans report, la phrase n'invente pas de compteur")
    func phraseSansReport() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let engagement = Commitment(text: "un chiffrage de la reprise AP",
                                     ownerSide: .manager,
                                     state: .missed,
                                     promisedAt: Self.vingtEtUnAout)
        context.insert(engagement)
        engagement.thread = fil

        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).first?.text
                == "Vous lui devez un chiffrage de la reprise AP.")
    }

    @Test("Un engagement du collaborateur en retard ne remonte pas ici")
    func engagementDuCollaborateurIgnore() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let engagement = Commitment(text: "cadrer la formation Admin",
                                     ownerSide: .collaborator,
                                     dueAt: Self.vingtEtUnAout,
                                     promisedAt: Self.vingtEtUnAout)
        context.insert(engagement)
        engagement.thread = fil

        // La carte s'appelle « À NE PAS OUBLIER » et s'adresse à moi : les
        // retards de l'autre sont dans la colonne des engagements.
        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    @Test("Les retards du manager sortent du plus ancien au plus récent")
    func plusieursRetardsTries() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        for (texte, jours) in [("un retour récent", -5.0), ("un retour ancien", -80.0)] {
            let engagement = Commitment(text: texte, ownerSide: .manager,
                                         dueAt: Self.quatreSeptembre.addingTimeInterval(jours * Self.jour),
                                         promisedAt: Self.quatreSeptembre.addingTimeInterval(jours * Self.jour))
            context.insert(engagement)
            engagement.thread = fil
        }

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        #expect(rappels.map(\.text) == ["Vous lui devez un retour ancien.",
                                        "Vous lui devez un retour récent."])
    }

    // MARK: - Règle 2

    @Test("Un sujet évoqué trois fois sans décision suit en position 2")
    func sujetNonTranche() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)
        for texte in ["Mobilité archi évoquée", "Souhait d'évolution vers l'archi",
                      "Mobilité : réponse ferme attendue"] {
            note(reunion, context, texte, kind: .note)
        }

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        #expect(rappels.count == 1)
        #expect(rappels[0].rule == .undecidedRecurringTopic)
        #expect(rappels[0].text == "Mobilité archi évoquée 3 fois, jamais tranchée.")
    }

    @Test("Un sujet évoqué deux fois ne remonte pas encore")
    func sujetSousLeSeuil() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)
        note(reunion, context, "Mobilité archi", kind: .note)
        note(reunion, context, "Évolution vers l'archi", kind: .note)

        #expect(ReminderRules.recurringTopicThreshold == 3)
        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    @Test("Un sujet déjà inscrit à l'ordre du jour ne remonte pas")
    func sujetDejaALOrdreDuJour() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)
        for texte in ["Mobilité archi évoquée", "Souhait d'évolution vers l'archi",
                      "Mobilité : réponse ferme attendue"] {
            note(reunion, context, texte, kind: .note)
        }

        // La carte s'appelle « À NE PAS OUBLIER » : un sujet déjà à l'ordre du
        // jour ne risque pas d'être oublié.
        let inscrit = OneOnOneAgendaItem(text: "Mobilité archi : trancher cette fois")
        context.insert(inscrit)
        inscrit.thread = fil
        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)

        // Reporté, en revanche, veut dire « pas traité » : le rappel revient.
        inscrit.state = .deferred
        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).count == 1)
    }

    @Test("Un sujet tranché par une décision ne remonte pas")
    func sujetTranche() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)
        for texte in ["Mobilité archi évoquée", "Souhait d'évolution vers l'archi",
                      "Mobilité : réponse ferme attendue"] {
            note(reunion, context, texte, kind: .note)
        }
        note(reunion, context, "La mobilité archi est actée pour janvier", kind: .decision)

        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    // MARK: - Règle 3

    @Test("Une réussite récente non citée en feedback vient en position 3")
    func reussiteNonReconnue() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let action = ActionTask(title: "la présentation COSUI du 1er sept.")
        action.collaborator = collab
        action.isCompleted = true
        action.completedAt = Self.quatreSeptembre.addingTimeInterval(-3 * Self.jour)
        context.insert(action)

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        #expect(rappels.count == 1)
        #expect(rappels[0].rule == .unrecognisedWin)
        #expect(rappels[0].text == "Féliciter pour la présentation COSUI du 1er sept.")
    }

    @Test("Une réussite déjà citée en feedback ne remonte pas")
    func reussiteDejaCitee() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)
        let action = ActionTask(title: "la présentation COSUI")
        action.collaborator = collab
        action.isCompleted = true
        action.completedAt = Self.quatreSeptembre.addingTimeInterval(-3 * Self.jour)
        context.insert(action)
        note(reunion, context, "Bravo pour la présentation COSUI, très claire", kind: .feedback)

        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    @Test("Une réussite antérieure au dernier 1:1 ne remonte pas")
    func reussiteTropAncienne() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let action = ActionTask(title: "un vieux livrable")
        action.collaborator = collab
        action.isCompleted = true
        action.completedAt = Self.vingtEtUnAout.addingTimeInterval(-10 * Self.jour)
        context.insert(action)

        // Elle a déjà été reconnue — ou pas — dans un entretien passé ; la
        // ressortir aujourd'hui ferait remonter tout l'historique à chaque
        // préparation.
        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    @Test("Une action encore ouverte n'est pas une réussite")
    func actionOuverte() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let action = ActionTask(title: "un livrable en cours")
        action.collaborator = collab
        context.insert(action)

        #expect(ReminderRules.reminders(for: fil, now: Self.quatreSeptembre).isEmpty)
    }

    // MARK: - Ordre et mise à l'ordre du jour

    @Test("Le jeu de la capture 2b rend les trois rappels dans l'ordre de la maquette")
    func troisReglesDansLOrdre() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, Self.vingtEtUnAout)

        // (1) Engagement du manager en retard.
        let engagement = Commitment(text: "un retour sur la grille d'astreinte",
                                     ownerSide: .manager,
                                     dueAt: Self.quatreSeptembre.addingTimeInterval(-42 * Self.jour),
                                     promisedAt: Self.quatreSeptembre.addingTimeInterval(-42 * Self.jour))
        engagement.deferralCount = 2
        context.insert(engagement)
        engagement.thread = fil

        // (2) Sujet évoqué trois fois, jamais tranché.
        for texte in ["Mobilité archi évoquée", "Souhait d'évolution vers l'archi",
                      "Mobilité : réponse ferme attendue"] {
            note(reunion, context, texte, kind: .note)
        }

        // (3) Réussite récente non reconnue.
        let action = ActionTask(title: "la présentation COSUI du 1er sept.")
        action.collaborator = collab
        action.isCompleted = true
        action.completedAt = Self.quatreSeptembre.addingTimeInterval(-3 * Self.jour)
        context.insert(action)

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        #expect(rappels.map(\.rule) == [.managerCommitmentLate,
                                        .undecidedRecurringTopic,
                                        .unrecognisedWin])
        #expect(rappels.map(\.text) == [
            "Vous lui devez un retour sur la grille d'astreinte — reporté 2 fois.",
            "Mobilité archi évoquée 3 fois, jamais tranchée.",
            "Féliciter pour la présentation COSUI du 1er sept."
        ])
        // Les trois pastilles de la capture 2b : rouge, orange, vert.
        #expect(rappels.map(\.tone) == [.report, .warn, .ok])
    }

    @Test("Mettre à l'ordre du jour crée un sujet par rappel, sans doublon")
    func mettreALOrdreDuJour() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let engagement = Commitment(text: "un retour sur la grille d'astreinte",
                                     ownerSide: .manager,
                                     state: .missed,
                                     promisedAt: Self.vingtEtUnAout)
        context.insert(engagement)
        engagement.thread = fil

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        let crees = ReminderRules.toAgendaItems(rappels, for: fil, role: .manager, in: context)

        #expect(crees.count == 1)
        #expect(crees[0].text == "Vous lui devez un retour sur la grille d'astreinte.")
        #expect(crees[0].addedBySide == .manager)
        #expect(crees[0].state == .todo)
        #expect(crees[0].kind == .topic)
        #expect(crees[0].visibility == .shared)

        // Rejouer le bouton ne double pas l'ordre du jour.
        #expect(ReminderRules.toAgendaItems(rappels, for: fil, role: .manager, in: context).isEmpty)
        #expect(fil.agendaItems.count == 1)
    }

    @Test("Les sujets créés se rangent à la suite de l'ordre du jour existant")
    func ordreALaSuite() throws {
        let (fil, context, collab) = try makeFil()
        seance(context, collab, Self.vingtEtUnAout)
        let existant = OneOnOneAgendaItem(text: "Charge de travail", order: 4)
        context.insert(existant)
        existant.thread = fil

        let engagement = Commitment(text: "un retour", ownerSide: .manager,
                                     state: .missed, promisedAt: Self.vingtEtUnAout)
        context.insert(engagement)
        engagement.thread = fil

        let rappels = ReminderRules.reminders(for: fil, now: Self.quatreSeptembre)
        let crees = ReminderRules.toAgendaItems(rappels, for: fil, role: .manager, in: context)
        #expect(crees.first?.order == 5)
    }
}
