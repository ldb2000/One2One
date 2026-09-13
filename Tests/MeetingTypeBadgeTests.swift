import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Le badge de type d'une réunion (décision **D10**).
///
/// `MeetingKind` n'a **pas** de COPIL et n'en aura pas : un COPIL est une
/// réunion projet que son thème ou son titre désigne. C'est la seule règle du
/// badge qui ne se lit pas dans une colonne, donc la seule qui puisse se
/// perdre — d'où ces tests avant la vue.
@Suite("Badge de type de réunion")
@MainActor
struct MeetingTypeBadgeTests {

    private func contexte() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func reunion(_ contexte: ModelContext,
                         titre: String = "Réunion",
                         kind: MeetingKind = .project,
                         themes: [String] = []) -> Meeting {
        let reunion = Meeting(title: titre, date: Date(), notes: "")
        reunion.kind = kind
        contexte.insert(reunion)
        for nom in themes {
            if let theme = MeetingTag.findOrCreate(name: nom, in: contexte) {
                reunion.tags.append(theme)
            }
        }
        return reunion
    }

    // MARK: - Les trois libellés

    @Test("Les trois libellés sont ceux de la capture 1d")
    func libelles() {
        #expect(MeetingTypeBadge.copil.libelle == "COPIL")
        #expect(MeetingTypeBadge.atelier.libelle == "Atelier")
        #expect(MeetingTypeBadge.oneOnOne.libelle == "1:1")
        #expect(MeetingTypeBadge.allCases.count == 3)
    }

    // MARK: - La règle COPIL

    @Test("Un thème « COPIL » fait un COPIL")
    func themeCopil() throws {
        let contexte = try contexte()
        let m = reunion(contexte, titre: "Arbitrage périmètre IO", themes: ["COPIL"])
        #expect(MeetingTypeBadge.from(m) == .copil)
    }

    @Test("Un titre qui contient « copil » fait un COPIL, casse et accents ignorés")
    func titreCopil() throws {
        let contexte = try contexte()
        #expect(MeetingTypeBadge.from(reunion(contexte, titre: "Copil mensuel")) == .copil)
        #expect(MeetingTypeBadge.from(reunion(contexte, titre: "COPIL de lancement")) == .copil)
        #expect(MeetingTypeBadge.estCopil(titre: "cópil", themes: []))
        #expect(MeetingTypeBadge.estCopil(titre: "", themes: ["Copil projet"]))
    }

    @Test("Sans thème ni titre COPIL, une réunion projet n'a pas de badge")
    func aucunBadge() throws {
        let contexte = try contexte()
        #expect(MeetingTypeBadge.from(reunion(contexte, titre: "Point hebdomadaire")) == nil)
        #expect(MeetingTypeBadge.from(reunion(contexte, kind: .global)) == nil)
        #expect(MeetingTypeBadge.from(reunion(contexte, kind: .note)) == nil)
        #expect(!MeetingTypeBadge.estCopil(titre: "Comité de pilotage", themes: ["Suivi"]))
    }

    // MARK: - Les deux `kind`

    @Test("Un atelier et un 1:1 se lisent dans le kind")
    func kinds() throws {
        let contexte = try contexte()
        #expect(MeetingTypeBadge.from(reunion(contexte, kind: .workshop)) == .atelier)
        #expect(MeetingTypeBadge.from(reunion(contexte, kind: .oneToOne)) == .oneOnOne)
    }

    /// L'ordre des épreuves : un COPIL tenu en atelier reste un COPIL — c'est
    /// l'instance qui se lit sur la carte, pas la forme de la séance.
    @Test("COPIL l'emporte sur le kind")
    func copilPrimeSurLeKind() throws {
        let contexte = try contexte()
        let m = reunion(contexte, titre: "COPIL", kind: .workshop)
        #expect(MeetingTypeBadge.from(m) == .atelier || MeetingTypeBadge.from(m) == .copil)
        #expect(MeetingTypeBadge.from(m) == .copil)
    }

    // MARK: - Les teintes

    /// Les trois couples du handoff §1d : `reportBg`/`reportInk`,
    /// `workshopBg`/`workshop`, `oneOnOneBg`/`oneOnOneInk`.
    @Test("Les teintes sont les trois couples du handoff")
    func teintes() {
        #expect(MeetingTypeBadgeView.fond(.copil) == One2OneToken.reportBg)
        #expect(MeetingTypeBadgeView.encre(.copil) == One2OneToken.reportInk)
        #expect(MeetingTypeBadgeView.fond(.atelier) == One2OneToken.workshopBg)
        #expect(MeetingTypeBadgeView.encre(.atelier) == One2OneToken.workshop)
        #expect(MeetingTypeBadgeView.fond(.oneOnOne) == One2OneToken.oneOnOneBg)
        #expect(MeetingTypeBadgeView.encre(.oneOnOne) == One2OneToken.oneOnOneInk)
    }

    @Test("Le badge est à la taille de la capture")
    func taille() {
        #expect(MeetingTypeBadgeView.taille == 11)
    }

    // MARK: - Sur le semis

    /// Les trois réunions nommées par la capture 1d, une par badge.
    @Test("Les trois réunions du semis portent les trois badges")
    func surLeSemis() throws {
        let contexte = try contexte()
        RefonteDemoSeed.seedPortfolio(in: contexte)
        let projet = try #require(try contexte.fetch(FetchDescriptor<Project>())
            .first { $0.code == RefonteDemoSeed.portfolioFocusProjectCode })
        let siennes = try contexte.fetch(FetchDescriptor<Meeting>())
            .filter { $0.project?.persistentModelID == projet.persistentModelID }

        let copil = try #require(siennes.first { $0.title == "Arbitrage périmètre IO" })
        let atelier = try #require(siennes.first { $0.title.hasPrefix("Cadrage technique") })
        let unAUn = try #require(siennes.first { $0.title.hasPrefix("Point d") })

        #expect(MeetingTypeBadge.from(copil) == .copil)
        #expect(MeetingTypeBadge.from(atelier) == .atelier)
        #expect(MeetingTypeBadge.from(unAUn) == .oneOnOne)
        // Les six réunions de remplissage n'ont pas de badge : la carte ne
        // colore que ce qui se distingue.
        #expect(siennes.filter { MeetingTypeBadge.from($0) == nil }.count == 6)
    }
}
