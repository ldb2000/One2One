import Testing
import Foundation
@testable import OneToOne

/// Le garde-fou des messages d'erreur des services de la refonte, par lecture
/// des sources.
///
/// Motif, daté du 2026-09-08 : sur une réunion 1:1 dont l'audio venait d'un
/// `.mp4` importé, « Transcrire + Rapport » a affiché **« The operation could
/// not be completed »**. Ce libellé est celui que `localizedDescription`
/// fabrique pour une erreur sans description : un `enum … : Error` qui n'est
/// pas `LocalizedError`, ou un `NSError(domain:code:)` sans
/// `NSLocalizedDescriptionKey`. L'alerte affiche `error.localizedDescription`
/// telle quelle ; une erreur sans texte est donc une erreur illisible, et rien
/// dans l'état d'un modèle ne le signale — d'où ce test de lecture, sur le
/// modèle de `RefonteTypographieTests` et de `AppShortcutsTests`.
///
/// Périmètre : les dossiers de services que la refonte a créés. Les erreurs
/// hors périmètre restent de la responsabilité de leur propre suite.
@Suite("Erreurs lisibles des services de la refonte")
struct RefonteErreursLisiblesTests {

    /// Racine du dépôt, déduite de `#filePath` (`<racine>/Tests/<fichier>`).
    private var racine: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Les dossiers de services nés de la refonte.
    private static let perimetres = [
        "OneToOne/Services/Meeting",
        "OneToOne/Services/Live",
        "OneToOne/Services/Capture",
        "OneToOne/Services/OneOnOne",
        "OneToOne/Services/Workshop",
        "OneToOne/Services/Report",
    ]

    private func sources() throws -> [(nom: String, lignes: [String])] {
        var resultat: [(nom: String, lignes: [String])] = []
        for perimetre in Self.perimetres {
            let url = racine.appendingPathComponent(perimetre)
            var estDossier: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier),
                  estDossier.boolValue else { continue }
            let enumerateur = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let fichier = enumerateur?.nextObject() as? URL {
                guard fichier.pathExtension == "swift" else { continue }
                let texte = try String(contentsOf: fichier, encoding: .utf8)
                resultat.append((fichier.lastPathComponent, texte.components(separatedBy: "\n")))
            }
        }
        return resultat
    }

    /// Le périmètre existe : sans cette garde, le test passerait en trouvant
    /// zéro fichier si un dossier était renommé.
    @Test("Le périmètre de lecture n'est pas vide")
    func perimetreNonVide() throws {
        let fichiers = try sources()
        #expect(fichiers.count >= 10,
                "Périmètre suspect : \(fichiers.count) fichier(s) lu(s) — un dossier a-t-il été renommé ?")
    }

    /// Un type d'erreur déclaré dans ces dossiers doit porter `LocalizedError`.
    @Test("Tout type d'erreur de la refonte est LocalizedError")
    func typesErreurLocalises() throws {
        // `enum X: Error`, `struct X: Error, Equatable`, `enum Failure: Error…`
        let declaration = try Regex(
            #"^\s*(?:public |internal |private |fileprivate )?(?:final )?(?:enum|struct)\s+(\w+)\s*:\s*([^{]*\bError\b[^{]*)\{"#
        )
        var fautes: [String] = []
        for (nom, lignes) in try sources() {
            for (index, ligne) in lignes.enumerated() {
                guard let capture = try declaration.firstMatch(in: ligne) else { continue }
                let conformances = String(capture[2].substring ?? "")
                guard !conformances.contains("LocalizedError") else { continue }
                let type = String(capture[1].substring ?? "")
                fautes.append("\(nom):\(index + 1) — \(type) : \(conformances.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(fautes.isEmpty, """
        Types d'erreur sans `LocalizedError` : leur `localizedDescription` sort en
        « The operation could not be completed. (Module.Type error N.) », affiché tel
        quel dans l'alerte. Ajoutez `LocalizedError` et un `errorDescription` en français.
        \(fautes.joined(separator: "\n"))
        """)
    }

    /// Un `NSError` construit dans ces dossiers doit porter un `userInfo`.
    ///
    /// `NSError(domain: "X", code: 2)` — sans troisième argument — produit le
    /// même message opaque qu'un enum non localisé (c'est le cas qu'a montré
    /// `PyannoteDiarizer` le 2026-09-08).
    @Test("Tout NSError de la refonte porte une description")
    func nsErrorAvecDescription() throws {
        let nu = try Regex(#"NSError\(domain:\s*"[^"]*",\s*code:\s*[^,)]+\)"#)
        var fautes: [String] = []
        for (nom, lignes) in try sources() {
            for (index, ligne) in lignes.enumerated() where try nu.firstMatch(in: ligne) != nil {
                fautes.append("\(nom):\(index + 1) — \(ligne.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(fautes.isEmpty, """
        `NSError` sans `userInfo` : ajoutez `[NSLocalizedDescriptionKey: "…"]` en français.
        \(fautes.joined(separator: "\n"))
        """)
    }

    /// Les erreurs du chemin audio, celui du défaut : elles sont hors des six
    /// dossiers ci-dessus mais ce sont elles que l'alerte a affichées.
    @Test("Les erreurs du chemin audio sont rédigées en français")
    func cheminAudioLocalise() throws {
        for fichier in ["OneToOne/Services/AudioImportService.swift",
                        "OneToOne/Services/PyannoteDiarizer.swift"] {
            let url = racine.appendingPathComponent(fichier)
            let texte = try String(contentsOf: url, encoding: .utf8)
            let nu = try Regex(#"NSError\(domain:\s*"[^"]*",\s*code:\s*[^,)]+\)"#)
            let lignes = texte.components(separatedBy: "\n")
            var fautes: [String] = []
            for (index, ligne) in lignes.enumerated() where try nu.firstMatch(in: ligne) != nil {
                fautes.append("\(fichier):\(index + 1)")
            }
            #expect(fautes.isEmpty, "NSError sans description : \(fautes.joined(separator: ", "))")
        }
    }
}
