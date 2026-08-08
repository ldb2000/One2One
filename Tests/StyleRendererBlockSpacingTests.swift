import XCTest
import AppKit
@testable import OneToOne

/// `StyleRenderer.applyBlockSpacing` pose l'écart vertical sur le **dernier**
/// paragraphe de chaque bloc logique. L'écart large s'applique dès qu'un des
/// deux blocs du couple dessine un cadre — sans quoi une carte suivie d'un
/// paragraphe aurait 28 pt en dessous mais 10 pt au-dessus, une asymétrie
/// visible à l'écran.
///
/// Ces tests n'utilisent **que** des blocs de code non-mermaid comme cartes :
/// un bloc ```` ```mermaid ```` déclencherait un vrai `WKWebView` en tâche de
/// fond (voir la doc de tête de `StyleRendererMermaidTests`).
final class StyleRendererBlockSpacingTests: XCTestCase {

    /// Espacement posé sur le dernier paragraphe du bloc contenant `needle`.
    private func spacingAfterBlock(containing needle: String, in markdown: String) throws -> CGFloat {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        let ns = storage.string as NSString
        let location = ns.range(of: needle).location
        XCTAssertNotEqual(location, NSNotFound, "« \(needle) » introuvable dans le storage stylé")
        let block = BlockRange.of(in: storage, at: location).range
        let lastCharacter = max(block.location, NSMaxRange(block) - 1)
        let terminal = ns.lineRange(for: NSRange(location: lastCharacter, length: 0))
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: terminal.location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacing
    }

