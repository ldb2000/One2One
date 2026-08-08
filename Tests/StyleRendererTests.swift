import AppKit
import XCTest
@testable import OneToOne

final class StyleRendererTests: XCTestCase {

    /// `ImageAttachmentFactory` a un cache statique partagé entre tous les
    /// tests (cf. `Tests/ImageAttachmentFactoryTests.swift`) : sans reset
    /// avant/après chaque test, un test qui peuple ce cache en influence
    /// d'autres selon l'ordre d'exécution.
    override func setUp() {
        super.setUp()
        ImageAttachmentFactory.invalidate()
    }

    override func tearDown() {
        ImageAttachmentFactory.invalidate()
        super.tearDown()
    }

    func test_boldAttributeRendersBoldWithoutMarkdownMarkers() {
        let storage = NSMutableAttributedString(string: "hello bold")
        storage.addAttribute(.mdBold, value: true, range: NSRange(location: 6, length: 4))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(textStorage.string, "hello bold")
        XCTAssertTrue(isBold(textStorage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont))
        XCTAssertFalse(isBold(textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
    }

    func test_partialStyleRefreshOnlyRecomputesAffectedLine() {
        let storage = NSMutableAttributedString(string: "Title\nplain")
        storage.addAttribute(.mdBlockType, value: BlockType.h2, range: NSRange(location: 0, length: 5))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)

        let plainRange = (textStorage.string as NSString).range(of: "plain")
        textStorage.addAttribute(.mdBold, value: true, range: plainRange)
        StyleRenderer.applyVisualStyle(to: textStorage, affectedRange: plainRange)

        XCTAssertTrue(isBold(textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont))
        XCTAssertTrue(isBold(textStorage.attribute(.font, at: plainRange.location, effectiveRange: nil) as? NSFont))
    }

    // MARK: - Lien cliquable

    /// `StyleRenderer` doit poser l'attribut natif `.link` (celui
    /// qu'AppKit/`NSTextView` reconnaît pour router un clic vers
    /// `clicked(onLink:at:)`), en plus du style visuel déjà posé — pas
    /// seulement `.mdLink`, qui n'est qu'une donnée interne lue par
    /// `MarkdownSerializer`.
    func test_mdLinkAttribute_getsNativeLinkAttributeToo() {
        let url = URL(string: "https://example.com")!
        let storage = NSMutableAttributedString(string: "un lien")
        storage.addAttribute(.mdLink, value: url, range: NSRange(location: 3, length: 4))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(textStorage.attribute(.link, at: 3, effectiveRange: nil) as? URL, url)
        XCTAssertNil(textStorage.attribute(.link, at: 0, effectiveRange: nil), "le texte hors lien ne doit pas porter `.link`")
    }

    // MARK: - Rendu distinct des liens internes (chantier 2, dates-et-rappels)

    /// Un lien externe garde le rendu historique — pas de fond, souligné —
    /// contrôle négatif des deux tests suivants.
    func test_externalLink_keepsHistoricalStyle_underlinedNoBackground() {
        let url = URL(string: "https://example.com")!
        let storage = NSMutableAttributedString(string: "un lien")
        storage.addAttribute(.mdLink, value: url, range: NSRange(location: 0, length: storage.length))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.linkColor)
        XCTAssertEqual(
            textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil), "un lien externe ne doit pas avoir de fond")
    }

    /// Une mention (`onetoone://collaborator/…`) doit se distinguer d'un lien
    /// externe : fond teinté, pas de soulignement — la pastille d'AppFlowy,
    /// sans icône (hors périmètre de ce chantier).
    func test_mentionLink_getsDistinctStyle_backgroundNoUnderline() {
        let url = MentionCatalog.mentionURL(for: UUID())
        let storage = NSMutableAttributedString(string: "@Marie Dupont")
        storage.addAttribute(.mdLink, value: url, range: NSRange(location: 0, length: storage.length))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertNotNil(textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil), "une mention doit avoir un fond")
        XCTAssertNil(
            textStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil),
            "une mention ne doit pas être soulignée, contrairement à un lien externe"
        )
        XCTAssertNotEqual(
            textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.linkColor,
            "une mention ne doit pas garder la couleur de lien historique"
        )
    }

    /// Une date (`onetoone://date/…`) doit elle aussi se distinguer d'un lien
    /// externe, avec une couleur différente de celle de la mention — sinon
    /// les deux se marcheraient dessus (mise en garde explicite de la tâche).
    func test_dateLink_getsDistinctStyle_backgroundNoUnderline_andDiffersFromMention() {
        let dateURL = DateLinkCatalog.dateURL(date: Date(), includesTime: false, reminder: .none)
        let dateStorage = NSMutableAttributedString(string: "@5 août 2026")
        dateStorage.addAttribute(.mdLink, value: dateURL, range: NSRange(location: 0, length: dateStorage.length))
        let dateTextStorage = NSTextStorage(attributedString: dateStorage)
        StyleRenderer.applyVisualStyle(to: dateTextStorage)

        XCTAssertNotNil(dateTextStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil), "une date doit avoir un fond")
        XCTAssertNil(
            dateTextStorage.attribute(.underlineStyle, at: 0, effectiveRange: nil),
            "une date ne doit pas être soulignée, contrairement à un lien externe"
        )

        let mentionURL = MentionCatalog.mentionURL(for: UUID())
        let mentionStorage = NSMutableAttributedString(string: "@Marie Dupont")
        mentionStorage.addAttribute(.mdLink, value: mentionURL, range: NSRange(location: 0, length: mentionStorage.length))
        let mentionTextStorage = NSTextStorage(attributedString: mentionStorage)
        StyleRenderer.applyVisualStyle(to: mentionTextStorage)

        XCTAssertNotEqual(
            dateTextStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            mentionTextStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            "une date et une mention doivent avoir des couleurs distinctes"
        )
    }

    /// Un schéma `onetoone` avec un hôte non reconnu (ni `date` ni
    /// `collaborator` — un futur hôte encore inconnu de cette version) doit
    /// retomber sur le rendu historique plutôt que de deviner un style :
    /// garde-fou de `LinkVisualStyle.style(for:)`.
    func test_onetooneLink_unknownHost_fallsBackToHistoricalStyle() {
        let url = URL(string: "onetoone://session-done")!
        let storage = NSMutableAttributedString(string: "texte")
        storage.addAttribute(.mdLink, value: url, range: NSRange(location: 0, length: storage.length))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.linkColor)
        XCTAssertNil(textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    /// Rien de visuel ne doit entrer dans le storage (piège mesuré à quatre
    /// reprises sur cette branche) : round-trip parse → style → serialize
    /// pour une mention et pour une date, sur le modèle de
    /// `test_link_visualLinkAttribute_doesNotLeakIntoSerializedMarkdown`.
    func test_mentionAndDateLinkVisualStyle_doNotLeakIntoSerializedMarkdown() {
        let dateURL = DateLinkCatalog.dateURL(date: Date(), includesTime: false, reminder: .dayBefore)
        let mentionURL = MentionCatalog.mentionURL(for: UUID())
        let fixtures = [
            "[@5 août 2026](\(dateURL.absoluteString))",
            "[@Marie Dupont](\(mentionURL.absoluteString))",
        ]

        for markdown in fixtures {
            let parsed = MarkdownParser.parse(markdown)
            let textStorage = NSTextStorage(attributedString: parsed)

            StyleRenderer.applyVisualStyle(to: textStorage)

            XCTAssertEqual(MarkdownSerializer.serialize(textStorage), markdown, "fixture : \(markdown)")
        }
    }

    /// Un rafraîchissement qui ne repose plus `.mdLink` sur une plage qui le
    /// portait auparavant doit aussi effacer `.link` — sinon la plage reste
    /// cliquable pour AppKit alors qu'elle n'est plus un lien.
    func test_removingMdLink_alsoRemovesNativeLinkAttribute() {
        let url = URL(string: "https://example.com")!
        let storage = NSMutableAttributedString(string: "un lien")
        storage.addAttribute(.mdLink, value: url, range: NSRange(location: 3, length: 4))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)
        XCTAssertNotNil(textStorage.attribute(.link, at: 3, effectiveRange: nil))

        textStorage.removeAttribute(.mdLink, range: NSRange(location: 3, length: 4))
        StyleRenderer.applyVisualStyle(to: textStorage, affectedRange: NSRange(location: 3, length: 4))

        XCTAssertNil(textStorage.attribute(.link, at: 3, effectiveRange: nil))
    }

    // MARK: - Titres 4/5/6 : distincts entre eux (réserve mesurée de la tâche)

    /// Avant cette tâche, `.h4`/`.h5`/`.h6` partageaient exactement la même
    /// taille (13,5 pt semibold) — sans conséquence tant qu'aucune entrée du
    /// menu `/` ne les rendait atteignables. Devenus atteignables, les trois
    /// doivent se distinguer visuellement l'un de l'autre : tailles
    /// strictement décroissantes.
    func test_heading4to6_haveStrictlyDecreasingFontSizes() {
        let h4 = fontForHeading(.h4)
        let h5 = fontForHeading(.h5)
        let h6 = fontForHeading(.h6)

        XCTAssertGreaterThan(h4.pointSize, h5.pointSize, "Titre 4 doit rester plus grand que Titre 5")
        XCTAssertGreaterThan(h5.pointSize, h6.pointSize, "Titre 5 doit rester plus grand que Titre 6")
    }

    /// `.h6`, passé sous la taille du corps de texte (`baseFontSize`, 13 pt),
    /// reçoit une couleur distincte (`.secondaryLabelColor`) pour rester
    /// identifiable comme un titre plutôt que comme du texte réduit — pas le
    /// même traitement que `.h4`/`.h5`, qui restent en `.labelColor` comme le
    /// paragraphe (aucune couleur d'accent, contrairement à `.h1`-`.h3`).
    func test_heading6_getsSecondaryLabelColor_unlikeHeading4And5() {
        let storage = NSMutableAttributedString(string: "h4\nh5\nh6")
        storage.addAttribute(.mdBlockType, value: BlockType.h4, range: NSRange(location: 0, length: 2))
        storage.addAttribute(.mdBlockType, value: BlockType.h5, range: NSRange(location: 3, length: 2))
        storage.addAttribute(.mdBlockType, value: BlockType.h6, range: NSRange(location: 6, length: 2))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.labelColor
        )
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor,
            NSColor.labelColor
        )
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor,
            NSColor.secondaryLabelColor
        )
    }

    /// `.h4` reste plus grand que le corps de texte (`baseFontSize`, 13 pt) —
    /// contrairement à `.h5`/`.h6`, volontairement passés en dessous (voir la
    /// doc de `StyleRenderer.baseFont`).
    func test_heading4_remainsLargerThanBodyText() {
        XCTAssertGreaterThan(fontForHeading(.h4).pointSize, StyleRenderer.baseFontSize)
    }

    private func fontForHeading(_ level: BlockType) -> NSFont {
        let storage = NSMutableAttributedString(string: "Titre")
        storage.addAttribute(.mdBlockType, value: level, range: NSRange(location: 0, length: 5))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)
        return textStorage.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
    }

    // MARK: - Images

    func test_imageAttribute_withReadableFile_getsAttachment() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = NSMutableAttributedString(string: "\u{FFFC}")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 1))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        let attachment = textStorage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        XCTAssertNotNil(attachment)
    }

    func test_imageAttribute_withMissingFile_getsNoAttachmentAndRedColor() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-stylerenderer-missing-\(UUID().uuidString).png")

        let storage = NSMutableAttributedString(string: "\u{FFFC}")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 1))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.systemRed
        )
    }

    func test_imageAttribute_surroundingTextKeepsNormalStyleAndNoAttachment() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = NSMutableAttributedString(string: "before\u{FFFC}after")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 6, length: 1))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        // Le caractère image porte bien l'attachment...
        XCTAssertNotNil(textStorage.attribute(.attachment, at: 6, effectiveRange: nil))

        // ...mais ni "before" ni "after" n'en héritent, et gardent la couleur
        // de texte normale (pas de rouge d'échec, pas d'attachment).
        for index in [0, 5, 7, 11] {
            XCTAssertNil(
                textStorage.attribute(.attachment, at: index, effectiveRange: nil),
                "index \(index) ne devrait pas porter d'attachment"
            )
            XCTAssertEqual(
                textStorage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor,
                NSColor.labelColor,
                "index \(index) devrait garder la couleur de texte normale"
            )
        }
    }

    func test_imageAttribute_repeatedRestyleDoesNotLeaveStaleAttachment() throws {
        let goodURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: goodURL) }
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-stylerenderer-missing-\(UUID().uuidString).png")

        // Premier passage : une image valide obtient bien un attachment.
        let storage = NSMutableAttributedString(string: "\u{FFFC}")
        storage.addAttribute(.mdImageURL, value: goodURL, range: NSRange(location: 0, length: 1))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)
        XCTAssertNotNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))

        // Deuxième passage : l'URL est remplacée par une URL manquante, sans
        // retirer l'ancien attachment nous-mêmes — c'est à applyVisualStyle
        // de nettoyer l'attachment périmé avant de réévaluer.
        textStorage.removeAttribute(.mdImageURL, range: NSRange(location: 0, length: 1))
        textStorage.addAttribute(.mdImageURL, value: missingURL, range: NSRange(location: 0, length: 1))
        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertNil(
            textStorage.attribute(.attachment, at: 0, effectiveRange: nil),
            "un restylage successif ne doit pas laisser d'attachment périmé"
        )
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.systemRed
        )

        // Et un restylage supplémentaire, à l'identique, reste stable.
        StyleRenderer.applyVisualStyle(to: textStorage)
        XCTAssertNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func test_imageAttribute_removedEntirelyClearsStaleAttachment() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = NSMutableAttributedString(string: "\u{FFFC}")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 1))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)
        XCTAssertNotNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))

        // Le caractère perd complètement son attribut `mdImageURL` (il n'est
        // plus une image) sans que quiconque n'ait retiré `.attachment` —
        // c'est à `applyVisualStyle` de le nettoyer via le
        // `removeAttribute(.attachment, range: renderRange)` du début.
        textStorage.removeAttribute(.mdImageURL, range: NSRange(location: 0, length: 1))
        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertNil(
            textStorage.attribute(.attachment, at: 0, effectiveRange: nil),
            "un caractère qui n'est plus une image ne doit garder aucun attachment périmé"
        )
    }

    func test_imageAttribute_leakedOntoFollowingText_onlyImageCharGetsAttachmentRestKeepsStyle() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // Reproduit le run que `NSTextView` produit quand on tape juste après
        // une image : `mdImageURL` est hérité via les `typingAttributes` sur
        // tout le texte tapé ensuite ("bonjour"), qui porte en plus `mdBold`
        // — un run peut donc porter `mdImageURL` sans être entièrement une
        // image.
        let storage = NSMutableAttributedString(string: "\u{FFFC}bonjour")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 8))
        storage.addAttribute(.mdBold, value: true, range: NSRange(location: 1, length: 7))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        // Le caractère image récupère bien l'attachment...
        XCTAssertNotNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))

        // ...mais "bonjour" n'en hérite pas, et garde sa police en gras à la
        // taille normale malgré le `mdImageURL` hérité par typingAttributes.
        for index in 1..<8 {
            XCTAssertNil(
                textStorage.attribute(.attachment, at: index, effectiveRange: nil),
                "index \(index) ne devrait pas porter d'attachment"
            )
            let font = textStorage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            XCTAssertTrue(isBold(font), "index \(index) devrait rester en gras")
            XCTAssertEqual(font?.pointSize, StyleRenderer.baseFontSize, "index \(index) devrait garder sa taille normale")
        }
    }

    /// Même défaut que le test précédent, mais avec un fichier manquant.
    /// Contrairement à `.attachment` — que `NSTextStorage` corrige tout seul
    /// après coup si on l'étend par erreur au-delà du caractère `U+FFFC` (son
    /// `fixAttributes(in:)` interne retire `.attachment` de tout caractère
    /// qui n'est pas un objet de remplacement, vérifié empiriquement pendant
    /// le développement de ce test) — `.foregroundColor` n'a aucun filet de
    /// sécurité de ce genre. Une restriction manquante aux `U+FFFC` ne se
    /// verrait donc pas forcément sur le cas "succès", seulement ici.
    func test_imageAttribute_leakedOntoFollowingText_missingFile_onlyImageCharGetsRedColor() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-stylerenderer-missing-\(UUID().uuidString).png")

        let storage = NSMutableAttributedString(string: "\u{FFFC}bonjour")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 8))
        storage.addAttribute(.mdBold, value: true, range: NSRange(location: 1, length: 7))
        let textStorage = NSTextStorage(attributedString: storage)

        StyleRenderer.applyVisualStyle(to: textStorage)

        // Le caractère image passe bien en rouge...
        XCTAssertEqual(
            textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.systemRed
        )

        // ...mais "bonjour" ne devient pas rouge par contamination : il garde
        // la couleur de texte normale et son gras.
        for index in 1..<8 {
            XCTAssertEqual(
                textStorage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor,
                NSColor.labelColor,
                "index \(index) ne devrait pas hériter du rouge d'échec"
            )
            let font = textStorage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            XCTAssertTrue(isBold(font), "index \(index) devrait rester en gras")
        }
    }

    func test_imageInListItem_getsSameHeadIndentAsTextualBullet() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // Markdown réellement parsé : la première puce ne contient qu'une
        // image, la seconde du texte — les deux doivent recevoir la même
        // indentation de paragraphe.
        let markdown = "- ![alt](\(url.absoluteString))\n- texte"
        let parsed = MarkdownParser.parse(markdown)
        let textStorage = NSTextStorage(attributedString: parsed)

        XCTAssertNotNil(
            textStorage.attribute(.mdListInfo, at: 0, effectiveRange: nil) as? ListInfo,
            "le caractère image devrait porter mdListInfo, sinon le test ne prouve rien"
        )

        StyleRenderer.applyVisualStyle(to: textStorage)

        let text = textStorage.string as NSString
        let textBulletRange = text.range(of: "texte")
        XCTAssertNotEqual(textBulletRange.location, NSNotFound)

        XCTAssertNotNil(textStorage.attribute(.attachment, at: 0, effectiveRange: nil))

        let imageParagraphStyle = textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let textParagraphStyle = textStorage.attribute(
            .paragraphStyle, at: textBulletRange.location, effectiveRange: nil
        ) as? NSParagraphStyle

        XCTAssertNotNil(imageParagraphStyle, "l'image en puce doit recevoir un paragraphStyle")
        XCTAssertEqual(imageParagraphStyle?.headIndent, textParagraphStyle?.headIndent)
        XCTAssertEqual(imageParagraphStyle?.firstLineHeadIndent, textParagraphStyle?.firstLineHeadIndent)
    }

    func test_imageInHeading_neighboringTextKeepsHeadingFont() throws {
        let url = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let markdown = "# Titre ![alt](\(url.absoluteString)) suite"
        let parsed = MarkdownParser.parse(markdown)
        let textStorage = NSTextStorage(attributedString: parsed)

        StyleRenderer.applyVisualStyle(to: textStorage)

        let text = textStorage.string as NSString
        let imageRange = text.range(of: "\u{FFFC}")
        let suiteRange = text.range(of: "suite")
        XCTAssertNotEqual(imageRange.location, NSNotFound)
        XCTAssertNotEqual(suiteRange.location, NSNotFound)

        // L'image reçoit bien son attachment...
        XCTAssertNotNil(textStorage.attribute(.attachment, at: imageRange.location, effectiveRange: nil))

        // ...et le texte voisin garde la police du titre (h1 : 22pt, gras),
        // malgré le run image intercalé.
        let font = textStorage.attribute(.font, at: suiteRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 22)
        XCTAssertTrue(isBold(font))
    }

    /// Vérifie que l'attachment posé par `applyVisualStyle` respecte bien la
    /// taille calculée par `ImageAttachmentFactory.displayBounds` une fois
    /// mis en page par TextKit (pas seulement que `attachment.bounds` est
    /// rempli, mais que le layout manager s'en sert réellement — le piège
    /// documenté dans `EditableTextField.swift` étant qu'un
    /// `NSTextAttachmentCell` explicite ignorerait `bounds`).
    func test_imageAttachment_layoutHonorsDisplayBounds() throws {
        // 960×480 dépasse `maxWidth` (480) : `displayBounds` doit réduire à
        // 480×240, un résultat different de la taille source — un test qui
        // se contenterait de vérifier "bounds non-nul" ne détecterait pas un
        // retour silencieux à la taille de l'image d'origine.
        let url = try makeTemporaryPNGFile(pixelsWide: 960, pixelsHigh: 480)
        defer { try? FileManager.default.removeItem(at: url) }

        let storage = NSTextStorage(string: "\u{FFFC}")
        storage.addAttribute(.mdImageURL, value: url, range: NSRange(location: 0, length: 1))

        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
        layoutManager.addTextContainer(container)

        StyleRenderer.applyVisualStyle(to: storage)

        let expected = ImageAttachmentFactory.displayBounds(for: NSSize(width: 960, height: 480))
        XCTAssertEqual(expected.width, 480)
        XCTAssertEqual(expected.height, 240)

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: 1),
            actualCharacterRange: nil
        )
        let laidOutRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

        XCTAssertEqual(laidOutRect.width, expected.width, accuracy: 1)
        XCTAssertEqual(laidOutRect.height, expected.height, accuracy: 1)
    }

    private func isBold(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    // MARK: - List markers (task 2 du plan menu-slash)

    /// Puce, item numéroté, case cochée et case décochée doivent produire un
    /// texte de marqueur non-vide et distinct les uns des autres — sinon deux
    /// types d'item seraient visuellement indiscernables.
    func test_listMarkerText_bulletOrderedCheckedUnchecked_areAllDistinctAndNonEmpty() {
        let cases: [ListInfo] = [
            ListInfo(kind: .bullet),
            ListInfo(kind: .ordered, index: 3),
            ListInfo(kind: .task, checked: true),
            ListInfo(kind: .task, checked: false),
        ]
        let markers = cases.map { ListMarkerLayout.markerText(for: $0) }

        for marker in markers {
            XCTAssertFalse(marker.isEmpty, "un marqueur vide ne serait pas visible")
        }
        XCTAssertEqual(Set(markers).count, markers.count, "les quatre marqueurs doivent être distincts : \(markers)")
    }

    /// Le marqueur n'est pas qu'un attribut logique : il doit réellement se
    /// peindre. Monte chaque cas dans la même pile TextKit 1 que
    /// `EditorRepresentable` (storage → `MarkdownLayoutManager` → container),
    /// dessine hors écran et vérifie que la marge réservée par
    /// `applyVisualStyle` (à gauche de `firstLineHeadIndent`) contient des
    /// pixels qui diffèrent du fond réellement peint.
    func test_listMarkers_bulletOrderedCheckedUnchecked_areActuallyPaintedInTheReservedMargin() throws {
        let cases: [(String, ListInfo)] = [
            ("puce", ListInfo(kind: .bullet)),
            ("numéro", ListInfo(kind: .ordered, index: 3)),
            ("case cochée", ListInfo(kind: .task, checked: true)),
            ("case décochée", ListInfo(kind: .task, checked: false)),
        ]

        for (label, info) in cases {
            let storage = NSTextStorage(string: "item")
            storage.addAttribute(.mdListInfo, value: info, range: NSRange(location: 0, length: storage.length))
            StyleRenderer.applyVisualStyle(to: storage)

            let paragraphStyle = try XCTUnwrap(
                storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
                "\(label) : un item de liste doit recevoir un paragraphStyle"
            )
            let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)

            XCTAssertGreaterThan(
                nonBackgroundPixelCount(bitmap, xRange: 0..<max(1, Int(paragraphStyle.firstLineHeadIndent))),
                0,
                "\(label) : le marqueur doit être peint dans la marge réservée, pas seulement porté par un attribut"
            )
        }
    }

    /// La marge de niveau 0 (`ListMarkerLayout.indentPerLevel`, 16pt, dont
    /// `markerTrailingGap` = 4 de gouttière, soit 12pt utilisables) ne suffit
    /// pas à un marqueur numéroté à deux ou trois chiffres — mesuré à la
    /// police du marqueur : `"10."` fait ~17,3pt, `"123."` ~25,1pt, tous deux
    /// au-delà des 12pt. `textIndent(for:)` doit donc élargir la colonne
    /// réservée pour ces cas, sous peine de dessiner le marqueur à une
    /// abscisse négative — rogné contre le bord gauche du conteneur.
    func test_multiDigitOrderedMarker_getsAnIndentWideEnoughToAvoidBeingClipped() {
        for index in [10, 123] {
            let info = ListInfo(kind: .ordered, index: index)
            let indent = ListMarkerLayout.textIndent(for: info)
            let markerWidth = (ListMarkerLayout.markerText(for: info) as NSString)
                .size(withAttributes: [.font: ListMarkerLayout.markerFont])
                .width
            let markerX = indent - ListMarkerLayout.markerTrailingGap - markerWidth

            XCTAssertGreaterThanOrEqual(
                markerX, 0,
                "l'item ordonné n°\(index) déborderait à gauche du conteneur (rogné) : indent=\(indent), largeur=\(markerWidth)"
            )
        }
    }

    /// Le marqueur d'un item à trois chiffres doit rester visible dans la
    /// marge réservée (pas de vérification pixel-perfect de son intégrité,
    /// simplement que quelque chose s'y peint bien, comme pour les autres
    /// marqueurs) — complète le test géométrique ci-dessus par une preuve de
    /// rendu réel, sur le modèle de
    /// `test_listMarkers_bulletOrderedCheckedUnchecked_areActuallyPaintedInTheReservedMargin`.
    func test_threeDigitOrderedMarker_isActuallyPaintedInItsWidenedMargin() throws {
        let info = ListInfo(kind: .ordered, index: 123)
        let storage = NSTextStorage(string: "item")
        storage.addAttribute(.mdListInfo, value: info, range: NSRange(location: 0, length: storage.length))
        StyleRenderer.applyVisualStyle(to: storage)

        let paragraphStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)

        XCTAssertGreaterThan(
            nonBackgroundPixelCount(bitmap, xRange: 0..<max(1, Int(paragraphStyle.firstLineHeadIndent))),
            0,
            "le marqueur « 123. » doit être peint dans sa marge élargie"
        )
    }

    /// Le marqueur doit avoir une apparence fixe (police/couleur), pas
    /// hériter du style *inline* du texte de l'item — mesuré avant
    /// correctif : `MarkdownLayoutManager` lisait `.font`/`.foregroundColor`
    /// au premier caractère de l'item, donc un item en gras, en lien ou en
    /// code inline dessinait sa case/puce respectivement en gras, en bleu ou
    /// en monospace grisé.
    ///
    /// Ne compare *pas* les bitmaps de la marge pixel à pixel : le code
    /// inline utilise une police monospace de taille différente
    /// (`StyleRenderer`), qui change légitimement la hauteur de ligne — le
    /// marqueur, vertically recentré dans cette hauteur, se décale donc de
    /// quelques pixels sans que sa couleur ni sa police n'aient changé
    /// (mesuré : une comparaison pixel à pixel naïve faisait ici échouer le
    /// cas code inline sur un pur décalage vertical, aucune teinte). Ce test
    /// vise spécifiquement la couleur et l'intensité de l'encre, pas sa
    /// position.
    func test_markerAppearance_isFixed_notInheritedFromTheItemsInlineTextStyle() throws {
        // Marqueur numéroté, pas une case à cocher : mesuré séparément (voir
        // le commit), le glyphe ☐ ne change pas visuellement de poids une
        // fois « embold » via `NSFontManager` dans cet environnement (aucune
        // variante grasse dédiée pour ce symbole ; largeur identique avant/
        // après conversion). Un chiffre, lui, s'élargit bien en gras (mesuré :
        // "3." fait 11,41pt en normal contre 12,56pt en gras) — nécessaire
        // pour que la vérification de couverture d'encre (3) puisse
        // réellement attraper une régression sur l'item en gras.
        func markerColumnPixels(styling: (NSTextStorage) -> Void) throws -> (pixels: [[CGFloat]], background: CGFloat) {
            let storage = NSTextStorage(string: "texte")
            storage.addAttribute(
                .mdListInfo, value: ListInfo(kind: .ordered, index: 3),
                range: NSRange(location: 0, length: storage.length)
            )
            styling(storage)
            StyleRenderer.applyVisualStyle(to: storage)

            let paragraphStyle = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)
            let pixels = pixelSnapshot(bitmap, xRange: 0..<max(1, Int(paragraphStyle.firstLineHeadIndent)))
            return (pixels, backgroundLightness(of: bitmap))
        }

        let (plain, background) = try markerColumnPixels { _ in }
        let variants: [(String, [[CGFloat]])] = [
            ("gras", try markerColumnPixels { storage in
                storage.addAttribute(.mdBold, value: true, range: NSRange(location: 0, length: storage.length))
            }.pixels),
            ("lien", try markerColumnPixels { storage in
                storage.addAttribute(
                    .mdLink, value: URL(string: "https://example.com")!,
                    range: NSRange(location: 0, length: storage.length)
                )
            }.pixels),
            ("code inline", try markerColumnPixels { storage in
                storage.addAttribute(.mdInlineCode, value: true, range: NSRange(location: 0, length: storage.length))
            }.pixels),
        ]
        // Le pixel le plus couvert par l'encre (voir 2, `darkest`) est un
        // meilleur témoin que la couverture (3) pour ce garde-fou : la
        // couverture peut légitimement être basse (marqueur fin), alors que
        // « aucun pixel ne s'écarte du fond » signifie sans ambiguïté un
        // bitmap vierge — exactement le symptôme mesuré en apparence sombre
        // avant que `renderToOffscreenBitmap` force `.aqua` : les quatre
        // bitmaps de ce test étaient uniformément blancs (`labelColor`
        // résolu en blanc peint sur fond blanc), donc `tinted` vide,
        // `darkest`/`lightest` égaux à 1 partout et `coverage` égal à 0 des
        // deux côtés — ce test passait sans plus rien vérifier.
        let plainCoverage = plain.filter { abs($0[0] - background) > 0.02 }.count
        XCTAssertGreaterThan(
            plainCoverage, 0,
            "prémisse : le témoin doit avoir une couverture d'encre non nulle, sinon ce test ne prouve rien"
        )

        for (label, pixels) in variants {
            // 1) Aucune teinte : `linkColor` est bleu (R ≠ B) contrairement
            // au gris neutre `labelColor` (R ≈ G ≈ B, quel que soit le taux
            // d'anti-crénelage) — un marqueur qui hérite la couleur de lien
            // se détecte donc sans dépendre de sa position exacte.
            let tinted = pixels.filter { abs($0[0] - $0[1]) > 0.02 || abs($0[1] - $0[2]) > 0.02 }
            XCTAssertTrue(
                tinted.isEmpty,
                "item en \(label) : le marqueur ne doit porter aucune teinte, trouvé \(tinted.prefix(3))"
            )

            // 2) Encre de même intensité : le pixel le plus sombre (le plus
            // couvert par l'encre, donc le moins sensible à un sous-décalage
            // de position) doit être la même couleur que dans le cas
            // témoin — `secondaryLabelColor` (code inline) est un gris plus
            // clair que `labelColor`, ce qui se verrait ici même sans teinte.
            let darkest = pixels.map { $0[0] }.min() ?? 1
            let plainDarkest = plain.map { $0[0] }.min() ?? 1
            XCTAssertEqual(
                darkest, plainDarkest, accuracy: 0.05,
                "item en \(label) : l'encre du marqueur ne doit pas changer d'intensité"
            )

            // 3) Couverture d'encre comparable : un marqueur en gras (police
            // différente, traits plus épais) couvrirait sensiblement plus de
            // pixels que le témoin — la seule des quatre vérifications
            // capable d'attraper une police différente à couleur inchangée.
            // Tolérance 10% : mesuré, un item en gras avec l'ancien bug (police
            // héritée) couvre ~21% de pixels en plus que le témoin — cette
            // marge laisse passer le bruit d'anti-crénelage normal tout en
            // attrapant cet écart.
            let coverage = pixels.filter { abs($0[0] - background) > 0.02 }.count
            XCTAssertEqual(
                Double(coverage), Double(plainCoverage), accuracy: Double(plainCoverage) * 0.1 + 1,
                "item en \(label) : la couverture d'encre du marqueur ne doit pas changer notablement (police différente ?)"
            )

            // 4) Fond intact : le halo de fond posé sur le *texte* du code
            // inline (`StyleRenderer`, `.backgroundColor`) ne doit pas
            // déborder dans la marge du marqueur — sinon le pixel le plus
            // clair de la marge ne serait plus blanc.
            let lightest = pixels.map { $0[0] }.max() ?? 0
            let plainLightest = plain.map { $0[0] }.max() ?? 0
            XCTAssertEqual(
                lightest, plainLightest, accuracy: 0.02,
                "item en \(label) : le fond de la marge ne doit pas être teinté"
            )
        }
    }

    /// L'indentation par niveau (`headIndent`) garde la même progression que
    /// l'ancien `StyleRenderer` (16pt par niveau) : ce chantier ajoute un
    /// marqueur, il ne change pas la profondeur d'imbrication visible d'un
    /// item de liste.
    func test_listInfo_headIndent_keepsThePreExisting16ptPerLevelProgression() {
        let storage = NSMutableAttributedString(string: "top\nnested")
        storage.addAttribute(.mdListInfo, value: ListInfo(kind: .bullet, level: 0), range: NSRange(location: 0, length: 3))
        storage.addAttribute(.mdListInfo, value: ListInfo(kind: .bullet, level: 1), range: NSRange(location: 4, length: 6))
        let textStorage = NSTextStorage(attributedString: storage)
        StyleRenderer.applyVisualStyle(to: textStorage)

        let topStyle = textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let nestedStyle = textStorage.attribute(.paragraphStyle, at: 4, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertEqual(topStyle?.headIndent, 16)
        XCTAssertEqual(nestedStyle?.headIndent, 32)
        // Première ligne et lignes de repli s'alignent désormais au même
        // endroit — voir la doc de `ListMarkerLayout.textIndent(for:)` : le
        // marqueur se dessine à gauche de cette position commune.
        XCTAssertEqual(topStyle?.firstLineHeadIndent, topStyle?.headIndent)
        XCTAssertEqual(nestedStyle?.firstLineHeadIndent, nestedStyle?.headIndent)
    }

    /// Le test le plus important : le marqueur dessiné par
    /// `MarkdownLayoutManager` n'est qu'un effet visuel, jamais du texte. Un
    /// aller-retour parse → applyVisualStyle → serialize doit redonner
    /// exactement le markdown d'origine, et aucun des glyphes de marqueur ne
    /// doit apparaître dans le storage.
    /// Pipeline complet (`MarkdownParser` → `StyleRenderer` → `MarkdownSerializer`),
    /// contrairement à `test_mdLinkAttribute_getsNativeLinkAttributeToo`
    /// ci-dessus qui pose `.mdLink` à la main : ce test-ci exerce le
    /// round-trip réel tel que produit en production, où `.link` (natif,
    /// posé par cette tâche) coexiste avec `.mdLink` sur le storage envoyé à
    /// `MarkdownSerializer.emitInline`, qui ne lit que `.mdLink` (cf. son
    /// implémentation).
    func test_link_visualLinkAttribute_doesNotLeakIntoSerializedMarkdown() throws {
        let markdown = "[texte](https://example.com)"
        let parsed = MarkdownParser.parse(markdown)
        let textStorage = NSTextStorage(attributedString: parsed)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertNotNil(textStorage.attribute(.link, at: 0, effectiveRange: nil), "prémisse : `.link` bien posé par le pipeline")
        XCTAssertEqual(MarkdownSerializer.serialize(textStorage), markdown)
    }

    func test_listMarkerVisualStyle_doesNotLeakIntoSerializedMarkdown() {
        let markdown = "- puce\n1. premier\n2. second\n- [ ] à faire\n- [x] fait"
        let parsed = MarkdownParser.parse(markdown)
        let textStorage = NSTextStorage(attributedString: parsed)

        StyleRenderer.applyVisualStyle(to: textStorage)

        XCTAssertEqual(MarkdownSerializer.serialize(textStorage), markdown)
        for marker in ["•", "☑", "☐"] {
            XCTAssertFalse(
                textStorage.string.contains(marker),
                "le glyphe de marqueur « \(marker) » ne doit jamais entrer dans le storage"
            )
        }
    }

    // MARK: - Blockquote rule

    /// Une citation doit recevoir la même sorte d'indentation de paragraphe
    /// qu'un item de liste (voir le bloc `if let info = listInfo` juste
    /// au-dessus dans `StyleRenderer`) — la marge ainsi réservée à gauche du
    /// texte est celle où `MarkdownLayoutManager` peint le filet.
    func test_blockquote_getsParagraphIndentation() {
        let storage = NSTextStorage(string: "une citation")
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: storage.length))

        StyleRenderer.applyVisualStyle(to: storage)

        let paragraphStyle = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(paragraphStyle?.headIndent, BlockquoteRuleLayout.textIndent)
        XCTAssertEqual(paragraphStyle?.firstLineHeadIndent, BlockquoteRuleLayout.textIndent)
    }

    /// Avant ce chantier, une citation était rendue en texte gris
    /// (`NSColor.secondaryLabelColor`) et légèrement penché (`obliqueness`).
    /// Le repère visuel passe désormais entièrement par le filet peint dans
    /// la marge : le *texte* doit garder la couleur normale, sans obliquité.
    func test_blockquote_hasNoObliquenessAndNoSecondaryLabelColor() {
        let storage = NSTextStorage(string: "une citation")
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: storage.length))

        StyleRenderer.applyVisualStyle(to: storage)

        XCTAssertNil(
            storage.attribute(.obliqueness, at: 0, effectiveRange: nil),
            "une citation ne doit plus être penchée"
        )
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.labelColor, "une citation doit garder la couleur de texte normale")
        XCTAssertNotEqual(color, NSColor.secondaryLabelColor, "une citation ne doit plus être grise")
    }

    /// Un paragraphe ordinaire ne doit recevoir ni l'indentation ni le filet
    /// d'une citation — contrôle négatif du test précédent et de ceux du
    /// filet ci-dessous.
    func test_plainParagraph_getsNoBlockquoteIndentAndNoRule() throws {
        let storage = NSTextStorage(string: "texte normal")
        // Pas de `.mdBlockType` du tout : `StyleRenderer` retombe sur
        // `.paragraph`, comme `MarkdownSerializer.boundaryKind` le documente.

        StyleRenderer.applyVisualStyle(to: storage)

        XCTAssertNil(
            storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil),
            "un paragraphe ordinaire ne doit recevoir aucun paragraphStyle"
        )

        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)
        let ruleXRange = Int(BlockquoteRuleLayout.ruleLeadingGap)
            ..< Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)
        XCTAssertEqual(
            nonBackgroundPixelCount(bitmap, xRange: ruleXRange), 0,
            "un paragraphe ordinaire ne doit peindre aucun filet dans la marge"
        )
    }

    /// Le filet n'est pas qu'un attribut logique : il doit réellement se
    /// peindre, sur le même modèle que
    /// `test_listMarkers_bulletOrderedCheckedUnchecked_areActuallyPaintedInTheReservedMargin`.
    func test_blockquoteRule_isActuallyPaintedInTheReservedMargin() throws {
        let storage = NSTextStorage(string: "citation")
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: storage.length))
        StyleRenderer.applyVisualStyle(to: storage)

        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)
        let ruleXRange = Int(BlockquoteRuleLayout.ruleLeadingGap)
            ..< Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)
        XCTAssertGreaterThan(
            nonBackgroundPixelCount(bitmap, xRange: ruleXRange), 0,
            "le filet doit être réellement peint dans la marge réservée, pas seulement porté par un attribut"
        )
    }

    /// Un test « quelque chose est peint » ne prouve pas que la géométrie est
    /// correcte — un glyphe rogné peint quand même quelque chose (mesuré
    /// ailleurs sur cette branche). Ce test vérifie la géométrie exacte du
    /// filet : rien avant sa gouttière gauche, rien entre lui et le début du
    /// texte (`BlockquoteRuleLayout.textIndent`) — le filet occupe
    /// exactement sa colonne, pas toute la marge.
    func test_blockquoteRule_occupiesExactlyItsReservedThickness_notTheWholeMargin() throws {
        let storage = NSTextStorage(string: "citation")
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: storage.length))
        StyleRenderer.applyVisualStyle(to: storage)

        let bitmap = try renderToOffscreenBitmap(storage: storage, width: 200, height: 40)

        let beforeRule = 0..<Int(BlockquoteRuleLayout.ruleLeadingGap)
        let ruleColumn = Int(BlockquoteRuleLayout.ruleLeadingGap)
            ..< Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)
        let afterRule = Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)
            ..< Int(BlockquoteRuleLayout.textIndent)

        XCTAssertEqual(
            nonBackgroundPixelCount(bitmap, xRange: beforeRule), 0,
            "rien ne doit être peint avant la gouttière gauche du filet"
        )
        XCTAssertGreaterThan(
            nonBackgroundPixelCount(bitmap, xRange: ruleColumn), 0,
            "le filet doit être peint dans sa propre colonne"
        )
        XCTAssertEqual(
            nonBackgroundPixelCount(bitmap, xRange: afterRule), 0,
            "rien ne doit être peint entre le filet et le début du texte indenté"
        )
    }

    /// Une citation de plusieurs paragraphes séparés par un `\n` à
    /// l'intérieur d'un même bloc — exactement ce que produit
    /// `MarkdownParser.emitBlockQuote` pour `"> l1\n>\n> l2\n>\n> l3"`, une
    /// plage `.mdBlockType == .blockquote` unique englobant les trois lignes
    /// — doit recevoir un filet **continu**, pas trois segments espacés
    /// verticalement. Un risque concret : dessiner seulement sur le premier
    /// fragment de ligne de chaque paragraphe, comme `drawListMarkers` le
    /// fait *volontairement* pour son marqueur (un marqueur ne se répète pas
    /// sur les lignes de repli) — le filet, lui, ne doit pas imiter cette
    /// restriction.
    ///
    /// Vérifié par géométrie, pas par une simple présence de pixels : la
    /// plage de lignes peintes dans la colonne du filet doit être un
    /// intervalle contigu (aucun trou) et couvrir sensiblement plus qu'une
    /// seule ligne.
    func test_multiParagraphBlockquote_getsAContinuousRuleAcrossAllLines() throws {
        let ruleXRange = Int(BlockquoteRuleLayout.ruleLeadingGap)
            ..< Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)

        let single = NSTextStorage(string: "ligne unique")
        single.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: single.length))
        StyleRenderer.applyVisualStyle(to: single)
        let singleBitmap = try renderToOffscreenBitmap(storage: single, width: 200, height: 120)
        let singleLineRows = paintedRows(singleBitmap, xRange: ruleXRange)
        XCTAssertFalse(singleLineRows.isEmpty, "prémisse : une citation d'une ligne doit déjà peindre son filet")

        let multi = NSTextStorage(string: "ligne un\nligne deux\nligne trois")
        multi.addAttribute(.mdBlockType, value: BlockType.blockquote, range: NSRange(location: 0, length: multi.length))
        StyleRenderer.applyVisualStyle(to: multi)
        let multiBitmap = try renderToOffscreenBitmap(storage: multi, width: 200, height: 120)
        let multiRows = paintedRows(multiBitmap, xRange: ruleXRange)

        XCTAssertGreaterThan(
            multiRows.count, singleLineRows.count * 2,
            "le filet d'une citation de trois lignes doit couvrir nettement plus de hauteur qu'une citation d'une ligne"
        )

        let span = (multiRows.max() ?? 0) - (multiRows.min() ?? 0) + 1
        XCTAssertEqual(
            span, multiRows.count,
            "le filet doit être un trait continu du haut au bas du bloc : \(span - multiRows.count) ligne(s) de pixels " +
            "manquante(s) — trois segments espacés au lieu d'un seul trait"
        )
    }

    /// Le filet ne doit pas s'allonger de l'écart qui **sépare** la citation
    /// du bloc suivant. `StyleRenderer.applyBlockSpacing` pose 10 pt sur le
    /// dernier paragraphe d'un bloc ordinaire, 28 pt au voisinage d'une carte
    /// — cet espace vit dans le rect de **fragment** de la dernière ligne, pas
    /// dans son rect *used* (piège TextKit 1, voir `MarkdownLayoutManager.
    /// drawBlockquoteRules`). Le dimensionner sur le fragment faisait courir
    /// le filet jusqu'à 28 pt sous sa dernière ligne de texte.
    ///
    /// Vérifié sans dépendre d'une conversion de coordonnées : la citation
    /// étant le premier bloc, sa mise en page ne dépend pas de son propre
    /// espacement de fin — les lignes de pixels peintes doivent donc être
    /// **exactement les mêmes** avec 10 pt et avec 28 pt.
    func test_blockquoteRule_neverRunsBelowItsLastLine_whateverTheBlockSpacing() throws {
        let ruleXRange = Int(BlockquoteRuleLayout.ruleLeadingGap)
            ..< Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)

        let narrow = try paintedRowsForBlockquote(
            trailingSpacing: BlockGutterLayout.blockSpacing, xRange: ruleXRange
        )
        let wide = try paintedRowsForBlockquote(
            trailingSpacing: BlockGutterLayout.cardBlockSpacing, xRange: ruleXRange
        )

        XCTAssertFalse(narrow.isEmpty, "prémisse : le filet doit être peint")
        XCTAssertEqual(
            wide, narrow,
            "le filet suit l'écart inter-blocs : \(wide.count - narrow.count) ligne(s) de pixels en trop sous la citation"
        )
    }

    /// Même piège pour le marqueur de liste, centré verticalement : sur le
    /// dernier item d'une liste voisine d'une carte, centrer sur le rect de
    /// **fragment** (qui inclut les 28 pt de `paragraphSpacing`) faisait
    /// descendre la puce d'environ 9 pt sous le centre de son propre texte.
    /// Même protocole que le test précédent : l'item étant le premier bloc,
    /// les lignes peintes doivent être identiques quel que soit l'écart.
    func test_listMarker_staysCenteredOnItsText_whateverTheBlockSpacing() throws {
        // Colonne du marqueur seule : au-delà du filet du bloc suivant (voir
        // `paintedRowsForBulletItem`), en deçà du texte de l'item.
        let markerXRange = Int(BlockquoteRuleLayout.ruleLeadingGap + BlockquoteRuleLayout.ruleThickness)
            ..< Int(ListMarkerLayout.textIndent(for: ListInfo(kind: .bullet)) - ListMarkerLayout.markerTrailingGap)

        let narrow = try paintedRowsForBulletItem(
            trailingSpacing: BlockGutterLayout.blockSpacing, xRange: markerXRange
        )
        let wide = try paintedRowsForBulletItem(
            trailingSpacing: BlockGutterLayout.cardBlockSpacing, xRange: markerXRange
        )

        XCTAssertFalse(narrow.isEmpty, "prémisse : la puce doit être peinte")
        XCTAssertEqual(
            wide, narrow,
            "la puce suit l'écart inter-blocs au lieu de rester centrée sur son texte"
        )
    }

    /// Citation d'une ligne, **suivie d'un autre bloc**, dont le paragraphe
    /// cité porte `trailingSpacing` — l'écart qu'`applyBlockSpacing` pose
    /// selon le voisinage, reposé ici à la main pour l'isoler du reste du
    /// pipeline.
    ///
    /// Le bloc suivant est indispensable : mesuré, TextKit ne réserve **pas**
    /// le `paragraphSpacing` du dernier paragraphe du conteneur (son fragment
    /// est alors égal à son rect *used*), et la fixture ne prouverait rien.
    private func paintedRowsForBlockquote(trailingSpacing: CGFloat, xRange: Range<Int>) throws -> [Int] {
        let storage = NSTextStorage(string: "citation\nsuite")
        let quote = (storage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: quote)
        StyleRenderer.applyVisualStyle(to: storage)
        overrideParagraphSpacing(trailingSpacing, in: storage, range: quote)

        return paintedRows(try renderToOffscreenBitmap(storage: storage, width: 200, height: 80), xRange: xRange)
    }

    /// Item de liste **suivi d'un autre bloc**, même raison que ci-dessus. Le
    /// paragraphe suivant est lui aussi une citation : son texte est indenté
    /// (`BlockquoteRuleLayout.textIndent`) et ne peint donc rien dans la
    /// colonne du marqueur, qui reste mesurable seule.
    private func paintedRowsForBulletItem(trailingSpacing: CGFloat, xRange: Range<Int>) throws -> [Int] {
        let storage = NSTextStorage(string: "item\nsuite")
        let ns = storage.string as NSString
        let item = ns.lineRange(for: NSRange(location: 0, length: 0))
        let next = NSRange(location: NSMaxRange(item), length: storage.length - NSMaxRange(item))
        storage.addAttribute(.mdListInfo, value: ListInfo(kind: .bullet), range: item)
        storage.addAttribute(.mdBlockType, value: BlockType.blockquote, range: next)
        StyleRenderer.applyVisualStyle(to: storage)
        overrideParagraphSpacing(trailingSpacing, in: storage, range: item)

        return paintedRows(try renderToOffscreenBitmap(storage: storage, width: 200, height: 80), xRange: xRange)
    }

    private func overrideParagraphSpacing(_ spacing: CGFloat, in storage: NSTextStorage, range: NSRange) {
        let existing = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.paragraphSpacing = spacing
        storage.addAttribute(.paragraphStyle, value: style, range: range)
    }

    /// Le plus important pour ce chantier, sur le modèle de
    /// `test_listMarkerVisualStyle_doesNotLeakIntoSerializedMarkdown` : le
    /// filet et l'indentation ne sont qu'un effet visuel, jamais du texte ni
    /// une information qui changerait la sérialisation. Fixtures reprises
    /// telles quelles de `MarkdownRoundTripTests` (déjà vérifiées stables au
    /// round-trip parse → serialize *sans* étape de style) : ce test insère
    /// `applyVisualStyle` au milieu et vérifie qu'il n'y change rien — pas
    /// une nouvelle preuve que ces markdown-là round-trippent (déjà acquis
    /// ailleurs), seulement que le style n'y ajoute aucune fuite. Ce point a
    /// été violé quatre fois sous des formes différentes sur cette branche :
    /// ne pas le tenir pour acquis pour un fixture inventé sans vérification.
    func test_blockquoteVisualStyle_doesNotLeakIntoSerializedMarkdown() {
        let fixtures = [
            "> citation simple",
            "> quote next line — kept as block",
            "> Avant\n\nAprès",
            "> Avant\n\n> Après",
        ]

        for markdown in fixtures {
            let parsed = MarkdownParser.parse(markdown)
            let textStorage = NSTextStorage(attributedString: parsed)

            StyleRenderer.applyVisualStyle(to: textStorage)

            XCTAssertEqual(MarkdownSerializer.serialize(textStorage), markdown, "fixture : \(markdown)")
        }
    }

    // MARK: - List marker rendering fixtures

    /// Monte `storage` dans la même pile TextKit 1 qu'`EditorRepresentable`
    /// (storage → `MarkdownLayoutManager` → container) et la peint hors écran
    /// dans un bitmap RGBA, pour vérifier qu'un marqueur est réellement
    /// dessiné — pas seulement porté par un attribut de paragraphe.
    ///
    /// Le remplissage de fond et les deux appels de dessin sont enveloppés
    /// dans `NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance`,
    /// pour rendre ce test indépendant de l'apparence système courante.
    /// `ListMarkerLayout.markerColor` (`NSColor.labelColor`) est une couleur
    /// **dynamique** : en apparence sombre elle se résout en blanc quasi-pur
    /// (`R=1 G=1 B=1 A≈0.85`), peint sur le fond blanc que cette fonction
    /// remplit elle-même — le marqueur devient alors invisible, non pas
    /// absent. Mesuré : les tests pixel de ce fichier passaient à 19h02/19h49
    /// (apparence claire) et échouaient après 22h17, sur une machine dont
    /// `AppleInterfaceStyleSwitchesAutomatically` est activé — un test dont
    /// le résultat dépend de l'heure du jour n'en est pas un. La tentative
    /// `-AppleInterfaceStyle Light` en domaine argument n'override PAS
    /// l'apparence AppKit (vérifié) ; seul `performAsCurrentDrawingAppearance`
    /// fonctionne ici. Ne fige *pas* `ListMarkerLayout.markerColor` en une
    /// couleur non dynamique à la place : `labelColor` est le bon choix
    /// produit (l'app doit suivre l'apparence système), c'est au test de
    /// s'en affranchir, pas l'inverse.
    private func renderToOffscreenBitmap(storage: NSTextStorage, width: Int, height: Int) throws -> NSBitmapImageRep {
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat(width), height: CGFloat(height)))
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))

        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
            let glyphRange = layoutManager.glyphRange(for: container)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// Composante rouge du fond réellement peint dans `bitmap`, échantillonnée
    /// à un pixel garanti hors de toute zone de texte (coin inférieur droit,
    /// à l'écart de la marge testée et de tout glyphe). Les marqueurs et le
    /// texte de test sont tous des teintes de gris (`labelColor` et
    /// consorts, voir `ListMarkerLayout`) : un seul canal suffit à
    /// représenter la clarté d'un pixel. Jamais une constante « blanc »
    /// supposée — voir la doc de `renderToOffscreenBitmap`.
    private func backgroundLightness(of bitmap: NSBitmapImageRep) -> CGFloat {
        bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)?.redComponent ?? 1
    }

    /// Compte les pixels de `bitmap` dans `xRange` (toutes lignes confondues)
    /// dont la clarté diffère de celle du fond réellement peint (mesurée par
    /// `backgroundLightness(of:)`) — remplace un ancien critère « non blanc »
    /// qui supposait un fond blanc constant. Cette hypothèse tient une fois
    /// l'apparence forcée en `.aqua` (voir `renderToOffscreenBitmap`), mais
    /// mesurer contre le fond réel plutôt que contre une constante évite de
    /// réintroduire la même dépendance implicite ailleurs.
    private func nonBackgroundPixelCount(_ bitmap: NSBitmapImageRep, xRange: Range<Int>) -> Int {
        let background = backgroundLightness(of: bitmap)
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in xRange where x >= 0 && x < bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                if abs(color.redComponent - background) > 0.02 { count += 1 }
            }
        }
        return count
    }

    /// Indices de ligne `y` de `bitmap` où au moins un pixel de `xRange`
    /// diffère du fond réellement peint — sert à vérifier la **géométrie**
    /// d'un trait vertical (continuité, étendue), pas seulement sa présence :
    /// `nonBackgroundPixelCount` répond « combien de pixels », celle-ci
    /// répond « quelles lignes », ce qui permet de détecter un trou
    /// (segments espacés) via la comparaison de `min`/`max`/`count` côté
    /// appelant.
    private func paintedRows(_ bitmap: NSBitmapImageRep, xRange: Range<Int>) -> [Int] {
        let background = backgroundLightness(of: bitmap)
        var rows: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            let rowIsPainted = xRange.contains { x in
                guard x >= 0, x < bitmap.pixelsWide, let color = bitmap.colorAt(x: x, y: y) else { return false }
                return abs(color.redComponent - background) > 0.02
            }
            if rowIsPainted { rows.append(y) }
        }
        return rows
    }

    /// Composantes RGBA de chaque pixel de `bitmap` dans `xRange` (toutes
    /// lignes confondues), dans un ordre stable — comparable directement par
    /// `XCTAssertEqual` entre deux rendus, pour prouver qu'une zone donnée
    /// est peinte à l'identique indépendamment d'un facteur qui ne devrait
    /// pas l'influencer (`test_markerAppearance_isFixed_...`).
    private func pixelSnapshot(_ bitmap: NSBitmapImageRep, xRange: Range<Int>) -> [[CGFloat]] {
        var snapshot: [[CGFloat]] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in xRange where x >= 0 && x < bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                snapshot.append([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent])
            }
        }
        return snapshot
    }

    // MARK: - Fixtures

    /// Construit les octets d'un petit PNG valide directement via
    /// `NSBitmapImageRep`, sans passer par `NSImage.lockFocus()` — qui
    /// dépend du window server et peut échouer en environnement headless.
    /// Repris de `Tests/ImageAttachmentFactoryTests.swift`.
    private func makeTemporaryPNGData(pixelsWide: Int = 10, pixelsHigh: Int = 10) throws -> Data {
        let bitmapRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try XCTUnwrap(bitmapRep.representation(using: .png, properties: [:]))
    }

    /// Écrit un petit PNG dans le répertoire temporaire. Le fichier n'est pas
    /// supprimé par cette fonction — l'appelant en a la responsabilité.
    private func makeTemporaryPNGFile(pixelsWide: Int = 10, pixelsHigh: Int = 10) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-stylerenderer-test-\(UUID().uuidString).png")
        try makeTemporaryPNGData(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh).write(to: url)
        return url
    }
}
