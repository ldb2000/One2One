import Testing
import Foundation
import SwiftData
@testable import OneToOne

/// La recherche lexicale dans les comptes rendus (décision **D8**), le second
/// bras de la palette : « Chercher « x » dans les CR ».
///
/// Trois promesses, et rien de plus : elle trouve le terme dans **tout** le
/// texte d'une réunion (`Meeting.textualContent`), elle écarte les notes, et
/// elle groupe par projet en rangeant « Sans projet » en dernier. Pas de RAG,
/// pas d'embeddings à la frappe.
@Suite("Recherche dans les comptes rendus")
@MainActor
struct ReportSearchTests {

    // MARK: - Outillage

    private func contexteEnMemoire() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @discardableResult
    private func reunion(_ contexte: ModelContext,
                         titre: String,
                         date: Date = Date(),
                         kind: MeetingKind = .project,
                         projet: Project? = nil,
                         notes: String = "",
                         resume: String = "",
                         decisions: [String] = []) -> Meeting {
        let m = Meeting(title: titre, date: date)
        m.kind = kind
        m.notes = notes
        m.summary = resume
        contexte.insert(m)
        m.decisions = decisions
        m.project = projet
        return m
    }

    private func projet(_ contexte: ModelContext, code: String, nom: String) -> Project {
        let p = Project(code: code, name: nom, domain: "", sponsor: "",
                        projectType: "Métier", phase: "Build")
        contexte.insert(p)
        return p
    }

    // MARK: - Correspondance

