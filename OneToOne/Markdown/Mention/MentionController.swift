import AppKit

/// Détection du `@`, navigation clavier et insertion d'une mention de
/// collaborateur sur l'`EditorTextView` réel — même patron que
/// `SlashController` (voir sa doc de tête pour le câblage attendu côté
/// `Coordinator`, identique ici), appliqué au problème symétrique : une
/// liste plate de collaborateurs plutôt que des commandes groupées, un lien
/// markdown `.mdLink` inséré inline plutôt qu'une conversion/insertion de
/// bloc.
///
/// Reçoit son `EditorTextView` **directement**, comme `SlashController` :
/// pas de `MarkdownEditorRegistry` (singleton non isolé, clés fournies par
/// l'appelant).
@MainActor
final class MentionController {

    // MARK: - Dépendances

    private weak var textView: EditorTextView?
    private let panel: MentionPanel
    private let cancelPendingWrite: () -> Void
    /// Renvoie les collaborateurs correspondant à `query`, **déjà** filtrés
    /// (nom, insensible casse/accents), triés et purgés des archivés — la
    /// requête part vers SwiftData ici (piège 2 de la spec), côté couche vue.
    /// `var` (pas `let`) : `updateHandlers` la rafraîchit à chaque
    /// `EditorRepresentable.updateNSView`, cf. sa doc.
    private var searchCollaborators: (String) -> [MentionCandidate]
    /// Crée un collaborateur nommé par l'entrée « Créer … » et renvoie le
    /// candidat créé, ou `nil` pour refuser — rien n'est alors inséré (piège
    /// documenté par la spec). `var` pour la même raison que
    /// `searchCollaborators`.
    private var createCollaborator: (String) -> MentionCandidate?

    // MARK: - État

    /// Vrai entre l'ouverture du menu et sa fermeture (sélection, Échap,
    /// `⌫` avant le `@`, ou sélection qui sort de la requête).
    private(set) var isOpen: Bool = false
    /// Position du caractère `@` qui a ouvert le menu.
    private var triggerLocation: Int = 0
    private var currentRows: [MentionRow] = []
    private var selectedIndex: Int = 0

    /// Pas de valeur par défaut pour `panel`/`searchCollaborators`/
    /// `createCollaborator` — même raison que `SlashController.init` (voir sa
    /// doc) : un défaut `@MainActor` en position de paramètre échoue en mode
    /// Swift 6 strict.
    init(
        textView: EditorTextView,
        panel: MentionPanel,
        cancelPendingWrite: @escaping () -> Void,
        searchCollaborators: @escaping (String) -> [MentionCandidate],
        createCollaborator: @escaping (String) -> MentionCandidate?
    ) {
        self.textView = textView
        self.panel = panel
        self.cancelPendingWrite = cancelPendingWrite
        self.searchCollaborators = searchCollaborators
        self.createCollaborator = createCollaborator
        panel.onSelect = { [weak self] row in self?.apply(row) }
    }

    /// À appeler depuis `EditorRepresentable.updateNSView` à chaque rendu
    /// SwiftUI. Nécessaire, pas seulement défensif : les closures injectées
    /// via `MarkdownTextEditor.markdownMentions(search:create:)` sont
    /// reconstruites à chaque évaluation du `body` de la vue appelante (ex.
    /// `MarkdownNoteEditor`, dont la closure capture un `@Query
    /// [Collaborator]` figé à l'instant de cette évaluation) — sans ce
    /// rafraîchissement, un collaborateur créé après le montage de l'éditeur
    /// resterait invisible à la recherche pour toute la durée de vie de la
    /// vue, la closure d'origine (capturée une seule fois dans `makeNSView`)
    /// ne voyant plus jamais que l'instantané initial.
    func updateHandlers(
        searchCollaborators: @escaping (String) -> [MentionCandidate],
        createCollaborator: @escaping (String) -> MentionCandidate?
    ) {
        self.searchCollaborators = searchCollaborators
        self.createCollaborator = createCollaborator
    }

