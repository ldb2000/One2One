import SwiftUI
import AppKit

/// SwiftUI bridge that owns the `EditorTextView`. Translates the markdown
/// `@Binding String` ↔ internal `NSAttributedString` using `MarkdownParser` /
/// `MarkdownSerializer`. Debounces outgoing changes so SwiftData isn't
/// notified on every keystroke.
struct EditorRepresentable: NSViewRepresentable {
    @Binding var markdown: String
    var placeholder: String
    var features: Set<MarkdownFeature>
    var debounce: TimeInterval
    var readOnly: Bool
    /// Identifiant d'enregistrement dans `MarkdownEditorRegistry` (vide = pas
    /// d'enregistrement). Permet à une `MarkdownToolbar` de piloter cet éditeur.
    var editorID: String = ""
    /// Closures des mentions `@` (voir `MarkdownTextEditor.markdownMentions(search:create:)`).
    /// `mentionSearch == nil` désactive entièrement la fonctionnalité :
    /// `makeNSView` ne construit alors aucun `MentionController`.
    var mentionSearch: ((String) -> [MentionCandidate])? = nil
    var mentionCreate: ((String) -> MentionCandidate?)? = nil
    /// Routeur des liens internes (voir `MarkdownTextEditor.markdownLinks(handler:)`).
    /// `nil` (le défaut) : tout clic sur un lien retombe sur l'ouverture système
    /// (voir `EditorTextView.clicked(onLink:at:)`).
    var linkHandler: ((URL) -> Bool)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit stack manually : NSTextStorage → NSLayoutManager →
        // NSTextContainer → NSTextView. Le pattern `scrollableTextView()` +
        // remplacement de documentView casse la chaîne (le layout manager
        // d'origine reste branché sur l'ancien NSTextView).
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let textStorage = NSTextStorage()
        // `MarkdownLayoutManager` dessine les marqueurs de liste (puce,
        // numéro, case à cocher) au-dessus du rendu standard — voir sa
        // documentation pour la raison (TextKit 1 ne les dessine pas
        // automatiquement).
        let layoutManager = MarkdownLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let huge: CGFloat = 1_000_000
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: huge)
        )
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        let initialFrame = NSRect(origin: .zero, size: NSSize(width: 200, height: 100))
        let editor = EditorTextView(frame: initialFrame, textContainer: container)
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: huge, height: huge)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [NSView.AutoresizingMask.width]

        editor.delegate = context.coordinator
        editor.onTaskToggle = { [weak coord = context.coordinator] (_: NSRange, _: Bool) in
            coord?.pushMarkdownToBinding(force: true)
        }
        editor.onLinkClick = linkHandler
        scroll.documentView = editor
        context.coordinator.textView = editor
        // Contrôleur du menu « / » (tâche 6) : construit juste après
        // l'`EditorTextView`, avec l'annulation du debounce en cours branchée
        // sur `cancelPendingWrite` du même `Coordinator` — voir l'en-tête de
        // `SlashController` pour le câblage attendu.
        context.coordinator.slashController = SlashController(
            textView: editor,
            features: features,
            panel: SlashPanel(),
            cancelPendingWrite: { [weak coord = context.coordinator] in
                coord?.cancelPendingWrite()
            },
            presentImagePicker: SlashController.presentImageOpenPanel,
            presentDatePicker: SlashController.presentDatePickerPopover,
            presentEmojiPicker: SlashController.presentCharacterPalette
        )
        // Contrôleur du menu « @ » : seulement si l'appelant a fourni une
        // closure de recherche (`markdownMentions(search:create:)`) — voir la
        // doc de `mentionSearch`. `createCollaborator` retombe sur une
        // closure qui refuse systématiquement (`nil`) si l'appelant n'a pas
        // fourni `create` : l'entrée « Créer … » reste alors affichée
        // (décision pure de `MentionCatalog.rows`, indépendante de cette
        // closure) mais n'insère rien si choisie, comme documenté par
        // `markdownMentions`.
        if let search = mentionSearch {
            context.coordinator.mentionController = MentionController(
                textView: editor,
                panel: MentionPanel(),
                cancelPendingWrite: { [weak coord = context.coordinator] in
                    coord?.cancelPendingWrite()
                },
                searchCollaborators: search,
                createCollaborator: mentionCreate ?? { _ in nil }
            )
        }
        // Expose l'éditeur à une éventuelle MarkdownToolbar via le registre partagé.
        if !editorID.isEmpty {
            MarkdownEditorRegistry.shared.register(editor, id: editorID)
        }
        applyInitialState(editor: editor, coordinator: context.coordinator)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        let id = coordinator.parent.editorID
        if !id.isEmpty { MarkdownEditorRegistry.shared.unregister(id: id) }
        coordinator.slashController?.teardown()
        coordinator.slashController = nil
        coordinator.mentionController?.teardown()
        coordinator.mentionController = nil
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? EditorTextView else { return }
        context.coordinator.parent = self
        editor.isEditable = !readOnly
        context.coordinator.features = features
        context.coordinator.debounce = debounce
        context.coordinator.slashController?.updateFeatures(features)
        // Rafraîchi à chaque rendu, même raison que les closures de mentions
        // ci-dessous : l'appelant peut capturer un `@Query`/`ModelContext`
        // reconstruit à chaque `body`.
        editor.onLinkClick = linkHandler
        // Rafraîchit les closures de recherche/création à chaque rendu — voir
        // la doc de `MentionController.updateHandlers` : nécessaire, pas
        // seulement défensif, tant que l'appelant capture un `@Query`/
        // `ModelContext` dans une closure reconstruite à chaque `body`.
        if let search = mentionSearch {
            context.coordinator.mentionController?.updateHandlers(
                searchCollaborators: search,
                createCollaborator: mentionCreate ?? { _ in nil }
            )
        }

        let incoming = markdown
        if context.coordinator.hasPendingLocalWrite {
            if incoming == context.coordinator.lastKnownMarkdown {
                context.coordinator.hasPendingLocalWrite = false
            }
            return
        }

        if context.coordinator.lastKnownMarkdown != incoming {
            context.coordinator.cancelPendingWrite()
            let attr = MarkdownParser.parse(incoming)
            let savedSelection = editor.selectedRange()
            editor.textStorage?.setAttributedString(attr)
            context.coordinator.lastKnownMarkdown = incoming
            if let storage = editor.textStorage {
                StyleRenderer.applyVisualStyle(to: storage)
            }
            let clampedLocation = min(savedSelection.location, attr.length)
            editor.setSelectedRange(NSRange(location: clampedLocation, length: 0))
        }
    }

    // MARK: - Initial state

    private func applyInitialState(editor: EditorTextView, coordinator: Coordinator) {
        editor.isEditable = !readOnly
        let attr = MarkdownParser.parse(markdown)
        editor.textStorage?.setAttributedString(attr)
        if let storage = editor.textStorage {
            StyleRenderer.applyVisualStyle(to: storage)
        }
        coordinator.lastKnownMarkdown = markdown
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorRepresentable
        weak var textView: EditorTextView?
        var lastKnownMarkdown: String = ""
        var features: Set<MarkdownFeature>
        var debounce: TimeInterval
        var hasPendingLocalWrite: Bool = false
        /// Menu « / » (tâche 6). Construit dans `makeNSView`, démonté dans
        /// `dismantleNSView`. `nil` seulement pour un `Coordinator` créé à la
        /// main sans passer par `makeNSView` (ex. certains tests plus anciens
        /// qui n'exercent pas le menu).
        var slashController: SlashController?
        /// Menu « @ » des mentions de collaborateurs. `nil` si l'appelant n'a
        /// pas fourni `markdownMentions(search:...)` — voir `mentionSearch`.
        var mentionController: MentionController?
        private var pendingStyleRange: NSRange?
        private var debounceTask: Task<Void, Never>?
        /// Garde anti-récursion : `ShortcutDetector.apply` mute le storage,
        /// ce qui re-déclenche `textDidChange`. Sans ce flag on appliquerait
        /// les shortcuts en boucle.
        private var isApplyingShortcut: Bool = false

        init(parent: EditorRepresentable) {
            self.parent = parent
            self.features = parent.features
            self.debounce = parent.debounce
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            let replacementLength = (replacementString ?? "").utf16.count
            pendingStyleRange = NSRange(location: range.location, length: max(range.length, replacementLength))
            return true
        }

        /// Délègue la navigation clavier (↑ ↓ ⏎ Tab ⇧Tab ⌫ Échap) au menu
        /// ouvert — « @ » en priorité s'il l'est (mentions de collaborateurs),
        /// sinon « / » (tâche 6), qui porte aussi le correctif du Retour après
        /// un titre (piège 4). Si aucun des deux menus n'a rien consommé — et
        /// que le menu « / » n'est pas ouvert (voir plus bas) —,
        /// `ListEditingCommands` prend le relais pour ⏎/Tab/⇧Tab/⌫ à
        /// l'intérieur d'un item de liste. Les deux menus ne peuvent pas être
        /// ouverts simultanément : chacun ne s'ouvre que sur son propre
        /// caractère déclencheur, et `Coordinator.textDidChange`
        /// court-circuite dès qu'un des deux absorbe la frappe (voir plus
        /// bas) — cet ordre est donc surtout une question de priorité de
        /// lecture, pas un vrai arbitrage entre deux états concurrents.
        /// `handle` renvoie `true` si la commande a été consommée —
        /// l'appelant (`NSTextView`) n'exécute alors pas son comportement par
        /// défaut.
        ///
        /// Garde `slashController?.isOpen == true` avant `ListEditingCommands` :
        /// `SlashController.handle` n'intercepte, menu ouvert, que
        /// ↑↓/⏎/Tab/Échap (voir sa doc — « Tout le reste (dont ⌫) n'est pas
        /// intercepté : le comportement par défaut s'applique ») ; sans cette
        /// garde, un `⌫`/`⇧Tab` tapé pendant la composition d'une requête sur
        /// une ligne qui est *aussi* un item de liste (ex. `/` tapé au tout
        /// début d'un item vide) tomberait à tort dans
        /// `ListEditingCommands` — la requête en cours de frappe n'est ni du
        /// texte de list ni un raccourci clavier de liste.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if mentionController?.isOpen == true {
                return mentionController?.handle(commandSelector: commandSelector) ?? false
            }
            if slashController?.handle(commandSelector: commandSelector) == true {
                return true
            }
            if slashController?.isOpen == true {
                return false
            }
            return ListEditingCommands.handle(commandSelector: commandSelector, in: textView)
        }

        /// Ferme le menu « / » et/ou « @ » si le curseur sort de la plage de
        /// leur requête respective (clic ailleurs, flèche gauche/droite) —
        /// voir `SlashController.selectionDidChange`/`MentionController.
        /// selectionDidChange`. Les deux appels sont sans risque même si un
        /// seul des deux menus (au plus) est effectivement ouvert : chacun
        /// vérifie son propre `isOpen` en interne et ne fait rien sinon.
        func textViewDidChangeSelection(_ notification: Notification) {
            slashController?.selectionDidChange()
            mentionController?.selectionDidChange()
        }

        /// Réagit à chaque frappe : applique les raccourcis markdown puis
        /// ré-applique le style visuel, le tout sous `isApplyingShortcut` pour
        /// ignorer les `textDidChange` ré-émis par ces mutations (anti-boucle),
        /// avant de pousser le markdown vers le binding (débouncé).
        func textDidChange(_ notification: Notification) {
            // Le menu « / » (tâche 6) absorbe la frappe s'il vient de
            // s'ouvrir, de filtrer ou de se fermer : ni `ShortcutDetector`, ni
            // la sérialisation, ni le (re)programmation du debounce ne
            // doivent alors s'exécuter — voir l'en-tête de `SlashController`.
            if slashController?.textDidChange() == true { return }
            // Même court-circuit pour le menu « @ » des mentions — voir
            // `MentionController.textDidChange()`. Appelé seulement si le
            // menu « / » n'a pas déjà absorbé la frappe : les deux ne
            // s'ouvrent jamais sur le même caractère, donc cet ordre ne fait
            // jamais manquer une frappe destinée à « @ ».
            if mentionController?.textDidChange() == true { return }

            guard let tv = textView, let storage = tv.textStorage else { return }
            if isApplyingShortcut { return }

            let cursor = tv.selectedRange().location
            if cursor > 0 {
                let inserted = (storage.string as NSString)
                    .substring(with: NSRange(location: cursor - 1, length: 1))
                isApplyingShortcut = true
                ShortcutDetector.apply(after: inserted, in: tv, cursor: cursor, features: features)
                isApplyingShortcut = false
            }

            let styleRange = pendingStyleRange ?? NSRange(location: tv.selectedRange().location, length: 0)
            pendingStyleRange = nil
            
            isApplyingShortcut = true
            StyleRenderer.applyVisualStyle(to: storage, affectedRange: styleRange)
            isApplyingShortcut = false

            let newMarkdown = MarkdownSerializer.serialize(storage)
            
            if newMarkdown == lastKnownMarkdown { return }
            lastKnownMarkdown = newMarkdown
            hasPendingLocalWrite = true
            
            debounceTask?.cancel()
            let delay = debounce
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard let self else { return }
                if Task.isCancelled { return }
                self.parent.markdown = newMarkdown
            }
        }

        func cancelPendingWrite() {
            debounceTask?.cancel()
            debounceTask = nil
        }

        /// Sérialise le storage en markdown et le propage au binding parent.
        /// Sans changement vs. `lastKnownMarkdown`, ne fait rien. Avec
        /// `force = true`, écrit immédiatement (ex. toggle de tâche) ;
        /// sinon l'écriture est débouncée et toute écriture en attente annulée.
        func pushMarkdownToBinding(force: Bool) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let md = MarkdownSerializer.serialize(storage)
            if md == lastKnownMarkdown { return }
            lastKnownMarkdown = md
            hasPendingLocalWrite = true
            if force {
                parent.markdown = md
                return
            }
            debounceTask?.cancel()
            let delay = debounce
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                guard let self else { return }
                if Task.isCancelled { return }
                self.parent.markdown = md
            }
        }
    }
}
