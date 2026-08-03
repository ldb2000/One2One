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
