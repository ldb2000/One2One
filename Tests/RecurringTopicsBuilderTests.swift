import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Spec §3.4 : « Sujets récurrents : chips `label · n` colorées par famille
/// (charge → warn, carrière → violet, reconnaissance → ok). »
///
/// Le comptage est un **calcul**, pas une table (programme §3 : « recurringTopics
/// — calculé depuis `MeetingTag` des réunions du fil + mots-clés des
/// `OneOnOneAgendaItem` »). Une table serait un troisième endroit à tenir en
/// phase avec les notes et les thèmes.
@Suite("Sujets récurrents — familles par lexique FR (spec §3.4)")
@MainActor
struct RecurringTopicsBuilderTests {

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
    private func seance(_ context: ModelContext, _ collab: Collaborator,
                        _ offsetJours: Double) -> Meeting {
        let reunion = Meeting(title: "1:1 Laurent",
                              date: Self.quatreSeptembre.addingTimeInterval(offsetJours * Self.jour),
                              notes: "")
        reunion.kind = .oneToOne
        context.insert(reunion)
        reunion.participants.append(collab)
        return reunion
    }

    private func sujet(_ fil: OneOnOneThread, _ context: ModelContext, _ texte: String) {
        let item = OneOnOneAgendaItem(text: texte)
        context.insert(item)
        item.thread = fil
    }

    private func note(_ reunion: Meeting, _ context: ModelContext,
                      _ texte: String, kind: MeetingNoteKind = .note) {
        let ligne = MeetingNote(t: 0, text: texte, kind: kind)
        context.insert(ligne)
        ligne.meeting = reunion
    }

    // MARK: - Lexique

    @Test("Les cinq familles se reconnaissent sans accent ni casse")
    func lexiqueRobuste() {
        #expect(RecurringTopicsBuilder.family(of: "Charge de travail sur la migration AP") == .charge)
        #expect(RecurringTopicsBuilder.family(of: "CHARGE DE TRAVAIL") == .charge)
        #expect(RecurringTopicsBuilder.family(of: "Je sature") == .charge)
        #expect(RecurringTopicsBuilder.family(of: "Souhait de mobilité vers l'archi") == .carriere)
        #expect(RecurringTopicsBuilder.family(of: "mobilite archi") == .carriere)
        #expect(RecurringTopicsBuilder.family(of: "Féliciter pour la présentation COSUI") == .reconnaissance)
        #expect(RecurringTopicsBuilder.family(of: "Formation Admin : est-ce que je peux la porter ?") == .formation)
        #expect(RecurringTopicsBuilder.family(of: "Astreintes week-end : compensation à clarifier") == .astreinte)
    }

    @Test("Un texte hors lexique n'entre dans aucune famille")
    func horsLexique() {
        #expect(RecurringTopicsBuilder.family(of: "Point météo du lundi") == nil)
        #expect(RecurringTopicsBuilder.family(of: "") == nil)
    }

    @Test("Chaque famille porte le libellé et le ton de la spécification")
    func libellesEtTons() {
        #expect(RecurringTopicFamily.charge.label == "Charge de travail")
        #expect(RecurringTopicFamily.charge.tone == .warn)
        #expect(RecurringTopicFamily.carriere.tone == .oneOnOne)
        #expect(RecurringTopicFamily.reconnaissance.tone == .ok)
        #expect(RecurringTopicFamily.allCases.count == 5)
    }

    // MARK: - Comptage

