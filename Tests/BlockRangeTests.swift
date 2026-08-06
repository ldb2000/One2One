import XCTest
import AppKit
@testable import OneToOne

/// Couvre `BlockRange.of(in:at:)` : le cas simple (une ligne, quel que soit
/// le `BlockType`/`ListInfo`) et les trois cas qui dépassent la ligne — bloc
/// de code, tableau, bloc brut — où une sonde à n'importe quelle position
/// interne doit renvoyer le bloc entier, pas seulement la ligne physique.
final class BlockRangeTests: XCTestCase {

    // MARK: - Cas simples (une ligne)

    func test_paragraph_isTheWholeLine() {
        let s = storage("Bonjour le monde")
        let block = BlockRange.of(in: s, at: 3)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
        XCTAssertEqual(s.attribute(.mdBlockType, at: block.range.location, effectiveRange: nil) as? BlockType, .paragraph)
    }

    func test_heading_isTheWholeLine() {
        let s = storage("## Titre")
        let block = BlockRange.of(in: s, at: 0)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
        XCTAssertEqual(s.attribute(.mdBlockType, at: block.range.location, effectiveRange: nil) as? BlockType, .h2)
        XCTAssertEqual(s.attributedSubstring(from: block.range).string, "Titre", "pas de marqueur littéral dans le storage")
    }

    func test_blockquote_isTheWholeLine() {
        let s = storage("> Une citation")
        let block = BlockRange.of(in: s, at: 5)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
        XCTAssertEqual(s.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .blockquote)
    }

    func test_listItem_isTheWholeLine() {
        let s = storage("- une puce")
        let block = BlockRange.of(in: s, at: 0)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
        XCTAssertNotNil(s.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo)
    }

    /// Deux paragraphes : ne renvoie que celui qui contient `location`, pas
    /// les deux collés. Ligne vide dans la source (comme `MarkdownBlockCommandsTests.
    /// test_operatesOnlyOnCaretLine`) : un simple `\n` serait un *soft break*
    /// (fusionné en un seul paragraphe avec un espace), pas deux blocs.
    func test_paragraph_doesNotAbsorbTheNeighbouringOne() {
        let s = storage("Première\n\nDeuxième")
        let ns = s.string as NSString
        let secondStart = ns.range(of: "Deuxième").location

        let first = BlockRange.of(in: s, at: 0)
        let second = BlockRange.of(in: s, at: secondStart)

        XCTAssertEqual(first.range, NSRange(location: 0, length: ns.range(of: "Première").length))
        XCTAssertEqual(second.range, NSRange(location: secondStart, length: "Deuxième".utf16.count))
    }

    // MARK: - Bloc de code (run unique, potentiellement multi-ligne)

    /// Sonder n'importe quelle ligne interne (première, milieu, dernière)
    /// doit renvoyer exactement le même bloc — pas seulement la ligne sondée.
    func test_codeBlock_wholeRunRegardlessOfProbedLine() {
        let s = storage("```swift\nune\ndeux\ntrois\n```")
        let ns = s.string as NSString
        let start = ns.range(of: "une").location
        let troisRange = ns.range(of: "trois")
        let expected = NSRange(location: start, length: troisRange.location + troisRange.length - start)

        for probe in ["une", "deux", "trois"] {
            let loc = ns.range(of: probe).location
            let block = BlockRange.of(in: s, at: loc)
            XCTAssertEqual(block.range, expected, "sonde sur « \(probe) »")
        }
    }

    func test_codeBlock_contentAndAttributeMatchExactly() {
        let s = storage("```swift\nune\ndeux\ntrois\n```")
        let ns = s.string as NSString
        let block = BlockRange.of(in: s, at: ns.range(of: "deux").location)

        XCTAssertEqual(s.attributedSubstring(from: block.range).string, "une\ndeux\ntrois")
        XCTAssertEqual(s.attribute(.mdBlockType, at: block.range.location, effectiveRange: nil) as? BlockType, .codeBlock)
    }

