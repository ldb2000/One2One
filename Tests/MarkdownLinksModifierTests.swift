import XCTest
import SwiftUI
@testable import OneToOne

/// Couvre `markdownLinks(handler:)` (`Modifiers.swift`) et son acheminement
/// jusqu'à `EditorRepresentable.linkHandler` via `MarkdownTextEditor.body`.
///
/// `EditorRepresentable.makeNSView`/`updateNSView` — l'endroit où
/// `linkHandler` est effectivement assigné à `EditorTextView.onLinkClick` —
/// ne sont volontairement pas exercés ici : ils prennent un
/// `NSViewRepresentableContext<Coordinator>`, non constructible depuis un
/// test (même contrainte déjà documentée en tête de `Tests/
/// EditorRepresentableMentionWiringTests.swift`, qui pour cette raison ne
/// teste pas non plus le rafraîchissement des closures de mentions à chaque
/// rendu). Ce fichier vérifie donc la couche juste en amont — que le
/// modificateur atteint bien `EditorRepresentable`, pas la couche
/// `NSViewRepresentable` elle-même — et `EditorTextView.onLinkClick`
/// (assignation directe, sans passer par `EditorRepresentable`) est déjà
/// couvert par `Tests/EditorTextViewLinkClickTests.swift`.
final class MarkdownLinksModifierTests: XCTestCase {

    func test_markdownLinks_reachesEditorRepresentable_throughBody() throws {
        var receivedURL: URL?
        let editor = MarkdownTextEditor(text: .constant("texte"))
            .markdownLinks { url in
                receivedURL = url
                return true
            }

        let representable = try XCTUnwrap(editor.body as? EditorRepresentable, "body doit rester un EditorRepresentable")
        let handled = representable.linkHandler?(URL(string: "onetoone://collaborator/abc")!)

        XCTAssertEqual(handled, true, "le résultat de la closure doit remonter tel quel")
        XCTAssertEqual(receivedURL, URL(string: "onetoone://collaborator/abc"), "l'URL cliquée doit être transmise inchangée")
    }

    /// Témoin : sans `markdownLinks(handler:)`, `linkHandler` doit rester
    /// `nil` — un éditeur qui ne configure pas le routage ne doit pas se
    /// comporter différemment d'avant cette fonctionnalité (tout lien
    /// s'ouvre par le système, voir `EditorTextView.clicked(onLink:at:)`).
    func test_withoutMarkdownLinks_linkHandlerStaysNil() throws {
        let editor = MarkdownTextEditor(text: .constant("texte"))

        let representable = try XCTUnwrap(editor.body as? EditorRepresentable)

        XCTAssertNil(representable.linkHandler)
    }

    /// `markdownLinks(handler:)` ne doit pas perturber les autres closures
    /// déjà acheminées de la même façon (mentions) — garde-fou contre une
    /// régression où le modificateur écraserait `mentionSearch`/`mentionCreate`
    /// au lieu de ne toucher que `linkHandler`.
    func test_markdownLinks_doesNotDisturbMentionHandlers() throws {
        let editor = MarkdownTextEditor(text: .constant("texte"))
            .markdownMentions(search: { _ in [] })
            .markdownLinks { _ in true }

        let representable = try XCTUnwrap(editor.body as? EditorRepresentable)

        XCTAssertNotNil(representable.mentionSearch)
        XCTAssertNotNil(representable.linkHandler)
    }
}