    // MARK: - Détection et filtrage (hook 1 : `Coordinator.textDidChange`)

    /// Réagit à une frappe. Renvoie `true` si le menu vient d'absorber cette
    /// frappe (ouverture ou mise à jour de la requête) — l'appelant ne doit
    /// alors ni lancer `ShortcutDetector`, ni sérialiser, ni (re)programmer
    /// le debounce, exactement comme pour `SlashController.textDidChange()`.
    ///
    /// Le `@` ouvre le menu s'il est en début de ligne ou précédé d'une
    /// espace (`isValidTriggerPosition`) — jamais en milieu de mot. C'est
    /// cette règle, et elle seule, qui protège une adresse courriel tapée en
    /// milieu de texte (`contact@exemple.fr`) : le `@` y est toujours précédé
    /// d'une lettre du nom d'utilisateur, jamais d'une espace ou d'un début
    /// de ligne — mesuré par `test_isValidTriggerPosition_emailAddress_midWord_isRejected`.
    @discardableResult
    func textDidChange() -> Bool {
        guard let textView, let storage = textView.textStorage else {
            close()
            return false
        }
        let ns = storage.string as NSString
        let cursor = textView.selectedRange().location

        if isOpen {
            guard let query = Self.currentQuery(in: ns, triggerLocation: triggerLocation, cursor: cursor) else {
                close()
                return false
            }
            updateFilter(query: query)
            cancelPendingWrite()
            return true
        }

        guard cursor > 0, cursor <= ns.length else { return false }
        let atLocation = cursor - 1
        guard ns.character(at: atLocation) == 0x40 /* "@" */ else { return false }
        guard Self.isValidTriggerPosition(in: ns, atLocation: atLocation) else { return false }

        open(triggerLocation: atLocation)
        cancelPendingWrite()
        return true
    }

    /// Réagit à un déplacement du curseur qui ne passe pas par
    /// `textDidChange()` (clic ailleurs, flèches gauche/droite) — même rôle
    /// que `SlashController.selectionDidChange()`.
    func selectionDidChange() {
        guard isOpen, let textView, let storage = textView.textStorage else { return }
        let ns = storage.string as NSString
        let cursor = textView.selectedRange().location
        if Self.currentQuery(in: ns, triggerLocation: triggerLocation, cursor: cursor) == nil {
            close()
        }
    }

    /// Vrai si le caractère à `atLocation` (déjà vérifié `"@"` par
    /// l'appelant) ouvre valablement le menu : position 0 du document, juste
    /// après un `\n`, ou juste après une espace. Fonction pure, testable
    /// sans `NSTextView` — copie de la règle de `SlashController.
    /// isValidTriggerPosition`, appliquée à `"@"` (`0x40`) au lieu de `"/"`.
    static func isValidTriggerPosition(in text: NSString, atLocation: Int) -> Bool {
        guard atLocation >= 0, atLocation < text.length else { return false }
        guard text.character(at: atLocation) == 0x40 else { return false }
        if atLocation == 0 { return true }
        let previous = text.character(at: atLocation - 1)
        return previous == 0x0A /* "\n" */ || previous == 0x20 /* " " */
    }

    /// Texte tapé depuis le `@` situé à `triggerLocation` jusqu'à `cursor` —
    /// peut contenir des espaces (contrairement à `SlashController.
    /// currentQuery`, une requête de mention filtre sur un nom complet, ex.
    /// « Marie Dupont »), mais jamais de saut de ligne. `nil` invalide l'état
    /// « menu ouvert » (mêmes cas que `SlashController.currentQuery` : voir
    /// sa doc). Fonction pure, testable sans `NSTextView`.
    static func currentQuery(in text: NSString, triggerLocation: Int, cursor: Int) -> String? {
        guard triggerLocation >= 0, triggerLocation < text.length else { return nil }
        guard text.character(at: triggerLocation) == 0x40 else { return nil }
        let queryStart = triggerLocation + 1
        guard cursor >= queryStart, cursor <= text.length else { return nil }
        let query = text.substring(with: NSRange(location: queryStart, length: cursor - queryStart))
        guard !query.contains("\n") else { return nil }
        return query
    }

