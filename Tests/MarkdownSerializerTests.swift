import XCTest
import AppKit
@testable import OneToOne

final class MarkdownSerializerTests: XCTestCase {

    func test_plainParagraph() {
        let s = NSAttributedString(string: "Hello", attributes: [.mdBlockType: BlockType.paragraph])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "Hello")
    }

    func test_heading2() {
        let s = NSAttributedString(string: "Title", attributes: [.mdBlockType: BlockType.h2])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "## Title")
    }

    func test_boldInline() {
        let m = NSMutableAttributedString(string: "hello bold word",
                                          attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdBold, value: true, range: NSRange(location: 6, length: 4))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "hello **bold** word")
    }

    func test_taskListUnchecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: false)
        let s = NSAttributedString(string: "todo",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [ ] todo")
    }

    func test_taskListChecked() {
        let info = ListInfo(kind: .task, level: 0, index: nil, checked: true)
        let s = NSAttributedString(string: "done",
                                   attributes: [.mdListInfo: info])
        XCTAssertEqual(MarkdownSerializer.serialize(s), "- [x] done")
    }

    /// Dans un `NSTextView`, du texte tapé juste après une image hérite des
    /// `typingAttributes` du caractère précédent — donc de `mdImageURL` et
    /// `mdImageAlt` — sans être lui-même une image. Ce layout ne peut pas être
    /// produit par le parser (qui n'attache ces attributs qu'au seul
    /// caractère `U+FFFC`) ; on le construit ici à la main pour vérifier que
    /// le texte qui suit n'est pas avalé par le markup de l'image.
    func test_imageAttributeOnRunDoesNotSwallowTrailingText() {
        let m = NSMutableAttributedString(string: "\u{FFFC}X",
                                           attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdImageURL, value: URL(string: "file:///x.png")!,
                       range: NSRange(location: 0, length: 2))
        m.addAttribute(.mdImageAlt, value: "a",
                       range: NSRange(location: 0, length: 2))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "![a](file:///x.png)X")
    }

    /// `(` est un caractère d'URL valide que `URL.absoluteString` laisse
    /// littéral, y compris déséquilibré — un nom de fichier réel peut en
    /// produire un. Sans l'encodage manuel dans `escapeURL`, ce `(` littéral
    /// casserait la syntaxe `](…)` au reparse.
    func test_imageURLWithUnbalancedParenthesisIsEncoded() {
        let m = NSAttributedString(string: "\u{FFFC}",
                                    attributes: [.mdBlockType: BlockType.paragraph,
                                                 .mdImageURL: URL(string: "file:///Users/x/a(b.png")!,
                                                 .mdImageAlt: "a"])
        XCTAssertEqual(MarkdownSerializer.serialize(m), "![a](file:///Users/x/a%28b.png)")
    }

    /// Un run peut porter à la fois `mdInlineCode` et `mdImageURL` — même
    /// dérive de `typingAttributes` que le test ci-dessus, mais héritée par
    /// du texte tapé à l'intérieur d'un span de code. Le `U+FFFC` doit être
    /// retiré avant émission plutôt que persisté tel quel entre les
    /// backticks.
    func test_inlineCodeAttributeStripsImagePlaceholder() {
        let m = NSMutableAttributedString(string: "a\u{FFFC}b",
                                           attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdInlineCode, value: true, range: NSRange(location: 0, length: 3))
        m.addAttribute(.mdImageURL, value: URL(string: "file:///x.png")!,
                       range: NSRange(location: 0, length: 3))
        m.addAttribute(.mdImageAlt, value: "a", range: NSRange(location: 0, length: 3))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "`ab`")
    }

    /// Deux caractères « object replacement » dans un même run : chacun émet
    /// indépendamment son propre markup d'image, sans fuite de l'un vers
    /// l'autre.
    func test_expandingImagePlaceholders_twoAdjacentImages() {
        let m = NSMutableAttributedString(string: "\u{FFFC}\u{FFFC}",
                                           attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdImageURL, value: URL(string: "file:///x.png")!,
                       range: NSRange(location: 0, length: 2))
        m.addAttribute(.mdImageAlt, value: "a", range: NSRange(location: 0, length: 2))
        XCTAssertEqual(MarkdownSerializer.serialize(m),
                       "![a](file:///x.png)![a](file:///x.png)")
    }

    /// Le caractère « object replacement » au milieu d'un run : le texte
    /// avant et après doit survivre de part et d'autre du markup de l'image.
    func test_expandingImagePlaceholders_placeholderInMiddleOfText() {
        let m = NSMutableAttributedString(string: "A\u{FFFC}B",
                                           attributes: [.mdBlockType: BlockType.paragraph])
        m.addAttribute(.mdImageURL, value: URL(string: "file:///x.png")!,
                       range: NSRange(location: 0, length: 3))
        m.addAttribute(.mdImageAlt, value: "a", range: NSRange(location: 0, length: 3))
        XCTAssertEqual(MarkdownSerializer.serialize(m), "A![a](file:///x.png)B")
    }
}
