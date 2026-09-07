import Testing
import Foundation
@testable import OneToOne

/// Critère d'acceptation n° 3 du chantier 1 : « Assigner responsable +
/// échéance à une action se fait **sans quitter le rail ni ouvrir de
/// modale**. »
///
/// Un critère de cette forme ne se vérifie pas par l'état d'un modèle : une
/// `sheet` ajoutée demain par distraction passerait toutes les autres suites.
/// Ces tests lisent donc les sources du rail et refusent les présentations
/// modales — la même approche que `MeetingEmptyInvite.Catalogue`, dont un test
/// garde l'exhaustivité plutôt que la vigilance.
///
/// `OwnerPickerMenu` (dans `Views/Shared/`) n'est **pas** dans le périmètre :
/// c'est un `Menu`, donc un survol, et sa seule feuille sert à *créer* un
/// collaborateur qui n'existe pas encore — pas à assigner un participant.
@Suite("Le rail n'ouvre aucune modale")
struct ActionsRailNoModalTests {

    /// La racine du paquet, déduite de l'emplacement de ce fichier :
    /// `<racine>/Tests/ActionsRailNoModalTests.swift`.
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var dossierRail: URL {
        racine
            .appendingPathComponent("OneToOne/Views/Meeting/Spaces/Rail", isDirectory: true)
    }

    private func sources() throws -> [(nom: String, texte: String)] {
        let fichiers = try FileManager.default
            .contentsOfDirectory(at: dossierRail, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try fichiers.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test("Le dossier du rail est bien celui qu'on croit lire")
    func railSourcesAreFound() throws {
        let noms = try sources().map(\.nom)
        // Si ce test tombe, c'est le chemin qui a bougé — et alors les deux
        // suivants ne prouveraient plus rien en passant.
        #expect(noms.contains("ActionCard.swift"))
        #expect(noms.contains("ActionComposer.swift"))
        #expect(noms.contains("ActionsRail.swift"))
        #expect(noms.count >= 6)
    }

    @Test("Aucune présentation modale dans les vues du rail")
    func noModalPresentation() throws {
        let interdits = [".sheet(", ".popover(", ".alert(", ".confirmationDialog(",
                         ".fullScreenCover("]
        for source in try sources() {
            for interdit in interdits {
                #expect(!source.texte.contains(interdit),
                        "\(source.nom) présente \(interdit) : l'édition du rail doit rester inline (critère chantier 1 n° 3)")
            }
        }
    }

    @Test("Le composeur ne reprend jamais le focus qu'il vient de donner")
    func composerNeverDropsFocus() throws {
        let composeur = try #require(try sources().first { $0.nom == "ActionComposer.swift" })
        // `⌘⏎` crée et vide le champ « sans perdre le focus » (spec §2.5) :
        // le seul moyen de le perdre serait d'écrire dans le `@FocusState`.
        #expect(composeur.texte.contains("@FocusState"))
        #expect(!composeur.texte.contains("champActif = false"))
        #expect(!composeur.texte.contains("champActif.toggle()"))
    }

    @Test("Les vues du rail ne nomment aucune couleur hors des jetons")
    func noColourOutsideTokens() throws {
        // Règle invariable du programme §7 : « jamais de nouvelle couleur hors
        // `One2OneTokens` ». `Color(hex:` y est privé au fichier, mais
        // `Color.red` et compagnie restent atteignables partout.
        let interdits = ["Color(hex:", "Color.red", "Color.green", "Color.blue",
                         "Color.orange", "Color.gray", "Color(nsColor:"]
        for source in try sources() {
            for interdit in interdits {
                #expect(!source.texte.contains(interdit),
                        "\(source.nom) nomme \(interdit) hors de One2OneToken")
            }
        }
    }
}
