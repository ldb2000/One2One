import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `MentionController` : détection du `@` selon le contexte,
/// extraction de la requête au fil de la frappe, filtrage/tri délégués à une
/// closure de recherche injectée, et insertion d'une mention (lien markdown)
/// sur un storage réel — même harnais que `Tests/SlashControllerTests.swift`
/// (`EditorTextView` + `Coordinator` câblés à la main), dont ce fichier
/// reprend la structure pour le problème symétrique.
///
/// `MentionPanel` n'est **pas** testable ici — pas de dépendance permettant
/// de piloter la vue SwiftUI qu'il héberge. Les tests ci-dessous vérifient le
/// comportement de `MentionController` par ses effets observables sur le
/// `NSTextStorage` et sur les closures injectées (`cancelPendingWrite`,
/// `searchCollaborators`, `createCollaborator`), jamais en lisant l'état
/// interne (privé) du panneau ou du contrôleur.
@MainActor
final class MentionControllerTests: XCTestCase {

    // MARK: - Détection pure du déclencheur (sans NSTextView)

    func test_isValidTriggerPosition_atStartOfDocument() {
        XCTAssertTrue(MentionController.isValidTriggerPosition(in: "@" as NSString, atLocation: 0))
    }

    func test_isValidTriggerPosition_afterNewline() {
        let text = "Ligne 1\n@reste" as NSString
        XCTAssertTrue(MentionController.isValidTriggerPosition(in: text, atLocation: 8))
    }

    func test_isValidTriggerPosition_afterSpace() {
        let text = "Hello @reste" as NSString
        XCTAssertTrue(MentionController.isValidTriggerPosition(in: text, atLocation: 6))
    }

