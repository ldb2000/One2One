import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La recherche de projets, source unique (décision **D7**).
///
/// Trois appelants la partageront : la barre latérale (ce lot), la palette `⌘K`
/// (lot 3) et le Portfolio (lot 2). Elle est donc testée pour ce que chacun
/// attend — trouver par un champ (`matches`), classer par pertinence (`rank`),
/// et dire où surligner (`highlightRanges`) — avant qu'aucune vue ne l'appelle.
///
/// Ce que `projectMatches` de `Sidebar.swift` savait faire (nom, code, domaine,
/// notes) est repris à l'identique ; ce que D7 ajoute — sponsor, chef de projet,
/// architecte — est vérifié champ par champ, parce que c'est la seule preuve
/// que la migration n'a rien perdu.
@Suite("Recherche de projets — D7")
@MainActor
struct ProjectSearchTests {

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Un projet inséré, aux champs que la recherche lit.
    @discardableResult
    private func projet(_ contexte: ModelContext,
                        code: String = "P25_001",
                        nom: String = "ASP – BLOOM",
                        domaine: String = "ASP",
                        sponsor: String = "",
                        chefDeProjet: String = "",
                        architecte: String = "",
                        epingle: Bool = false) -> Project {
        let p = Project(code: code, name: nom, domain: domaine,
                        sponsor: sponsor, projectType: "Métier", phase: "Build",
                        status: "Green")
        p.chefDeProjet = chefDeProjet
        p.architecte = architecte
        p.pinned = epingle
        contexte.insert(p)
        return p
    }

    // MARK: - Les champs

    @Test("Les quatre champs de l'ancien prédicat sont conservés : nom, code, domaine, notes")
    func champsHistoriques() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_193", nom: "AE – Services IO", domaine: "ASP")
        #expect(ProjectSearch.matches(p, query: "services"))
        #expect(ProjectSearch.matches(p, query: "P25_193"))
        #expect(ProjectSearch.matches(p, query: "asp"))
        #expect(!ProjectSearch.matches(p, query: "facturation"))

