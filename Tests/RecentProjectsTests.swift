import Testing
import Foundation
@testable import OneToOne

/// Les projets récents (décision **D4**) : une chaîne d'UUID séparés par des
/// virgules dans `@AppStorage`, cinq au plus, le dernier ouvert en tête.
///
/// `@AppStorage` ne sait pas stocker un `[UUID]` (constat §2.20 de la spec) ;
/// le format est donc une chaîne, et toute la logique est ici, pure et testée
/// avant la vue qui l'affichera (lot 1).
@Suite("Projets récents — FIFO de cinq, sans doublon")
struct RecentProjectsTests {

    @Test("La clé et la borne sont celles de D4")
    func cleEtBorne() {
        #expect(RecentProjects.key == "projects.recentIDs")
        #expect(RecentProjects.max == 5)
    }

    @Test("Pousser dans une chaîne vide donne un seul identifiant")
    func premierPush() {
        let id = UUID()
        let raw = RecentProjects.push(id, into: "")
        #expect(raw == id.uuidString)
        #expect(RecentProjects.ids(from: raw) == [id])
    }

    @Test("Le dernier ouvert passe en tête")
    func dernierEnTete() {
        let a = UUID(), b = UUID()
        var raw = RecentProjects.push(a, into: "")
        raw = RecentProjects.push(b, into: raw)
        #expect(RecentProjects.ids(from: raw) == [b, a])
    }

    @Test("Rouvrir un projet déjà présent le remonte sans le dupliquer")
    func doublonRemonte() {
        let a = UUID(), b = UUID(), c = UUID()
        var raw = ""
        for id in [a, b, c] { raw = RecentProjects.push(id, into: raw) }
        raw = RecentProjects.push(a, into: raw)
        #expect(RecentProjects.ids(from: raw) == [a, c, b])
        #expect(RecentProjects.ids(from: raw).count == 3, "aucun doublon")
    }

    @Test("La liste est bornée à cinq : le sixième chasse le plus ancien")
    func borneACinq() {
        let ids = (0..<7).map { _ in UUID() }
        var raw = ""
        for id in ids { raw = RecentProjects.push(id, into: raw) }
        let lus = RecentProjects.ids(from: raw)
        #expect(lus.count == RecentProjects.max)
        // Les cinq derniers poussés, du plus récent au plus ancien.
        #expect(lus == ids.suffix(5).reversed())
        #expect(!lus.contains(ids[0]))
        #expect(!lus.contains(ids[1]))
    }

    @Test("Une chaîne vide ou blanche ne rend aucun identifiant")
    func chaineVide() {
        #expect(RecentProjects.ids(from: "").isEmpty)
        #expect(RecentProjects.ids(from: "   ").isEmpty)
        #expect(RecentProjects.ids(from: ",,,").isEmpty)
    }

    /// Un réglage écrit à la main, ou par une version antérieure, ne doit pas
    /// faire disparaître les identifiants valides qui l'entourent.
    @Test("Un fragment illisible est ignoré, les identifiants valides restent")
    func fragmentIllisible() {
        let a = UUID(), b = UUID()
        let raw = "\(a.uuidString),pas-un-uuid,\(b.uuidString)"
        #expect(RecentProjects.ids(from: raw) == [a, b])
    }

    /// Le format est lu par `@AppStorage` : les espaces qu'un humain ajoute
    /// après la virgule ne doivent pas invalider la ligne.
    @Test("Les espaces autour des virgules sont tolérés")
    func espacesTolere() {
        let a = UUID(), b = UUID()
        #expect(RecentProjects.ids(from: "\(a.uuidString) , \(b.uuidString)") == [a, b])
    }

    @Test("Pousser normalise une chaîne héritée : bornée, sans doublon, sans vide")
    func pushNormalise() {
        let ids = (0..<6).map { _ in UUID() }
        let heritee = ids.map(\.uuidString).joined(separator: ",") + ",," + ids[0].uuidString
        let neuf = UUID()
        let raw = RecentProjects.push(neuf, into: heritee)
        let lus = RecentProjects.ids(from: raw)
        #expect(lus.first == neuf)
        #expect(lus.count == RecentProjects.max)
        #expect(Set(lus).count == lus.count)
    }
}
