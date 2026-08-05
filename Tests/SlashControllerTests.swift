import XCTest
import AppKit
import SwiftUI
@testable import OneToOne

/// Couvre `SlashController` : détection du `/` selon le contexte, extraction
/// de la requête au fil de la frappe, et application de chaque type de
/// commande sur un storage réel (via un `EditorTextView` + `Coordinator`
/// câblés à la main, sur le modèle de `Tests/EditorTextViewPasteTests.swift`
/// et `Tests/EditorTextViewTaskToggleTests.swift`).
///
/// `SlashPanel` (tâche 4) n'est **pas** testable ici — pas de dépendance
/// permettant de piloter la vue SwiftUI qu'il héberge. Les tests ci-dessous
/// n'inspectent jamais son contenu affiché ; ils vérifient le comportement
/// de `SlashController` par ses effets observables sur le `NSTextStorage`
/// (ce qui a été appliqué) et sur les fermetures injectées (`cancelPendingWrite`,
/// `presentImagePicker`), jamais en lisant l'état interne du panneau.
///
/// Le câblage réel dans `Coordinator` (tâche 6) n'existe pas encore : ces
/// tests appellent donc `controller.textDidChange()` / `.handle(commandSelector:)`
/// à la main, à la place de l'appel que la tâche 6 fera depuis
/// `Coordinator.textDidChange` / `textView(_:doCommandBy:)`. `EditorTextView.delegate`
/// reste branché sur un vrai `Coordinator` dans tous ces tests, donc les
/// effets de bord réels de `Coordinator.textDidChange` (non modifié — pas
/// encore court-circuité) s'exécutent pour de vrai à chaque `insertText`
/// que `SlashController` déclenche, exactement comme en production.
@MainActor
final class SlashControllerTests: XCTestCase {

    // MARK: - Détection pure du déclencheur (sans NSTextView)

    func test_isValidTriggerPosition_atStartOfDocument() {
        XCTAssertTrue(SlashController.isValidTriggerPosition(in: "/" as NSString, slashLocation: 0))
    }

    func test_isValidTriggerPosition_afterNewline() {
        let text = "Ligne 1\n/reste" as NSString
        XCTAssertTrue(SlashController.isValidTriggerPosition(in: text, slashLocation: 8))
    }

    func test_isValidTriggerPosition_afterSpace() {
        let text = "Hello /reste" as NSString
        XCTAssertTrue(SlashController.isValidTriggerPosition(in: text, slashLocation: 6))
    }

    func test_isValidTriggerPosition_midWord_isRejected() {
        let text = "foo/bar" as NSString
        XCTAssertFalse(SlashController.isValidTriggerPosition(in: text, slashLocation: 3))
    }

    func test_isValidTriggerPosition_afterNonSpaceNonNewlineChar_isRejected() {
        let text = "**/x" as NSString
        XCTAssertFalse(SlashController.isValidTriggerPosition(in: text, slashLocation: 2))
    }

    func test_isValidTriggerPosition_positionWithoutSlashCharacter_isRejected() {
        let text = "hello" as NSString
        XCTAssertFalse(SlashController.isValidTriggerPosition(in: text, slashLocation: 2))
    }

    func test_isValidTriggerPosition_outOfBounds_isRejected() {
        let text = "abc" as NSString
        XCTAssertFalse(SlashController.isValidTriggerPosition(in: text, slashLocation: 10))
        XCTAssertFalse(SlashController.isValidTriggerPosition(in: text, slashLocation: -1))
    }

    // MARK: - Extraction pure de la requête (sans NSTextView)

    func test_currentQuery_extractsTypedCharactersAfterSlash() {
        let text = "/head" as NSString
        XCTAssertEqual(SlashController.currentQuery(in: text, triggerLocation: 0, cursor: 5), "head")
    }

    func test_currentQuery_emptyRightAfterSlash() {
        let text = "/" as NSString
        XCTAssertEqual(SlashController.currentQuery(in: text, triggerLocation: 0, cursor: 1), "")
    }

    func test_currentQuery_cursorAtOrBeforeSlash_returnsNil() {
        let text = "/head" as NSString
        XCTAssertNil(SlashController.currentQuery(in: text, triggerLocation: 0, cursor: 0))
    }

