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

    /// Sous-ensemble du manifeste : `- chemin:` sous `documents:`, `genere_par:` de l'item
    /// courant, `- …` sous `code_documente:`, `- "…"` sous `sections:`. Les valeurs sont
    /// débarrassées de leurs guillemets, qu'elles en portent ou non (le manifeste peut être
    /// reformulé). Pas de bibliothèque YAML (aucune dépendance nouvelle).
    struct DocumentationManifest {
        var documents: [String] = []
        /// Documents que le manifeste déclare générés (clé `genere_par:`) : leur contenu vient
        /// d'ailleurs (ici des en-têtes d'ADR) et ne se corrige pas en place.
        var documentsGeneres: [String] = []
        var codeDocumente: [String] = []
        var sections: [String] = []
        var symbolesExternes: [String] = []

        init(texte: String) {
            let guillemets = CharacterSet(charactersIn: "\"")
            func valeur(_ nette: String, apres cle: String) -> String {
                String(nette.dropFirst(cle.count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: guillemets)
            }
            var bloc = ""
            var dernierDocument: String?
            for brute in texte.split(separator: "\n", omittingEmptySubsequences: false) {
                let ligne = String(brute)
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                if nette.hasPrefix("#") || nette.isEmpty { continue }
                if !ligne.hasPrefix(" "), nette.hasSuffix(":") { bloc = String(nette.dropLast()); continue }
                if nette.hasPrefix("sections:") { bloc = "sections"; continue }
                if nette.hasPrefix("- chemin:") {
                    let chemin = valeur(nette, apres: "- chemin:")
                    documents.append(chemin)
                    dernierDocument = chemin
                    bloc = "documents"
                } else if nette.hasPrefix("genere_par:"), let doc = dernierDocument {
                    documentsGeneres.append(doc)
                } else if bloc == "code_documente", nette.hasPrefix("- ") {
                    codeDocumente.append(valeur(nette, apres: "- "))
                } else if bloc == "sections", nette.hasPrefix("- ") {
                    sections.append(valeur(nette, apres: "- "))
                } else if bloc == "symboles_externes", nette.hasPrefix("- ") {
                    symbolesExternes.append(valeur(nette, apres: "- "))
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

    /// Tous les noms de fichiers de l'arbre documenté : permet de résoudre une citation
    /// dénudée de son dossier (`ColorHex.swift`), qui n'est pas une correction acceptable
    /// mais ne doit pas non plus échapper à la vérification.
    private func nomsDeFichiers() -> Set<String> {
        var noms = Set<String>()
        for dossier in ["OneToOne", "Tests", "Scripts", "docs"] {
            let base = racine.appendingPathComponent(dossier)
            guard let it = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in it { noms.insert(url.lastPathComponent) }
        }
        return noms
    }

    /// Le texte hors blocs de code ``` … ``` et hors accents graves (contenu des citations retiré) :
    /// évite qu'un chemin/symbole cité entre accents graves déclenche une fausse détection.
    private func horsCitations(dans texte: String) -> String {
        var horsCode = ""
        var dansBloc = false
        for ligne in texte.split(separator: "\n", omittingEmptySubsequences: false) {
            if ligne.hasPrefix("```") { dansBloc.toggle(); continue }
            if !dansBloc { horsCode += ligne + "\n" }
        }
        return horsCode.replacingOccurrences(of: "`[^`\\n]+`", with: "", options: .regularExpression)
    }

    // MARK: - Tests

    /// Garde du parseur autant que du manifeste : une reformulation qui viderait une liste
    /// rendrait tous les autres tests verts à vide.
    @Test("Le manifeste est bien formé : documents, code documenté et sections non vides")
    func manifesteBienForme() throws {
        let m = try manifeste()
        #expect(!m.documents.isEmpty, "`documents:` vide — manifeste reformulé ou parseur dépassé")
        #expect(!m.codeDocumente.isEmpty, "`code_documente:` vide — manifeste reformulé ou parseur dépassé")
        #expect(!m.sections.isEmpty, "`sections:` vide — manifeste reformulé ou parseur dépassé")
        for d in m.documents {
            #expect(!d.isEmpty, "chemin de document vide")
            #expect(!d.contains("\""), "chemin de document encore guillemeté : \(d)")
            #expect(existe(d), "`documents:` cite \(d), absent du dépôt")
        }
        for c in m.codeDocumente {
            #expect(!c.isEmpty, "entrée `code_documente:` vide")
            #expect(existe(c), "`code_documente:` cite \(c), absent du dépôt")
        }
        for s in m.sections {
            #expect(!s.isEmpty, "titre de section vide")
            #expect(!s.contains("\""), "titre de section encore guillemeté : \(s)")
        }
    }

    @Test("Tout chemin cité dans un document tenu existe")
    func cheminsCitesExistent() throws {
        let m = try manifeste()
        let noms = nomsDeFichiers()
        // Un nom de fichier nu : `ColorHex.swift`, `Package.swift`, `documentation.yml`…
        let motifNomNu = try NSRegularExpression(pattern: "^[\\w.-]+\\.(swift|sh|py|yml|json|md)$")
        var manquants: [String] = []
        for doc in m.documents {
            #expect(existe(doc), "`documents:` cite \(doc), absent du dépôt")
            guard existe(doc) else { continue }
            for c in citations(dans: try texte(doc)) {
                let ns = c as NSString
                let plage = NSRange(location: 0, length: ns.length)
                if motifNomNu.firstMatch(in: c, range: plage) != nil {
                    // Racine du dépôt (`Package.swift`, `run.sh`) ou quelque part dans l'arbre.
                    if !existe(c), !noms.contains(c) { manquants.append("\(doc) → \(c)") }
                    continue
                }
                guard c.hasPrefix("OneToOne/") || c.hasPrefix("Scripts/") || c.hasPrefix("Tests/") || c.hasPrefix("docs/") else { continue }
                if c.contains("*") || c.contains("<") || c.contains("…") { continue }
                let chemin = c.split(separator: ":").first.map(String.init) ?? c   // `Fichier.swift:123`
                if !existe(chemin) { manquants.append("\(doc) → \(c)") }
            }
        }
        #expect(manquants.isEmpty, "Chemins inexistants cités : \(manquants)")
    }

    @Test("Tout symbole cité dans un document tenu à la main est déclaré dans les sources")
    func symbolesCitesExistent() throws {
        let declares = try typesDeclares()
        let m = try manifeste()
        let externes = Set(m.symbolesExternes)
        let generes = Set(m.documentsGeneres)
        let motif = try NSRegularExpression(pattern: "^[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*$")   // exclut les sigles (MLX, WAV…)
        // Préfixes de frameworks système : ces symboles ne sont jamais déclarables dans les sources.
        let motifFramework = try NSRegularExpression(pattern: "^(NS|UI|CG|CF|AV|WK|SC|CT|EK|CN|UN|AX|MLX)[A-Z]")
        var inconnus: [String] = []
        for doc in m.documents {
            #expect(existe(doc), "`documents:` cite \(doc), absent du dépôt")
            guard existe(doc) else { continue }
            // Un document généré reprend des en-têtes d'ADR : un ADR validé peut citer en titre
            // un symbole retiré depuis (`Interview`) et ne se réécrit pas pour un test.
            guard !generes.contains(doc) else { continue }
            for c in citations(dans: try texte(doc)) {
                let ns = c as NSString
                guard motif.firstMatch(in: c, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
                guard motifFramework.firstMatch(in: c, range: NSRange(location: 0, length: ns.length)) == nil else { continue }
                if externes.contains(c) { continue }
                if !declares.contains(c) { inconnus.append("\(doc) → \(c)") }
            }
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
        // La table de l'inventaire seule : du titre `### Inventaire des modèles` au titre suivant.
        // Bornée ainsi, la table ne contient que des modèles — les symboles de schéma et de
        // migration (`SchemaV1`…, `MigrationStage`, `OneToOneMigrationPlan`) vivent hors d'elle.
        guard let debut = doc.range(of: "### Inventaire des modèles") else {
            Issue.record("Titre « ### Inventaire des modèles » absent de docs/architecture.md")
            return
        }
        let reste = doc[debut.upperBound...]
        let fin = reste.range(of: "\n#")?.lowerBound ?? reste.endIndex
        let table = String(reste[..<fin])
        let documentes = Set(citations(dans: table).filter { $0.range(of: "^[A-Z][A-Za-z0-9]+$", options: .regularExpression) != nil })
        let schema = Set(CurrentSchema.models.map { String(describing: $0) })
        // Égalité, dans les deux sens (spec §7.1) — deux attentes pour un message lisible.
        #expect(
            schema.subtracting(documentes).isEmpty,
            "Modèles du schéma absents de l'inventaire : \(schema.subtracting(documentes).sorted())"
        )
        #expect(
            documentes.subtracting(schema).isEmpty,
            "Inventaire : \(documentes.subtracting(schema).sorted()) sans modèle dans CurrentSchema.models"
        )
    }

    @Test("Tout ADR référencé existe et tout ADR figure dans decisions.md")
    func adrReferencesExistent() throws {
        let m = try manifeste()
        let motif = try NSRegularExpression(pattern: "docs/adr/(\\d{4}-\\d{2}-\\d{2}-[a-z0-9-]+\\.md)")
        for doc in m.documents {
            #expect(existe(doc), "`documents:` cite \(doc), absent du dépôt")
            guard existe(doc) else { continue }
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
        // Bornes de mot : `\b` évite qu'« hier » matche à l'intérieur de « fichier ».
        let motif = try NSRegularExpression(
            pattern: "\\b(hier|récemment|la semaine dernière|ce matin|demain matin|il y a quelques jours)\\b",
            options: [.caseInsensitive]
        )
        for doc in m.documents {
            #expect(existe(doc), "`documents:` cite \(doc), absent du dépôt")
            guard existe(doc) else { continue }
            let texteSansCitations = horsCitations(dans: try texte(doc))
            for ligne in texteSansCitations.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(ligne)
                let ns = s as NSString
                guard let r = motif.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
                let mot = ns.substring(with: r.range)
                Issue.record("\(doc) contient « \(mot) » : \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    @Test("Les sections stables du manifeste sont présentes dans architecture.md")
    func sectionsStablesPresentes() throws {
        let m = try manifeste()
        let doc = try texte("docs/architecture.md")
        for s in m.sections { #expect(doc.contains("## \(s)"), "Section « \(s) » absente") }
    }
}