        let note = Meeting(title: "Point IO", date: Date(), notes: "")
        note.kind = .note
        note.liveNotes = "Relancer l’ALP sur la facturation"
        contexte.insert(note)
        note.project = p
        #expect(ProjectSearch.matches(p, query: "facturation", notes: [note]))
        #expect(ProjectSearch.matches(p, query: "Point IO", notes: [note]))
    }

    @Test("Le sponsor est trouvé — ce que le handoff 1c demandait d'ajouter")
    func sponsor() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, sponsor: "Direction financière")
        #expect(ProjectSearch.matches(p, query: "financière"))
        // Sans accent : la recherche plie les diacritiques.
        #expect(ProjectSearch.matches(p, query: "financiere"))
    }

    @Test("Le chef de projet est trouvé par la relation quand elle existe")
    func chefParRelation() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, chefDeProjet: "NOMINE Laurent")
        let manuel = Collaborator(name: "RIGAUT Manuel", role: "Chef de projet")
        contexte.insert(manuel)
        p.projectManager = manuel
        // D3 : la relation fait foi, et c'est elle que la colonne affiche.
        #expect(ProjectSearch.matches(p, query: "rigaut"))
    }

    @Test("Le chef de projet en chaîne libre est trouvé quand la relation manque")
    func chefParChaine() throws {
        let contexte = try contexteEnMemoire()
        // Le cas `P25_099` du semis : le nom vient du xlsx, la relation manque.
        let p = projet(contexte, chefDeProjet: "NOMINE Laurent")
        #expect(p.projectManager == nil)
        #expect(ProjectSearch.matches(p, query: "nomine"))
    }

    @Test("L'architecte suit la même règle : relation, puis chaîne")
    func architecte() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, architecte: "THEDREZ Wilfried")
        #expect(ProjectSearch.matches(p, query: "thedrez"))

        let nicolas = Collaborator(name: "PAOLI Nicolas", role: "Architecte technique")
        contexte.insert(nicolas)
        p.technicalArchitect = nicolas
        #expect(ProjectSearch.matches(p, query: "paoli"))
    }

    @Test("L'entité est lue, comme le faisait le sélecteur de la liste des réunions")
    func entite() throws {
        // Ajoutée au lot 3 (**D7**) : elle n'était que dans le prédicat de
        // `MeetingsProjectFilterPicker`, qui migre ici. Une recherche unique
        // est l'union de ce qu'elle remplace.
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, nom: "BLOOM", domaine: "")
        #expect(!ProjectSearch.matches(p, query: "logistique"))

        let entite = Entity(name: "LOG – Logistique")
        contexte.insert(entite)
        p.entity = entite
        #expect(ProjectSearch.matches(p, query: "logistique"))
        // Casse et accents pliés ici aussi.
        #expect(ProjectSearch.matches(p, query: "LOGISTIQUE"))
    }

    @Test("Une recherche vide ne filtre rien")
    func rechercheVide() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte)
        #expect(ProjectSearch.matches(p, query: ""))
        #expect(ProjectSearch.matches(p, query: "   "))
    }

    @Test("Une note d'un autre projet ne fait pas remonter celui-ci")
    func notesDUnAutreProjet() throws {
        let contexte = try contexteEnMemoire()
        let p = projet(contexte, code: "P25_001")
        let autre = projet(contexte, code: "P25_002", nom: "RH – TIME & APPLI")
        let note = Meeting(title: "Rétrospective", date: Date(), notes: "")
        note.kind = .note
        note.liveNotes = "Sujet du second projet"
        contexte.insert(note)
        note.project = autre
        #expect(!ProjectSearch.matches(p, query: "second", notes: [note]))
    }

    // MARK: - Le classement

    @Test("Préfixe avant mot, mot avant sous-chaîne")
    func rangDesTroisNatures() throws {
        let contexte = try contexteEnMemoire()
        let prefixe = projet(contexte, code: "P25_001", nom: "GED – refonte")
        let mot = projet(contexte, code: "P25_002", nom: "ASP – Installation nouvelle GED")
        let sousChaine = projet(contexte, code: "P25_003", nom: "ASP – Budget")
        // « ged » n'apparaît dans le troisième que par son sponsor, au milieu
        // d'un mot : c'est la sous-chaîne.
        sousChaine.sponsor = "Direction MEGEDIS"

        let classes = ProjectSearch.rank([sousChaine, mot, prefixe], query: "ged")
        #expect(classes.map(\.code) == ["P25_001", "P25_002", "P25_003"])
    }

    @Test("À pertinence égale, les épinglés passent devant")
    func epinglesDAbord() throws {
        let contexte = try contexteEnMemoire()
        let ordinaire = projet(contexte, code: "P25_001", nom: "GED – annuaire")
        let epingle = projet(contexte, code: "P25_002", nom: "GED – bascule", epingle: true)
        let classes = ProjectSearch.rank([ordinaire, epingle], query: "ged")
        #expect(classes.map(\.code) == ["P25_002", "P25_001"])
    }

    @Test("À pertinence et épinglage égaux, le nom tranche")
    func puisLeNom() throws {
        let contexte = try contexteEnMemoire()
        let b = projet(contexte, code: "P25_002", nom: "GED – bascule")
        let a = projet(contexte, code: "P25_001", nom: "GED – annuaire")
        #expect(ProjectSearch.rank([b, a], query: "ged").map(\.code) == ["P25_001", "P25_002"])
    }

    @Test("Le classement écarte ce qui ne correspond pas")
    func rangFiltre() throws {
        let contexte = try contexteEnMemoire()
        let trouve = projet(contexte, code: "P25_001", nom: "ASP – GED")
        let absent = projet(contexte, code: "P25_002", nom: "RH – TIME & APPLI")
        #expect(ProjectSearch.rank([trouve, absent], query: "ged").map(\.code) == ["P25_001"])
    }

    @Test("Sans terme, le classement rend tout : épinglés d'abord, puis le nom")
    func rangSansTerme() throws {
        let contexte = try contexteEnMemoire()
        let b = projet(contexte, code: "P25_002", nom: "BLOOM")
        let a = projet(contexte, code: "P25_001", nom: "ANNUAIRE")
        let epingle = projet(contexte, code: "P25_003", nom: "ZÉNITH", epingle: true)
        #expect(ProjectSearch.rank([b, a, epingle], query: "").map(\.code)
                == ["P25_003", "P25_001", "P25_002"])
    }

    // MARK: - Le surlignage

    @Test("Le surlignage rend chaque occurrence, casse et accents pliés")
    func surlignage() {
        let texte = "ASP – Installation nouvelle GED, puis migration ged"
        let plages = ProjectSearch.highlightRanges(in: texte, query: "GeD")
        #expect(plages.count == 2)
        #expect(plages.map { String(texte[$0]) } == ["GED", "ged"])
    }

    @Test("Un terme absent, vide ou blanc ne surligne rien")
    func surlignageVide() {
        #expect(ProjectSearch.highlightRanges(in: "ASP – BLOOM", query: "ged").isEmpty)
        #expect(ProjectSearch.highlightRanges(in: "ASP – BLOOM", query: "").isEmpty)
        #expect(ProjectSearch.highlightRanges(in: "ASP – BLOOM", query: "   ").isEmpty)
        #expect(ProjectSearch.highlightRanges(in: "", query: "ged").isEmpty)
    }

    @Test("Le surlignage plie les diacritiques du texte comme du terme")
    func surlignageAccents() {
        let texte = "Refonte des états réglementaires"
        let plages = ProjectSearch.highlightRanges(in: texte, query: "etats")
        #expect(plages.count == 1)
        #expect(plages.map { String(texte[$0]) } == ["états"])
    }
}
