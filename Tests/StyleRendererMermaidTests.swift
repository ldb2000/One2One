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

    // MARK: - Géométrie fermée (états 1/2/4) : jamais de fond gris, source masqué

    /// Le fond gris standard des blocs de code (posé pour tout `.codeBlock`)
    /// ne doit jamais s'appliquer à un bloc mermaid fermé — il débordait sur
    /// toute la largeur (constat de tâche).
    func test_closedMermaidBlock_hasNoBackgroundColor() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        let background = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        XCTAssertNil(background, "un bloc mermaid fermé ne porte plus le fond gris des blocs de code")
    }

    /// Le source reste masqué (couleur transparente) dès la pose du
    /// placeholder — jamais visible « sous » le diagramme.
    func test_closedMermaidBlock_sourceForegroundIsClear() {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        StyleRenderer.applyVisualStyle(to: storage)

        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear)
    }

    /// Seule la première ligne du bloc porte la hauteur réservée — les
    /// lignes suivantes sont plafonnées à un filet quasi nul
    /// (`hiddenLineMaximumHeight`), jamais à une fraction de l'ancien
    /// `reservedHeight` (220pt).
    ///
    /// N'exige pas la hauteur exacte du placeholder (104pt) : un vrai
    /// `WKWebView` est déclenché en tâche de fond par ce test (voir la doc
    /// de tête de la suite) et peut, rarement, livrer le diagramme rendu
    /// avant même l'assertion — mesuré en pratique (190pt observé, un cadre
    /// réel dont l'image fait 190pt de haut, pas une régression). La
    /// hauteur réservée doit rester **cohérente avec l'attachment courant**,
    /// quel que soit son état à cet instant précis — jamais une fraction de
    /// 220pt dans tous les cas.
    func test_closedMermaidBlock_onlyFirstLineReservesHeight_restIsCapped() throws {
        let markdown = "```mermaid\ngraph TD\nA-->B\n```"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        // Le source stocké (fences exclues, voir `MarkdownParser`) est
        // "graph TD\nA-->B" : la première ligne ("graph TD\n") fait 9
        // caractères, jusqu'à l'index 8 inclus depuis le début du bloc.
        let blockStart = (storage.string as NSString).range(of: "graph TD").location
        let attachment = storage.attribute(.mdMermaidAttachment, at: blockStart, effectiveRange: nil) as? NSTextAttachment
        let expectedHeight = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: attachment?.image?.size)

        let firstLineStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockStart, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(firstLineStyle.minimumLineHeight, expectedHeight)
        // Le « jamais une fraction de 220pt » est couvert de façon
        // déterministe par `MermaidBlockLayoutTests.
        // test_closedFrameHeight_smallImage_isNotInflatedByReservedHeightLegacy`
        // (fonction pure, taille d'image contrôlée) — pas ici, où la
        // hauteur réelle dépend du rendu `WKWebView` en tâche de fond.

        let restIndex = blockStart + 9 // juste après "graph TD\n"
        let restStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: restIndex, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(restStyle.maximumLineHeight, MermaidBlockLayout.hiddenLineMaximumHeight)
        XCTAssertNotEqual(
            restStyle.maximumLineHeight, expectedHeight,
            "la 2e ligne ne doit jamais hériter d'une fraction de la hauteur réservée"
        )
    }

    // MARK: - Géométrie ouverte (état 3) : interligne normal, jamais fermée par erreur

    /// Un restylage **ciblé** (frappe, ou changement de sélection — voir
    /// `EditorRepresentable.Coordinator.updateMermaidBlockGeometryIfNeeded`)
    /// alors que le curseur touche le bloc doit produire la géométrie
    /// ouverte : interligne normal, marge de gouttière — jamais la
    /// réservation à une ligne de l'état fermé.
    func test_targetedRestyle_withSelectionInsideBlock_getsOpenGeometry() throws {
        let (storage, editor) = makeWiredEditor(markdown: "```mermaid\ngraph TD\nA-->B\n```")
        var blockRange = NSRange(location: 0, length: 0)
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is NSTextAttachment, range.length > 0 { blockRange = range; stop.pointee = true }
        }
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))

        StyleRenderer.applyVisualStyle(to: storage, affectedRange: blockRange)

        let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.lineHeightMultiple, MermaidSourceLayout.lineHeightMultiple)
        XCTAssertEqual(style.headIndent, MermaidSourceLayout.gutterWidth)
        XCTAssertEqual(style.paragraphSpacingBefore, MermaidSourceLayout.headerHeight)

        let color = storage.attribute(.foregroundColor, at: blockRange.location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.clear, "le source reste lisible pendant l'édition")
    }

    /// Corrige un bug latent découvert pendant ce chantier :
    /// `NSTextStorage.setAttributedString` déplace le curseur en fin de
    /// document *avant* que `applyVisualStyle` ne s'exécute, sans notifier
    /// le délégué (`Tests/EditorTextViewMermaidClickTests.swift`) — un
    /// document se terminant par un bloc mermaid verrait donc sa sélection
    /// « accidentellement » dedans lors d'un restylage du document entier.
    /// Un tel restylage (`affectedRange == nil`) doit toujours refermer le
    /// bloc, quelle que soit la sélection courante.
    func test_fullDocumentRestyle_staysClosed_evenWithSelectionInsideBlock() {
        let (storage, editor) = makeWiredEditor(markdown: "```mermaid\ngraph TD\nA-->B\n```")
        var blockRange = NSRange(location: 0, length: 0)
        storage.enumerateAttribute(.mdMermaidAttachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is NSTextAttachment, range.length > 0 { blockRange = range; stop.pointee = true }
        }
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))

        // Restylage du document entier (`affectedRange` omis) — comme
        // `applyInitialState`/`updateNSView` après `setAttributedString`.
        StyleRenderer.applyVisualStyle(to: storage)

        let color = storage.attribute(.foregroundColor, at: blockRange.location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "toujours fermé après un restylage du document entier")
    }

    /// Régression : un restylage **ciblé** sur une ligne du milieu d'un bloc
    /// mermaid (ex. une frappe sur la 2e ligne d'un bloc de 3) ne doit
    /// jamais recalculer l'attachment/la géométrie sur cette seule ligne —
    /// `expandedForMermaidBlock` doit élargir la plage à la totalité du bloc
    /// avant qu'`applyMermaidAttachment` ne relise `source`.
    func test_targetedRestyleOfAMiddleLine_stillCoversTheWholeMermaidBlockSource() throws {
        let markdown = "```mermaid\ngraph TD\nA-->B\nB-->C\n```"
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)

        let ns = storage.string as NSString
        let middleLineLocation = ns.range(of: "A-->B").location
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: NSRange(location: middleLineLocation, length: 1))

        let blockRange = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: middleLineLocation))
        let source = ns.substring(with: blockRange)
        XCTAssertTrue(source.contains("graph TD"), "la 1re ligne ne doit pas avoir disparu du bloc reconnu")
        XCTAssertTrue(source.contains("A-->B"))
        XCTAssertTrue(source.contains("B-->C"), "la 3e ligne ne doit pas avoir disparu du bloc reconnu")
    }

    // MARK: - refreshClosedMermaidGeometry (rafraîchissement après rendu asynchrone)

    /// Défaut constaté (rapport de tâche) : le cadre d'erreur
    /// (`MermaidBlockLayout.errorFrameHeight`, 132pt) est **toujours** plus
    /// haut que le placeholder (`placeholderHeight`, 104pt) réservé au
    /// moment de la pose synchrone de l'attachment. Sans
    /// `refreshClosedMermaidGeometry`, la hauteur réservée
    /// (`NSParagraphStyle.minimumLineHeight`, une valeur figée dans
    /// l'attribut posé) ne suivait jamais l'image une fois le rendu
    /// asynchrone livré — `MarkdownLayoutManager.drawMermaidDiagram` dessine
    /// pourtant l'image à sa taille **native**, débordant alors de la ligne
    /// réservée et empiétant sur les lignes de source suivantes (masquage
    /// couleur intact, mais espace insuffisant pour les couvrir : le
    /// débordement de l'image lui-même, visible « en travers » du cadre).
    ///
    /// Construit le storage à la main (pas `StyleRenderer.applyVisualStyle`,
    /// qui déclencherait un vrai rendu `WKWebView` en tâche de fond — timing
    /// non déterministe, voir la doc de tête de la suite et le commentaire
    /// de `test_closedMermaidBlock_onlyFirstLineReservesHeight_restIsCapped`) :
    /// place directement l'attachment et la géométrie fermée qu'
    /// `applyMermaidAttachment`/`applyClosedMermaidGeometry` auraient posées
    /// pour un placeholder tout juste livré, puis mute l'image en place
    /// (même geste que `MermaidAttachmentFactory.render`) avant d'appeler la
    /// fonction sous test.
    @MainActor
    func test_refreshClosedMermaidGeometry_growsReservedHeightToMatchTallerImage() throws {
        let (storage, blockRange) = try makeClosedMermaidStorage()
        let attachment = try XCTUnwrap(storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment)

        let tallerImage = MermaidAttachmentFactory.frameImage(
            title: "Diagramme invalide", detail: "Lexical error on line 2. Unrecognized text.",
            borderColor: .systemRed, titleColor: .systemRed, tinted: true, actionLabel: "Ouvrir le source"
        )
        XCTAssertGreaterThan(tallerImage.size.height, MermaidBlockLayout.placeholderHeight, "prémisse : le cadre d'erreur est bien plus haut que le placeholder")
        attachment.image = tallerImage

        StyleRenderer.refreshClosedMermaidGeometry(in: storage, range: blockRange)

        let refreshedStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(
            refreshedStyle.minimumLineHeight, tallerImage.size.height,
            "la hauteur réservée doit suivre la taille réelle et actuelle de l'image, pas rester figée sur celle du placeholder"
        )
    }

    /// Le bloc peut être rouvert (curseur dedans) entre la pose du
    /// placeholder et l'arrivée du rendu asynchrone — dans ce cas, rafraîchir
    /// la géométrie **fermée** serait faux (le bloc affiche son source, pas
    /// de diagramme) : `refreshClosedMermaidGeometry` doit se taire.
    @MainActor
    func test_refreshClosedMermaidGeometry_doesNothing_whenBlockIsCurrentlyOpen() throws {
        let (storage, blockRange) = try makeClosedMermaidStorage()
        let attachment = try XCTUnwrap(storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment)
        let editor = try XCTUnwrap(storage.layoutManagers.first?.firstTextView as? EditorTextView)
        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0)) // curseur dans le bloc : ouvert

        let styleBefore = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle)
        let reservedHeightBefore = styleBefore.minimumLineHeight

        attachment.image = MermaidAttachmentFactory.frameImage(
            title: "Diagramme invalide", detail: "erreur", borderColor: .systemRed, titleColor: .systemRed, tinted: true
        )
        StyleRenderer.refreshClosedMermaidGeometry(in: storage, range: blockRange)

        let styleAfter = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(styleAfter.minimumLineHeight, reservedHeightBefore, "un bloc ouvert ne doit pas voir sa géométrie fermée recalculée")
    }

    /// Construit un storage portant un bloc mermaid déjà **fermé**, avec
    /// exactement la géométrie qu'`applyMermaidAttachment`/
    /// `applyClosedMermaidGeometry` posent pour un placeholder tout juste
    /// livré (104pt réservés) — sans passer par `StyleRenderer.
    /// applyVisualStyle` (voir la doc des deux tests ci-dessus).
    private func makeClosedMermaidStorage() throws -> (NSTextStorage, NSRange) {
        // « intro » avant le bloc : sans préfixe, le bloc commencerait à la
        // position 0 — le curseur par défaut (0) « toucherait » alors son
        // propre début (`MermaidBlockLayout.selectionTouches` est inclusive
        // aux deux bornes) et serait à tort considéré dedans (bloc ouvert).
        // Même piège déjà mesuré dans `EditorTextViewMermaidClickTests.
        // makeWiredEditorWithMermaidBlock`.
        let markdown = "intro\n\n```mermaid\ngraph TD\nA-->B\n```"
        let parsed = MarkdownParser.parse(markdown)
        let storage = NSTextStorage(attributedString: parsed)
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        editor.setSelectedRange(NSRange(location: 0, length: 0)) // hors du bloc : fermé

        let blockStart = (storage.string as NSString).range(of: "graph TD").location
        var blockRange = NSRange(location: 0, length: 0)
        let blockType = storage.attribute(.mdBlockType, at: blockStart, longestEffectiveRange: &blockRange, in: NSRange(location: 0, length: storage.length)) as? BlockType
        let codeLanguage = storage.attribute(.mdCodeLanguage, at: blockStart, effectiveRange: nil) as? String
        XCTAssertEqual(blockType, .codeBlock)
        XCTAssertEqual(codeLanguage, "mermaid")

        let placeholder = MainActor.assumeIsolated { MermaidAttachmentFactory.placeholder(for: (storage.string as NSString).substring(with: blockRange)) }
        storage.addAttribute(.mdMermaidAttachment, value: placeholder, range: blockRange)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: blockRange)

        let ns = storage.string as NSString
        let (firstLine, rest) = MermaidBlockLayout.splitFirstLine(of: blockRange, in: ns)
        let firstLineStyle = NSMutableParagraphStyle()
        firstLineStyle.minimumLineHeight = MermaidBlockLayout.closedFrameHeight(forAttachmentSize: placeholder.image?.size)
        storage.addAttribute(.paragraphStyle, value: firstLineStyle, range: firstLine)
        if rest.length > 0 {
            let restStyle = NSMutableParagraphStyle()
            restStyle.maximumLineHeight = MermaidBlockLayout.hiddenLineMaximumHeight
            storage.addAttribute(.paragraphStyle, value: restStyle, range: rest)
        }

        return (storage, blockRange)
    }

    // MARK: - Fixture

    /// Storage + `MarkdownLayoutManager` + `EditorTextView` câblés, sans
    /// `Coordinator`/délégué — ces tests appellent `StyleRenderer.
    /// applyVisualStyle` directement, ils n'ont besoin que d'un
    /// `firstTextView` capable de répondre à `selectedRange()`.
    private func makeWiredEditor(markdown: String) -> (NSTextStorage, EditorTextView) {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        StyleRenderer.applyVisualStyle(to: textStorage)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        return (textStorage, editor)
    }
}