    func test_isValidTriggerPosition_midWord_isRejected() {
        let text = "foo@bar" as NSString
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: 3))
    }

    /// Mesure directe du piège 5 de la spec : le `@` d'une adresse courriel
    /// tapée après une espace ne doit pas déclencher le panneau. Il est
    /// toujours précédé d'une lettre du nom d'utilisateur (ici "t" de
    /// "contact"), jamais d'une espace ni d'un début de ligne — la même règle
    /// que pour tout `@` en milieu de mot suffit donc, mesuré ici sur un cas
    /// réaliste plutôt que supposé.
    func test_isValidTriggerPosition_emailAddress_midWord_isRejected() {
        let text = "Écrire à contact@exemple.fr" as NSString
        let atLocation = text.range(of: "@").location
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: atLocation))
    }

    func test_isValidTriggerPosition_afterNonSpaceNonNewlineChar_isRejected() {
        let text = "**@x" as NSString
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: 2))
    }

    func test_isValidTriggerPosition_positionWithoutAtCharacter_isRejected() {
        let text = "hello" as NSString
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: 2))
    }

    func test_isValidTriggerPosition_outOfBounds_isRejected() {
        let text = "abc" as NSString
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: 10))
        XCTAssertFalse(MentionController.isValidTriggerPosition(in: text, atLocation: -1))
    }

    // MARK: - Extraction pure de la requête (sans NSTextView)

    func test_currentQuery_extractsTypedCharactersAfterAt() {
        let text = "@marie" as NSString
        XCTAssertEqual(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 6), "marie")
    }

    /// Différence assumée avec `SlashController.currentQuery` : une requête
    /// de mention filtre sur un nom complet, potentiellement composé de
    /// plusieurs mots (« Marie Dupont ») — les espaces y sont donc valides,
    /// contrairement à une requête de commande `/`.
    func test_currentQuery_allowsSpacesInQuery() {
        let text = "@Marie Dup" as NSString
        XCTAssertEqual(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 10), "Marie Dup")
    }

    func test_currentQuery_emptyRightAfterAt() {
        let text = "@" as NSString
        XCTAssertEqual(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 1), "")
    }

    func test_currentQuery_cursorAtOrBeforeAt_returnsNil() {
        let text = "@marie" as NSString
        XCTAssertNil(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 0))
    }

    func test_currentQuery_atNoLongerPresent_returnsNil() {
        let text = "marie" as NSString
        XCTAssertNil(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 5))
    }

    func test_currentQuery_newlineInQuery_returnsNil() {
        let text = "@ma\nrie" as NSString
        XCTAssertNil(MentionController.currentQuery(in: text, triggerLocation: 0, cursor: 7))
    }

    func test_currentQuery_triggerLocationOutOfBounds_returnsNil() {
        let text = "abc" as NSString
        XCTAssertNil(MentionController.currentQuery(in: text, triggerLocation: 10, cursor: 10))
    }

    // MARK: - Ouverture / fermeture sur un éditeur réel

    func test_typingAtSignAtStartOfLine_opensMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("@", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)
    }

    func test_typingAtSignMidWord_doesNotOpenMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("foo@bar", into: editor, controller: controller)
        XCTAssertFalse(controller.isOpen)
    }

    /// Bout en bout (piège 5) : taper une adresse courriel complète après une
    /// espace ne doit jamais ouvrir le panneau, même une fois le domaine tapé.
    func test_typingEmailAddress_afterSpace_doesNotOpenMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Écrire à contact@exemple.fr", into: editor, controller: controller)
        XCTAssertFalse(controller.isOpen)
    }

    func test_typingAtSignAfterSpace_opensMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Hello @", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)
    }

    func test_escape_closesMenu_keepingTheAtSignAndQueryInTheText() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("@mar", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        let handled = controller.handle(commandSelector: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(editor.textStorage?.string, "@mar", "Échap ne doit pas toucher au texte tapé")
    }

    func test_backspaceRemovingTheAtSign_closesMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("@", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        editor.deleteBackward(nil)
        let handled = controller.textDidChange()

        XCTAssertFalse(handled)
        XCTAssertFalse(controller.isOpen)
    }

    func test_movingSelectionOutsideTheQuery_closesMenu_viaSelectionDidChange() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("@mar", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        controller.selectionDidChange()

        XCTAssertFalse(controller.isOpen)
    }

    func test_movingSelectionInsideTheQuery_keepsMenuOpen() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("@marie", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        editor.setSelectedRange(NSRange(location: 3, length: 0)) // toujours dans "marie"
        controller.selectionDidChange()

        XCTAssertTrue(controller.isOpen, "un déplacement resté dans la requête ne doit pas fermer le menu")
    }

    // MARK: - Piège 2 : la requête ne doit jamais atteindre le binding débouncé

    func test_composingQuery_invokesCancelPendingWriteOnEveryKeystrokeOnceOpen() {
        let (editor, _) = makeWiredEditor(markdown: "")
        var cancelCount = 0
        let controller = MentionController(
            textView: editor,
            panel: MentionPanel(),
            cancelPendingWrite: { cancelCount += 1 },
            searchCollaborators: { _ in [] },
            createCollaborator: { _ in nil }
        )

        type("Hello ", into: editor, controller: controller) // 6 frappes, menu jamais ouvert
        XCTAssertEqual(cancelCount, 0)

        type("@ma", into: editor, controller: controller) // "@", "m", "a" : 3 frappes, menu ouvert dès la 1ère
        XCTAssertEqual(cancelCount, 3)
        XCTAssertTrue(controller.isOpen)
    }

    // MARK: - Application : sélection d'un candidat existant

    func test_selectingCandidate_insertsMarkdownLink_andClearsQuery() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie] })

        type("@mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let expected = "[@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
        XCTAssertFalse(controller.isOpen)
    }

    /// Contrairement à `SlashController.apply`, l'espace qui précède le `@`
    /// (validant le déclencheur) doit être **préservée** : ce n'est pas un
    /// espace résiduel de début de ligne, c'est le séparateur entre deux mots
    /// d'une même phrase.
    func test_selectingCandidate_afterOrdinaryWord_preservesTheSeparatingSpace() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie] })

        type("Bonjour @mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let expected = "Bonjour [@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
    }

    func test_insertedMention_roundTripsThroughMarkdownParserAndSerializer() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie] })

        type("Bonjour @mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized,
                       "la mention doit survivre à l'aller-retour markdown : \(serialized.debugDescription)")
    }

    // MARK: - Piège 1 : la mention n'hérite pas des attributs de frappe

    func test_insertingMention_afterInlineCode_doesNotInheritInlineCode() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "code", attributes: [.mdInlineCode: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = makeController(for: editor, search: { _ in [marie] })

        type(" @mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let storage = editor.textStorage!
        let mentionRange = (storage.string as NSString).range(of: "@Marie Dupont")
        XCTAssertNotEqual(mentionRange.location, NSNotFound, "prémisse : la mention doit avoir été insérée")
        for location in mentionRange.location..<(mentionRange.location + mentionRange.length) {
            XCTAssertNil(storage.attribute(.mdInlineCode, at: location, effectiveRange: nil),
                         "position \(location) de la mention hérite à tort de .mdInlineCode")
        }
    }

    func test_insertingMention_afterBold_doesNotInheritBold() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "bold", attributes: [.mdBold: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = makeController(for: editor, search: { _ in [marie] })

        type(" @mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let storage = editor.textStorage!
        let mentionRange = (storage.string as NSString).range(of: "@Marie Dupont")
        XCTAssertNotEqual(mentionRange.location, NSNotFound, "prémisse : la mention doit avoir été insérée")
        for location in mentionRange.location..<(mentionRange.location + mentionRange.length) {
            XCTAssertNil(storage.attribute(.mdBold, at: location, effectiveRange: nil),
                         "position \(location) de la mention hérite à tort de .mdBold")
        }
    }

    /// Le texte tapé **après** la mention ne doit pas continuer le lien —
    /// sans quoi tout ce qu'on tape ensuite deviendrait cliquable/mentionné.
    func test_typingRightAfterMention_doesNotContinueTheLink() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie] })

        type("@mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)
        editor.insertText(" merci", replacementRange: editor.selectedRange())

        let storage = editor.textStorage!
        let suffixRange = (storage.string as NSString).range(of: " merci")
        XCTAssertNotEqual(suffixRange.location, NSNotFound)
        XCTAssertNil(storage.attribute(.mdLink, at: suffixRange.location, effectiveRange: nil),
                     "le texte tapé après la mention ne doit pas continuer le lien")
    }

    /// Contrairement aux insertions de bloc de `SlashController` (séparateur,
    /// tableau), une mention est inline : le type de bloc/liste de la ligne
    /// courante doit survivre à l'insertion, pour la frappe qui suit.
    func test_insertingMention_insideListItem_subsequentTypingStaysInTheListItem() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let (editor, _) = makeWiredEditor(markdown: "- item")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        let controller = makeController(for: editor, search: { _ in [marie] })

        type(" @mar", into: editor, controller: controller)
        applySelectedEntry(controller: controller)
        editor.insertText(" suite", replacementRange: editor.selectedRange())

        XCTAssertEqual(
            MarkdownSerializer.serialize(editor.textStorage!),
            "- item [@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString)) suite",
            "la ligne doit rester un item de liste après la mention"
        )
    }

    // MARK: - Application : création d'un collaborateur inconnu

    func test_noMatch_selectingCreateEntry_callsCreateClosureWithTypedName_andInsertsResult() {
        let created = MentionCandidate(id: UUID(), name: "Nouveau Collab", role: "Architecte")
        var capturedName: String?
        let (editor, controller, _) = makeWiredController(
            markdown: "",
            search: { _ in [] },
            create: { name in
                capturedName = name
                return created
            }
        )

        type("@Nouveau Collab", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        XCTAssertEqual(capturedName, "Nouveau Collab")
        let expected = "[@Nouveau Collab](\(MentionCatalog.mentionURL(for: created.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
    }

    /// Le refus de la closure de création (`nil`) ne doit rien insérer —
    /// piège explicitement documenté par la spec.
    func test_createClosureReturningNil_insertsNothing() {
        let (editor, controller, _) = makeWiredController(
            markdown: "",
            search: { _ in [] },
            create: { _ in nil }
        )

        type("@Nouveau", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        XCTAssertEqual(editor.textStorage?.string, "", "un refus de création ne doit rien insérer")
    }

    /// Taper le nom exact d'un collaborateur existant ne doit **pas**
    /// proposer l'entrée « Créer … » (`MentionCatalogTests` le couvre déjà en
    /// pur) : ⏎ doit alors sélectionner ce candidat, jamais appeler la
    /// closure de création.
    func test_exactMatch_enterAppliesTheOnlyCandidate_notCreate() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        var createWasCalled = false
        let (editor, controller, _) = makeWiredController(
            markdown: "",
            search: { _ in [marie] },
            create: { name in
                createWasCalled = true
                return MentionCandidate(id: UUID(), name: name, role: "")
            }
        )

        type("@Marie Dupont", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        XCTAssertFalse(createWasCalled, "aucune correspondance exacte ne doit déclencher la création")
        let expected = "[@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
    }

    // MARK: - Rafraîchissement des closures (`EditorRepresentable.updateNSView`)

    /// Le mécanisme derrière la doc de `MentionController.updateHandlers` :
    /// une nouvelle paire de closures doit remplacer l'ancienne pour de vrai,
    /// pas seulement être acceptée sans effet. `EditorRepresentable.
    /// updateNSView` (non testable directement, `Context` non constructible —
    /// voir `Tests/EditorRepresentableMentionWiringTests.swift`) appelle
    /// cette méthode à chaque rendu SwiftUI ; c'est ce point précis que ce
    /// test couvre, indépendamment du reste du câblage.
    func test_updateHandlers_replacesSearchAndCreateClosures() {
        let alice = MentionCandidate(id: UUID(), name: "Alice", role: "")
        let bob = MentionCandidate(id: UUID(), name: "Bob", role: "")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [alice] })

        controller.updateHandlers(searchCollaborators: { _ in [bob] }, createCollaborator: { _ in nil })

        type("@b", into: editor, controller: controller)
        applySelectedEntry(controller: controller)

        let expected = "[@Bob](\(MentionCatalog.mentionURL(for: bob.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected,
                       "la recherche doit utiliser la closure la plus récente (Bob), pas celle capturée à l'init (Alice)")
    }

    // MARK: - Navigation clavier

    func test_arrowDown_thenEnter_appliesTheSecondCandidate() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let marc = MentionCandidate(id: UUID(), name: "Marc Martin", role: "Chef de projet")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie, marc] })

        type("@ma", into: editor, controller: controller)
        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.moveDown(_:))))
        applySelectedEntry(controller: controller)

        let expected = "[@Marc Martin](\(MentionCatalog.mentionURL(for: marc.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
    }

    func test_arrowUp_atTop_staysClamped_appliesFirstCandidate() {
        let marie = MentionCandidate(id: UUID(), name: "Marie Dupont", role: "Architecte")
        let marc = MentionCandidate(id: UUID(), name: "Marc Martin", role: "Chef de projet")
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [marie, marc] })

        type("@ma", into: editor, controller: controller)
        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.moveUp(_:)))) // déjà en haut
        applySelectedEntry(controller: controller)

        let expected = "[@Marie Dupont](\(MentionCatalog.mentionURL(for: marie.id).absoluteString))"
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
    }

    /// Requête vide (juste après « @ »), aucun candidat : ⏎ ne doit ni
    /// planter ni toucher au texte — le menu reste ouvert.
    func test_enterWithNoRows_doesNothing() {
        let (editor, controller, _) = makeWiredController(markdown: "", search: { _ in [] })
        type("@", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        let handled = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled, "la touche est consommée (le menu est ouvert) même si rien n'est appliqué")
        XCTAssertEqual(editor.textStorage?.string, "@")
        XCTAssertTrue(controller.isOpen)
    }

    // MARK: - Fixtures

    /// Reproduit le câblage TextKit + coordinateur fait par
    /// `EditorRepresentable.makeNSView`, à la main — repris de
    /// `Tests/SlashControllerTests.swift`.
    private func makeWiredEditor(markdown: String) -> (EditorTextView, EditorRepresentable.Coordinator) {
        var text = markdown
        let binding = Binding<String>(get: { text }, set: { text = $0 })
        let representable = EditorRepresentable(
            markdown: binding,
            placeholder: "",
            features: Set<MarkdownFeature>.full,
            debounce: 0,
            readOnly: false
        )
        let coordinator = representable.makeCoordinator()

        let textStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: 1_000_000))
        layoutManager.addTextContainer(container)
        let editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100), textContainer: container)
        editor.delegate = coordinator
        coordinator.textView = editor

        let parsed = MarkdownParser.parse(markdown)
        textStorage.setAttributedString(parsed)
        StyleRenderer.applyVisualStyle(to: textStorage)
        layoutManager.ensureLayout(for: container)
        editor.setSelectedRange(NSRange(location: textStorage.length, length: 0))

        return (editor, coordinator)
    }

    /// `MentionController` prêt à l'emploi, avec `cancelPendingWrite` inerte
    /// et des closures de recherche/création injectables (par défaut : aucun
    /// candidat, création toujours refusée).
    private func makeController(
        for editor: EditorTextView,
        search: @escaping (String) -> [MentionCandidate] = { _ in [] },
        create: @escaping (String) -> MentionCandidate? = { _ in nil }
    ) -> MentionController {
        MentionController(
            textView: editor,
            panel: MentionPanel(),
            cancelPendingWrite: {},
            searchCollaborators: search,
            createCollaborator: create
        )
    }

    private func makeWiredController(
        markdown: String,
        search: @escaping (String) -> [MentionCandidate] = { _ in [] },
        create: @escaping (String) -> MentionCandidate? = { _ in nil }
    ) -> (EditorTextView, MentionController, EditorRepresentable.Coordinator) {
        let (editor, coordinator) = makeWiredEditor(markdown: markdown)
        return (editor, makeController(for: editor, search: search, create: create), coordinator)
    }

    /// Simule une frappe caractère par caractère, comme `Tests/
    /// SlashControllerTests.swift.type(_:into:controller:)`.
    private func type(_ text: String, into editor: EditorTextView, controller: MentionController) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            controller.textDidChange()
        }
    }

    /// Simule ⏎ pour appliquer l'entrée actuellement sélectionnée — l'API
    /// publique de `MentionController` ne permet rien d'autre (pas de lecture
    /// de son état interne, privé), même choix que `SlashControllerTests.
    /// applySelectedCommand`.
    private func applySelectedEntry(controller: MentionController) {
        _ = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))
    }
}