    func test_currentQuery_slashNoLongerPresent_returnsNil() {
        // Simule un `⌫` qui a supprimé le "/" : le caractère à `triggerLocation`
        // n'en est plus un.
        let text = "head" as NSString
        XCTAssertNil(SlashController.currentQuery(in: text, triggerLocation: 0, cursor: 4))
    }

    func test_currentQuery_newlineInQuery_returnsNil() {
        let text = "/he\nad" as NSString
        XCTAssertNil(SlashController.currentQuery(in: text, triggerLocation: 0, cursor: 6))
    }

    func test_currentQuery_triggerLocationOutOfBounds_returnsNil() {
        let text = "abc" as NSString
        XCTAssertNil(SlashController.currentQuery(in: text, triggerLocation: 10, cursor: 10))
    }

    // MARK: - Ouverture / fermeture sur un éditeur réel

    func test_typingSlashAtStartOfLine_opensMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)
    }

    func test_typingSlashMidWord_doesNotOpenMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("foo/bar", into: editor, controller: controller)
        XCTAssertFalse(controller.isOpen)
    }

    func test_typingSlashAfterSpace_opensMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Hello /", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)
    }

    func test_escape_closesMenu_keepingTheSlashAndQueryInTheText() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/head", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        let handled = controller.handle(commandSelector: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(controller.isOpen)
        XCTAssertEqual(editor.textStorage?.string, "/head", "Échap ne doit pas toucher au texte tapé")
    }

    func test_backspaceRemovingTheSlash_closesMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        // `⌫` n'est pas intercepté par `handle(commandSelector:)` (comportement
        // par défaut laissé à `NSTextView`) : on simule directement la
        // suppression, puis l'appel à `textDidChange()` que la tâche 6 fera
        // après coup.
        editor.deleteBackward(nil)
        let handled = controller.textDidChange()

        XCTAssertFalse(handled)
        XCTAssertFalse(controller.isOpen)
    }

    /// Variante du test précédent où le texte restant après coup ne rend
    /// invalides ni `triggerLocation` (toujours dans les bornes) ni `cursor`
    /// (toujours `>= triggerLocation + 1`) — seule la vérification « le
    /// caractère à `triggerLocation` est encore `"/"` » peut détecter
    /// l'incohérence. Simulé par une sélection couvrant le `/` et le début de
    /// la requête, remplacée d'un coup par un caractère de texte ordinaire
    /// (ex. sélectionner "/h" puis taper "x" par-dessus) : `triggerLocation`
    /// (0) reste dans les bornes du texte résultant, `cursor` (1) reste
    /// `>= triggerLocation + 1`, mais le caractère à `triggerLocation` est
    /// désormais `"x"`. Mesuré par mutation : sans cette variante,
    /// `test_backspaceRemovingTheSlash_closesMenu` (qui tape seulement `"/"`,
    /// sans rien après) ne peut être fermée que par la garde « `triggerLocation`
    /// désormais hors bornes » — neutraliser la garde sur le caractère lui-même
    /// ne faisait alors échouer aucun test.
    func test_replacingTheSlashWithOrdinaryText_closesMenu() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/head", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        editor.insertText("x", replacementRange: NSRange(location: 0, length: 2)) // remplace "/h" par "x"
        XCTAssertEqual(editor.textStorage?.string, "xead")

        let handled = controller.textDidChange()

        XCTAssertFalse(handled)
        XCTAssertFalse(controller.isOpen)
    }

    func test_movingSelectionOutsideTheQuery_closesMenu_viaSelectionDidChange() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/head", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        // Clic ailleurs / flèche qui sort de la plage de la requête : simulé
        // par un déplacement direct du curseur avant le "/".
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        controller.selectionDidChange()

        XCTAssertFalse(controller.isOpen)
    }

    func test_movingSelectionInsideTheQuery_keepsMenuOpen() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/head", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        editor.setSelectedRange(NSRange(location: 3, length: 0)) // toujours dans "head"
        controller.selectionDidChange()

        XCTAssertTrue(controller.isOpen, "un déplacement resté dans la requête ne doit pas fermer le menu")
    }

    // MARK: - Piège 1 : la requête ne doit jamais atteindre le binding débouncé

    /// Preuve directe : `cancelPendingWrite` (injecté, ici une espionne plutôt
    /// que le vrai `Coordinator.cancelPendingWrite`, pour rester synchrone et
    /// déterministe — pas de dépendance à un vrai délai `Task.sleep`) doit
    /// être invoqué à chaque frappe tant que le menu reste ouvert, et
    /// seulement à partir du `/` qui l'ouvre — pas avant.
    func test_composingQuery_invokesCancelPendingWriteOnEveryKeystrokeOnceOpen() {
        let (editor, _) = makeWiredEditor(markdown: "")
        var cancelCount = 0
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: { cancelCount += 1 },
            presentImagePicker: { $0(nil) }
        )

        type("Hello ", into: editor, controller: controller) // 6 frappes, menu jamais ouvert
        XCTAssertEqual(cancelCount, 0)

        type("/h1", into: editor, controller: controller) // "/", "h", "1" : 3 frappes, menu ouvert dès la 1ère
        XCTAssertEqual(cancelCount, 3)
        XCTAssertTrue(controller.isOpen)
    }

    // MARK: - Application : conversions de bloc

    func test_applyingHeading1_onNonEmptyLine_convertsExistingContentAndClearsQuery() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Hello /h1", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        applySelectedCommand(.heading1, controller: controller)

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "# Hello")
        XCTAssertFalse(controller.isOpen)
    }

    /// Distinct du test précédent : celui-ci vérifie que `didChangeText()`
    /// est bien appelé après la mutation d'attributs de
    /// `applyBlockConversion` (branche ligne non vide), et pas seulement que
    /// le storage a changé. `MarkdownSerializer.serialize(editor.textStorage!)`
    /// lit le storage directement — il refléterait le bon résultat même sans
    /// `didChangeText()`, puisque `MarkdownBlockCommands.setBlockType` mute
    /// déjà le storage réel. `coordinator.lastKnownMarkdown` en revanche n'est
    /// mis à jour que par un vrai passage dans `Coordinator.textDidChange`,
    /// déclenché par `didChangeText()` — updated synchrone, sans dépendre du
    /// debounce asynchrone. Mesuré par mutation : supprimer l'appel à
    /// `didChangeText()` dans `applyBlockConversion` ne faisait échouer aucun
    /// test avant l'ajout de celui-ci.
    func test_applyingHeading_onNonEmptyLine_notifiesCoordinatorSynchronously() {
        let (editor, controller, coordinator) = makeWiredController(markdown: "")
        type("Hello /h1", into: editor, controller: controller)

        applySelectedCommand(.heading1, controller: controller)

        XCTAssertEqual(
            coordinator.lastKnownMarkdown, "# Hello",
            "didChangeText() doit notifier synchrone le Coordinator, pas seulement muter le storage"
        )
    }

    func test_applyingHeading2_onEmptyLine_primesTypingAttributesForNextKeystroke() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/h2", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        applySelectedCommand(.heading2, controller: controller)

        // Rien à styler tout de suite (ligne vide) : c'est la frappe SUIVANTE
        // qui doit porter `.mdBlockType = .h2`, via `typingAttributes` amorcé
        // par `SlashController` — pas `MarkdownBlockCommands.setBlockType`,
        // qui ne fait rien sur une plage de longueur 0 (mesuré).
        editor.insertText("Titre", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "## Titre")
    }

    func test_applyingBlockquote_onEmptyLine_primesTypingAttributes() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/citation", into: editor, controller: controller)

        applySelectedCommand(.blockquote, controller: controller)
        editor.insertText("dit quelque chose", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "> dit quelque chose")
    }

    func test_applyingText_revertsAnExistingHeadingBackToParagraph() {
        // "Texte" (le paragraphe) est modélisé comme `.convertBlock(.paragraph)`
        // — même mécanisme que les titres, exercé ici sur une ligne déjà
        // stylée pour vérifier que la conversion s'applique bien aux
        // caractères existants (pas seulement au cas ligne vide). Le `/`
        // est tapé en tout début de ligne (déclencheur valide sans espace à
        // ajouter) pour que l'effacement de la requête restitue exactement
        // le contenu existant, sans espace résiduel à comptabiliser.
        let (editor, _) = makeWiredEditor(markdown: "## Déjà un titre")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let controller = makeController(for: editor)

        type("/texte", into: editor, controller: controller)
        applySelectedCommand(.text, controller: controller)

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "Déjà un titre")
    }

    // MARK: - Application : listes

    func test_applyingBulletList_onEmptyLine() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/puce", into: editor, controller: controller)

        applySelectedCommand(.bulletList, controller: controller)
        editor.insertText("item", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "- item")
    }

    func test_applyingOrderedList_onEmptyLine() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/numerotee", into: editor, controller: controller)

        applySelectedCommand(.orderedList, controller: controller)
        editor.insertText("item", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "1. item")
    }

    func test_applyingTaskList_onEmptyLine_startsUnchecked() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/todo", into: editor, controller: controller)

        applySelectedCommand(.taskList, controller: controller)
        editor.insertText("à faire", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "- [ ] à faire")
    }

    // MARK: - Application : séparateur (insertion, pas conversion)

    func test_applyingThematicBreak_insertsANewLine_withoutErasingCursorLineContent() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Avant /sep", into: editor, controller: controller)

        applySelectedCommand(.thematicBreak, controller: controller)
        editor.insertText("Après", replacementRange: editor.selectedRange())

        // La ligne du curseur ("Avant") garde son contenu ; le séparateur est
        // une insertion distincte, pas une conversion de cette ligne (refusée
        // par `MarkdownBlockCommands` depuis f20b979). Une ligne vide sépare
        // "Avant" du séparateur (paire paragraphe→séparateur, à risque —
        // tâche 1) mais pas "---" d'"Après" (paire non listée dans
        // `needsBlankLine`, donc pas de ligne vide de ce côté).
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "Avant\n\n---\nAprès")

        // Round-trip : le séparateur survit au reparse.
        let reparsed = MarkdownParser.parse(MarkdownSerializer.serialize(editor.textStorage!))
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), MarkdownSerializer.serialize(editor.textStorage!))
    }

    // MARK: - Application : image

    func test_applyingImage_opensPickerAndInsertsPlaceholderOnChosenURL() throws {
        let imageURL = try makeTemporaryPNGFile()
        defer { try? FileManager.default.removeItem(at: imageURL) }
        ImageAttachmentFactory.invalidate()
        defer { ImageAttachmentFactory.invalidate() }

        let (editor, _) = makeWiredEditor(markdown: "")
        var pickerWasInvoked = false
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { completion in
                pickerWasInvoked = true
                completion(imageURL)
            }
        )

        type("/image", into: editor, controller: controller)
        applySelectedCommand(.image, controller: controller)

        XCTAssertTrue(pickerWasInvoked)
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "\n![image](\(imageURL.absoluteString))")
    }

    func test_applyingImage_pickerCancelled_insertsNothing() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { completion in completion(nil) }
        )

        type("/image", into: editor, controller: controller)
        applySelectedCommand(.image, controller: controller)

        XCTAssertEqual(editor.textStorage?.string, "", "annulation du sélecteur : rien ne doit être inséré")
    }

    // MARK: - Navigation clavier (↑ ↓ changent l'entrée que ⏎ applique)

    func test_arrowDown_thenEnter_appliesTheNextEntryInDeclaredOrder() {
        // Catalogue filtré par "titre" (voir `SlashCatalogTests`) : Titre 1,
        // Titre 2, Titre 3 dans cet ordre. Naviguer une fois vers le bas doit
        // donc désigner Titre 2, sans qu'on ait besoin de lire l'état interne
        // (privé) du panneau — l'entrée effectivement appliquée en fait foi.
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/titre", into: editor, controller: controller)

        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:))))
        // La ligne était vide : rien à styler tout de suite (cf.
        // `applyBlockConversion`) — c'est la frappe suivante qui doit porter
        // `.mdBlockType = .h2`.
        editor.insertText("Deux", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "## Deux")
    }

    /// Aucune entrée ne correspond : ⏎ ne doit ni planter (garde de bornes
    /// sur `flatCommands`, vide ici) ni toucher au texte — le menu reste
    /// ouvert, affichant « Aucun résultat » (`SlashPanel`, non vérifié ici).
    func test_enterWithNoMatchingResults_doesNothing() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/zzzznomatch", into: editor, controller: controller)
        XCTAssertTrue(controller.isOpen)

        let handled = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled, "la touche est consommée (le menu est ouvert) même si rien n'est appliqué")
        XCTAssertEqual(editor.textStorage?.string, "/zzzznomatch")
        XCTAssertTrue(controller.isOpen, "aucune sélection valide à appliquer : le menu ne se ferme pas")
    }

    func test_arrowUp_atTop_staysClamped_appliesFirstEntry() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/titre", into: editor, controller: controller)

        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.moveUp(_:)))) // déjà en haut, ne déborde pas
        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.insertTab(_:))))
        editor.insertText("Un", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "# Un")
    }

    // MARK: - Piège 3 : pas de raccourci inline parasite au moment d'appliquer

    /// Mesure directe du piège annoncé : un `` ` `` non refermé plus tôt dans
    /// le document, suivi d'une conversion de bloc juste après une espace
    /// (déclencheur valide). Si l'effacement de la requête (`insertText("",
    /// replacementRange:)`, qui redéclenche pour de vrai `ShortcutDetector`
    /// via le `Coordinator` câblé) réintroduisait le caractère précédant le
    /// curseur comme `` ` ``/`*`/`_`, ce backtick isolé se retrouverait
    /// apparié à tort. Le déclencheur exige un espace ou un début de ligne
    /// juste avant le `/` (jamais un de ces trois marqueurs) : ce test vérifie
    /// que ça suffit en pratique, pas seulement en théorie.
    func test_applyingCommand_afterUnmatchedBacktickEarlierInDocument_doesNotTriggerInlineCode() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Note `pas fermé et texte /h1", into: editor, controller: controller)

        applySelectedCommand(.heading1, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        // Le backtick littéral (non apparié à un `.mdInlineCode`) est échappé
        // par le sérialiseur (`MarkdownEscaping.inlineSpecials` contient
        // `` ` ``) — c'est cette forme échappée, round-trippable, qui prouve
        // qu'aucun raccourci parasite ne l'a transformé en code inline.
        XCTAssertEqual(serialized, "# Note \\`pas fermé et texte")
        // Un appariement parasite aurait avalé le texte entre les deux
        // occurrences de `` ` `` dans du code inline (`` ` ``…`` ` ``) : il
        // n'y a ici qu'un seul backtick, donc rien à apparier — le round-trip
        // exact ci-dessus suffit déjà à le prouver, cette assertion
        // supplémentaire documente l'absence explicite d'attribut de code.
        let backtickLocation = (editor.textStorage!.string as NSString).range(of: "`").location
        XCTAssertNotEqual(backtickLocation, NSNotFound)
        XCTAssertNil(editor.textStorage!.attribute(.mdInlineCode, at: backtickLocation, effectiveRange: nil))
    }

    // MARK: - Piège 4 : le Retour après un titre revient au paragraphe

    func test_returnAfterHeading_revertsToParagraph_forSubsequentTyping() {
        // Reproduit exactement la mesure du plan : "## Titre" + ⏎ + "corps".
        let (editor, _) = makeWiredEditor(markdown: "## Titre")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        let controller = makeController(for: editor)

        let handled = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(handled, "doit être traité par le contrôleur, pas laissé au comportement par défaut")
        editor.insertText("corps", replacementRange: editor.selectedRange())

        XCTAssertEqual(
            MarkdownSerializer.serialize(editor.textStorage!), "## Titre\ncorps",
            "« corps » doit être un paragraphe distinct, pas un second titre"
        )
    }

    /// Témoin : sans passer par `controller.handle(...)`, l'action standard
    /// `insertNewline` d'`NSTextView` reproduit bien le bug mesuré — sans ce
    /// test, `test_returnAfterHeading_revertsToParagraph_forSubsequentTyping`
    /// pourrait passer pour une tout autre raison (ex. si plus rien ne
    /// portait jamais `.mdBlockType` du tout).
    func test_witness_defaultInsertNewline_withoutController_propagatesHeadingType() {
        let (editor, _) = makeWiredEditor(markdown: "## Titre")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))

        editor.insertNewline(nil)
        editor.insertText("corps", replacementRange: editor.selectedRange())

        XCTAssertEqual(
            MarkdownSerializer.serialize(editor.textStorage!), "## Titre\n## corps",
            "témoin : reproduit le bug mesuré par le plan en l'absence du correctif"
        )
    }

    func test_returnAfterHeading_withNonEmptySelection_isNotHandled_fallsBackToDefault() {
        let (editor, _) = makeWiredEditor(markdown: "## Titre")
        editor.setSelectedRange(NSRange(location: 3, length: 2)) // sélectionne "Ti"
        let controller = makeController(for: editor)

        let handled = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(handled, "cas non mesuré (sélection non vide) : laissé au comportement par défaut")
    }

    func test_returnAfterParagraph_isNotHandled_listBehaviorUntouched() {
        let (editor, _) = makeWiredEditor(markdown: "Simple paragraphe")
        editor.setSelectedRange(NSRange(location: editor.textStorage!.length, length: 0))
        let controller = makeController(for: editor)

        let handled = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))

        XCTAssertFalse(handled, "un paragraphe ordinaire n'est pas concerné par ce correctif")
    }

    // MARK: - Fixtures

    /// Reproduit le câblage TextKit + coordinateur fait par
    /// `EditorRepresentable.makeNSView`, à la main (repris de
    /// `Tests/EditorTextViewTaskToggleTests.swift`) : charge `markdown` via le
    /// pipeline réel (`MarkdownParser` + `StyleRenderer`) pour que
    /// `.mdBlockType`/`.mdListInfo` soient posés comme en production, avec un
    /// `Coordinator` réellement branché comme délégué (voir la doc de tête de
    /// fichier sur ce que ça implique pour ces tests).
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

    /// `SlashController` prêt à l'emploi pour `editor`, avec des fermetures
    /// injectées inertes (`cancelPendingWrite` ne fait rien — hors de portée
    /// des tests qui n'en ont pas besoin ; `presentImagePicker` répond
    /// immédiatement `nil`, comme un utilisateur qui annule).
    private func makeController(for editor: EditorTextView) -> SlashController {
        SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) }
        )
    }

    /// Combine `makeWiredEditor` et `makeController` — le cas courant des
    /// tests de ce fichier, qui démarrent d'un éditeur vide.
    private func makeWiredController(markdown: String) -> (EditorTextView, SlashController, EditorRepresentable.Coordinator) {
        let (editor, coordinator) = makeWiredEditor(markdown: markdown)
        return (editor, makeController(for: editor), coordinator)
    }

    /// Simule une frappe caractère par caractère : chaque caractère passe par
    /// `insertText` (déclenche vraiment le cycle délégué du `Coordinator`,
    /// comme une vraie frappe), suivi de l'appel à `controller.textDidChange()`
    /// que la tâche 6 doit câbler au même endroit. Insérer la chaîne entière
    /// d'un coup ne reproduirait pas cette granularité et masquerait des bugs
    /// de détection propres à la frappe caractère par caractère (ouverture
    /// détectée trop tard, par exemple).
    private func type(_ text: String, into editor: EditorTextView, controller: SlashController) {
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            controller.textDidChange()
        }
    }

    /// Simule ⏎ pour appliquer l'entrée actuellement sélectionnée — l'API
    /// publique de `SlashController` ne permet rien d'autre (pas de lecture
    /// de son état interne, privé). Chaque appelant de cette fonction a
    /// composé une requête qui ne laisse qu'une seule entrée (la ciblée) dans
    /// le résultat filtré, donc déjà sélectionnée par défaut
    /// (`updateFilter` remet `selectedIndex` à 0 à chaque frappe) : aucune
    /// navigation n'est nécessaire ici. La navigation elle-même
    /// (`moveDown`/`moveUp`) est couverte séparément par
    /// `test_arrowDown_thenEnter_appliesTheNextEntryInDeclaredOrder` et
    /// `test_arrowUp_atTop_staysClamped_appliesFirstEntry`, qui filtrent sur
    /// une requête ("titre") laissant volontairement plusieurs entrées.
    private func applySelectedCommand(_ key: SlashCommand.Key, controller: SlashController) {
        _ = key // valeur documentaire : quelle entrée le test attend voir appliquée.
        _ = controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:)))
    }

    /// Repris de `Tests/EditorTextViewPasteTests.swift`.
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
            .appendingPathComponent("onetoone-slashcontroller-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }
}
