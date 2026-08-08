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
        XCTAssertEqual(
            style.headIndent,
            MermaidSourceLayout.gutterWidth + MermaidSourceLayout.codeHorizontalPadding
        )
        XCTAssertEqual(
            style.minimumLineHeight,
            MermaidSourceLayout.sourceLineHeight
        )
        // `applyMermaidAttachment` pose toujours une image sur l'attachment
        // (placeholder au minimum — jamais `nil`) avant d'atteindre la
        // géométrie ouverte : la bande réservée dépend donc de la taille
        // *réelle* de cette image (chargement en cours ou déjà servie par
        // `MermaidRenderCache`, selon le timing du rendu asynchrone), jamais
        // d'un band figé à 0 — recalculée ici avec le même point d'entrée
        // que `StyleRenderer.applyOpenMermaidGeometry` pour ne pas dupliquer
        // la formule.
        let attachedImageSize = (storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment)?.image?.size
        let expectedBand = MermaidSourceLayout.previewHeight(forAttachmentSize: attachedImageSize, containerWidth: 400)
        XCTAssertEqual(
            style.paragraphSpacingBefore,
            MermaidSourceLayout.headerHeight + expectedBand + MermaidSourceLayout.bodyTopPadding,
            accuracy: 0.001
        )
        XCTAssertNil(storage.attribute(.baselineOffset, at: blockRange.location, effectiveRange: nil))

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

        StyleRenderer.refreshClosedMermaidGeometry(in: storage, attachment: attachment)

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
        StyleRenderer.refreshClosedMermaidGeometry(in: storage, attachment: attachment)

        let styleAfter = try XCTUnwrap(storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(styleAfter.minimumLineHeight, reservedHeightBefore, "un bloc ouvert ne doit pas voir sa géométrie fermée recalculée")
    }

    // MARK: - Édition d'un bloc ouvert : jamais de rendu ni de fermeture en vol

    /// Une frappe dans un bloc **ouvert** ne doit pas re-créer l'attachment :
    /// chaque frappe relançait un rendu du source incomplet (invalide →
    /// `WKWebView` à chaque caractère) et remplaçait l'attachment posé — les
    /// completions en vol, armées d'une plage capturée avant les frappes
    /// suivantes, refermaient ensuite la géométrie du bloc en pleine édition
    /// (superposition carte/erreur/source mesurée à l'écran). L'attachment
    /// existant reste posé tel quel ; le rendu du source final part à la
    /// fermeture du bloc.
    @MainActor
    func test_targetedRestyle_ofAnEditedOpenBlock_keepsTheExistingAttachmentInstance() throws {
        let (storage, editor) = makeWiredEditor(markdown: "```mermaid\ngraph TD\nA-->B\n```")
        let initialRange = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: 0))
        let before = try XCTUnwrap(
            storage.attribute(.mdMermaidAttachment, at: initialRange.location, effectiveRange: nil) as? NSTextAttachment
        )

        // Frappe simulée au milieu du source : le texte change, le bloc grandit.
        let insertion = initialRange.location + 7
        storage.replaceCharacters(in: NSRange(location: insertion, length: 0), with: "x")
        editor.setSelectedRange(NSRange(location: insertion + 1, length: 0))
        let grownRange = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: initialRange.location))
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: grownRange)

        let after = try XCTUnwrap(
            storage.attribute(.mdMermaidAttachment, at: grownRange.location, effectiveRange: nil) as? NSTextAttachment
        )
        XCTAssertTrue(before === after, "pas de nouveau rendu tant que le bloc est en édition")
    }

    /// Reproduit le bug d'écran : un rendu lancé AVANT des frappes se termine
    /// APRÈS — sa plage capturée au lancement est périmée (le bloc a grandi),
    /// le curseur est au-delà de l'ancienne borne mais toujours dans le bloc.
    /// La completion doit retrouver le bloc par l'**identité** de son
    /// attachment et voir qu'il est encore ouvert — jamais refermer la
    /// géométrie sur la foi d'une plage figée.
    @MainActor
    func test_refreshClosedMermaidGeometry_afterTheBlockGrew_leavesTheOpenGeometryIntact() throws {
        let (storage, editor) = makeWiredEditor(markdown: "```mermaid\ngraph TD\nA-->B\n```")
        let staleRange = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: 0))
        let attachment = try XCTUnwrap(
            storage.attribute(.mdMermaidAttachment, at: staleRange.location, effectiveRange: nil) as? NSTextAttachment
        )

        // Le bloc grandit pendant le rendu asynchrone (frappes en fin de source).
        storage.replaceCharacters(in: NSRange(location: NSMaxRange(staleRange) - 1, length: 0), with: "xxxx")
        let grownRange = try XCTUnwrap(MermaidBlockLayout.blockRange(in: storage, at: staleRange.location))
        editor.setSelectedRange(NSRange(location: NSMaxRange(staleRange) + 2, length: 0))
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: grownRange)

        StyleRenderer.refreshClosedMermaidGeometry(in: storage, attachment: attachment)

        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: grownRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(
            style.lineHeightMultiple, MermaidSourceLayout.lineHeightMultiple,
            "la géométrie ouverte doit rester intacte après la completion périmée"
        )
        let color = storage.attribute(.foregroundColor, at: grownRange.location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.clear, "le source reste visible : la completion périmée ne referme pas le bloc")
    }

    /// Un rendu dont l'attachment a été remplacé entre-temps (nouveau rendu
    /// posé à la fermeture, bloc supprimé…) ne doit toucher à rien : son
    /// attachment n'est plus dans le storage, la completion est périmée.
    @MainActor
    func test_refreshClosedMermaidGeometry_forAnAttachmentNoLongerInTheStorage_doesNothing() throws {
        let (storage, blockRange) = try makeClosedMermaidStorage()
        let styleBefore = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        let orphan = MermaidAttachmentFactory.placeholder(for: "graph TD")

        StyleRenderer.refreshClosedMermaidGeometry(in: storage, attachment: orphan)

        let styleAfter = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: blockRange.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(
            styleAfter.minimumLineHeight, styleBefore.minimumLineHeight,
            "une completion dont l'attachment n'est plus posé ne doit rien recalculer"
        )
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

    // MARK: - Bande d'aperçu réservée (bloc ouvert)

    /// Storage d'un bloc mermaid **ouvert** (curseur dedans) portant déjà un
    /// attachment dont l'image fait `imageSize` — construit sans passer par
    /// `applyVisualStyle`, qui déclencherait un vrai `WKWebView` (voir la doc
    /// de tête de cette suite).
    private func makeOpenMermaidStorage(imageSize: NSSize?) throws -> (NSTextStorage, NSRange) {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        let ns = storage.string as NSString
        let start = ns.range(of: "graph TD").location
        let end = NSMaxRange(ns.range(of: "A-->B"))
        let range = NSRange(location: start, length: end - start)

        let attachment = NSTextAttachment()
        if let imageSize {
            let image = NSImage(size: imageSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: imageSize).fill()
            image.unlockFocus()
            attachment.image = image
        }
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)
        return (storage, range)
    }

    /// Hauteur réservée au-dessus de la première ligne d'un bloc ouvert.
    private func paragraphSpacingBefore(in storage: NSTextStorage, at location: Int) throws -> CGFloat {
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacingBefore
    }

    /// Avec une image livrée, l'espace réservé au-dessus du source couvre
    /// l'en-tête **et** la bande d'aperçu : c'est là que
    /// `MarkdownLayoutManager` peint le diagramme figé.
    func test_openMermaidBlock_withAnImage_reservesTheHeaderAndThePreviewBand() throws {
        let imageSize = NSSize(width: 300, height: 150)
        let (storage, range) = try makeOpenMermaidStorage(imageSize: imageSize)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: imageSize, containerWidth: 400
        )

        let band = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)
        XCTAssertGreaterThan(band, 0, "prémisse : une image de 300×150 produit une bande")
        XCTAssertEqual(
            try paragraphSpacingBefore(in: storage, at: range.location),
            MermaidSourceLayout.headerHeight + band + MermaidSourceLayout.bodyTopPadding,
            accuracy: 0.001
        )
    }

    /// Sans image (bloc jamais rendu), la réservation reste exactement celle
    /// d'avant ce chantier — le cadre garde son allure d'origine.
    func test_openMermaidBlock_withoutAnImage_reservesOnlyTheHeader() throws {
        let (storage, range) = try makeOpenMermaidStorage(imageSize: nil)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: nil, containerWidth: 400
        )

        XCTAssertEqual(
            try paragraphSpacingBefore(in: storage, at: range.location),
            MermaidSourceLayout.headerHeight + MermaidSourceLayout.bodyTopPadding,
            accuracy: 0.001
        )
    }

    /// La première ligne d'un bloc ouvert garde une hauteur de ligne de code
    /// normale : la bande est réservée par l'espacement de paragraphe, jamais
    /// en gonflant `minimumLineHeight` — ce qui produirait un curseur vertical
    /// surdimensionné (défaut déjà corrigé, à ne pas réintroduire).
    func test_openMermaidBlock_neverInflatesTheFirstLineHeight() throws {
        let imageSize = NSSize(width: 300, height: 900)
        let (storage, range) = try makeOpenMermaidStorage(imageSize: imageSize)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: imageSize, containerWidth: 400
        )

        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(style.minimumLineHeight, MermaidSourceLayout.sourceLineHeight)
    }
}
