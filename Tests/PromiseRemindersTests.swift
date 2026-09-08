import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// `Relancer` (spec §6.2 : « pilules `Promise le …`, `n reports`, `Relancer`
/// (crée un rappel **et** un item d'ordre du jour pour le prochain 1:1) »).
///
/// Le rappel système est **injecté** : `UNUserNotificationCenter` n'existe pas
/// dans le binaire de test (son `mainBundle` n'est pas un `.app`), et la règle
/// à vérifier est « une relance, un rappel », pas la plomberie de macOS.
@Suite("Écran 5a — relancer une promesse (spec §6.2)")
@MainActor
struct PromiseRemindersTests {

    static let seance = Date(timeIntervalSince1970: 1_788_506_100)

    private func makeFil() throws -> (context: ModelContext,
                                      fil: OneOnOneThread,
                                      seance: Meeting,
                                      prochaine: Meeting) {
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

        let prochaine = Meeting(title: "1:1 avec Yann · 5",
                                date: Self.seance.addingTimeInterval(14 * 86_400),
                                notes: "")
        prochaine.kind = .manager
        context.insert(prochaine)
        prochaine.participants.append(yann)

        let fil = try #require(OneOnOneThreadStore.thread(for: seance, in: context))
        try context.save()
        return (context, fil, seance, prochaine)
    }

    private func promesse(in fil: OneOnOneThread,
                          _ context: ModelContext) -> Commitment {
        let engagement = Commitment(text: "Grille de compensation des astreintes",
                                    ownerSide: .manager,
                                    dueAt: Self.seance.addingTimeInterval(-42 * 86_400),
                                    promisedAt: Self.seance.addingTimeInterval(-42 * 86_400),
                                    visibility: .private)
        engagement.deferralCount = 2
        context.insert(engagement)
        engagement.thread = fil
        return engagement
    }

    @Test("Une relance crée un sujet privé sur la prochaine séance et compte la relance")
    func premiereRelance() throws {
        let (context, fil, _, prochaine) = try makeFil()
        let engagement = promesse(in: fil, context)
        try context.save()

        var rappels: [String] = []
        let sujet = PromiseReminders.remind(engagement, in: fil, nextMeeting: prochaine,
                                            in: context) { rappels.append($0) }

        #expect(sujet.text == "Relancer : Grille de compensation des astreintes")
        #expect(sujet.visibility == .private)
        #expect(sujet.addedBySide == .collaborator)
        #expect(sujet.kind == .topic)
        #expect(sujet.meeting?.persistentModelID == prochaine.persistentModelID)
        #expect(sujet.remindedCount == 1)
        #expect(rappels.count == 1)
        #expect(rappels.first == "Relancer : Grille de compensation des astreintes")
        // La relance ne solde pas la promesse et n'ajoute pas un report de
        // plus : reporter est le geste du manager, relancer est le mien.
        #expect(engagement.state == .open)
        #expect(engagement.deferralCount == 2)
    }

    @Test("Deux relances ne créent qu'un sujet, avec le compteur à deux")
    func deuxiemeRelance() throws {
        let (context, fil, _, prochaine) = try makeFil()
        let engagement = promesse(in: fil, context)
        try context.save()

        var rappels: [String] = []
        let premier = PromiseReminders.remind(engagement, in: fil, nextMeeting: prochaine,
                                              in: context) { rappels.append($0) }
        let second = PromiseReminders.remind(engagement, in: fil, nextMeeting: prochaine,
                                             in: context) { rappels.append($0) }

        #expect(premier.persistentModelID == second.persistentModelID)
        #expect(second.remindedCount == 2)
        #expect(fil.agendaItems.filter { $0.text == PromiseReminders.agendaText(for: engagement) }
                    .count == 1)
        // Un rappel par relance : c'est le geste qui le déclenche, pas la
        // création du sujet.
        #expect(rappels.count == 2)
    }

    @Test("Sans prochaine séance planifiée, le sujet est créé sans cible")
    func sansProchaineSeance() throws {
        let (context, fil, _, _) = try makeFil()
        let engagement = promesse(in: fil, context)
        try context.save()

        let sujet = PromiseReminders.remind(engagement, in: fil, nextMeeting: nil,
                                            in: context, notify: nil)
        // Il vaut mieux un sujet sans séance — `AgendaCarryover.items` le
        // rattache alors à la prochaine ouverte — qu'une relance perdue.
        #expect(sujet.meeting == nil)
        #expect(sujet.remindedCount == 1)
    }

    @Test("Le sujet de relance est bien à l'ordre du jour de la séance suivante")
    func sujetVisibleSurLaProchaine() throws {
        let (context, fil, _, prochaine) = try makeFil()
        let engagement = promesse(in: fil, context)
        try context.save()

        PromiseReminders.remind(engagement, in: fil, nextMeeting: prochaine,
                                in: context, notify: nil)

        let ordre = AgendaCarryover.items(of: fil, for: prochaine)
        #expect(ordre.map(\.text) == ["Relancer : Grille de compensation des astreintes"])
    }

    @Test("Le libellé du sujet nomme la promesse, pour être lisible seul")
    func libelleDuSujet() throws {
        let (context, fil, _, _) = try makeFil()
        let engagement = promesse(in: fil, context)
        try context.save()

        #expect(PromiseReminders.agendaText(for: engagement)
                == "Relancer : Grille de compensation des astreintes")
    }
}