    @Test("le terme est cherché dans tout le texte de la réunion")
    func correspondanceSurTousLesChamps() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "COPIL GED", notes: "rien")
        reunion(c, titre: "COPIL", notes: "la GED est livrée")
        reunion(c, titre: "Atelier", resume: "migration de la ged")
        reunion(c, titre: "Revue", decisions: ["retenir la GED de l'éditeur"])
        reunion(c, titre: "Hors sujet", notes: "budget")

        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let trouves = ReportSearch.resultats(in: reunions, query: "ged")
        #expect(Set(trouves.map(\.titre))
                == ["COPIL GED", "COPIL", "Atelier", "Revue"])
    }

    @Test("la correspondance plie la casse et les accents")
    func casseEtAccents() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "Revue", notes: "les états financiers")
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        #expect(ReportSearch.resultats(in: reunions, query: "ETATS").count == 1)
        #expect(ReportSearch.resultats(in: reunions, query: "états").count == 1)
    }

    @Test("les notes ne sont pas des comptes rendus")
    func notesEcartees() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "Note GED", kind: .note, notes: "GED")
        reunion(c, titre: "COPIL GED", kind: .project)
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let trouves = ReportSearch.resultats(in: reunions, query: "ged")
        #expect(trouves.map(\.titre) == ["COPIL GED"])
    }

    @Test("un terme vide ou blanc ne rend rien — ce n'est pas « tout »")
    func termeVide() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "COPIL GED")
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        for terme in ["", "   ", "\n"] {
            #expect(ReportSearch.resultats(in: reunions, query: terme).isEmpty)
            #expect(ReportSearch.groupes(in: reunions, query: terme).isEmpty)
        }
    }

    @Test("une réunion ne rend qu'un résultat, étiqueté par le champ trouvé")
    func unResultatParReunion() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "COPIL GED", notes: "la GED encore", decisions: ["GED"])
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let trouves = ReportSearch.resultats(in: reunions, query: "ged")
        #expect(trouves.count == 1)
        // `textualContent` énumère le titre d'abord : c'est l'étiquette rendue.
        #expect(trouves[0].etiquette == "titre")

        let ailleurs = try contexteEnMemoire()
        reunion(ailleurs, titre: "COPIL", decisions: ["retenir la GED"])
        let autres = try ailleurs.fetch(FetchDescriptor<Meeting>())
        #expect(ReportSearch.resultats(in: autres, query: "ged")[0].etiquette == "décision")
    }

    @Test("les résultats sont rendus de la plus récente à la plus ancienne")
    func triParDate() throws {
        let c = try contexteEnMemoire()
        let hier = Date().addingTimeInterval(-86_400)
        let avant = Date().addingTimeInterval(-8 * 86_400)
        reunion(c, titre: "Ancienne GED", date: avant)
        reunion(c, titre: "Récente GED", date: hier)
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        #expect(ReportSearch.resultats(in: reunions, query: "ged").map(\.titre)
                == ["Récente GED", "Ancienne GED"])
    }

    // MARK: - Groupement

    @Test("les résultats sont groupés par projet, « Sans projet » en dernier")
    func groupement() throws {
        let c = try contexteEnMemoire()
        let rh = projet(c, code: "P24_211", nom: "RH – Migration GED documentaire")
        let asp = projet(c, code: "P25_087", nom: "ASP – Installation nouvelle GED")
        reunion(c, titre: "Sans rattachement GED", projet: nil)
        reunion(c, titre: "COPIL GED", projet: rh)
        reunion(c, titre: "Atelier GED", projet: asp)
        reunion(c, titre: "Revue GED", projet: asp)

        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let groupes = ReportSearch.groupes(in: reunions, query: "ged")
        #expect(groupes.map(\.projet) == ["ASP – Installation nouvelle GED",
                                          "RH – Migration GED documentaire",
                                          ReportSearch.sansProjet])
        #expect(groupes[0].resultats.count == 2)
        #expect(groupes[2].resultats.map(\.titre) == ["Sans rattachement GED"])
        #expect(ReportSearch.sansProjet == "Sans projet")
    }

    @Test("le nombre de réunions trouvées est celui du sous-titre")
    func comptes() throws {
        let c = try contexteEnMemoire()
        let asp = projet(c, code: "P25_087", nom: "ASP – GED")
        reunion(c, titre: "COPIL GED", projet: asp)
        reunion(c, titre: "Atelier GED", projet: asp)
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let groupes = ReportSearch.groupes(in: reunions, query: "ged")
        #expect(ReportSearch.nombreDeReunions(groupes) == 2)
    }

    // MARK: - Extrait

    @Test("l'extrait tient ±60 caractères autour de la première occurrence")
    func extraitBorne() {
        let avant = String(repeating: "a", count: 200)
        let apres = String(repeating: "b", count: 200)
        let extrait = ReportSearch.extrait(avant + "GED" + apres, terme: "ged")
        #expect(extrait.hasPrefix("…"))
        #expect(extrait.hasSuffix("…"))
        #expect(extrait.contains("GED"))
        // 60 + 3 + 60 caractères, plus les deux ellipses.
        #expect(extrait.count == ReportSearch.rayon * 2 + 3 + 2)
    }

    @Test("un texte court est rendu entier, sans ellipse")
    func extraitCourt() {
        #expect(ReportSearch.extrait("la GED est livrée", terme: "ged")
                == "la GED est livrée")
    }

    @Test("l'extrait aplatit les retours à la ligne et les espaces multiples")
    func extraitAplati() {
        let texte = "décision  :\n\n  retenir\tla GED\n de l'éditeur"
        #expect(ReportSearch.extrait(texte, terme: "ged")
                == "décision : retenir la GED de l'éditeur")
    }

    @Test("un terme introuvable rend le début du texte, jamais rien")
    func extraitSansOccurrence() {
        // Le cas ne se produit pas par le chemin normal (le résultat n'existe
        // que si le terme est trouvé), mais un extrait vide serait une ligne
        // muette dans la liste.
        let extrait = ReportSearch.extrait("un texte quelconque", terme: "zzz")
        #expect(extrait == "un texte quelconque")
    }

    @Test("l'extrait du résultat contient le terme, donc se surligne")
    func extraitDuResultat() throws {
        let c = try contexteEnMemoire()
        reunion(c, titre: "COPIL",
                notes: String(repeating: "x ", count: 80) + "la GED est livrée")
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        let extrait = try #require(ReportSearch.resultats(in: reunions, query: "ged").first?.extrait)
        #expect(!ProjectSearch.highlightRanges(in: extrait, query: "ged").isEmpty)
    }

    // MARK: - Libellés

    @Test("l'en-tête et le sous-titre sont ceux de la spec, au mot près")
    func libelles() {
        #expect(ReportSearch.titre == "Recherche dans les CR")
        #expect(ReportSearch.sousTitre(reunions: 3, terme: "ged")
                == "3 réunions · « ged »")
        #expect(ReportSearch.sousTitre(reunions: 1, terme: "ged")
                == "1 réunion · « ged »")
        #expect(ReportSearch.sousTitre(reunions: 0, terme: "ged")
                == "0 réunion · « ged »")
        #expect(ReportSearch.sousTitre(reunions: 2, terme: "  ged  ")
                == "2 réunions · « ged »")
    }

    // MARK: - Sur le semis

    @Test("« ged » trouve les comptes rendus du semis de démonstration")
    func surLeSemis() throws {
        let c = try contexteEnMemoire()
        RefonteDemoSeed.seedPortfolio(in: c)
        let reunions = try c.fetch(FetchDescriptor<Meeting>())
        // Le semis ne promet pas de CR contenant « ged » : le test vérifie que
        // la recherche s'exécute sur les quatre-vingts réunions du store sans
        // lever et sans rendre de résultat sur une note.
        let trouves = ReportSearch.resultats(in: reunions, query: "ged")
        let notes = Set(reunions.filter { $0.kind == .note }.map(\.persistentModelID))
        #expect(trouves.allSatisfy { !notes.contains($0.meetingID) })
    }
}
