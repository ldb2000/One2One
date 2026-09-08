import Foundation
import Testing
@testable import OneToOne

/// La documentation développeur est fausse de façon bruyante, comme le code :
/// tout chemin, symbole, modèle ou ADR cité dans `/docs` doit exister.
@Suite("Documentation — ce qui est écrit dans /docs existe dans le code")
struct DocumentationTests {

    // MARK: - Racine et manifeste

    private var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Sous-ensemble du manifeste : `- chemin:` sous `documents:`, `- …` sous `code_documente:`,
    /// `- "…"` sous `sections:`. Pas de bibliothèque YAML (aucune dépendance nouvelle).
    struct DocumentationManifest {
        var documents: [String] = []
        var codeDocumente: [String] = []
        var sections: [String] = []

        init(texte: String) {
            var bloc = ""
            for brute in texte.split(separator: "\n", omittingEmptySubsequences: false) {
                let ligne = String(brute)
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                if nette.hasPrefix("#") || nette.isEmpty { continue }
                if !ligne.hasPrefix(" "), nette.hasSuffix(":") { bloc = String(nette.dropLast()); continue }
                if nette.hasPrefix("sections:") { bloc = "sections"; continue }
                if nette.hasPrefix("- chemin:") {
                    documents.append(nette.replacingOccurrences(of: "- chemin:", with: "").trimmingCharacters(in: .whitespaces))
                    bloc = "documents"
                } else if bloc == "code_documente", nette.hasPrefix("- ") {
                    codeDocumente.append(String(nette.dropFirst(2)))
                } else if bloc == "sections", nette.hasPrefix("- ") {
                    sections.append(String(nette.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
        }
    }

    private func manifeste() throws -> DocumentationManifest {
        let url = racine.appendingPathComponent("docs/documentation.yml")
        return DocumentationManifest(texte: try String(contentsOf: url, encoding: .utf8))
    }

    private func texte(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    /// Le contenu des accents graves, hors blocs de code ``` … ```.
    private func citations(dans texte: String) -> [String] {
        var horsCode = ""
        var dansBloc = false
        for ligne in texte.split(separator: "\n", omittingEmptySubsequences: false) {
            if ligne.hasPrefix("```") { dansBloc.toggle(); continue }
            if !dansBloc { horsCode += ligne + "\n" }
        }
        let motif = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
        let ns = horsCode as NSString
        return motif.matches(in: horsCode, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private func existe(_ relatif: String) -> Bool {
        FileManager.default.fileExists(atPath: racine.appendingPathComponent(relatif).path)
    }

    // MARK: - Tests

    @Test("Tout chemin cité dans un document tenu existe")
    func cheminsCitesExistent() throws {
        let m = try manifeste()
        var manquants: [String] = []
        for doc in m.documents where existe(doc) {
            for c in citations(dans: try texte(doc)) {
                guard c.hasPrefix("OneToOne/") || c.hasPrefix("Scripts/") || c.hasPrefix("Tests/") || c.hasPrefix("docs/") else { continue }
                if c.contains("*") || c.contains("<") || c.contains("…") { continue }
                let chemin = c.split(separator: ":").first.map(String.init) ?? c   // `Fichier.swift:123`
                if !existe(chemin) { manquants.append("\(doc) → \(c)") }
            }
        }
        #expect(manquants.isEmpty, "Chemins inexistants cités : \(manquants)")
    }

    @Test("Tout symbole cité dans architecture.md est déclaré dans les sources")
    func symbolesCitesExistent() throws {
        let declares = try typesDeclares()
        let motif = try NSRegularExpression(pattern: "^[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*$")   // exclut les sigles (MLX, WAV…)
        var inconnus: [String] = []
        for c in citations(dans: try texte("docs/architecture.md")) {
            let ns = c as NSString
            guard motif.firstMatch(in: c, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
            if !declares.contains(c) { inconnus.append(c) }
        }
        #expect(inconnus.isEmpty, "Symboles inconnus : \(Array(Set(inconnus)).sorted())")
    }

    /// Noms de `struct|class|enum|actor|protocol|typealias` déclarés sous OneToOne/ et Tests/.
    private func typesDeclares() throws -> Set<String> {
        let motif = try NSRegularExpression(pattern: "\\b(?:struct|class|enum|actor|protocol|typealias)\\s+([A-Z][A-Za-z0-9]*)")
        var noms = Set<String>()
        for dossier in ["OneToOne", "Tests"] {
            let base = racine.appendingPathComponent(dossier)
            guard let it = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in it where url.pathExtension == "swift" {
                let s = try String(contentsOf: url, encoding: .utf8)
                let ns = s as NSString
                for r in motif.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    noms.insert(ns.substring(with: r.range(at: 1)))
                }
            }
        }
        return noms
    }

    @Test("La liste des modèles documentée égale CurrentSchema.models")
    func modelesDocumentesEgalentLeSchema() throws {
        let doc = try texte("docs/architecture.md")
        // Section « Modèle de données » : du titre de niveau 2 qui la contient au prochain `## `.
        guard let debut = doc.range(of: "Modèle de données") else { Issue.record("Section « Modèle de données » absente"); return }
        let reste = doc[debut.upperBound...]
        let fin = reste.range(of: "\n## ")?.lowerBound ?? reste.endIndex
        let section = String(reste[..<fin])
        let documentes = Set(citations(dans: section).filter { $0.range(of: "^[A-Z][A-Za-z0-9]+$", options: .regularExpression) != nil })
        let schema = Set(CurrentSchema.models.map { String(describing: $0) })
        #expect(schema.subtracting(documentes).isEmpty, "Modèles du schéma absents de la doc : \(schema.subtracting(documentes).sorted())")
        #expect(documentes.intersection(schema) == schema)
    }

    @Test("Tout ADR référencé existe et tout ADR figure dans decisions.md")
    func adrReferencesExistent() throws {
        let m = try manifeste()
        let motif = try NSRegularExpression(pattern: "docs/adr/(\\d{4}-\\d{2}-\\d{2}-[a-z0-9-]+\\.md)")
        for doc in m.documents where existe(doc) {
            let s = try texte(doc); let ns = s as NSString
            for r in motif.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let f = ns.substring(with: r.range(at: 0))
                #expect(existe(f), "\(doc) cite \(f), absent")
            }
        }
        let registre = try texte("docs/decisions.md")
        let adrs = try FileManager.default.contentsOfDirectory(atPath: racine.appendingPathComponent("docs/adr").path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
        for f in adrs { #expect(registre.contains(f), "decisions.md ne mentionne pas \(f)") }
    }

    @Test("docs/README.md référence chaque document de /docs hors archives")
    func indexComplet() throws {
        let index = try texte("docs/README.md")
        let fm = FileManager.default
        var attendus = try fm.contentsOfDirectory(atPath: racine.appendingPathComponent("docs").path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
        attendus.append("adr/README.md")
        for f in attendus { #expect(index.contains(f), "README.md n'indexe pas \(f)") }
    }

    @Test("Les documents tenus n'emploient que des dates absolues")
    func datesAbsolues() throws {
        let m = try manifeste()
        let interdits = ["hier", "la semaine dernière", "récemment", "ce matin", "demain matin", "il y a quelques jours"]
        for doc in m.documents where existe(doc) {
            let s = try texte(doc).lowercased()
            for mot in interdits { #expect(!s.contains(mot), "\(doc) contient « \(mot) »") }
        }
    }

    @Test("Les sections stables du manifeste sont présentes dans architecture.md")
    func sectionsStablesPresentes() throws {
        let m = try manifeste()
        let doc = try texte("docs/architecture.md")
        for s in m.sections { #expect(doc.contains("## \(s)"), "Section « \(s) » absente") }
    }
}
