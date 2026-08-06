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
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) }
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

    /// Titres 4/5/6 : même mécanisme que « Titre 1 »/« Titre 2 »
    /// (`applyBlockConversion`, non dupliqué pour ces trois niveaux), vérifié
    /// ligne non vide (conversion réelle de contenu existant) pour chacun des
    /// trois, jusqu'à l'aller-retour markdown.
    func test_applyingHeading4_onNonEmptyLine_convertsExistingContent() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Sous section /h4", into: editor, controller: controller)

        applySelectedCommand(.heading4, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "#### Sous section")
        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .h4)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized)
    }

    func test_applyingHeading5_onNonEmptyLine_convertsExistingContent() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Sous section /h5", into: editor, controller: controller)

        applySelectedCommand(.heading5, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "##### Sous section")
        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .h5)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized)
    }

    func test_applyingHeading6_onEmptyLine_primesTypingAttributesForNextKeystroke() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/h6", into: editor, controller: controller)

        applySelectedCommand(.heading6, controller: controller)
        editor.insertText("Détail", replacementRange: editor.selectedRange())

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertEqual(serialized, "###### Détail")
        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType, .h6)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized)
    }

    func test_applyingBlockquote_onEmptyLine_primesTypingAttributes() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/citation", into: editor, controller: controller)

        applySelectedCommand(.blockquote, controller: controller)
        editor.insertText("dit quelque chose", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "> dit quelque chose")
    }

    // MARK: - Application : encadré (citation préfixée d'un emoji)

    /// Ligne vide : `applyCallout` insère `"💡 "` (littéralement, pas
    /// seulement une amorce de `typingAttributes` comme
    /// `applyBlockConversion` seul sur ligne vide) puis délègue à
    /// `applyBlockConversion(.blockquote, …)`, qui trouve alors une ligne
    /// non vide et pose réellement `.mdBlockType = .blockquote` dessus — la
    /// frappe suivante en hérite via `typingAttributes` amorcé par
    /// `applyBlockConversion`.
    ///
    /// N'affirme pas seulement sur la chaîne sérialisée (`>` n'est pas dans
    /// `MarkdownEscaping.inlineSpecials` — un paragraphe commençant par
    /// `"> 💡 "` littéral sérialiserait à l'identique) : vérifie aussi
    /// directement `.mdBlockType` sur le préfixe.
    func test_applyingCallout_onEmptyLine_insertsEmojiPrefixAsABlockquote() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/encadre", into: editor, controller: controller)

        applySelectedCommand(.callout, controller: controller)
        editor.insertText("dit quelque chose", replacementRange: editor.selectedRange())

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "> 💡 dit quelque chose")

        let emojiLocation = (editor.textStorage!.string as NSString).range(of: "💡").location
        XCTAssertNotEqual(emojiLocation, NSNotFound)
        XCTAssertEqual(
            editor.textStorage!.attribute(.mdBlockType, at: emojiLocation, effectiveRange: nil) as? BlockType,
            .blockquote
        )
    }

    /// Ligne non vide, déclencheur au milieu de la ligne (« Hello /encadre ») :
    /// le préfixe doit se planter en tête de ligne, pas au point du curseur —
    /// résultat attendu `"> 💡 Hello"`, pas `"Hello> 💡 "` ni un préfixe
    /// planté au milieu du mot.
    func test_applyingCallout_onNonEmptyLine_prefixesExistingContentAtLineStart() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Hello /encadre", into: editor, controller: controller)

        applySelectedCommand(.callout, controller: controller)

        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "> 💡 Hello")
        let helloLocation = (editor.textStorage!.string as NSString).range(of: "Hello").location
        XCTAssertNotEqual(helloLocation, NSNotFound)
        XCTAssertEqual(
            editor.textStorage!.attribute(.mdBlockType, at: helloLocation, effectiveRange: nil) as? BlockType,
            .blockquote,
            "le contenu existant doit lui aussi devenir partie de l'encadré, pas seulement le préfixe"
        )
    }

    /// Aller-retour markdown : ce que produit `applyCallout` doit reparser en
    /// exactement le même texte affiché (préfixe compris), puis se
    /// resérialiser à l'identique dès la 2ᵉ passe.
    func test_applyingCallout_roundTripsThroughSerializeAndReparse() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Hello /encadre", into: editor, controller: controller)
        applySelectedCommand(.callout, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        let reparsed = MarkdownParser.parse(serialized)

        XCTAssertEqual(reparsed.string, "💡 Hello")
        XCTAssertEqual(
            reparsed.attribute(.mdBlockType, at: 0, effectiveRange: nil) as? BlockType,
            .blockquote
        )
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized)
    }

    /// Même mesure que pour le séparateur/le tableau/la date (piège 6) : sans
    /// `stripRiskyTypingAttributes`, le préfixe 💡 inséré juste après du code
    /// inline hériterait de `.mdInlineCode` via `insertText(_:replacementRange:)`,
    /// qui fusionne les `typingAttributes` courants dans le texte simple
    /// qu'on lui passe. Le contenu existant (« code »), lui, doit garder son
    /// style inline en devenant partie de l'encadré — seul le préfixe neuf ne
    /// doit rien hériter.
    func test_applyingCallout_afterInlineCode_prefixDoesNotInheritInlineCode() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "code", attributes: [.mdInlineCode: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = makeController(for: editor)

        type(" /encadre", into: editor, controller: controller)
        applySelectedCommand(.callout, controller: controller)

        XCTAssertEqual(editor.textStorage!.string, "💡 code")

        let emojiLocation = (editor.textStorage!.string as NSString).range(of: "💡").location
        XCTAssertNotEqual(emojiLocation, NSNotFound)
        XCTAssertNil(
            editor.textStorage!.attribute(.mdInlineCode, at: emojiLocation, effectiveRange: nil),
            "le préfixe 💡 inséré ne doit pas hériter de .mdInlineCode du texte qui précède"
        )
        XCTAssertEqual(
            editor.textStorage!.attribute(.mdBlockType, at: emojiLocation, effectiveRange: nil) as? BlockType,
            .blockquote
        )

        let codeLocation = (editor.textStorage!.string as NSString).range(of: "code").location
        XCTAssertNotEqual(codeLocation, NSNotFound)
        XCTAssertEqual(
            editor.textStorage!.attribute(.mdInlineCode, at: codeLocation, effectiveRange: nil) as? Bool,
            true,
            "le contenu existant garde son style inline en devenant un encadré"
        )
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

    // MARK: - Application : tableau (insertion, pas conversion)

    /// Vérifie directement le squelette inséré sur le storage réel : 3
    /// colonnes × 3 rangées (en-tête incluse) = 9 cellules `.mdTableCell`,
    /// toutes de la même `tableID` (un seul tableau logique), toutes sans
    /// alignement (round-trip en `---` sans `:`).
    func test_applyingTable_insertsThreeByThreeSkeleton_allCellsEmpty() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/tableau", into: editor, controller: controller)

        applySelectedCommand(.table, controller: controller)

        let storage = editor.textStorage!
        var cells: [String: TableCellInfo] = [:]
        var tableIDs: Set<UUID> = []
        storage.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            cells["\(info.row),\(info.column)"] = info
            tableIDs.insert(info.tableID)
        }
        XCTAssertEqual(tableIDs.count, 1, "un seul tableau logique")
        XCTAssertEqual(cells.count, 9, "3 colonnes × 3 rangées (en-tête incluse) doit donner 9 cellules")
        for row in 0...2 {
            for column in 0...2 {
                let info = cells["\(row),\(column)"]
                XCTAssertNotNil(info, "cellule (\(row), \(column)) manquante")
                XCTAssertEqual(info?.columnCount, 3)
                XCTAssertNil(info?.alignment, "aucune colonne n'a d'alignement explicite dans le squelette")
            }
        }
    }

    /// Aller-retour texte complet : le storage sérialisé, puis reparsé par
    /// `MarkdownParser.parse` comme au rechargement d'une note, doit encore
    /// donner un tableau à 9 cellules — pas seulement rester stable dans le
    /// storage vivant (déjà couvert ci-dessus). Le tableau inséré ici est en
    /// toute fin de document (cas le plus courant : `/tableau` tapé en
    /// dernière ligne) — mesuré exprès plutôt que supposé : `MarkdownParser.
    /// parse` retire toujours le dernier `\n` de fin de document, et une
    /// dernière cellule vide n'a que ce `\n` pour porter `.mdTableCell`
    /// (`MarkdownRoundTripTests` documente ce défaut connu du parser pour une
    /// cellule vide qui termine *à la fois* sa rangée et le document — ce
    /// test vérifie que le tableau inséré ici ne tombe pas dans ce cas).
    func test_applyingTable_atEndOfDocument_survivesSerializeThenFullReparse() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/tableau", into: editor, controller: controller)
        applySelectedCommand(.table, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        let reparsed = MarkdownParser.parse(serialized)

        var cells: Set<String> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            cells.insert("\(info.row),\(info.column)")
        }
        XCTAssertEqual(cells.count, 9,
                       "les 9 cellules doivent survivre à un aller-retour texte complet, y compris en toute fin de document : \(serialized.debugDescription)")

        // Stable dès la 2e passe.
        let secondPass = MarkdownSerializer.serialize(reparsed)
        XCTAssertEqual(secondPass, serialized)
    }

    /// Inséré après un paragraphe existant : le paragraphe ne doit pas être
    /// absorbé comme rangée de données supplémentaire du tableau (piège 2 du
    /// plan, mesuré sur `meeting_158`/`meeting_157` — voir
    /// `MarkdownSerializer.needsBlankLine`).
    func test_applyingTable_insertedAfterParagraph_paragraphNotAbsorbed() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("Avant /tableau", into: editor, controller: controller)

        applySelectedCommand(.table, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        let reparsed = MarkdownParser.parse(serialized)

        let avantLocation = (reparsed.string as NSString).range(of: "Avant").location
        XCTAssertNotEqual(avantLocation, NSNotFound)
        XCTAssertNil(reparsed.attribute(.mdTableCell, at: avantLocation, effectiveRange: nil),
                     "« Avant » ne doit pas être devenu une cellule du tableau")
        let blockType = reparsed.attribute(.mdBlockType, at: avantLocation, effectiveRange: nil) as? BlockType
        XCTAssertEqual(blockType, .paragraph, "« Avant » doit rester un paragraphe distinct : \(serialized.debugDescription)")

        var cells: Set<String> = []
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            guard let info = value as? TableCellInfo else { return }
            cells.insert("\(info.row),\(info.column)")
        }
        XCTAssertEqual(cells.count, 9, "le tableau doit garder ses 9 cellules malgré le paragraphe qui le précède")
    }

    /// Le curseur atterrit dans la première cellule (rangée 0, colonne 0) :
    /// la frappe qui suit immédiatement l'insertion doit remplir cette
    /// cellule précise, pas un autre endroit du tableau ni du texte hors
    /// tableau.
    func test_applyingTable_cursorLandsInFirstCell_typedCharacterFillsHeaderFirstColumn() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/tableau", into: editor, controller: controller)

        applySelectedCommand(.table, controller: controller)

        // Position exacte, pas seulement « une entrée quelque part porte la
        // bonne valeur » : le document démarrait vide, donc le curseur doit
        // se retrouver exactement à la position 0 — celle du `\n` de la
        // première cellule — pas ailleurs (ex. après la dernière cellule,
        // où `insertText` laisserait le curseur par défaut).
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0),
                       "le curseur doit atterrir juste avant le \\n de la cellule (0, 0), pas ailleurs dans le tableau inséré")

        editor.insertText("A", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.textStorage?.string.first, "A",
                       "« A » doit être devenu le tout premier caractère du document (poussé avant le \\n de la cellule (0, 0))")

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        let reparsed = MarkdownParser.parse(serialized)
        let aLocation = (reparsed.string as NSString).range(of: "A").location
        XCTAssertNotEqual(aLocation, NSNotFound)
        let info = reparsed.attribute(.mdTableCell, at: aLocation, effectiveRange: nil) as? TableCellInfo
        XCTAssertEqual(info?.row, 0)
        XCTAssertEqual(info?.column, 0,
                       "la frappe suivant l'insertion doit atterrir dans la première cellule (rangée 0, colonne 0) : \(serialized.debugDescription)")
    }

    /// Preuve directe, sans passer par une frappe supplémentaire : juste
    /// après l'insertion, `typingAttributes` doit déjà porter `.mdTableCell`
    /// pour la cellule (0, 0), et la sélection doit être un curseur vide à
    /// la position exacte de cette cellule (0, sur un document qui démarrait
    /// vide) — pas seulement « quelque part, une sélection de longueur 0 ».
    func test_applyingTable_typingAttributesCarryFirstCellInfo_beforeAnyKeystroke() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/tableau", into: editor, controller: controller)

        applySelectedCommand(.table, controller: controller)

        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
        let info = editor.typingAttributes[.mdTableCell] as? TableCellInfo
        XCTAssertEqual(info?.row, 0)
        XCTAssertEqual(info?.column, 0)
    }

    // MARK: - Piège 6 (tableau) : le texte inséré n'hérite pas des attributs de frappe

    /// Même mesure que pour l'entrée « Date » (voir plus bas) : sans
    /// `stripRiskyTypingAttributes`, le tableau inséré juste après du code
    /// inline hériterait de `.mdInlineCode` sur tout son contenu inséré (le
    /// `\n` nu initial et les 9 cellules), via `insertText(_:replacementRange:)`
    /// qui fusionne les `typingAttributes` courants.
    func test_applyingTable_afterInlineCode_insertedContentDoesNotInheritInlineCode() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "code", attributes: [.mdInlineCode: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = makeController(for: editor)

        type(" /tableau", into: editor, controller: controller)
        applySelectedCommand(.table, controller: controller)

        let storage = editor.textStorage!
        XCTAssertGreaterThan(storage.length, 4, "prémisse du test : le tableau doit avoir été inséré après « code »")
        for location in 4..<storage.length {
            XCTAssertNil(
                storage.attribute(.mdInlineCode, at: location, effectiveRange: nil),
                "position \(location) du tableau inséré hérite à tort de .mdInlineCode du code inline qui précède"
            )
        }
    }

    /// Même mesure pour le gras.
    func test_applyingTable_afterBold_insertedContentDoesNotInheritBold() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "bold", attributes: [.mdBold: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = makeController(for: editor)

        type(" /tableau", into: editor, controller: controller)
        applySelectedCommand(.table, controller: controller)

        let storage = editor.textStorage!
        XCTAssertGreaterThan(storage.length, 4, "prémisse du test : le tableau doit avoir été inséré après « bold »")
        for location in 4..<storage.length {
            XCTAssertNil(
                storage.attribute(.mdBold, at: location, effectiveRange: nil),
                "position \(location) du tableau inséré hérite à tort de .mdBold du texte en gras qui précède"
            )
        }
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
            },
            presentDatePicker: { _, _, completion in completion(nil) }
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
            presentImagePicker: { completion in completion(nil) },
            presentDatePicker: { _, _, completion in completion(nil) }
        )

        type("/image", into: editor, controller: controller)
        applySelectedCommand(.image, controller: controller)

        XCTAssertEqual(editor.textStorage?.string, "", "annulation du sélecteur : rien ne doit être inséré")
    }

    // MARK: - Application : date

    func test_applyingDate_opensPickerAndInsertsChosenDate() {
        let (editor, _) = makeWiredEditor(markdown: "")
        var pickerWasInvoked = false
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in
                pickerWasInvoked = true
                completion(Self.fixedTestSelection)
            }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        XCTAssertTrue(pickerWasInvoked)
        // Calculé via le même formateur que la production
        // (`SlashController.dateInsertionFormatter`) plutôt qu'une chaîne
        // recopiée à la main : un test qui dupliquerait la configuration du
        // formateur pourrait diverger silencieusement (fuseau horaire,
        // locale) sans jamais détecter une régression du formateur réel.
        let expected = SlashController.dateInsertionFormatter.string(from: Self.fixedTestDate)
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), expected)
        XCTAssertFalse(controller.isOpen)
    }

    func test_applyingDate_pickerCancelled_insertsNothing() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        XCTAssertEqual(editor.textStorage?.string, "", "annulation du sélecteur : rien ne doit être inséré")
    }

    /// Format retenu contre `MarkdownEscaping.inlineSpecials` : round-trip
    /// exact (sérialiser, reparser, resérialiser donne la même chaîne) et
    /// aucun antislash d'échappement dans le résultat — la preuve directe que
    /// le format choisi (`dateStyle = .long`, locale `fr_FR`, ex. « 25
    /// décembre 2025 ») ne contient aucun caractère qu'`escapeInline`
    /// échapperait.
    func test_applyingDate_roundTripsWithoutEscaping() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(Self.fixedTestSelection) }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertFalse(serialized.contains("\\"), "le format de date choisi ne doit nécessiter aucun antislash d'échappement : \(serialized.debugDescription)")

        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized, "la date insérée doit survivre à l'aller-retour markdown")
    }

    /// `includesTime: false` (le cas par défaut de `fixedTestSelection`) ne
    /// doit ajouter aucune heure au texte inséré — sans ce test, un bug qui
    /// ajouterait toujours l'heure (ignorant `includesTime`) ne serait
    /// détecté par aucun test existant : les tests « sans heure » vérifient
    /// le texte exact via `dateInsertionFormatter`, mais aucun ne vérifiait
    /// explicitement l'absence du séparateur `":"` propre à l'heure.
    func test_applyingDate_withoutTime_insertsNoTimeSuffix() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(Self.fixedTestSelection) }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        XCTAssertFalse(editor.textStorage!.string.contains(":"), "includesTime: false ne doit pas ajouter d'heure au texte inséré")
    }

    /// `includesTime: true` : le texte inséré doit porter la date **et**
    /// l'heure (`SlashController.timeInsertionFormatter`, séparateur `":"`,
    /// absent d'`MarkdownEscaping.inlineSpecials`), sans échappement, et doit
    /// survivre à l'aller-retour markdown — même charte que
    /// `test_applyingDate_roundTripsWithoutEscaping`, étendue au format avec
    /// heure demandé par la tâche (« 6 août 2026 13:08 »).
    func test_applyingDate_withTime_insertsDateAndTime_withoutEscaping_andRoundTrips() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in
                completion(SlashDateSelection(date: Self.fixedTestDate, includesTime: true, reminder: .none))
            }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        let expectedDate = SlashController.dateInsertionFormatter.string(from: Self.fixedTestDate)
        let expectedTime = SlashController.timeInsertionFormatter.string(from: Self.fixedTestDate)
        XCTAssertEqual(editor.textStorage?.string, "\(expectedDate) \(expectedTime)")

        let serialized = MarkdownSerializer.serialize(editor.textStorage!)
        XCTAssertFalse(serialized.contains("\\"), "le format avec heure ne doit nécessiter aucun antislash d'échappement : \(serialized.debugDescription)")

        let reparsed = MarkdownParser.parse(serialized)
        XCTAssertEqual(MarkdownSerializer.serialize(reparsed), serialized, "la date+heure insérée doit survivre à l'aller-retour markdown")
    }

    /// `SlashController.dateAnchorRect` (ancrage du popover) doit renvoyer
    /// `.zero` plutôt que d'appeler `firstRect(forCharacterRange:actualRange:)`
    /// quand l'éditeur n'a pas de fenêtre — même garde que `reposition()`
    /// pour `SlashPanel`. Capture le rectangle reçu par le stub
    /// `presentDatePicker` pour le vérifier sans accéder à la méthode privée
    /// directement.
    func test_applyingDate_anchorRectIsZero_whenEditorHasNoWindow() {
        let (editor, _) = makeWiredEditor(markdown: "")
        XCTAssertNil(editor.window, "prémisse du test : pas de fenêtre attachée dans ce montage")
        var capturedRect: NSRect?
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, rect, completion in
                capturedRect = rect
                completion(nil)
            }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        XCTAssertEqual(capturedRect, .zero)
    }

    /// Preuve directe et indépendante de `MarkdownEscaping.inlineSpecials` :
    /// contrairement aux deux tests précédents (qui inspectent le résultat
    /// *sérialisé*, donc déjà passé par `escapeInline`), celui-ci lit le
    /// texte brut tel qu'inséré dans le storage et le compare à la liste
    /// **recopiée à la main** des caractères risqués — pas à
    /// `SlashController.dateInsertionFormatter` lui-même, pour ne pas être
    /// aveugle à une régression du formateur qui choisirait un format
    /// toujours round-trippable (aucun antislash requis) mais construit sur
    /// un caractère risqué qui n'a simplement pas besoin d'échappement en
    /// position isolée (aucun cas de ce genre dans la liste actuelle, mais
    /// rien ne garantit qu'un futur format candidat s'en tienne à cette
    /// propriété).
    func test_applyingDate_insertedTextContainsNoInlineSpecialCharacter() {
        let (editor, _) = makeWiredEditor(markdown: "")
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(Self.fixedTestSelection) }
        )

        type("/date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        // Copie volontairement littérale de `MarkdownEscaping.inlineSpecials`
        // (`private`, donc non réutilisable ici) — la charte du test décrite
        // ci-dessus dépend de cette indépendance.
        let riskyCharacters: Set<Character> = [
            "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!"
        ]
        let insertedText = editor.textStorage!.string
        XCTAssertFalse(insertedText.isEmpty, "prémisse du test : la date doit avoir été insérée")
        for character in insertedText {
            XCTAssertFalse(
                riskyCharacters.contains(character),
                "le format de date choisi contient '\(character)', qu'MarkdownEscaping.inlineSpecials échapperait : \(insertedText.debugDescription)"
            )
        }
    }

    // MARK: - Piège 6 : le texte inséré n'hérite pas des attributs de frappe

    /// Reproduit le bug de la doc de tête de fichier pour l'entrée « Date » :
    /// insérer juste après du code inline hériterait de `.mdInlineCode` sur
    /// la date insérée (`typingAttributes` fusionnés par
    /// `insertText(_:replacementRange:)`) sans `stripRiskyTypingAttributes`.
    func test_applyingDate_afterInlineCode_insertedTextDoesNotInheritInlineCode() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "code", attributes: [.mdInlineCode: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(Self.fixedTestSelection) }
        )

        type(" /date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        let expectedDateText = SlashController.dateInsertionFormatter.string(from: Self.fixedTestDate)
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "`code`\(expectedDateText)")

        let insertedRange = (editor.textStorage!.string as NSString).range(of: expectedDateText)
        XCTAssertNotEqual(insertedRange.location, NSNotFound)
        XCTAssertNil(
            editor.textStorage!.attribute(.mdInlineCode, at: insertedRange.location, effectiveRange: nil),
            "la date insérée ne doit pas hériter de .mdInlineCode du code inline qui précède"
        )
    }

    /// Même mesure pour le gras : sans `stripRiskyTypingAttributes`, la date
    /// insérée juste après du texte en gras hériterait de `.mdBold` et se
    /// retrouverait emballée en `**...**` sans que l'utilisateur l'ait
    /// demandé.
    func test_applyingDate_afterBold_insertedTextDoesNotInheritBold() {
        let (editor, _) = makeWiredEditor(markdown: "")
        editor.textStorage?.setAttributedString(
            NSAttributedString(string: "bold", attributes: [.mdBold: true])
        )
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(Self.fixedTestSelection) }
        )

        type(" /date", into: editor, controller: controller)
        applySelectedCommand(.date, controller: controller)

        let expectedDateText = SlashController.dateInsertionFormatter.string(from: Self.fixedTestDate)
        XCTAssertEqual(MarkdownSerializer.serialize(editor.textStorage!), "**bold**\(expectedDateText)")

        let insertedRange = (editor.textStorage!.string as NSString).range(of: expectedDateText)
        XCTAssertNotEqual(insertedRange.location, NSNotFound)
        XCTAssertNil(
            editor.textStorage!.attribute(.mdBold, at: insertedRange.location, effectiveRange: nil),
            "la date insérée ne doit pas hériter de .mdBold du texte en gras qui précède"
        )
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

    /// Le panneau (`SlashPanel`) plafonne désormais sa hauteur à
    /// `SlashPanelMetrics.maxVisibleRows` lignes et fait défiler le reste
    /// dans un `ScrollView` (voir `SlashPanel.swift`) — mais c'est du rendu
    /// SwiftUI, non pilotable par les tests de ce projet (aucune dépendance
    /// ne permet de conduire une vue SwiftUI ici, voir la doc de tête de ce
    /// fichier et `Tests/SlashPanelPositioningTests.swift`) : le défilement
    /// visuel lui-même — `ScrollViewReader.scrollTo` déclenché par
    /// `.onChange(of: state.selectedIndex)` dans `SlashPanelContent` —
    /// **n'est pas couvert**.
    ///
    /// Ce qui *est* testable, et vérifié ici : `SlashController` fait bien
    /// progresser `selectedIndex` (et donc l'entrée qu'⏎ applique) au-delà du
    /// nombre de lignes visibles sans défilement — condition nécessaire pour
    /// que le défilement visuel ait quelque chose de correct à amener en vue.
    /// Catalogue complet non filtré (`/` seul, `.full` : 16 entrées depuis
    /// l'ajout de « Encadré » et des titres 4/5/6 — voir `SlashCatalog.all`) ;
    /// `maxVisibleRows + 5` pressions de flèche bas mènent à l'index 13
    /// (« Tableau »), au-delà des 8 premières lignes visibles sans défiler.
    func test_arrowDown_beyondVisibleRowCap_stillAdvancesSelection_toEntryPastTheFold() {
        let (editor, controller, _) = makeWiredController(markdown: "")
        type("/", into: editor, controller: controller)

        for _ in 0...(SlashPanelMetrics.maxVisibleRows + 4) {
            XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.moveDown(_:))))
        }
        XCTAssertTrue(controller.handle(commandSelector: #selector(NSResponder.insertNewline(_:))))

        let storage = editor.textStorage!
        var cellCount = 0
        storage.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { cellCount += 1 }
        }
        XCTAssertEqual(cellCount, 9,
                       "l'entrée appliquée doit être « Tableau » (index 13, 9 cellules) — au-delà des 8 premières lignes visibles sans défilement")
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
    /// des tests qui n'en ont pas besoin ; `presentImagePicker` et
    /// `presentDatePicker` répondent immédiatement `nil`, comme un
    /// utilisateur qui annule).
    private func makeController(for editor: EditorTextView) -> SlashController {
        SlashController(
            textView: editor,
            features: .full,
            panel: SlashPanel(),
            cancelPendingWrite: {},
            presentImagePicker: { $0(nil) },
            presentDatePicker: { _, _, completion in completion(nil) }
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

    /// Date fixe utilisée par les tests de l'entrée « Date » : midi (évite
    /// tout effet de bord DST/minuit) le 25 décembre 2025, construite via
    /// `Calendar.current` — le même calendrier/fuseau par défaut que
    /// `SlashController.dateInsertionFormatter` (qui ne fixe pas `timeZone`
    /// explicitement). N'importe quelle date conviendrait : les tests
    /// calculent la chaîne attendue via `dateInsertionFormatter` lui-même,
    /// jamais recopiée à la main.
    private static var fixedTestDate: Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 25
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    /// `SlashDateSelection` construite sur `fixedTestDate`, sans heure et
    /// sans rappel — la sélection renvoyée par la plupart des stubs
    /// `presentDatePicker` de ce fichier, qui ne testent que le chemin
    /// « date seule ». Les tests spécifiques à l'heure/au rappel construisent
    /// leur propre `SlashDateSelection` plutôt que d'étendre celle-ci.
    private static var fixedTestSelection: SlashDateSelection {
        SlashDateSelection(date: fixedTestDate, includesTime: false, reminder: .none)
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