    func test_textFollowedByText_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }

    func test_textFollowedByACard_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByText_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "```swift\nprint(1)\n```\n\nSuite")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByACard_getsTheWideSpacing() throws {
        let markdown = "```swift\nprint(1)\n```\n\n```swift\nprint(2)\n```"
        let spacing = try spacingAfterBlock(containing: "print(1)", in: markdown)
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    /// Dernier bloc du document : aucun bloc ne suit, seule la nature du bloc
    /// lui-même décide. Garde-fou contre une lecture hors bornes du « bloc
    /// suivant ».
    func test_lastCardOfTheDocument_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "Intro\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_lastTextBlockOfTheDocument_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Second", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }

    /// `MarkdownParser.parse` normalise toujours à un seul `\n` entre deux
    /// blocs — un test qui ne passe que par `parse` ne peut donc jamais
    /// exercer un séparateur plus large et resterait aveugle à un bug là-dessus.
    /// Mais le storage **vivant** n'est jamais renormalisé après coup : un
    /// utilisateur qui tape Retour deux fois à la frontière de deux blocs crée
    /// une vraie ligne vide, donc deux `\n` consécutifs. Ce test simule cette
    /// frappe directement sur le storage — `NSMutableAttributedString.
    /// replaceCharacters(in:with:)` hérite les attributs du caractère qui
    /// précède l'insertion, exactement comme le ferait AppKit avec les
    /// `typingAttributes` — puis relance `applyVisualStyle` pour vérifier que
    /// le second `\n` ne fait pas manquer le bloc-carte qui suit.
    func test_textFollowedByAnExtraBlankLineThenACard_stillGetsTheWideSpacing() throws {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("Premier\n\n```swift\nprint(1)\n```"))
        let firstBlockEnd = NSMaxRange(BlockRange.of(in: storage, at: 0).range)
        storage.replaceCharacters(in: NSRange(location: firstBlockEnd, length: 0), with: "\n")

        StyleRenderer.applyVisualStyle(to: storage)

        let ns = storage.string as NSString
        let location = ns.range(of: "Premier").location
        XCTAssertNotEqual(location, NSNotFound, "prémisse : « Premier » présent dans le storage stylé")
        let block = BlockRange.of(in: storage, at: location).range
        let lastCharacter = max(block.location, NSMaxRange(block) - 1)
        let terminal = ns.lineRange(for: NSRange(location: lastCharacter, length: 0))
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: terminal.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(style.paragraphSpacing, BlockGutterLayout.cardBlockSpacing)
    }

    // MARK: - Restylage **ciblé** : le bloc précédent porte l'écart

    /// L'écart inter-blocs est posé sur le **dernier paragraphe du bloc du
    /// dessus** : c'est donc lui qu'il faut restyler quand une carte apparaît
    /// ou disparaît en dessous. Un restylage ciblé sur la seule plage insérée
    /// ne le touchait pas — le paragraphe au-dessus gardait ses 10 pt jusqu'à
    /// ce qu'autre chose le restyle.
    ///
    /// Ces deux tests passent par le **chemin réel** : mutation du storage,
    /// puis `applyVisualStyle(to:affectedRange:)` sur la plage que le chemin
    /// de production transmet (`EditorTextView.
    /// replaceBlockCharactersRegisteringUndo` pour l'insertion, la plage
    /// supprimée mémorisée par `Coordinator.textView(_:shouldChangeTextIn:
    /// replacementString:)` pour la suppression).
    func test_insertingACardBelowAParagraph_widensTheSpacingOfThatParagraph() throws {
        let storage = makeParagraphFollowedByAnEmptyLine()
        XCTAssertEqual(
            try spacingOfTheFirstParagraph(in: storage), BlockGutterLayout.blockSpacing,
            "prémisse : sans carte en dessous, le paragraphe porte l'écart étroit"
        )

        let inserted = insertCard(in: storage)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: inserted)

        XCTAssertEqual(
            try spacingOfTheFirstParagraph(in: storage), BlockGutterLayout.cardBlockSpacing,
            "le paragraphe au-dessus de la carte garde ses 10 pt : la plage restylée n'inclut pas le bloc précédent"
        )
    }

    func test_removingACardBelowAParagraph_restoresTheNarrowSpacing() throws {
        let storage = makeParagraphFollowedByAnEmptyLine()
        let inserted = insertCard(in: storage)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: inserted)
        XCTAssertEqual(
            try spacingOfTheFirstParagraph(in: storage), BlockGutterLayout.cardBlockSpacing,
            "prémisse : la carte insérée a bien élargi l'écart du paragraphe au-dessus"
        )

        // Suppression de la carte. La plage transmise au restylage est celle
        // que `Coordinator.textView(_:shouldChangeTextIn:replacementString:)`
        // a mémorisée **avant** la mutation — `normalizedRenderRange` la borne
        // ensuite au storage raccourci.
        storage.replaceCharacters(in: inserted, with: "")
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: inserted)

        XCTAssertEqual(
            try spacingOfTheFirstParagraph(in: storage), BlockGutterLayout.blockSpacing,
            "la carte supprimée laisse un écart de 28 pt périmé sur le bloc d'avant"
        )
    }

    /// Un paragraphe, puis un Retour : le storage se termine par un `\n` et le
    /// point d'insertion est au **début** d'une ligne vide. C'est la situation
    /// réelle d'une commande `/` (le menu s'ouvre sur une ligne neuve), et la
    /// seule où la plage restylée d'une insertion ne recouvre pas déjà, par
    /// `lineRange`, la dernière ligne du bloc précédent.
    private func makeParagraphFollowedByAnEmptyLine() -> NSTextStorage {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("Premier"))
        StyleRenderer.applyVisualStyle(to: storage)
        let returnKey = NSRange(location: storage.length, length: 0)
        storage.replaceCharacters(in: returnKey, with: "\n")
        StyleRenderer.applyVisualStyle(
            to: storage, affectedRange: NSRange(location: returnKey.location, length: 1)
        )
        return storage
    }

    /// Insère `\n` + un bloc de code au point d'insertion courant (fin du
    /// storage) et renvoie la plage insérée — celle que le chemin de
    /// production transmet ensuite à `applyVisualStyle(to:affectedRange:)`
    /// (`SlashController.insertCodeBlock`/`insertMermaidDiagram` insèrent
    /// exactement ce motif : `"\n"` + le corps + `"\n"`).
    private func insertCard(in storage: NSTextStorage) -> NSRange {
        let card = NSMutableAttributedString(string: "\n")
        card.append(MarkdownParser.parse("```swift\nprint(1)\n```"))
        let location = storage.length
        storage.replaceCharacters(in: NSRange(location: location, length: 0), with: card)
        return NSRange(location: location, length: card.length)
    }

    private func spacingOfTheFirstParagraph(in storage: NSTextStorage) throws -> CGFloat {
        let ns = storage.string as NSString
        let location = ns.range(of: "Premier").location
        XCTAssertNotEqual(location, NSNotFound, "« Premier » introuvable dans le storage stylé")
        let terminal = ns.lineRange(for: NSRange(location: location, length: 0))
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: terminal.location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacing
    }
}