    /// Artefact d'édition en direct (documenté par `MarkdownSerializer.
    /// fencedCodeBlock`) : un Retour tapé en toute fin de bloc hérite
    /// `.mdBlockType == .codeBlock` par `typingAttributes`, étendant le run
    /// jusqu'à inclure son propre `\n`. `BlockRange` doit le retirer, comme
    /// `MarkdownSerializer.trimmingTrailingNewlines`.
    func test_codeBlock_trimsATrailingNewlineAbsorbedIntoTheRun() {
        let s = NSTextStorage(string: "code\n")
        s.addAttribute(.mdBlockType, value: BlockType.codeBlock, range: NSRange(location: 0, length: 5))

        let block = BlockRange.of(in: s, at: 0)

        XCTAssertEqual(block.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(s.attributedSubstring(from: block.range).string, "code")
    }

    // MARK: - Bloc brut (HTML, run unique multi-ligne)

    func test_rawBlock_wholeRunRegardlessOfProbedLine() {
        let s = storage("<div>\nbloc\nsur trois\nlignes\n</div>")
        let ns = s.string as NSString
        let expected = NSRange(location: 0, length: s.length)

        for probe in ["<div>", "bloc", "sur trois", "lignes", "</div>"] {
            let loc = ns.range(of: probe).location
            let block = BlockRange.of(in: s, at: loc)
            XCTAssertEqual(block.range, expected, "sonde sur « \(probe) »")
            XCTAssertEqual(s.attribute(.mdBlockType, at: block.range.location, effectiveRange: nil) as? BlockType,
                           .rawBlock, "sonde sur « \(probe) »")
        }
    }

    func test_rawBlock_trimsATrailingNewlineAbsorbedIntoTheRun() {
        let s = NSTextStorage(string: "<div>\n")
        s.addAttribute(.mdBlockType, value: BlockType.rawBlock, range: NSRange(location: 0, length: 6))

        let block = BlockRange.of(in: s, at: 0)

        XCTAssertEqual(block.range, NSRange(location: 0, length: 5))
    }

    // MARK: - Tableau (paragraphes-cellules regroupés par `tableID`)

    /// Sonder n'importe quelle cellule (en-tête ou corps, n'importe quelle
    /// colonne) doit renvoyer le tableau entier.
    func test_table_wholeTableRegardlessOfProbedCell() {
        let s = storage("| A | B |\n|---|---|\n| 1 | 2 |")
        let ns = s.string as NSString

        for probe in ["A", "B", "1", "2"] {
            let loc = ns.range(of: probe).location
            let block = BlockRange.of(in: s, at: loc)
            XCTAssertEqual(s.attributedSubstring(from: block.range).string, "A\nB\n1\n2", "sonde sur « \(probe) »")
        }
    }

    func test_table_startsAtFirstCellEndsAtLastCellContent() {
        let s = storage("| A | B |\n|---|---|\n| 1 | 2 |")
        let ns = s.string as NSString
        let block = BlockRange.of(in: s, at: ns.range(of: "B").location)

        let aStart = ns.range(of: "A").location
        let twoRange = ns.range(of: "2")
        XCTAssertEqual(block.range.location, aStart)
        XCTAssertEqual(block.range.location + block.range.length, twoRange.location + twoRange.length)
    }

    /// Un paragraphe qui suit le tableau ne doit pas être avalé dans la
    /// plage — vérifie l'arrêt du balayage avant.
    func test_table_doesNotAbsorbTheFollowingParagraph() {
        let s = storage("| A | B |\n|---|---|\n| 1 | 2 |\n\nAprès")
        let ns = s.string as NSString

        let table = BlockRange.of(in: s, at: ns.range(of: "1").location)
        XCTAssertEqual(s.attributedSubstring(from: table.range).string, "A\nB\n1\n2")

        let after = BlockRange.of(in: s, at: ns.range(of: "Après").location)
        XCTAssertEqual(s.attributedSubstring(from: after.range).string, "Après")
        XCTAssertEqual(s.attribute(.mdBlockType, at: after.range.location, effectiveRange: nil) as? BlockType, .paragraph)
    }

    /// Un paragraphe qui précède le tableau ne doit pas être avalé — vérifie
    /// l'arrêt du balayage arrière.
    func test_table_doesNotAbsorbThePrecedingParagraph() {
        let s = storage("Avant\n| A | B |\n|---|---|\n| 1 | 2 |")
        let ns = s.string as NSString

        let table = BlockRange.of(in: s, at: ns.range(of: "B").location)
        XCTAssertEqual(s.attributedSubstring(from: table.range).string, "A\nB\n1\n2")
    }

    /// Une cellule vide (`TableCellInfo` posé seulement sur son `\n`
    /// terminal, cf. sa doc) doit rester incluse dans le tableau — construite
    /// à la main : `MarkdownParser` ne produit pas facilement une cellule
    /// vide au milieu d'une rangée non vide depuis une source markdown.
    func test_table_includesAnEmptyCell() {
        let s = NSTextStorage()
        let tableID = UUID()
        func cell(_ text: String, row: Int, column: Int) -> NSAttributedString {
            let info = TableCellInfo(tableID: tableID, row: row, column: column, columnCount: 2, alignment: nil)
            return NSAttributedString(string: text + "\n", attributes: [.mdTableCell: info])
        }
        s.append(cell("A", row: 0, column: 0))
        s.append(cell("", row: 0, column: 1))
        s.append(cell("1", row: 1, column: 0))
        s.append(cell("2", row: 1, column: 1))

        let fromFirstCell = BlockRange.of(in: s, at: 0)
        XCTAssertEqual(s.attributedSubstring(from: fromFirstCell.range).string, "A\n\n1\n2")

        // Sonde directement sur la cellule vide (juste après "A\n", à l'index 2).
        let fromEmptyCell = BlockRange.of(in: s, at: 2)
        XCTAssertEqual(fromEmptyCell.range, fromFirstCell.range)
    }

    // MARK: - Bords / robustesse

    func test_emptyStorage_doesNotCrash_returnsZeroLengthRange() {
        let s = NSTextStorage(attributedString: MarkdownParser.parse(""))
        let block = BlockRange.of(in: s, at: 0)
        XCTAssertEqual(block.range, NSRange(location: 0, length: 0))
    }

    func test_locationBeyondEnd_isClampedToTheLastBlock() {
        let s = storage("Bonjour")
        let block = BlockRange.of(in: s, at: 1_000)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
    }

    func test_negativeLocation_isClampedToTheFirstBlock() {
        let s = storage("Bonjour")
        let block = BlockRange.of(in: s, at: -5)
        XCTAssertEqual(block.range, NSRange(location: 0, length: s.length))
    }

    // MARK: - Fixtures

    private func storage(_ markdown: String) -> NSTextStorage {
        NSTextStorage(attributedString: MarkdownParser.parse(markdown))
    }
}