    @Test("Le comptage additionne ordre du jour, notes et thèmes")
    func comptageSurTroisSources() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, 0)

        sujet(fil, context, "Charge de travail sur la migration AP")
        note(reunion, context, "Charge AP — estime 3 j-h de reprise non prévus")
        let theme = MeetingTag(name: "Surcharge")
        context.insert(theme)
        reunion.tags.append(theme)

        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil)
        let charge = try #require(topics.first { $0.family == .charge })
        #expect(charge.count == 3)
    }

    @Test("La sortie est triée par comptage décroissant")
    func triParComptage() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, 0)

        for _ in 0..<3 { sujet(fil, context, "Charge de travail") }
        note(reunion, context, "Mobilité archi à trancher")
        note(reunion, context, "Point sur les astreintes")
        note(reunion, context, "Astreintes week-end")

        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil)
        #expect(topics.map(\.count) == topics.map(\.count).sorted(by: >))
        #expect(topics.first?.family == .charge)
        #expect(topics.first?.count == 3)
    }

    @Test("Le jeu de la capture 2b donne Charge de travail · 5 en tête")
    func jeuDeLaCapture() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, 0)

        // Cinq mentions de charge, trois de mobilité, trois d'astreinte, deux
        // de formation, deux de reconnaissance — les chips de la capture 2b.
        sujet(fil, context, "Charge de travail sur la migration AP — je sature")
        for texte in ["Charge AP : 3 j-h non prévus",
                      "Surcharge sur la migration",
                      "Il ne tient plus le rythme",
                      "Capacité de l'équipe insuffisante"] {
            note(reunion, context, texte)
        }
        for texte in ["Mobilité archi évoquée", "Souhait d'évolution vers l'archi",
                      "Mobilité : réponse ferme attendue"] {
            note(reunion, context, texte)
        }
        for texte in ["Astreintes week-end", "Compensation des astreintes",
                      "Grille d'astreinte promise"] {
            note(reunion, context, texte)
        }
        for texte in ["Formation Admin à porter", "Certification Terraform"] {
            note(reunion, context, texte)
        }
        for texte in ["Féliciter pour le COSUI", "Reconnaissance du travail fourni"] {
            note(reunion, context, texte)
        }

        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil)
        #expect(topics.first?.label == "Charge de travail")
        #expect(topics.first?.count == 5)
        #expect(topics.map(\.count) == [5, 3, 3, 2, 2])
        #expect(RecurringTopicsBuilder.chipLabel(topics[0]) == "Charge de travail · 5")
    }

    @Test("Un texte qui touche deux familles ne compte qu'une fois")
    func pasDeDoubleComptage() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, 0)
        // « charge » et « astreinte » dans la même ligne : trancher plutôt que
        // compter deux fois, sinon la somme des chips dépasse le nombre de
        // lignes et plus personne ne sait ce qu'elle mesure.
        note(reunion, context, "Charge de travail liée aux astreintes")

        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil)
        #expect(topics.map(\.count).reduce(0, +) == 1)
        #expect(topics.first?.family == .charge)
    }

    @Test("Le filtre de période exclut ce qui précède `since`")
    func filtreDePeriode() throws {
        let (fil, context, collab) = try makeFil()
        let ancienne = seance(context, collab, -120)
        let recente = seance(context, collab, 0)
        note(ancienne, context, "Charge de travail en avril")
        note(recente, context, "Charge de travail en septembre")

        let depuisJuin = Self.quatreSeptembre.addingTimeInterval(-90 * Self.jour)
        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: depuisJuin)
        #expect(topics.first?.count == 1)
    }

    @Test("Les réunions à venir ne comptent pas encore")
    func pasDeReunionFuture() throws {
        let (fil, context, collab) = try makeFil()
        let future = seance(context, collab, 14)
        note(future, context, "Charge de travail à venir")

        #expect(RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil).isEmpty)
    }

    @Test("Une note privée compte quand même : le comptage est pour moi seul")
    func notePriveeComptee() throws {
        let (fil, context, collab) = try makeFil()
        let reunion = seance(context, collab, 0)
        note(reunion, context, "Risque de départ si la mobilité n'avance pas")
        let privee = MeetingNote(t: 0, text: "Charge de travail intenable", visibility: .private)
        context.insert(privee)
        privee.meeting = reunion

        // Les chips ne sortent jamais de l'écran de préparation : ce sont mes
        // notes, sur mon poste. Les exclure me priverait du signal.
        let topics = RecurringTopicsBuilder.build(fil, now: Self.quatreSeptembre, since: nil)
        #expect(topics.contains { $0.family == .charge })
    }
}
