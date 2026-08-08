import XCTest
import AppKit
@testable import OneToOne

/// Réservation de la bande (en-tête + aperçu + `bodyTopPadding`) au-dessus du
/// source d'un bloc mermaid **ouvert**, quand ce bloc est le **premier** du
/// storage.
///
/// Défaut mesuré : TextKit 1 ignore `NSParagraphStyle.paragraphSpacingBefore`
/// sur le premier paragraphe du conteneur. Un `/diagramme` inséré en toute
/// première position ne réservait donc rien — en-tête et aperçu étaient
/// calculés à des `y` négatifs, hors clip (invisibles), et le bouton
/// « Terminé » (le seul geste qui referme un bloc) était incliquable.
///
/// Correctif : `MarkdownLayoutManager` est son propre `NSLayoutManagerDelegate`
/// et **relit** le `paragraphSpacingBefore` posé sur le storage pour le
/// renvoyer tel quel — la valeur du délégué *remplace* celle du style (doc
/// Apple), elle ne s'y ajoute pas, donc ce passe-plat est exactement
/// l'identité partout ailleurs. C'est ce que vérifie
/// `test_openMermaidBlock_precededByAParagraph_reservesTheBandExactlyOnce` :
/// une réservation doublée (2×) serait le défaut symétrique.
///
/// Tous ces tests partent d'une **mise en page réelle** (`ensureLayout`) et
/// comparent des sommets de texte (`lineFragmentUsedRect`) : les relations
/// algébriques pures ne peuvent pas attraper ce défaut-là.
final class MarkdownLayoutManagerParagraphSpacingTests: XCTestCase {

    private let containerWidth: CGFloat = 400

    // MARK: - Réservation

    /// Un bloc mermaid ouvert **en tête de storage** réserve bien la bande :
    /// le sommet de son texte descend d'exactement `paragraphSpacingBefore`
    /// sous le haut du conteneur.
    func test_openMermaidBlockAtStorageStart_reservesTheHeaderBand() throws {
        let fixture = try makeOpenMermaidBlock(markdown: "```mermaid\ngraph TD\nA-->B\n```\n\nsuite")

        XCTAssertGreaterThan(fixture.reservedBand, 0, "prémisse : la géométrie ouverte réserve une bande")
        XCTAssertEqual(
            fixture.sourceTextTop, fixture.reservedBand, accuracy: 0.001,
            "un bloc mermaid ouvert en tête de storage ne réserve rien : TextKit ignore "
            + "`paragraphSpacingBefore` sur le premier paragraphe du conteneur"
        )
    }

    /// … et un bloc **précédé** d'un paragraphe la réserve **une seule fois**
    /// (le défaut symétrique serait 2×, si la valeur du délégué s'ajoutait à
    /// celle de l'attribut au lieu de la remplacer).
    func test_openMermaidBlock_precededByAParagraph_reservesTheBandExactlyOnce() throws {
        let fixture = try makeOpenMermaidBlock(markdown: "intro\n\n```mermaid\ngraph TD\nA-->B\n```\n\nsuite")
        let previousBottom = try XCTUnwrap(fixture.previousBlockTextBottom)

        XCTAssertGreaterThan(fixture.reservedBand, 0, "prémisse : la géométrie ouverte réserve une bande")
        XCTAssertEqual(
            fixture.sourceTextTop - previousBottom, fixture.reservedBand, accuracy: 0.001,
            "la bande est réservée deux fois (délégué + attribut) ou pas du tout"
        )
    }

    // MARK: - Conséquence : « Terminé » cliquable

