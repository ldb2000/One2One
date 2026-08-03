import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre le mécanisme sur lequel s'appuie `EditorTextView.paste(_:)` :
/// insérer le placeholder produit par `EditorTextView.imagePlaceholder(for:)`
/// (même représentation que `MarkdownParser` — un caractère `U+FFFC` porteur
/// de `.mdImageURL`/`.mdImageAlt`, voir `ImagePlaceholder`) via
/// `insertText(_:replacementRange:)` déclenche-t-il, à travers le cycle
/// `NSTextViewDelegate` de `EditorRepresentable.Coordinator`, un rendu
/// immédiat (sans frappe supplémentaire) et une sérialisation correcte ?
///
/// `paste(_:)` lui-même n'est PAS appelé ici : il lit `NSPasteboard.general`,
/// l'état partagé de la machine qui exécute les tests, et je n'ai pas voulu y
/// écrire (voir la même décision documentée dans `MediaStoreTests`). Cette
/// classe appelle en revanche `imagePlaceholder(for:alt:)` et
/// `insertImagePlaceholder(for:alt:)`, réellement utilisées par `paste(_:)`
/// et par `MarkdownToolbar`, ce qui couvre le mécanisme de rendu/
/// sérialisation mais pas le branchement au presse-papiers ni le repli vers
/// `super.paste(sender)`.
final class EditorTextViewPasteTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ImageAttachmentFactory.invalidate()
    }

    override func tearDown() {
        ImageAttachmentFactory.invalidate()
        super.tearDown()
    }

    func test_insertingImagePlaceholder_rendersImmediately_andRoundTripsCorrectly() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()

        // Appelle la fonction de construction réellement utilisée par
        // `EditorTextView.paste(_:)`, pas une reproduction manuelle : une
        // mutation de `imagePlaceholder(for:alt:)` fait donc échouer ce test.
        let insertion = EditorTextView.imagePlaceholder(for: imageURL)
        editor.insertText(insertion, replacementRange: editor.selectedRange())

        // Rendu immédiat : pas de frappe supplémentaire nécessaire pour que
        // StyleRenderer (déclenché par textDidChange) pose l'attachment réel.
        let attrsAtPlaceholder = editor.textStorage!.attributes(at: 1, effectiveRange: nil)
        XCTAssertNotNil(
            attrsAtPlaceholder[.attachment],
            "l'image doit apparaître dès insertText, sans attendre une frappe supplémentaire"
        )

        // Round-trip correct : pas d'échappement des caractères spéciaux.
        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "\n![image](\(imageURL.absoluteString))")
    }

    /// Forme exacte du placeholder : un caractère `U+FFFC` seul sur sa ligne
    /// (un `\n` avant, un `\n` après). Sans le `\n` de queue, un contenu
    /// tapé juste après le collage se retrouverait sur la même ligne que
    /// l'image au lieu d'une nouvelle ligne — régression qu'aucun des deux
    /// tests précédents ne détecte (ils n'insèrent rien après le placeholder).
    func test_imagePlaceholder_isAloneOnItsOwnLine() {
        let url = URL(string: "file:///tmp/img_test.png")!
        let placeholder = EditorTextView.imagePlaceholder(for: url)
        XCTAssertEqual(placeholder.string, "\n\u{FFFC}\n")
    }

    /// Collage avec une sélection non vide : le texte sélectionné doit être
    /// remplacé, pas conservé à côté du placeholder.
    func test_insertingImagePlaceholder_replacesNonEmptySelection() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()
        editor.textStorage?.setAttributedString(NSAttributedString(string: "hello world"))
        let selection = (editor.string as NSString).range(of: "world")
        editor.setSelectedRange(selection)

        editor.insertImagePlaceholder(for: imageURL)

        let text = editor.textStorage!.string
        XCTAssertFalse(text.contains("world"), "la sélection doit être remplacée, pas conservée à côté du placeholder")
        XCTAssertEqual(text, "hello \n\u{FFFC}\n")
    }

    // MARK: - Attributs hérités par typingAttributes (code inline, gras…)

    /// Reproduit le bug mesuré en revue : coller juste après du code inline
    /// hérite `.mdInlineCode` sur le `U+FFFC` via `typingAttributes` (que
    /// `NSTextView` maintient à partir du caractère précédent). Sans le
    /// nettoyage fait par `insertImagePlaceholder`,
    /// `MarkdownSerializer.emitInline` donnerait la priorité exclusive au
    /// code inline — qui filtre les `U+FFFC` de son contenu — et l'URL de
    /// l'image disparaîtrait purement et simplement à la sérialisation
    /// (fichier resté orphelin sur disque).
    func test_pasteAfterInlineCode_imageURLSurvivesSerialization() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()
        // État laissé par `ShortcutDetector` après la frappe de `` `code` `` :
        // "code" porte `.mdInlineCode`, curseur juste après.
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "code", attributes: [.mdInlineCode: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))

        editor.insertImagePlaceholder(for: imageURL)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertTrue(
            serialized.contains(imageURL.absoluteString),
            "l'URL de l'image ne doit pas disparaître après du code inline : \(serialized.debugDescription)"
        )
        XCTAssertEqual(serialized, "`code`\n![image](\(imageURL.absoluteString))")
    }

    /// Même mesure pour le gras : sans nettoyage, l'image collée juste après
    /// du texte en gras hérite `.mdBold` et se retrouve emballée en
    /// `**![...]**` sans que l'utilisateur l'ait demandé.
    func test_pasteAfterBold_imageIsNotWrappedInBoldMarkers() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "bold", attributes: [.mdBold: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))

        editor.insertImagePlaceholder(for: imageURL)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "**bold**\n![image](\(imageURL.absoluteString))")
    }

    // MARK: - Contre-preuve : texte brut littéral

    /// Contre-preuve : insérer le texte brut `![alt](url)` (l'approche
    /// volontairement écartée pour `EditorTextView`, cf. doc-comment de
    /// `paste(_:)`) ne produit aucun attachment, même avec un fichier valide
    /// sur disque — la représentation affichable dépend de `.mdImageURL`,
    /// pas du contenu textuel.
    func test_insertingRawMarkdownText_doesNotRenderAsImage() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()

        let reference = MediaStore.markdownReference(for: imageURL)
        editor.insertText("\n\(reference)\n", replacementRange: editor.selectedRange())

        let attrsAtCharacterOne = editor.textStorage!.attributes(at: 1, effectiveRange: nil)
        XCTAssertNil(
            attrsAtCharacterOne[.attachment],
            "du texte brut ne porte pas mdImageURL, donc pas d'attachment, même avec un fichier valide sur disque"
        )
    }

    /// Contre-preuve complémentaire, avec une référence fixe (le texte est le
    /// seul objet du test, aucun fichier réel n'est nécessaire) : la
    /// sérialisation échappe les caractères spéciaux un par un au lieu de
    /// round-tripper vers une image. Assertion sur la chaîne exacte — pas une
    /// simple inégalité, qui passerait pour n'importe quelle divergence, y
    /// compris une régression sans rapport.
    func test_insertingRawMarkdownText_getsEscapedCharacterByCharacterOnSerialize() {
        let (editor, _) = makeWiredEditor()
        let url = URL(string: "file:///tmp/img_test.png")!
        let reference = MediaStore.markdownReference(for: url)
        XCTAssertEqual(reference, "![image](file:///tmp/img_test.png)", "prémisse du test : sinon la chaîne échappée ci-dessous ne correspond plus")

        editor.insertText("\n\(reference)\n", replacementRange: editor.selectedRange())

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "\n\\!\\[image\\]\\(file:///tmp/img\\_test.png\\)")
    }

    // MARK: - Fixtures

    /// Reproduit le câblage TextKit + coordinateur fait par
    /// `EditorRepresentable.makeNSView`, à la main : aucune
    /// `NSViewRepresentableContext` n'est constructible depuis un test.
    private func makeWiredEditor() -> (EditorTextView, EditorRepresentable.Coordinator) {
        var markdown = ""
        let binding = Binding<String>(get: { markdown }, set: { markdown = $0 })
        let representable = EditorRepresentable(
            markdown: binding,
            placeholder: "",
            features: Set<MarkdownFeature>.prep,
            debounce: 0,
            readOnly: false
        )
        let coordinator = representable.makeCoordinator()

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        editor.delegate = coordinator
        coordinator.textView = editor
        return (editor, coordinator)
    }

    /// Construit les octets d'un petit PNG valide via `NSBitmapImageRep`
    /// (repris de `Tests/StyleRendererTests.swift`).
    private func makeTemporaryPNGFile() throws -> URL {
        let bitmapRep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 10,
            pixelsHigh: 10,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmapRep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetoone-editortextview-paste-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
