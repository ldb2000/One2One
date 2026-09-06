import Testing
@testable import OneToOne

/// Couvre le parsing des tableaux GFM ajouté à `MarkdownText` (headers, rows, alignements),
/// via les accesseurs réservés aux tests (`blockKindsForTesting`/`parsedTablesForTesting`) —
/// pas de dépendance au rendu SwiftUI.
@Suite("MarkdownText — tableaux GFM")
struct MarkdownTextTableTests {

    @Test("Tableau 3 colonnes, headers + 2 rows")
    func simpleTableParsesHeadersAndRows() {
        let markdown = """
        | Projet | Statut | Charge |
        |---|---|---|
        | Alpha | En cours | 12j |
        | Beta | Terminé | 5j |
        """
        let view = MarkdownText(markdown: markdown)
        let tables = view.parsedTablesForTesting()

        #expect(tables.count == 1)
        #expect(tables[0].headers == ["Projet", "Statut", "Charge"])
        #expect(tables[0].rows == [
            ["Alpha", "En cours", "12j"],
            ["Beta", "Terminé", "5j"]
        ])
    }

    @Test("Alignements :---, :---: et ---: correctement détectés")
    func alignmentsAreDetectedFromSeparatorLine() {
        let markdown = """
        | Gauche | Centre | Droite |
        |:---|:---:|---:|
        | a | b | c |
        """
        let view = MarkdownText(markdown: markdown)
        let tables = view.parsedTablesForTesting()

        #expect(tables.count == 1)
        #expect(tables[0].alignments == ["left", "center", "right"])
    }

    @Test("Alignement par défaut (aucun `:`) est gauche")
    func alignmentDefaultsToLeftWithoutColons() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let view = MarkdownText(markdown: markdown)
        let tables = view.parsedTablesForTesting()

        #expect(tables[0].alignments == ["left", "left"])
    }

    @Test("Un paragraphe avant et après un tableau ne casse pas le parsing")
    func adjacentParagraphsSurviveTableParsing() {
        let markdown = """
        Avant le tableau.

        | A | B |
        |---|---|
        | 1 | 2 |

        Après le tableau.
        """
        let view = MarkdownText(markdown: markdown)
        let kinds = view.blockKindsForTesting()

        #expect(kinds.contains("paragraph"))
        #expect(kinds.contains("table"))
        // Ordre : paragraphe, spacer, table, spacer, paragraphe.
        #expect(kinds.firstIndex(of: "paragraph") == 0)
        #expect(kinds.firstIndex(of: "table")! > kinds.firstIndex(of: "paragraph")!)
        #expect(kinds.lastIndex(of: "paragraph")! > kinds.firstIndex(of: "table")!)

        let tables = view.parsedTablesForTesting()
        #expect(tables.count == 1)
        #expect(tables[0].headers == ["A", "B"])
        #expect(tables[0].rows == [["1", "2"]])
    }

    @Test("Un texte sans ligne de séparateurs reste un paragraphe (pas de faux positif)")
    func pipesWithoutSeparatorLineStayParagraph() {
        let markdown = "| Ceci n'est pas | un tableau |"
        let view = MarkdownText(markdown: markdown)
        let kinds = view.blockKindsForTesting()

        #expect(kinds == ["paragraph"])
    }

    @Test("Tableau sans pipes de bordure (headers et séparateurs sans | en tête/fin)")
    func tableWithoutOuterPipesParses() {
        let markdown = """
        A | B
        --- | ---
        1 | 2
        """
        let view = MarkdownText(markdown: markdown)
        let tables = view.parsedTablesForTesting()

        #expect(tables.count == 1)
        #expect(tables[0].headers == ["A", "B"])
        #expect(tables[0].rows == [["1", "2"]])
    }
}
