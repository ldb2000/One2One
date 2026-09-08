import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// **Critère d'acceptation du chantier 2, n° 2** : « un engagement manqué côté
/// manager est visible aussi bien dans 2a que dans 2b, avec son compteur de
/// reports ». Le registre est pur : les deux écrans liront la même liste.
@Suite("Engagements — le registre du fil (spec §3.3, §3.4)")
@MainActor
struct CommitmentLedgerTests {

    private static let jour: TimeInterval = 86_400
    private static let quatreSeptembre = Date(timeIntervalSince1970: 1_788_506_100)
    private static let vingtEtUnAout = quatreSeptembre.addingTimeInterval(-14 * jour)

    private func makeFil() throws -> (OneOnOneThread, ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let laurent = Collaborator(name: "Laurent NOMINÉ")
        laurent.oneToOneCadence = .bimensuelle
        context.insert(laurent)
        let fil = try #require(OneOnOneThreadStore.thread(for: laurent, kind: .oneToOne, in: context))
        return (fil, context)
    }

    @discardableResult
    private func engagement(_ fil: OneOnOneThread,
                            _ context: ModelContext,
                            _ texte: String,
                            side: OneOnOneSide = .manager,
                            state: CommitmentState = .open,
                            dueAt: Date? = nil,
                            promisedAt: Date = quatreSeptembre,
                            reports: Int = 0) -> Commitment {
        let c = Commitment(text: texte, ownerSide: side, dueAt: dueAt,
                           state: state, promisedAt: promisedAt)
        c.deferralCount = reports
        context.insert(c)
        c.thread = fil
        return c
    }

    // MARK: - Critère chantier 2 n° 2

