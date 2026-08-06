import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre le routage de clic sur un lien introduit par ce chantier :
/// `EditorTextView.clicked(onLink:at:)` (le point d'entrée qu'AppKit appelle
/// lui-même — voir son commentaire), et les deux méthodes internes qui
/// préservent le placement du curseur sur un simple clic en mode éditable
/// (`nativeLinkRange(at:)`, `suspendingNativeLink(in:_:)`).
///
/// `mouseDown(with:)` lui-même n'est pas exercé, pour la même raison que
/// documentée dans `Tests/EditorTextViewTaskToggleTests.swift` : construire
/// un `NSEvent` de clic dont `locationInWindow` traverse correctement
/// `convert(_:from:nil)` est fragile sans fenêtre réelle — et, mesuré lors
/// de la sonde jetable qui a précédé ce commit, `NSTextView.mouseDown`
/// entre de toute façon dans une boucle de tracking synchrone qui bloque le
/// process de test tant qu'aucun `mouseUp` n'est préposté sur la file
/// `NSApp`. Un clic réel dans une fenêtre affichée n'est donc pas couvert
/// par ces tests.
///
/// `clicked(onLink:at:)`, en revanche, est un point d'entrée testable
/// directement : c'est la méthode qu'AppKit appelle une fois qu'il a déjà
/// décidé qu'un clic visait un lien, sans avoir besoin de reconstruire
/// l'événement souris qui l'a déclenché.
final class EditorTextViewLinkClickTests: XCTestCase {

    /// Reproduit le câblage TextKit fait par `EditorRepresentable.makeNSView`
    /// (repris de `Tests/EditorTextViewTaskToggleTests.swift`), puis pose un
    /// lien `.mdLink`/`.link` sur `linkRange` via le pipeline réel
    /// (`StyleRenderer`), pour que `.link` soit posé comme en production —
    /// pas ajouté à la main dans le test.
    private func makeWiredEditor(text: String, linkRange: NSRange, url: URL) -> EditorTextView {
        let textStorage = NSTextStorage(string: text)
        textStorage.addAttribute(.mdLink, value: url, range: linkRange)
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)

