import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le tableau `Engagements réciproques` de la capture 2b : filtre, tri, badge
/// de retard côté manager, taux de tenue et composeur.
///
/// **Critère d'acceptation du chantier 2, n° 2** : « un engagement manqué côté
/// manager est visible aussi bien dans 2a que dans 2b, avec son compteur de
/// reports. » C'est ce modèle qui le tient pour 2b.
@Suite("Préparation 1:1 — tableau des engagements (capture 2b, spec §3.4)")
@MainActor
struct ManagerPrepCommitmentsTableTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }
    private static let jour: TimeInterval = 86_400

    private func semer() throws -> (fil: OneOnOneThread,
                                    courante: Meeting,
                                    context: ModelContext) {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let fils = RefonteDemoSeed.seedLot12(in: context)
        let courante = try #require(OneOnOneThreadStore.allMeetings(of: fils.manager).last)
        return (fils.manager, courante, context)
    }

    private func modele(_ fil: OneOnOneThread,
                        _ courante: Meeting?,
                        _ filtre: PrepCommitmentFilter = .both) -> CommitmentsTableModel {
        CommitmentsTableModel.build(fil, current: courante, filter: filtre,
                                    now: Self.maintenant)
    }

    // MARK: - Contenu

    @Test("Le tableau montre les quatre lignes de la capture, pas tout le fil")
    func quatreLignes() throws {
        let (fil, courante, _) = try semer()
        let table = modele(fil, courante)

        #expect(fil.commitments.count == 14)
        #expect(table.rows.count == 4)
        #expect(Set(table.rows.map(\.text)) == Set([
            "Arbitrer renfort ou décalage du Webcast",
            "Retour sur la grille d'astreinte",
            "Cadrer la formation Admin (plan + 2 dates)",
            "Reprise du périmètre Nexus"
        ]))
    }

    @Test("Le tri met le retard le plus ancien en tête, le sans-échéance en fin")
    func tri() throws {
        let (fil, courante, _) = try semer()
        let table = modele(fil, courante)

        #expect(table.rows.first?.text == "Retour sur la grille d'astreinte")
        #expect(table.rows.first?.isOverdue == true)
        // « Reprise du périmètre Nexus » est tenu et sans échéance : il ferme
        // la liste, il ne devance aucune échéance connue.
        #expect(table.rows.last?.text == "Reprise du périmètre Nexus")
        #expect(table.rows.last?.isKept == true)
    }

    @Test("Porteur et teintes : « Moi » en violet, le prénom en vert")
    func porteurs() throws {
        let (fil, courante, _) = try semer()
        let table = modele(fil, courante)

        #expect(table.firstName == "Laurent")
        let mien = try #require(table.rows.first { $0.text.hasPrefix("Arbitrer") })
        #expect(mien.ownerLabel == "Moi")
        #expect(mien.ownerTone == .oneOnOne)
        let sien = try #require(table.rows.first { $0.text.hasPrefix("Cadrer") })
        #expect(sien.ownerLabel == "Laurent")
        #expect(sien.ownerTone == .ok)
    }

    // MARK: - Colonne échéance

    @Test("La colonne échéance a les cinq écritures de la capture")
    func colonneEcheance() throws {
        let (fil, courante, context) = try semer()
        let table = modele(fil, courante)

        let enRetard = try #require(table.rows.first { $0.text.hasPrefix("Retour sur la grille") })
        #expect(enRetard.dueLabel == "En retard")
        #expect(enRetard.dueTone == .report)
        #expect(enRetard.deferralLabel == "2× reporté")

        let tenu = try #require(table.rows.first { $0.isKept })
        #expect(tenu.dueLabel == "Tenu")
        #expect(tenu.dueTone == nil)

        // Une échéance à sept jours s'écrit en date, mise en avant.
        let lointaine = try #require(table.rows.first { $0.text.hasPrefix("Cadrer") })
        #expect(lointaine.dueLabel == "11 sept.")
        #expect(lointaine.dueEmphasised)

        // Une échéance du lendemain s'écrit en jour de la semaine.
        let proche = try #require(table.rows.first { $0.text.hasPrefix("Arbitrer") })
        #expect(proche.dueLabel == OneOnOneDateFormat.weekday(
            Self.maintenant.addingTimeInterval(Self.jour)))
        #expect(!proche.dueEmphasised)

        // Un manqué le dit, en `accent/report`.
        let manque = try #require(fil.commitments.first { $0.state == .missed })
        let ecriture = CommitmentsTableModel.dueLabel(manque, now: Self.maintenant)
        #expect(ecriture.label == "Manqué")
        #expect(ecriture.tone == .report)

        // Un ouvert sans échéance ne prétend pas en avoir une.
        let sansDate = try #require(OneOnOnePrepStore.addCommitment(text: "Sans échéance",
                                                                    in: fil, in: context))
        #expect(CommitmentsTableModel.dueLabel(sansDate, now: Self.maintenant).label == "—")
    }

    @Test("La fenêtre du jour de la semaine s'arrête au septième jour")
    func fenetreDuJourDeLaSemaine() {
        let maintenant = Self.maintenant
        #expect(OneOnOneDateFormat.isWithinWeekdayWindow(maintenant, now: maintenant))
        #expect(OneOnOneDateFormat.isWithinWeekdayWindow(
            maintenant.addingTimeInterval(6 * Self.jour), now: maintenant))
        #expect(!OneOnOneDateFormat.isWithinWeekdayWindow(
            maintenant.addingTimeInterval(7 * Self.jour), now: maintenant))
        #expect(!OneOnOneDateFormat.isWithinWeekdayWindow(
            maintenant.addingTimeInterval(-Self.jour), now: maintenant))
        // Initiale en majuscule, locale française forcée.
        #expect(OneOnOneDateFormat.weekday(maintenant) == "Vendredi")
    }

    // MARK: - Filtre

    @Test("Le filtre segmenté ne garde qu'un côté à la fois")
    func filtre() throws {
        let (fil, courante, _) = try semer()

        let miens = modele(fil, courante, .mine)
        #expect(!miens.rows.isEmpty)
        #expect(miens.rows.allSatisfy { $0.ownerLabel == "Moi" })

        let siens = modele(fil, courante, .theirs)
        #expect(!siens.rows.isEmpty)
        #expect(siens.rows.allSatisfy { $0.ownerLabel == "Laurent" })

        #expect(miens.rows.count + siens.rows.count == modele(fil, courante, .both).rows.count)
    }

    @Test("Les trois segments portent les libellés de la capture")
    func libellesDesSegments() {
        #expect(PrepCommitmentFilter.allCases == [.both, .mine, .theirs])
        #expect(PrepCommitmentFilter.both.label(firstName: "Laurent") == "Les deux")
        #expect(PrepCommitmentFilter.mine.label(firstName: "Laurent") == "Moi")
        #expect(PrepCommitmentFilter.theirs.label(firstName: "Laurent") == "Laurent")
        #expect(PrepCommitmentFilter.both.side == nil)
        #expect(PrepCommitmentFilter.mine.side == .manager)
        #expect(PrepCommitmentFilter.theirs.side == .collaborator)
        // Un fil sans nom garde un segment lisible.
        #expect(PrepCommitmentFilter.theirs.label(firstName: "") == "Elle ou lui")
    }

    // MARK: - Badge et pied

    /// Critère chantier 2 n° 2 : le manquement du manager est visible ici.
    @Test("Le badge compte les retards côté manager et le pied donne le taux")
    func badgeEtPied() throws {
        let (fil, courante, _) = try semer()
        let table = modele(fil, courante)

        #expect(table.lateBadge == "1 en retard côté manager")
        #expect(table.rateLabel == "8 tenus sur 11 · taux 73 %")
        // Le pied compte tout le fil, y compris ce que le tableau ne montre
        // pas : c'est un taux de tenue, pas un décompte d'écran.
        #expect(table.rows.filter(\.isKept).count == 1)
    }

    @Test("Un fil sans engagement manqué ni échu n'affiche pas de badge")
    func sansBadge() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let personne = Collaborator(name: "Alice MARTIN", role: "Architecte")
        context.insert(personne)
        let fil = try #require(OneOnOneThreadStore.thread(for: personne, kind: .oneToOne,
                                                          in: context))

        let vide = modele(fil, nil)
        #expect(vide.isEmpty)
        #expect(vide.lateBadge == nil)
        #expect(vide.rateLabel == nil)
    }

    // MARK: - Composeur et bascule d'état

    @Test("Le composeur refuse le vide et pose « Moi » comme porteur")
    func composeur() throws {
        let (fil, courante, context) = try semer()

        #expect(OneOnOnePrepStore.addCommitment(text: "  \n ", in: fil, in: context) == nil)

        let cree = try #require(OneOnOnePrepStore.addCommitment(
            text: "  Relire la fiche d'astreinte  ",
            promisedAt: Self.maintenant,
            in: fil, in: context))
        #expect(cree.text == "Relire la fiche d'astreinte")
        #expect(cree.ownerSide == .manager)
        #expect(cree.state == .open)
        // Le manager écrit en `shared` (spec §3.2).
        #expect(cree.visibility == .shared)

        let table = modele(fil, courante)
        #expect(table.rows.contains { $0.text == "Relire la fiche d'astreinte" })
    }

    @Test("Le clic sur l'état solde puis rouvre, et ne réécrit pas un manqué")
    func basculeDEtat() throws {
        let (fil, _, context) = try semer()
        let ouvert = try #require(fil.commitments.first {
            $0.state == .open && $0.text.hasPrefix("Arbitrer")
        })

        OneOnOnePrepStore.toggleKept(ouvert, on: Self.maintenant, in: context)
        #expect(ouvert.state == .kept)
        #expect(ouvert.settledAt == Self.maintenant)

        OneOnOnePrepStore.toggleKept(ouvert, on: Self.maintenant, in: context)
        #expect(ouvert.state == .open)
        #expect(ouvert.settledAt == nil)

        // Un manquement est un fait de l'entretien : il ne s'efface pas d'un
        // clic depuis un écran de préparation.
        let manque = try #require(fil.commitments.first { $0.state == .missed })
        OneOnOnePrepStore.toggleKept(manque, on: Self.maintenant, in: context)
        #expect(manque.state == .missed)
    }

    // MARK: - Largeurs de colonnes (spec §3.4)

    @Test("Les largeurs fixes sont celles de la spec : 20 | 1fr | 92 | 84 | 96")
    func largeurs() {
        #expect(CommitmentsTableModel.stateColumn == 20)
        #expect(CommitmentsTableModel.ownerColumn == 92)
        #expect(CommitmentsTableModel.dueColumn == 84)
        #expect(CommitmentsTableModel.promisedColumn == 96)
    }
}
