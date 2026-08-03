import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre le mécanisme sur lequel s'appuie `EditorTextView.paste(_:)` :
/// insérer le placeholder produit par `EditorTextView.imagePlaceholder(for:)`
/// (même représentation que `MarkdownParser` — un caractère `U+FFFC` porteur
/// de `.mdImageURL`/`.mdImageAlt`) via `insertText(_:replacementRange:)`
/// déclenche-t-il, à travers le cycle `NSTextViewDelegate` de
/// `EditorRepresentable.Coordinator`, un rendu immédiat (sans frappe
/// supplémentaire) et une sérialisation correcte ?
///
/// `paste(_:)` lui-même n'est PAS appelé ici : il lit `NSPasteboard.general`,
/// l'état partagé de la machine qui exécute les tests, et je n'ai pas voulu y
/// écrire (voir la même décision documentée dans `MediaStoreTests`). Cette
/// classe appelle en revanche la fonction `imagePlaceholder(for:alt:)`
/// réellement utilisée par `paste(_:)`, ce qui couvre le mécanisme de rendu/
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

    /// Contre-preuve : insérer le texte brut `![alt](url)` (ce que ferait un
    /// `insertText` de chaîne littérale, comme dans `PastableMarkdownTextView`
    /// — approche volontairement écartée pour `EditorTextView`) ne produit
    /// aucun attachment, et la sérialisation échappe les caractères spéciaux
    /// au lieu de round-tripper vers une image. Documente pourquoi le
    /// placeholder attribué est nécessaire.
    func test_insertingRawMarkdownText_doesNotRenderAndGetsEscapedOnSerialize() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let (editor, _) = makeWiredEditor()

        let reference = MediaStore.markdownReference(for: imageURL)
        editor.insertText("\n\(reference)\n", replacementRange: editor.selectedRange())

        let attrsAtCharacterOne = editor.textStorage!.attributes(at: 1, effectiveRange: nil)
        XCTAssertNil(attrsAtCharacterOne[.attachment], "du texte brut ne porte pas mdImageURL, donc pas d'attachment")

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertNotEqual(
            serialized,
            "\n\(reference)",
            "sans attribut mdImageURL, MarkdownEscaping échappe les caractères spéciaux : la référence ne round-trippe pas telle quelle"
        )
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