        StyleRenderer.applyVisualStyle(to: textStorage)
        layoutManager.ensureLayout(for: container)
        return editor
    }

    /// Point (coordonnées de la vue) tombant au milieu du rectangle englobant
    /// `range`. Dérivé de la mise en page réelle, sur le même principe que
    /// `markerPoint` dans `EditorTextViewTaskToggleTests`.
    private func midPoint(of range: NSRange, in editor: EditorTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        return NSPoint(
            x: rect.midX + editor.textContainerInset.width,
            y: rect.midY + editor.textContainerInset.height
        )
    }

    // MARK: - clicked(onLink:at:)

    /// `openExternalLink` est substitué (voir sa doc dans `EditorTextView`)
    /// pour observer précisément si le fallback système est atteint, sans
    /// jamais réellement appeler `NSWorkspace` pendant les tests.
    func test_clickedOnLink_urlHandledByClosure_doesNotFallThroughToSystem() {
        let url = URL(string: "onetoone://collaborator/abc")!
        let editor = makeWiredEditor(text: "un lien", linkRange: NSRange(location: 3, length: 4), url: url)
        var received: URL?
        editor.onLinkClick = { clicked in
            received = clicked
            return true
        }
        var openedExternally: URL?
        editor.openExternalLink = { openedExternally = $0 }

        editor.clicked(onLink: url, at: 3)

        XCTAssertEqual(received, url, "la closure doit recevoir l'URL exacte du lien cliqué")
        XCTAssertNil(openedExternally, "un lien pris en charge par la closure ne doit pas retomber sur le système")
    }

    func test_clickedOnLink_closureDeclines_fallsThroughToSystem() {
        let url = URL(string: "https://example.com")!
        let editor = makeWiredEditor(text: "un lien", linkRange: NSRange(location: 3, length: 4), url: url)
        var callCount = 0
        editor.onLinkClick = { _ in
            callCount += 1
            return false
        }
        var openedExternally: URL?
        editor.openExternalLink = { openedExternally = $0 }

        editor.clicked(onLink: url, at: 3)

        XCTAssertEqual(callCount, 1, "la closure doit être appelée même si elle décline")
        XCTAssertEqual(openedExternally, url, "un lien décliné doit retomber sur le système")
    }

    func test_clickedOnLink_noClosureSet_fallsThroughToSystem() {
        let url = URL(string: "https://example.com")!
        let editor = makeWiredEditor(text: "un lien", linkRange: NSRange(location: 3, length: 4), url: url)
        var openedExternally: URL?
        editor.openExternalLink = { openedExternally = $0 }

        editor.clicked(onLink: url, at: 3)

        XCTAssertEqual(openedExternally, url, "sans closure, le lien doit retomber sur le système")
    }

    // La branche `guard let url = link as? URL else { super.clicked(...); return }`
    // (un `link` qui ne serait pas une `URL`) n'est volontairement pas
    // exercée par un test : ce cas retombe sur `super.clicked(onLink:at:)`,
    // comportement natif d'AppKit qu'on ne contrôle pas et dont on ignore ce
    // qu'il ferait concrètement d'une valeur non-`URL` (potentiellement une
    // vraie tentative d'ouverture système) — l'appeler pendant les tests
    // serait le même risque que `openExternalLink` a précisément été
    // introduit pour éviter. Cette branche reste couverte par relecture de
    // code uniquement : `StyleRenderer` ne pose jamais `.link` avec autre
    // chose qu'une `URL` (voir `StyleRendererTests`), donc en pratique ce
    // chemin n'est atteignable qu'en dehors du pipeline de ce chantier.

    // MARK: - nativeLinkRange(at:)

    func test_nativeLinkRange_atPointOverLink_returnsEffectiveRange() throws {
        let linkRange = NSRange(location: 3, length: 4)
        let editor = makeWiredEditor(text: "un lien", linkRange: linkRange, url: URL(string: "https://example.com")!)

        let point = try midPoint(of: linkRange, in: editor)
        let found = editor.nativeLinkRange(at: point)

        XCTAssertEqual(found, linkRange)
    }

    func test_nativeLinkRange_atPointAwayFromLink_returnsNil() throws {
        let linkRange = NSRange(location: 3, length: 4)
        let editor = makeWiredEditor(text: "un lien", linkRange: linkRange, url: URL(string: "https://example.com")!)

        let point = try midPoint(of: NSRange(location: 0, length: 2), in: editor)
        let found = editor.nativeLinkRange(at: point)

        XCTAssertNil(found)
    }

    // MARK: - suspendingNativeLink(in:_:)

    func test_suspendingNativeLink_removesDuringBody_andRestoresAfter() throws {
        let url = URL(string: "https://example.com")!
        let linkRange = NSRange(location: 3, length: 4)
        let editor = makeWiredEditor(text: "un lien", linkRange: linkRange, url: url)
        let storage = try XCTUnwrap(editor.textStorage)
        XCTAssertNotNil(storage.attribute(.link, at: 3, effectiveRange: nil), "prémisse : `.link` posé par StyleRenderer")

        var duringBody: URL?
        editor.suspendingNativeLink(in: linkRange) {
            duringBody = storage.attribute(.link, at: 3, effectiveRange: nil) as? URL
        }

        XCTAssertNil(duringBody, "`.link` doit être absent pendant `body`")
        XCTAssertEqual(
            storage.attribute(.link, at: 3, effectiveRange: nil) as? URL, url,
            "`.link` doit être restauré après `body`"
        )
        // `.mdLink`, la source de vérité markdown, n'a jamais dû bouger.
        XCTAssertEqual(storage.attribute(.mdLink, at: 3, effectiveRange: nil) as? URL, url)
    }

    func test_suspendingNativeLink_noLinkAtRange_stillRunsBody() throws {
        let editor = makeWiredEditor(
            text: "un lien", linkRange: NSRange(location: 3, length: 4), url: URL(string: "https://example.com")!
        )
        var bodyRan = false

        editor.suspendingNativeLink(in: NSRange(location: 0, length: 2)) {
            bodyRan = true
        }

        XCTAssertTrue(bodyRan)
    }
}