    /// Le bouton « Terminé » d'un bloc en tête tombe dans la bande réservée —
    /// donc dans le conteneur, donc cliquable. Sans réservation, son rect est
    /// calculé à un `y` négatif et aucun point de la vue ne peut l'atteindre.
    func test_doneButtonOfAHeadBlock_isHitTestable() throws {
        let fixture = try makeOpenMermaidBlock(markdown: "```mermaid\ngraph TD\nA-->B\n```\n\nsuite")

        let textBounds = MermaidSourceLayout.textBounds(
            forBlockRange: fixture.blockRange, layoutManager: fixture.layoutManager
        )
        let previewHeight = MermaidSourceLayout.previewHeight(
            in: fixture.storage, blockRange: fixture.blockRange, containerWidth: containerWidth
        )
        let buttonRect = MermaidSourceLayout.doneButtonRect(
            above: textBounds, containerWidth: containerWidth, previewHeight: previewHeight
        )

        XCTAssertGreaterThanOrEqual(
            buttonRect.minY, 0,
            "le bouton « Terminé » est peint au-dessus du haut du conteneur : hors clip, incliquable"
        )

        // Point de clic en coordonnées **vue** : l'inverse exact de la
        // conversion faite par `mermaidDoneButtonRange`.
        let inset = fixture.editor.textContainerInset
        let click = NSPoint(x: buttonRect.midX + inset.width, y: buttonRect.midY + inset.height)
        XCTAssertEqual(
            fixture.editor.mermaidDoneButtonRange(at: click), fixture.blockRange,
            "un clic au centre du bouton « Terminé » doit refermer le bloc"
        )
    }

    // MARK: - Fixture

    private struct OpenMermaidBlock {
        let storage: NSTextStorage
        let layoutManager: MarkdownLayoutManager
        let editor: EditorTextView
        let blockRange: NSRange
        /// `paragraphSpacingBefore` réellement posé par la géométrie ouverte.
        let reservedBand: CGFloat
        let sourceTextTop: CGFloat
        /// `nil` si le bloc est en tête de storage.
        let previousBlockTextBottom: CGFloat?
    }

    /// Monte un éditeur réel sur `markdown`, ouvre le bloc mermaid (curseur
    /// dedans) et pose la géométrie ouverte par le point d'entrée de test de
    /// `StyleRenderer` — jamais `applyVisualStyle`, qui lancerait un vrai
    /// `WKWebView` (voir la doc de tête de `StyleRendererMermaidTests`).
    private func makeOpenMermaidBlock(markdown: String) throws -> OpenMermaidBlock {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: containerWidth, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: containerWidth, height: 600), textContainer: container
        )

        let ns = storage.string as NSString
        let blockStart = ns.range(of: "graph TD").location
        guard blockStart != NSNotFound else { throw XCTSkip("bloc mermaid introuvable — prémisse de fixture non remplie") }
        var blockRange = NSRange(location: 0, length: 0)
        let blockType = storage.attribute(
            .mdBlockType, at: blockStart, longestEffectiveRange: &blockRange,
            in: NSRange(location: 0, length: storage.length)
        ) as? BlockType
        guard blockType == .codeBlock,
              storage.attribute(.mdCodeLanguage, at: blockStart, effectiveRange: nil) as? String == "mermaid"
        else { throw XCTSkip("bloc mermaid introuvable — prémisse de fixture non remplie") }

        let imageSize = NSSize(width: 300, height: 150)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = image
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: blockRange)

        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: blockRange,
            attachmentImageSize: imageSize, containerWidth: containerWidth
        )

        layoutManager.ensureLayout(for: container)

        let reservedBand = (storage.attribute(
            .paragraphStyle, at: blockRange.location, effectiveRange: nil
        ) as? NSParagraphStyle)?.paragraphSpacingBefore ?? 0

        let previousBottom: CGFloat?
        let introRange = ns.range(of: "intro")
        if introRange.location != NSNotFound {
            previousBottom = usedRect(at: introRange.location, layoutManager).maxY
        } else {
            previousBottom = nil
        }

        return OpenMermaidBlock(
            storage: storage,
            layoutManager: layoutManager,
            editor: editor,
            blockRange: blockRange,
            reservedBand: reservedBand,
            sourceTextTop: usedRect(at: blockRange.location, layoutManager).minY,
            previousBlockTextBottom: previousBottom
        )
    }

    /// Rect du **texte** de la ligne portant `location` — jamais son fragment,
    /// qui inclut justement la réservation que ces tests mesurent.
    private func usedRect(at location: Int, _ layoutManager: NSLayoutManager) -> NSRect {
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
    }
}
