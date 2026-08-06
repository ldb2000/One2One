import XCTest
import AppKit
@testable import OneToOne

/// Couvre la reconnaissance mermaid de `StyleRenderer.applyMermaidAttachment`
/// — posée pour `.mdBlockType == .codeBlock` avec `.mdCodeLanguage ==
/// "mermaid"`, jamais pour un autre langage ni pour un bloc ordinaire.
///
/// Le rendu web réel (`MermaidRenderer`, `WKWebView`) n'est volontairement
/// **pas** attendu ici — pas pilotable en test headless (chargement
/// asynchrone d'une page web hors écran). `MermaidAttachmentFactory.
/// attachment(for:isDark:onUpdate:)` renvoie toujours un placeholder de façon
/// synchrone (voir `MermaidAttachmentFactoryTests`), et c'est cette partie
/// synchrone — l'attribution de l'attachment et la réservation de hauteur —
/// que ces tests vérifient. Chaque test qui touche un bloc mermaid déclenche
/// donc, en tâche de fond, un vrai `WKWebView` (via `applyMermaidAttachment`) ;
/// il n'est ni attendu ni observé, mais explique pourquoi cette suite reste
/// volontairement courte.
final class StyleRendererMermaidTests: XCTestCase {

    override func tearDown() {
        MainActor.assumeIsolated {
            MermaidAttachmentFactory.invalidateLiveCache()
        }
        super.tearDown()
    }

    func test_mermaidCodeBlock_getsMermaidAttachmentAttribute() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        var found = false
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value is NSTextAttachment { found = true }
        }
        XCTAssertTrue(found, "un bloc ```mermaid``` doit recevoir .mdMermaidAttachment")
    }

    func test_nonMermaidCodeBlock_getsNoMermaidAttachmentAttribute() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```swift\nprint(1)\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        var found = false
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        XCTAssertFalse(found, "un bloc de code non-mermaid ne doit jamais recevoir .mdMermaidAttachment")
    }

    func test_unlabelledCodeBlock_getsNoMermaidAttachmentAttribute() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```\nsans langage\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        var found = false
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        XCTAssertFalse(found)
    }

    func test_plainParagraph_getsNoMermaidAttachmentAttribute() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("hello world"))
        StyleRenderer.applyVisualStyle(to: storage)

        var found = false
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        XCTAssertFalse(found)
    }

    /// Réserve une hauteur de ligne minimale (`MermaidBlockLayout`) — sans
    /// ça, `MarkdownLayoutManager.drawMermaidDiagrams` n'aurait aucune place
    /// pour inscrire le diagramme une fois rendu.
    func test_mermaidCodeBlock_getsPositiveMinimumLineHeight() throws {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertGreaterThan(style.minimumLineHeight, 0)
    }

    /// Deux blocs mermaid de sources différentes ne doivent pas partager le
    /// même attachment — sinon le diagramme de l'un s'afficherait (une fois
    /// rendu) à la place de l'autre.
    func test_twoDifferentMermaidBlocks_getDistinctAttachments() throws {
        let markdown = "```mermaid\ngraph TD\nA-->B\n```\ntexte\n```mermaid\ngraph TD\nC-->D\n```"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        var attachments: [NSTextAttachment] = []
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment, range.length > 0 { attachments.append(attachment) }
        }
        XCTAssertEqual(attachments.count, 2, "prémisse : deux runs distincts")
        XCTAssertFalse(attachments[0] === attachments[1], "deux sources différentes ne doivent pas partager le même attachment")
    }
}
