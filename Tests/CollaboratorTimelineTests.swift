import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le fil de la fiche collaborateur : un seul axe temps, quatre types de
/// ligne. Réunions, 1:1, notes et décisions partagent une chronologie ; les
/// séparer en quatre listes oblige à la recoller de tête.
///
/// Les actions n'en sont pas. La spec le dit par ses compteurs :
/// `Tout 38 · 1:1 6 · Notes 9 · Décisions 4 · Réunions 19` s'additionne
/// exactement. Les actions vivent dans la colonne d'état.
@Suite("CollaboratorTimeline — un fil, pas quatre listes")
struct CollaboratorTimelineTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func meeting(_ context: ModelContext, _ collab: Collaborator,
                         kind: MeetingKind, title: String, daysAgo: Int) -> Meeting {
        let m = Meeting(title: title, date: Date(timeIntervalSince1970: 1_760_000_000 - Double(daysAgo) * 86_400))
        m.kind = kind
        m.participants = [collab]
        context.insert(m)
        return m
    }

    @Test("Chaque type de réunion prend sa pastille")
    func eachKindGetsItsPill() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        _ = meeting(context, alice, kind: .oneToOne, title: "Entretien", daysAgo: 1)
        _ = meeting(context, alice, kind: .note, title: "Pense-bête", daysAgo: 2)
        _ = meeting(context, alice, kind: .project, title: "Comité", daysAgo: 3)

        let kinds = CollaboratorTimeline.build(for: alice).map(\.kind)
        #expect(kinds == [.oneToOne, .note, .meeting])
    }

    @Test("Une décision devient une ligne, datée de sa réunion")
    func decisionsBecomeTheirOwnRows() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let m = meeting(context, alice, kind: .oneToOne, title: "Entretien", daysAgo: 5)
        m.decisions = ["Le support bascule sur Youssef", "Budget arbitré en comité"]

        let items = CollaboratorTimeline.build(for: alice)
        let decisions = items.filter { $0.kind == .decision }
        #expect(decisions.count == 2)
        #expect(decisions.allSatisfy { $0.date == m.date })
        #expect(decisions.first?.title == "Le support bascule sur Youssef")
    }

    @Test("Le badge d'une réunion compte les actions qu'elle a produites")
    func badgeCountsProducedActions() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let m = meeting(context, alice, kind: .project, title: "Revue", daysAgo: 1)
        for titre in ["Relancer la DSI", "Cadrer le budget"] {
            let t = ActionTask(title: titre); t.meeting = m; context.insert(t)
        }

        let ligne = try #require(CollaboratorTimeline.build(for: alice).first { $0.kind == .meeting })
        #expect(ligne.actionCount == 2)
        #expect(ligne.producedActions)
    }

    /// « Un Echange activité sans note ni action ne mérite pas une ligne de
    /// 44 px dans la fiche de quelqu'un. » — c'est ce drapeau qui permet au
    /// groupe de mois de n'afficher, déplié, que celles qui ont produit.
    @Test("Une réunion sans action est marquée comme n'ayant rien produit")
    func barrenMeetingIsFlagged() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        _ = meeting(context, alice, kind: .global, title: "Echange activité", daysAgo: 1)

        let ligne = try #require(CollaboratorTimeline.build(for: alice).first)
        #expect(!ligne.producedActions)
        #expect(ligne.actionCount == 0)
    }

    @Test("Le fil descend du plus récent au plus ancien")
    func newestFirst() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        _ = meeting(context, alice, kind: .oneToOne, title: "Ancien", daysAgo: 30)
        _ = meeting(context, alice, kind: .oneToOne, title: "Récent", daysAgo: 1)

        #expect(CollaboratorTimeline.build(for: alice).map(\.title) == ["Récent", "Ancien"])
    }

    @Test("Les compteurs de segments s'additionnent exactement au total")
    func segmentCountsAddUp() throws {
        let context = try makeContext()
        let alice = Collaborator(name: "Alice"); context.insert(alice)
        let m = meeting(context, alice, kind: .oneToOne, title: "Entretien", daysAgo: 1)
        m.decisions = ["Une décision"]
        _ = meeting(context, alice, kind: .note, title: "Note", daysAgo: 2)
        _ = meeting(context, alice, kind: .project, title: "Comité", daysAgo: 3)

        let items = CollaboratorTimeline.build(for: alice)
        let counts = CollaboratorTimeline.counts(of: items)
        #expect(counts[.oneToOne] == 1)
        #expect(counts[.note] == 1)
        #expect(counts[.decision] == 1)
        #expect(counts[.meeting] == 1)
        #expect(items.count == 4)
    }
}
