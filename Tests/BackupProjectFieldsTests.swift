import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les champs que la refonte de la gestion des projets a ajoutés doivent
/// survivre à un aller-retour de sauvegarde.
///
/// Un champ absent du DTO ne casse rien à la compilation, ne fait échouer aucun
/// test, et ne se voit qu'au jour où quelqu'un restaure : ses projets épinglés
/// ne le sont plus, ses vues enregistrées ont disparu, et la date du périmètre
/// est repartie à zéro. C'est exactement ce qui était arrivé à
/// `Project.pinned` (D4), `Project.scopeText`/`scopeUpdatedAt` (D9) et
/// `AppSettings.portfolioSavedViewsJSON` (D4).
@MainActor
@Suite("Sauvegarde — les champs de la refonte des projets")
struct BackupProjectFieldsTests {

    private func contexteEnMemoire() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    /// Le 3 septembre 2026 à midi, en temps absolu — une date qui ne dépend ni
    /// du fuseau ni du calendrier du poste.
    private static let dateDePerimetre = Date(timeIntervalSince1970: 1_788_782_400)

    /// Un store qui porte les trois champs renseignés, et sa sauvegarde.
    private func sauvegarde() throws -> (Data, ModelContext) {
        let contexte = try contexteEnMemoire()

        let reglages = AppSettings()
        contexte.insert(reglages)
        reglages.portfolioSavedViews = [
            PortfolioSavedView(name: "Mes projets ASP",
                               filters: PortfolioFilters(entities: ["ASP"]),
                               sort: .parDefaut)
        ]

        let epingle = Project(code: "P25_112", name: "ASP – BLOOM",
                              domain: "ASP", phase: "Build")
        epingle.pinned = true
        epingle.scopeText = "Refonte du parcours de souscription."
        epingle.scopeUpdatedAt = Self.dateDePerimetre
        contexte.insert(epingle)

        let ordinaire = Project(code: "P25_113", name: "ASP – Obsolescence VM",
                                domain: "ASP", phase: "Run")
        contexte.insert(ordinaire)

        try contexte.save()
        let data = try BackupService().backup(settings: reglages,
                                              entities: [],
                                              projects: [epingle, ordinaire],
                                              collaborators: [])
        return (data, contexte)
    }

    @Test("Épinglage, périmètre et vues enregistrées survivent à l'aller-retour")
    func allerRetour() throws {
        let (data, _) = try sauvegarde()
        let cible = try contexteEnMemoire()
        try BackupService().restore(from: data, into: cible)

        let projets = try cible.fetch(FetchDescriptor<Project>())
        #expect(projets.count == 2)
        let bloom = try #require(projets.first { $0.code == "P25_112" })
        #expect(bloom.pinned, "l'épinglage doit revenir — sinon la barre latérale se vide")
        #expect(bloom.scopeText == "Refonte du parcours de souscription.")
        #expect(bloom.scopeUpdatedAt == Self.dateDePerimetre)

        // Un projet non épinglé le reste : le défaut du modèle est `false`, et
        // la restauration ne doit pas l'inverser.
        let autre = try #require(projets.first { $0.code == "P25_113" })
        #expect(!autre.pinned)
        #expect(autre.scopeText.isEmpty)
        #expect(autre.scopeUpdatedAt == nil)

        let reglages = try cible.fetch(FetchDescriptor<AppSettings>())
        let vues = PortfolioSavedViewStore.vues(reglages.canonicalSettings)
        #expect(vues.map(\.name) == ["Mes projets ASP"])
        #expect(vues.first?.filters.entities == ["ASP"])
    }

    /// Le format porte bien les clés : sans cette vérification, un DTO qui
    /// encoderait `nil` passerait le test d'aller-retour par le seul jeu des
    /// valeurs par défaut.
    @Test("Les trois clés sont réellement écrites dans le JSON")
    func clesPresentesDansLeJSON() throws {
        let (data, _) = try sauvegarde()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let reglages = try #require(json["settings"] as? [String: Any])
        let vues = try #require(reglages["portfolioSavedViewsJSON"] as? String)
        #expect(vues.contains("Mes projets ASP"))

        let projets = try #require(json["projects"] as? [[String: Any]])
        let bloom = try #require(projets.first { $0["code"] as? String == "P25_112" })
        #expect(bloom["pinned"] as? Bool == true)
        #expect(bloom["scopeText"] as? String == "Refonte du parcours de souscription.")
        #expect(bloom["scopeUpdatedAt"] != nil)
    }

    /// Une sauvegarde **antérieure** à la refonte n'a aucune de ces clés : elle
    /// doit se restaurer sans erreur, sur les valeurs par défaut du modèle.
    @Test("Une sauvegarde d'avant la refonte se restaure sur les défauts")
    func sauvegardeAncienne() throws {
        let (data, _) = try sauvegarde()
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        var reglages = try #require(json["settings"] as? [String: Any])
        reglages["portfolioSavedViewsJSON"] = nil
        json["settings"] = reglages

        let projets = try #require(json["projects"] as? [[String: Any]])
        json["projects"] = projets.map { projet -> [String: Any] in
            var copie = projet
            copie["pinned"] = nil
            copie["scopeText"] = nil
            copie["scopeUpdatedAt"] = nil
            return copie
        }

        let ancienne = try JSONSerialization.data(withJSONObject: json)
        let cible = try contexteEnMemoire()
        try BackupService().restore(from: ancienne, into: cible)

        let restaures = try cible.fetch(FetchDescriptor<Project>())
        #expect(restaures.count == 2, "le reste de la sauvegarde doit revenir")
        #expect(restaures.allSatisfy { !$0.pinned })
        #expect(restaures.allSatisfy { $0.scopeText.isEmpty })
        #expect(restaures.allSatisfy { $0.scopeUpdatedAt == nil })

        let reglagesRestaures = try cible.fetch(FetchDescriptor<AppSettings>())
        #expect(reglagesRestaures.canonicalSettings?.portfolioSavedViewsJSON == "[]")
        #expect(PortfolioSavedViewStore.vues(reglagesRestaures.canonicalSettings).isEmpty)
    }
}
