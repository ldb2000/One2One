import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// Les vues enregistrées du Portfolio (décision **D4**) : un jeu de filtres et
/// un tri nommés, stockés dans une colonne `…JSON` d'`AppSettings` — le motif
/// de `managerCategoriesJSON`, seul disponible pour une structure persistée
/// (constat §2.20). Aucun nouveau `@Model`, donc aucun `SchemaV4`.
@Suite("Vues enregistrées du Portfolio — D4")
@MainActor
struct PortfolioSavedViewTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// La vue de la capture 1a : « Mes projets ASP », entité ASP et risque au
    /// moins modéré.
    private var vueDeLaCapture: PortfolioSavedView {
        PortfolioSavedView(
            id: UUID(uuidString: "1F0C9E1A-0000-4000-8000-00000000AA01")!,
            name: "Mes projets ASP",
            filters: PortfolioFilters(entities: ["ASP"],
                                      phases: [],
                                      statuses: [],
                                      riskAtLeast: "Modéré",
                                      managers: [],
                                      text: ""),
            sort: PortfolioSort(column: .name, ascending: true)
        )
    }

    // MARK: - Aller-retour JSON

    @Test("Une vue enregistrée traverse l'encodage JSON sans rien perdre")
    func allerRetourJSON() throws {
        let vue = vueDeLaCapture
        let donnees = try JSONEncoder().encode([vue])
        let relues = try JSONDecoder().decode([PortfolioSavedView].self, from: donnees)
        #expect(relues == [vue])
    }

    @Test("Le tri par défaut du Portfolio est le nom, croissant")
    func triParDefaut() {
        #expect(PortfolioSort.parDefaut == PortfolioSort(column: .name, ascending: true))
    }

    @Test("Des filtres vides ne filtrent rien")
    func filtresVides() {
        let vides = PortfolioFilters.aucun
        #expect(vides.entities.isEmpty)
        #expect(vides.phases.isEmpty)
        #expect(vides.statuses.isEmpty)
        #expect(vides.riskAtLeast == nil)
        #expect(vides.managers.isEmpty)
        #expect(vides.text.isEmpty)
        #expect(vides.estVide)
    }

    @Test("Des filtres renseignés ne sont pas vides")
    func filtresRenseignes() {
        #expect(!vueDeLaCapture.filters.estVide)
    }

    // MARK: - Accesseur d'AppSettings

    @Test("La colonne naît sur un tableau vide")
    func colonneParDefaut() throws {
        let contexte = try contexteEnMemoire()
        let reglages = AppSettings()
        contexte.insert(reglages)
        try contexte.save()
        #expect(reglages.portfolioSavedViewsJSON == "[]")
        #expect(reglages.portfolioSavedViews.isEmpty)
    }

    @Test("L'accesseur écrit et relit les vues enregistrées")
    func accesseurAllerRetour() throws {
        let contexte = try contexteEnMemoire()
        let reglages = AppSettings()
        contexte.insert(reglages)
        reglages.portfolioSavedViews = [vueDeLaCapture]
        try contexte.save()

        #expect(reglages.portfolioSavedViews == [vueDeLaCapture])
        #expect(reglages.portfolioSavedViewsJSON.contains("Mes projets ASP"))
    }

    /// Motif de `managerCategories` : un JSON corrompu rend le repli, jamais
    /// une exception. Une colonne éditée à la main ne doit pas empêcher
    /// l'ouverture du Portfolio.
    @Test("Un JSON corrompu rend un tableau vide, sans lever")
    func jsonCorrompu() throws {
        let contexte = try contexteEnMemoire()
        let reglages = AppSettings()
        contexte.insert(reglages)
        reglages.portfolioSavedViewsJSON = "{ceci n'est pas du JSON"
        try contexte.save()
        #expect(reglages.portfolioSavedViews.isEmpty)

        // Et l'écriture suivante répare la colonne.
        reglages.portfolioSavedViews = [vueDeLaCapture]
        #expect(reglages.portfolioSavedViews.count == 1)
    }

    @Test("Un JSON valide mais d'une autre forme rend aussi un tableau vide")
    func jsonDUneAutreForme() throws {
        let contexte = try contexteEnMemoire()
        let reglages = AppSettings()
        contexte.insert(reglages)
        reglages.portfolioSavedViewsJSON = "{\"name\":\"Mes projets ASP\"}"
        #expect(reglages.portfolioSavedViews.isEmpty)
    }

    @Test("Vider les vues enregistrées réécrit un tableau JSON vide")
    func videEcritTableauVide() throws {
        let contexte = try contexteEnMemoire()
        let reglages = AppSettings()
        contexte.insert(reglages)
        reglages.portfolioSavedViews = [vueDeLaCapture]
        reglages.portfolioSavedViews = []
        #expect(reglages.portfolioSavedViewsJSON == "[]")
    }
}
