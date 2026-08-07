import XCTest
import AppKit
@testable import OneToOne

/// Couvre le défaut constaté : taper `-->` dans un bloc ```` ```mermaid ````
/// affichait `—>` (un tiret cadratin) — mermaid refusait alors le diagramme
/// (« Lexical error on line 2. Unrecognized text. ») bien que l'utilisateur
/// ait tapé une syntaxe de flèche valide.
///
/// Deux angles, faute de pouvoir piloter la substitution AppKit réellement en
/// test : `NSTextView.isAutomaticDashSubstitutionEnabled` (défaut `true`, non
/// couvert par `isAutomaticTextReplacementEnabled`, voir `EditorTextView.
/// commonInit`) est un service de correction de texte macOS — mesuré
/// pendant le diagnostic : ni un appel direct à
/// `insertText(_:replacementRange:)`, ni le passage complet par
/// `keyDown(with:)`/`interpretKeyEvents:` sur une vue rattachée à une
/// fenêtre réelle ne déclenchent la substitution dans ce process `swift
/// test` (headless, hors bundle applicatif — le service de vérification de
/// texte macOS ne s'y active pas). Donc :
///
/// 1. `test_commonInit_disablesAutomaticDashSubstitution` fige la
///    **configuration** qui pilote la transformation — c'est la seule prise
///    directement mesurable et déterministe sur le défaut lui-même.
/// 2. `test_pipelineFromStorageToWebViewSource_preservesLiteralHyphens`
///    fige les **caractères réels** (codes Unicode, pas leur apparence) à
///    trois endroits une fois un texte déjà correct dans le storage : le
///    storage lui-même, le markdown sérialisé (`MarkdownSerializer`,
///    élimine la piste `MarkdownEscaping.inlineSpecials` — `-` y figure mais
///    ne s'applique jamais au corps d'un bloc de code, voir
///    `MarkdownSerializer.fencedCodeBlock`), et la sous-chaîne `source`
///    telle qu'extraite par `StyleRenderer.applyMermaidAttachment`
///    (`(storage.string as NSString).substring(with: range)`) — exactement
///    ce qui est ensuite transmis à `MermaidRenderer`/`WKWebView.
///    callAsyncJavaScript(arguments: ["source": source, …])`. Les trois
///    endroits sont fidèles : la transformation constatée par l'utilisateur
///    ne s'y produit pas, elle a lieu en amont, à la frappe.
final class EditorTextViewDashSubstitutionTests: XCTestCase {

    // MARK: - 1. La configuration qui pilote la transformation à la frappe

    func test_commonInit_disablesAutomaticDashSubstitution() {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)

        XCTAssertFalse(
            editor.isAutomaticDashSubstitutionEnabled,
            "isAutomaticTextReplacementEnabled ne couvre pas la substitution --/--- → tiret : propriété séparée, doit être coupée explicitement"
        )
    }

    // MARK: - 2. Fidélité du reste du pipeline (storage → markdown → source WKWebView)

    func test_pipelineFromStorageToWebViewSource_preservesLiteralHyphens() throws {
        let markdown = "```mermaid\nflowchart TD\nA-->B\n```"
        let parsed = MarkdownParser.parse(markdown)
        // `MarkdownParser.parse` seul (pas `StyleRenderer.applyVisualStyle`,
        // volontairement pas appelé ici) : la géométrie/l'attachment ne
        // changent aucun caractère, seulement des attributs d'affichage —
        // appeler `applyVisualStyle` déclencherait en plus le rendu web
        // asynchrone réel de `MermaidAttachmentFactory` (effet de bord
        // inutile ici, et mesuré comme source de flakiness dans la suite
        // `MermaidRenderCacheTests` exécutée dans le même process).
        let storage = NSTextStorage(attributedString: parsed)

        // Point 1 — ce qui est dans le storage : la ligne de flèche telle
        // que le parseur l'a laissée, jamais réécrite.
        let ns = storage.string as NSString
        let arrowLineRange = ns.range(of: "A-->B")
        XCTAssertNotEqual(arrowLineRange.location, NSNotFound, "le texte de la flèche doit rester intact dans le storage")
        let storageScalars = ns.substring(with: arrowLineRange).unicodeScalars.map(\.value)
        XCTAssertEqual(storageScalars, expectedArrowScalars, "storage : deux U+002D réels, pas un tiret cadratin/demi-cadratin")

        // Point 2 — ce qui est sérialisé en markdown : round-trip via
        // `MarkdownSerializer`, jamais échappé (le corps d'un bloc de code
        // est émis brut par `fencedCodeBlock`, hors de portée d'
        // `MarkdownEscaping.escapeInline`/`inlineSpecials`).
        let serialized = MarkdownSerializer.serialize(storage)
        XCTAssertTrue(serialized.contains("A-->B"), "le markdown sérialisé doit contenir la flèche telle quelle")
        let serializedRange = try XCTUnwrap(serialized.range(of: "A-->B"))
        let serializedScalars = serialized[serializedRange].unicodeScalars.map(\.value)
        XCTAssertEqual(serializedScalars, expectedArrowScalars, "markdown sérialisé : deux U+002D réels")

        // Point 3 — ce qui est passé au WKWebView : `StyleRenderer.
        // applyMermaidAttachment` extrait `source` comme une sous-chaîne
        // brute du storage sur la plage du bloc de code (celle du run
        // `.mdBlockType == .codeBlock`, calculée ici de la même façon —
        // `longestEffectiveRange`, sans passer par `applyVisualStyle` pour
        // éviter de déclencher le rendu web asynchrone réel, effet de bord
        // inutile ici et mesuré comme source de flakiness partagée avec
        // `MermaidRenderCacheTests` dans le même process de test). C'est
        // exactement cette chaîne que `MermaidRenderer.render` transmet à
        // `webView.callAsyncJavaScript(arguments: ["source": …])`.
        var blockRange = NSRange(location: 0, length: 0)
        let blockType = storage.attribute(
            .mdBlockType, at: 0, longestEffectiveRange: &blockRange, in: NSRange(location: 0, length: storage.length)
        ) as? BlockType
        let codeLanguage = storage.attribute(.mdCodeLanguage, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(blockType, .codeBlock)
        XCTAssertEqual(codeLanguage, "mermaid")
        let source = ns.substring(with: blockRange)
        XCTAssertTrue(source.contains("A-->B"), "la source transmise au WKWebView doit contenir la flèche telle quelle")
        let sourceRange = try XCTUnwrap(source.range(of: "A-->B"))
        let sourceScalars = source[sourceRange].unicodeScalars.map(\.value)
        XCTAssertEqual(sourceScalars, expectedArrowScalars, "source WKWebView : deux U+002D réels — mermaid ne reconnaît que ceux-ci comme syntaxe de flèche")
    }

    /// U+0041 A, U+002D -, U+002D -, U+003E >, U+0042 B — jamais U+2013 (EN
    /// DASH) ni U+2014 (EM DASH), visuellement proches selon la police mais
    /// pas la syntaxe `-->` que mermaid reconnaît.
    private let expectedArrowScalars: [UInt32] = [0x41, 0x2D, 0x2D, 0x3E, 0x42]
}
