import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// L'ancienneté de la carte personne (`Ingénieur CI/CD · dans l'équipe depuis
/// 3 ans`, capture 2a) et les deux colonnes que le lot 11 ajoute.
@Suite("Carte personne — ancienneté et colonnes du lot 11")
@MainActor
struct OneOnOneSeniorityTests {

    private static var maintenant: Date { RefonteDemoSeed.oneOnOneSeedDate }

    private func annees(_ n: Double) -> Date {
        Self.maintenant.addingTimeInterval(-n * 365.25 * 86_400)
    }

    private func mois(_ n: Double) -> Date {
        Self.maintenant.addingTimeInterval(-n * 30.44 * 86_400)
    }

    // MARK: - Libellé

    @Test("Trois ans et deux mois se lisent « dans l'équipe depuis 3 ans »")
    func troisAns() {
        #expect(OneOnOneSeniority.label(joinedAt: annees(3.2), now: Self.maintenant)
                == "dans l'équipe depuis 3 ans")
    }

    @Test("Un an se dit au singulier")
    func unAn() {
        #expect(OneOnOneSeniority.label(joinedAt: annees(1.1), now: Self.maintenant)
                == "dans l'équipe depuis 1 an")
    }

    @Test("Sous un an, l'ancienneté se compte en mois")
    func moisEntiers() {
        #expect(OneOnOneSeniority.label(joinedAt: mois(8), now: Self.maintenant)
                == "dans l'équipe depuis 8 mois")
        #expect(OneOnOneSeniority.label(joinedAt: mois(1.2), now: Self.maintenant)
                == "dans l'équipe depuis 1 mois")
    }

    @Test("Le premier mois se dit « arrivé ce mois-ci »")
    func premierMois() {
        // « depuis 0 mois » n'est pas une phrase. Une arrivée toute fraîche est
        // justement l'information qui compte en 1:1.
        #expect(OneOnOneSeniority.label(joinedAt: mois(0.2), now: Self.maintenant)
                == "arrivé ce mois-ci")
    }

    @Test("Sans date d'arrivée, rien n'est affirmé")
    func sansDate() {
        // La colonne est optionnelle et vide sur les 372 fiches existantes :
        // inventer « depuis 0 an » mettrait un chiffre faux sur chaque carte.
        #expect(OneOnOneSeniority.label(joinedAt: nil, now: Self.maintenant) == nil)
    }

    @Test("Une date d'arrivée future ne produit pas d'ancienneté négative")
    func dateFuture() {
        let dansUnMois = Self.maintenant.addingTimeInterval(30 * 86_400)
        #expect(OneOnOneSeniority.label(joinedAt: dansUnMois, now: Self.maintenant) == nil)
    }

    @Test("Le libellé complet de la carte joint le rôle et l'ancienneté")
    func libelleDeCarte() {
        #expect(OneOnOneSeniority.roleLine(role: "Ingénieur CI/CD",
                                           joinedAt: annees(3.2),
                                           now: Self.maintenant)
                == "Ingénieur CI/CD · dans l'équipe depuis 3 ans")
        // Sans date, le rôle reste seul — pas de séparateur orphelin.
        #expect(OneOnOneSeniority.roleLine(role: "Ingénieur CI/CD",
                                           joinedAt: nil,
                                           now: Self.maintenant)
                == "Ingénieur CI/CD")
    }

    // MARK: - Colonnes ajoutées

    @Test("Les deux colonnes du lot 11 existent avec leur valeur par défaut")
    func colonnesParDefaut() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)

        let personne = Collaborator(name: "Laurent NOMINÉ", role: "Ingénieur CI/CD")
        context.insert(personne)
        // Optionnelle : les fiches existantes restent lisibles sans migration
        // lourde (même règle que `Commitment.settledAt` au lot 10).
        #expect(personne.joinedAt == nil)
        personne.joinedAt = annees(3.2)

        let engagement = Commitment(text: "Arbitrer renfort ou décalage du Webcast")
        context.insert(engagement)
        #expect(engagement.blocksOther == false)
        engagement.blocksOther = true

        try context.save()
        #expect(try context.fetch(FetchDescriptor<Collaborator>()).first?.joinedAt != nil)
        #expect(try context.fetch(FetchDescriptor<Commitment>()).first?.blocksOther == true)
    }
}