    @Test("Un engagement manqué côté manager sort avec son compteur de reports")
    func engagementManqueCoteManager() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Retour sur la grille d'astreinte",
                   side: .manager, state: .missed, reports: 2)
        engagement(fil, context, "Reprise du périmètre Nexus",
                   side: .collaborator, state: .kept)

        let manques = CommitmentLedger.missed(fil, side: .manager)
        #expect(manques.count == 1)
        #expect(manques.first?.text == "Retour sur la grille d'astreinte")
        #expect(manques.first?.deferralCount == 2)
        #expect(CommitmentLedger.deferralLabel(manques[0]) == "2× reporté")
    }

    @Test("Sans report, il n'y a pas de compteur à afficher")
    func pasDeCompteurSansReport() throws {
        let (fil, context) = try makeFil()
        let c = engagement(fil, context, "Chiffrer la reprise AP", state: .missed)
        #expect(CommitmentLedger.deferralLabel(c) == nil)
    }

    @Test("Un engagement en retard côté manager est signalé, même encore ouvert")
    func retardCoteManagerSignale() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Retour sur la grille d'astreinte",
                   side: .manager, state: .open,
                   dueAt: Self.quatreSeptembre.addingTimeInterval(-42 * Self.jour),
                   reports: 2)

        let retards = CommitmentLedger.overdue(fil, now: Self.quatreSeptembre)
        #expect(retards.count == 1)
        #expect(CommitmentLedger.lateOnManagerSideLabel(fil, now: Self.quatreSeptembre)
                == "1 en retard côté manager")
    }

    @Test("Sans engagement en retard côté manager, aucun libellé d'alerte")
    func pasDeLibelleSansRetard() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Cadrer la formation Admin", side: .collaborator,
                   dueAt: Self.quatreSeptembre.addingTimeInterval(7 * Self.jour))
        #expect(CommitmentLedger.lateOnManagerSideLabel(fil, now: Self.quatreSeptembre) == nil)
    }

    // MARK: - Taux de tenue

    @Test("Le taux de tenue est kept / (kept + missed)")
    func tauxDeTenue() throws {
        let (fil, context) = try makeFil()
        for index in 0..<8 {
            engagement(fil, context, "Tenu \(index)", state: .kept)
        }
        for index in 0..<3 {
            engagement(fil, context, "Manqué \(index)", state: .missed)
        }

        let comptes = CommitmentLedger.counts(fil)
        #expect(comptes.kept == 8)
        #expect(comptes.missed == 3)
        #expect(comptes.open == 0)
        // 8 / 11 = 72,7 % → « taux 73 % » sur la capture 2b.
        #expect(CommitmentLedger.rateLabel(fil) == "8 tenus sur 11 · taux 73 %")
    }

    @Test("Sans engagement soldé, il n'y a pas de taux")
    func pasDeTauxSansSolde() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "En cours")
        #expect(CommitmentLedger.keptRate(fil) == nil)
        #expect(CommitmentLedger.rateLabel(fil) == nil)
    }

    // MARK: - Retard et tri

    @Test("Les engagements en retard sont ceux qui sont ouverts et dont l'échéance est passée")
    func retards() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Passé et ouvert", dueAt: Self.vingtEtUnAout)
        engagement(fil, context, "Passé mais tenu", state: .kept, dueAt: Self.vingtEtUnAout)
        engagement(fil, context, "À venir",
                   dueAt: Self.quatreSeptembre.addingTimeInterval(7 * Self.jour))
        engagement(fil, context, "Sans échéance")

        let retards = CommitmentLedger.overdue(fil, now: Self.quatreSeptembre)
        #expect(retards.map(\.text) == ["Passé et ouvert"])
    }

    @Test("Le tri met le plus en retard d'abord, les sans-échéance à la fin")
    func triParRetard() throws {
        let (fil, context) = try makeFil()
        let recent = engagement(fil, context, "Récent",
                                dueAt: Self.quatreSeptembre.addingTimeInterval(-2 * Self.jour))
        let ancien = engagement(fil, context, "Ancien",
                                dueAt: Self.quatreSeptembre.addingTimeInterval(-60 * Self.jour))
        let futur = engagement(fil, context, "Futur",
                               dueAt: Self.quatreSeptembre.addingTimeInterval(10 * Self.jour))
        let sansDate = engagement(fil, context, "Sans date")

        let tries = CommitmentLedger.byLatenessDescending([recent, ancien, futur, sansDate],
                                                          now: Self.quatreSeptembre)
        #expect(tries.map(\.text) == ["Ancien", "Récent", "Futur", "Sans date"])
    }

    // MARK: - Tenus depuis le dernier 1:1

    @Test("Tenus depuis le dernier 1:1 : rien avant cette date")
    func tenusDepuisLeDernier() throws {
        let (fil, context) = try makeFil()
        let ancien = engagement(fil, context, "Soldé en juillet", state: .kept,
                                promisedAt: Self.quatreSeptembre.addingTimeInterval(-60 * Self.jour))
        ancien.settledAt = Self.quatreSeptembre.addingTimeInterval(-50 * Self.jour)
        let recent = engagement(fil, context, "Soldé fin août", state: .kept)
        recent.settledAt = Self.quatreSeptembre.addingTimeInterval(-3 * Self.jour)
        engagement(fil, context, "Toujours ouvert")

        let depuis = CommitmentLedger.settledSince(Self.vingtEtUnAout, in: fil)
        #expect(depuis.map(\.text) == ["Soldé fin août"])

        // Sans séance précédente, tout ce qui est soldé remonte.
        #expect(CommitmentLedger.settledSince(nil, in: fil).count == 2)
    }

    // MARK: - Transitions

    @Test("Reporter ne solde pas : l'engagement reste ouvert, le compteur monte")
    func reporterNeSoldePas() throws {
        let (fil, context) = try makeFil()
        let c = engagement(fil, context, "Retour sur la grille d'astreinte",
                           dueAt: Self.vingtEtUnAout)
        let nouvelle = Self.quatreSeptembre.addingTimeInterval(14 * Self.jour)

        CommitmentLedger.postpone(c, to: nouvelle)
        #expect(c.state == .open)
        #expect(c.deferralCount == 1)
        #expect(c.dueAt == nouvelle)

        CommitmentLedger.postpone(c, to: nil)
        #expect(c.deferralCount == 2)
        // Reporter sans nouvelle date garde l'ancienne : effacer l'échéance
        // ferait disparaître l'engagement de la liste des retards.
        #expect(c.dueAt == nouvelle)
    }

    @Test("Marquer tenu ou manqué pose l'état et la date de solde")
    func marquerTenuOuManque() throws {
        let (fil, context) = try makeFil()
        let tenu = engagement(fil, context, "Tenu")
        let manque = engagement(fil, context, "Manqué")

        CommitmentLedger.markKept(tenu, on: Self.quatreSeptembre)
        CommitmentLedger.markMissed(manque, on: Self.quatreSeptembre)

        #expect(tenu.state == .kept)
        #expect(tenu.settledAt == Self.quatreSeptembre)
        #expect(manque.state == .missed)
        #expect(manque.settledAt == Self.quatreSeptembre)
    }

    @Test("Le premier solde fait foi")
    func premierSoldeFaitFoi() throws {
        let (fil, context) = try makeFil()
        let c = engagement(fil, context, "Tenu")
        CommitmentLedger.markKept(c, on: Self.vingtEtUnAout)
        CommitmentLedger.markMissed(c, on: Self.quatreSeptembre)

        #expect(c.state == .kept)
        #expect(c.settledAt == Self.vingtEtUnAout)
    }

    // MARK: - Filtre par côté

    @Test("Le filtre par côté rend Moi, l'autre, ou les deux")
    func filtreParCote() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Moi 1", side: .manager)
        engagement(fil, context, "Moi 2", side: .manager)
        engagement(fil, context, "Laurent 1", side: .collaborator)

        #expect(CommitmentLedger.all(fil, side: .manager).count == 2)
        #expect(CommitmentLedger.all(fil, side: .collaborator).count == 1)
        #expect(CommitmentLedger.all(fil, side: nil).count == 3)
    }

    @Test("Les engagements sortent du plus récemment promis au plus ancien")
    func triParDatePrise() throws {
        let (fil, context) = try makeFil()
        engagement(fil, context, "Ancien",
                   promisedAt: Self.quatreSeptembre.addingTimeInterval(-40 * Self.jour))
        engagement(fil, context, "Récent", promisedAt: Self.quatreSeptembre)

        #expect(CommitmentLedger.all(fil, side: nil).map(\.text) == ["Récent", "Ancien"])
    }
}
