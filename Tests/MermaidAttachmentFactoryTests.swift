import XCTest
import AppKit
@testable import OneToOne

final class MermaidAttachmentFactoryTests: XCTestCase {

    // MARK: - placeholder(for:)

    @MainActor
    func test_placeholder_hasNonNilImageAndPositiveBounds() {
        let attachment = MermaidAttachmentFactory.placeholder(for: "graph TD; A-->B")
        XCTAssertNotNil(attachment.image)
        XCTAssertGreaterThan(attachment.bounds.width, 0)
        XCTAssertGreaterThan(attachment.bounds.height, 0)
    }

    // MARK: - frameImage geometry (pitfall #4 : géométrie, pas juste « ça peint »)

    /// La présence d'un détail (message d'erreur) doit se traduire par un
    /// cadre plus haut — pas juste par du texte en plus qui déborderait du
    /// même cadre. Vérifie la géométrie réelle, pas seulement qu'un pixel a
    /// été peint (cf. piège mesuré n°4 : un glyphe rogné peint aussi).
    @MainActor
    func test_frameImage_withDetail_isTallerThanWithout() {
        let short = MermaidAttachmentFactory.frameImage(title: "Diagramme…", detail: nil, borderColor: .tertiaryLabelColor, titleColor: .secondaryLabelColor)
        let tall = MermaidAttachmentFactory.frameImage(title: "Diagramme invalide", detail: "Parse error on line 2", borderColor: .systemRed, titleColor: .systemRed)

        XCTAssertGreaterThan(tall.size.height, short.size.height)
        XCTAssertEqual(tall.size.width, short.size.width, "la largeur du cadre ne dépend pas du détail")
    }

    @MainActor
    func test_framedDiagram_usesTheSharedCardWidthAndAddsProfessionalInsets() {
        let diagram = NSImage(size: NSSize(width: 100, height: 40))

        let framed = MermaidAttachmentFactory.framedDiagram(diagram)

        XCTAssertEqual(framed.size.width, MermaidBlockLayout.columnWidth)
        XCTAssertEqual(
            framed.size.height,
            diagram.size.height + MermaidBlockLayout.verticalInset * 2
        )
    }

    @MainActor
    func test_framedDiagram_neverExceedsTheSharedCardWidth() {
        let diagram = NSImage(size: NSSize(width: 900, height: 300))

        let framed = MermaidAttachmentFactory.framedDiagram(diagram)

        XCTAssertEqual(framed.size.width, MermaidBlockLayout.columnWidth)
        XCTAssertGreaterThan(framed.size.height, MermaidBlockLayout.verticalInset * 2)
    }

    // MARK: - Le contrat central du palier : muter .image ne touche pas NSTextStorage

    /// Piège mesuré sur cette branche : remplacer l'image d'un attachment déjà
    /// posé dans le storage NE DOIT PAS déclencher d'édition de
    /// `NSTextStorage` (pas de pile d'annulation polluée, pas de sauvegarde
    /// déclenchée, pas de curseur qui saute). On le vérifie directement en
    /// observant `NSTextStorageDelegate.textStorage(_:didProcessEditing:...)`
    /// : muter `attachment.image`/`.bounds` hors de tout
    /// `replaceCharacters`/`addAttribute` sur le storage ne doit produire
    /// aucun appel à ce délégué.
    @MainActor
    func test_mutatingAttachmentImage_doesNotEditTextStorage() {
        final class EditRecorder: NSObject, NSTextStorageDelegate {
            var editCount = 0
            func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
                editCount += 1
            }
        }

        let storage = NSTextStorage(string: "\u{FFFC}")
        let attachment = NSTextAttachment()
        attachment.image = MermaidAttachmentFactory.frameImage(title: "Diagramme…", detail: nil, borderColor: .tertiaryLabelColor, titleColor: .secondaryLabelColor)
        storage.beginEditing()
        storage.addAttribute(.attachment, value: attachment, range: NSRange(location: 0, length: 1))
        storage.endEditing()

        let recorder = EditRecorder()
        storage.delegate = recorder

        // Mutation directe de l'attachment — le chemin emprunté par
        // `MermaidAttachmentFactory.render(...)` une fois le rendu prêt.
        let renderedImage = MermaidAttachmentFactory.frameImage(title: "Diagramme invalide", detail: "erreur", borderColor: .systemRed, titleColor: .systemRed)
        attachment.image = renderedImage
        attachment.bounds = NSRect(x: 0, y: 0, width: 42, height: 42)

        XCTAssertEqual(recorder.editCount, 0, "muter l'image/bounds d'un attachment ne doit déclencher aucune édition du storage")
        // Le caractère U+FFFC du storage reste inchangé : seule l'instance
        // d'attachment partagée a changé d'apparence.
        XCTAssertEqual(storage.string, "\u{FFFC}")
    }
}