    // MARK: - Clavier (hook 2 : `Coordinator.textView(_:doCommandBy:)`)

    /// Traite une commande d'édition standard. Renvoie `true` si consommée.
    /// Contrairement à `SlashController.handle(commandSelector:)`, aucun
    /// correctif n'est appliqué menu fermé (le piège 4 — Retour après un
    /// titre — reste porté par `SlashController` uniquement ; le dupliquer
    /// ici produirait un double correctif inoffensif mais inutile, voir le
    /// câblage de `Coordinator.textView(_:doCommandBy:)`).
    func handle(commandSelector: Selector) -> Bool {
        guard isOpen else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            applySelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    // MARK: - Fermeture

    /// Ferme le menu sans toucher au texte (le `@` et la requête tapés
    /// restent tels quels) — même contrat que `SlashController.close()`.
    func close() {
        isOpen = false
        triggerLocation = 0
        currentRows = []
        selectedIndex = 0
        panel.dismiss()
    }

    /// À appeler quand l'`EditorTextView` associé est démonté
    /// (`dismantleNSView`) — même contrat que `SlashController.teardown()`.
    func teardown() {
        isOpen = false
        panel.close()
    }

    // MARK: - Ouverture / filtrage

    private func open(triggerLocation: Int) {
        self.triggerLocation = triggerLocation
        self.isOpen = true
        updateFilter(query: "")
    }

    private func updateFilter(query: String) {
        let candidates = searchCollaborators(query)
        currentRows = MentionCatalog.rows(candidates: candidates, query: query)
        selectedIndex = 0
        panel.update(rows: currentRows, selectedIndex: selectedIndex)
        reposition()
    }

    private func moveSelection(by delta: Int) {
        guard !currentRows.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), currentRows.count - 1)
        panel.update(rows: currentRows, selectedIndex: selectedIndex)
    }

    /// Même technique que `SlashController.reposition()` : ne fait rien sans
    /// fenêtre (tests qui n'attachent pas l'éditeur à une fenêtre réelle).
    private func reposition() {
        guard let textView, let window = textView.window else { return }
        var actualRange = NSRange(location: 0, length: 0)
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: triggerLocation, length: 0),
            actualRange: &actualRange
        )
        panel.show(near: screenRect, on: window.screen)
    }

    private func applySelected() {
        guard selectedIndex >= 0, selectedIndex < currentRows.count else { return }
        apply(currentRows[selectedIndex])
    }

    // MARK: - Application d'une entrée

    /// Efface le `@` et la requête (piège 3 : `insertText("",
    /// replacementRange:)`, jamais une mutation directe du storage), ferme
    /// le menu, puis insère la mention (ou crée le collaborateur puis
    /// l'insère).
    ///
    /// Contrairement à `SlashController.apply(_:)`, **n'absorbe pas**
    /// l'espace qui a validé le déclencheur : celui-ci sépare deux mots d'une
    /// même phrase (« Bonjour @marie » → « Bonjour » + espace + mention), ce
    /// n'est pas un espace résiduel de début de ligne comme pour une
    /// conversion de bloc — le supprimer collerait la mention au mot
    /// précédent (mesuré : sans cette différence,
    /// `test_selectingCandidate_afterOrdinaryWord_preservesTheSeparatingSpace`
    /// échoue, la mention se retrouvant collée à « Bonjour »).
    private func apply(_ row: MentionRow) {
        guard let textView, let storage = textView.textStorage else {
            close()
            return
        }
        let start = min(triggerLocation, storage.length)
        let cursor = min(textView.selectedRange().location, storage.length)
        let clearRange = NSRange(location: start, length: max(0, cursor - start))
        close()

        textView.insertText("", replacementRange: clearRange)

        guard let refreshedStorage = textView.textStorage else { return }
        let applyLocation = min(start, refreshedStorage.length)

        switch row {
        case .candidate(let candidate):
            insertMention(candidate, at: applyLocation, in: textView)
        case .create(let typedName):
            guard let candidate = createCollaborator(typedName) else { return }
            insertMention(candidate, at: applyLocation, in: textView)
        }
    }

    /// Insère `"@" + candidate.name` avec `.mdLink` pointant vers
    /// `MentionCatalog.mentionURL(for: candidate.id)` — un lien markdown
    /// standard, round-trippé par `MarkdownParser`/`MarkdownSerializer` sans
    /// mécanisme dédié (raison n°1 de la spec pour ce choix de
    /// représentation).
    ///
    /// `stripRiskyInlineTypingAttributes` **avant** l'insertion — mesuré
    /// nécessaire (piège 1 de la spec) : sans lui, le texte inséré hérite de
    /// `.mdInlineCode`/`.mdBold`/`.mdItalic`/`.mdStrikethrough` du contexte
    /// (`insertText` complète les clés absentes de la chaîne insérée avec les
    /// `typingAttributes` courants — `.mdLink`, lui, est fourni explicitement
    /// sur la chaîne insérée et n'est donc jamais écrasé par cette fusion,
    /// contrairement aux quatre autres clés).
    ///
    /// Répété **après** l'insertion par prudence plutôt que par nécessité
    /// mesurée : `insertText(_:replacementRange:)` ne recopie pas, en
    /// pratique, les attributs du texte inséré dans `typingAttributes` —
    /// vérifié par mutation, retirer cet appel ne fait échouer aucun test,
    /// y compris `test_typingRightAfterMention_doesNotContinueTheLink`, écrit
    /// spécifiquement pour le détecter. Conservé quand même : c'est le même
    /// filet de sécurité que celui que `SlashController.insertTable` pose
    /// après son propre `setSelectedRange` explicite (voir sa doc) pour le
    /// cas où un recalcul de `typingAttributes` depuis le caractère voisin
    /// interviendrait malgré tout — coût nul, et protège un futur appel
    /// explicite à `setSelectedRange` qui, lui, déclencherait ce recalcul
    /// (comportement documenté d'AppKit).
    ///
    /// Ne touche volontairement **pas** à `.mdBlockType`/`.mdListInfo` :
    /// contrairement aux insertions de bloc de `SlashController`
    /// (séparateur, tableau, qui démarrent un contexte de bloc neuf), une
    /// mention est **inline**, à l'intérieur du bloc courant — un item de
    /// liste qui contient une mention doit rester un item de liste pour la
    /// frappe qui suit (mesuré :
    /// `test_insertingMention_insideListItem_subsequentTypingStaysInTheListItem`).
    private func insertMention(_ candidate: MentionCandidate, at location: Int, in textView: EditorTextView) {
        stripRiskyInlineTypingAttributes(in: textView)
        let url = MentionCatalog.mentionURL(for: candidate.id)
        let insertion = NSAttributedString(string: "@\(candidate.name)", attributes: [.mdLink: url])
        let safeLocation = min(location, textView.textStorage?.length ?? 0)
        textView.insertText(insertion, replacementRange: NSRange(location: safeLocation, length: 0))
        stripRiskyInlineTypingAttributes(in: textView)
    }

    /// Clés inline à risque — même liste qu'`EditorTextView.
    /// inlineAttributesToStripBeforeImageInsertion` (le précédent le plus
    /// proche : une insertion attribuée en place, pas une conversion de
    /// bloc), délibérément **sans** `.mdBlockType`/`.mdListInfo` — voir la
    /// doc d'`insertMention`.
    private static let riskyInlineTypingAttributeKeys: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    private func stripRiskyInlineTypingAttributes(in textView: EditorTextView) {
        for key in Self.riskyInlineTypingAttributeKeys {
            textView.typingAttributes.removeValue(forKey: key)
        }
    }
}
