import AppKit
import os

private let editorLog = Logger(subsystem: "com.onetoone.app", category: "markdown-editor")

/// `NSTextView` subclass that owns markdown-aware editing. Renders the custom
/// `md*` attribute keys with appropriate fonts/colours and intercepts clicks
/// on task-list checkboxes to toggle them in place.
final class EditorTextView: NSTextView {

    /// Set by the SwiftUI coordinator so toggling a checkbox can push the
    /// new state up the binding.
    var onTaskToggle: ((NSRange, Bool) -> Void)?

    // MARK: - Lifecycle

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Configure les options d'édition de texte. Les corrections/complétions/
    /// remplacements automatiques sont désactivés car ils interféreraient avec
    /// la syntaxe markdown (ex. transformation des `--` en tiret long), et
    /// `importsGraphics` est coupé car l'éditeur ne gère que du texte balisé.
    private func commonInit() {
        isRichText = true
        allowsUndo = true
        importsGraphics = false
        usesFindBar = true
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        font = NSFont.systemFont(ofSize: 13)
        textContainerInset = NSSize(width: 6, height: 6)
    }

    // MARK: - Collage

    /// Attributs `md*` à retirer des `typingAttributes` avant d'insérer un
    /// placeholder d'image. Sans ce nettoyage, `insertText(_:replacementRange:)`
    /// les fusionne dans la plage insérée : `NSTextView` maintient
    /// `typingAttributes` à partir des attributs du caractère précédant le
    /// curseur, et complète avec ces valeurs les clés absentes de la chaîne
    /// attribuée qu'on lui passe. Un collage juste après du code inline
    /// hériterait ainsi `.mdInlineCode` sur le caractère `U+FFFC` — et
    /// `MarkdownSerializer.emitInline` donne la priorité exclusive au code
    /// inline, qui filtre les `U+FFFC` de son contenu : l'image disparaîtrait
    /// purement et simplement à la sérialisation, fichier resté orphelin sur
    /// disque. Un collage après du gras hériterait `.mdBold` et se
    /// retrouverait emballé en `**![...]**` sans que l'utilisateur l'ait
    /// demandé. Vérifié empiriquement pour ces deux cas — voir
    /// `Tests/EditorTextViewPasteTests.swift`.
    private static let inlineAttributesToStripBeforeImageInsertion: [NSAttributedString.Key] = [
        .mdInlineCode, .mdBold, .mdItalic, .mdStrikethrough, .mdLink
    ]

    /// Insère le placeholder référençant `imageURL` sur sa propre ligne, en
    /// évitant qu'il hérite des attributs `md*` du contexte via
    /// `typingAttributes` (voir `inlineAttributesToStripBeforeImageInsertion`).
    /// Point d'entrée commun à `paste(_:)` et au bouton image de
    /// `MarkdownToolbar`, pour que les deux bénéficient du même nettoyage.
    func insertImagePlaceholder(for imageURL: URL, alt: String = "image") {
        for key in Self.inlineAttributesToStripBeforeImageInsertion {
            typingAttributes.removeValue(forKey: key)
        }
        insertText(Self.imagePlaceholder(for: imageURL, alt: alt), replacementRange: selectedRange())
    }

    /// Si le presse-papiers contient une image, l'enregistre sur disque et
    /// insère son placeholder ; sinon délègue au collage standard.
    ///
    /// Le placeholder inséré est la même représentation que celle produite par
    /// `MarkdownParser` pour une image (voir `ImagePlaceholder`), et non le
    /// texte `![alt](url)` littéral : sans ses attributs, `MarkdownSerializer`
    /// traiterait ce texte comme de la saisie ordinaire et échapperait ses
    /// caractères spéciaux (`!`, `[`, `]`, `(`, `)`, `_` — voir
    /// `MarkdownEscaping.escapeInline`) dès le `textDidChange` déclenché par
    /// cette insertion, corrompant la référence de façon permanente. Avec le
    /// placeholder attribué, ce même `textDidChange` fait au contraire
    /// apparaître l'image immédiatement : `StyleRenderer.applyVisualStyle`
    /// repère `.mdImageURL` sur la plage insérée et y attache le
    /// `NSTextAttachment` réel, sans attendre de frappe supplémentaire.
    ///
    /// Si `saveClipboardImage()` échoue (écriture disque impossible), le
    /// repli vers `super.paste(sender)` ne colle rien de visible : le
    /// presse-papiers ne contient par construction que de l'image à ce point
    /// (le `guard` a déjà exclu le cas contraire), et `importsGraphics =
    /// false` (`commonInit`) fait que `NSTextView` ignore le contenu image
    /// brut. C'est un échec silencieux connu et accepté (pas de UI d'erreur
    /// pour un cas limite — disque plein, permissions — jugé hors périmètre
    /// ici) plutôt qu'un bug : l'utilisateur ne perd rien puisque rien
    /// n'avait encore été inséré.
    override func paste(_ sender: Any?) {
        guard MediaStore.clipboardHasImage,
              let imageURL = MediaStore.saveClipboardImage() else {
            super.paste(sender)
            return
        }
        insertImagePlaceholder(for: imageURL)
    }

    /// Construit le placeholder à insérer pour référencer `imageURL` : le
    /// caractère `ImagePlaceholder.attributedString` entouré de retours à la
    /// ligne pour que l'image occupe sa propre ligne. Isolé en fonction
    /// `static` pour être exercé par les tests indépendamment de
    /// `NSPasteboard.general`.
    static func imagePlaceholder(for imageURL: URL, alt: String = "image") -> NSAttributedString {
        let insertion = NSMutableAttributedString(string: "\n")
        insertion.append(ImagePlaceholder.attributedString(for: imageURL, alt: alt))
        insertion.append(NSAttributedString(string: "\n"))
        return insertion
    }

    // MARK: - Click handling for task checkboxes

    /// Intercepte le clic pour détecter s'il vise la case à cocher d'un item
    /// de tâche. Délègue au comportement standard de `NSTextView` si ce
    /// n'est pas le cas.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if toggleTaskMarker(at: point) { return }
        super.mouseDown(with: event)
    }

    /// Bascule l'état d'une case à cocher si `point` (coordonnées de la vue,
    /// mêmes que celles de `mouseDown`) tombe sur son marqueur, et renvoie si
    /// c'était le cas. Lit `.mdListInfo` à la ligne cliquée plutôt que de
    /// comparer des caractères littéraux : le storage ne contient jamais
    /// `"- [ ] "`/`"- [x] "`, seulement le texte affichable (voir
    /// `MarkdownParser`) — comparer ces préfixes, comme le faisait l'ancienne
    /// version de cette méthode, ne pouvait donc jamais matcher sur un
    /// véritable item de tâche.
    ///
    /// La zone cliquable est restreinte à la marge où `MarkdownLayoutManager`
    /// dessine le marqueur — à gauche de `paragraphStyle.firstLineHeadIndent`,
    /// sur la hauteur du fragment de ligne — pour ne pas intercepter un clic
    /// destiné à positionner le curseur dans le texte de l'item. Ne fait rien
    /// en lecture seule (`isEditable == false`) : basculer une case reste une
    /// édition.
    ///
    /// Internal (pas `private`) pour être exercée directement par les tests
    /// sans reconstruire un `NSEvent`/`NSWindow`, sur le modèle de
    /// `insertImagePlaceholder`.
    @discardableResult
    func toggleTaskMarker(at point: NSPoint) -> Bool {
        guard isEditable, let storage = textStorage, storage.length > 0, let layoutManager else { return false }

        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return false }

        let ns = storage.string as NSString
        var lineStart = safeIndex
        while lineStart > 0, ns.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }

        // Plage du *paragraphe cliqué* uniquement — jamais
        // `longestEffectiveRange` : `ListInfo` est `Hashable`, donc
        // `NSAttributedString` fusionne les runs adjacents de valeur égale.
        // Mesuré : une checklist neuve à trois items décochés ne porte qu'un
        // unique run `.mdListInfo` couvrant les trois lignes ; y lire
        // `longestEffectiveRange` à la 2e ligne renvoyait la plage des
        // *trois*, et écrire dessus cochait les trois d'un seul clic.
        // `NSString.lineRange(for:)` inclut le `\n` terminal, exactement
        // comme `MarkdownParser.emitList` pose `.mdListInfo` sur la plage
        // d'un item (contenu + retour à la ligne) : c'est donc la plage d'un
        // seul item, quel que soit l'état de ses voisins.
        let range = ns.lineRange(for: NSRange(location: lineStart, length: 0))

        guard let info = storage.attribute(.mdListInfo, at: lineStart, effectiveRange: nil) as? ListInfo,
              info.kind == .task else {
            return false
        }

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let paragraphStyle = storage.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle
        let textIndent = paragraphStyle?.firstLineHeadIndent ?? ListMarkerLayout.textIndent(for: info)
        guard containerPoint.x < textIndent else { return false }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard containerPoint.y >= lineFragmentRect.minY, containerPoint.y <= lineFragmentRect.maxY else {
            return false
        }

        let toggled = ListInfo(kind: info.kind, level: info.level, index: info.index, checked: !(info.checked ?? false))
        applyTaskToggle(range: range, from: info, to: toggled)
        return true
    }

    /// Bascule effectivement `.mdListInfo` sur `range`, de `oldInfo` vers
    /// `newInfo` : mute l'attribut, restyle, notifie `onTaskToggle`, et
    /// enregistre l'inverse auprès de `undoManager`.
    ///
    /// N'utilise pas `shouldChangeText(in:replacementString:)`/
    /// `didChangeText()` : ce chemin redéclencherait tout
    /// `Coordinator.textDidChange` (raccourcis markdown, sérialisation,
    /// poussée *débouncée* vers le binding), qui ferait double emploi avec la
    /// poussée *immédiate* que fait déjà `onTaskToggle` — et la débouncée,
    /// planifiée après coup, absorberait l'avantage recherché (persistance
    /// immédiate d'un clic de case à cocher, cf. doc d'`onTaskToggle` dans
    /// `EditorRepresentable`).
    ///
    /// `applyTaskToggle` réenregistre son propre inverse à chaque exécution —
    /// bascule initiale, annulation ou rétablissement — ce qui fait
    /// fonctionner ⌘Z et ⇧⌘Z symétriquement sans code dédié à chacun. Sans
    /// cet enregistrement, une bascule mutait `textStorage` sans passer par
    /// aucun mécanisme d'undo : ⌘Z n'avait alors aucun effet sur elle et
    /// annulait à la place la dernière édition de texte réelle, sans rapport
    /// (vérifié dans une fenêtre réelle : frapper du texte, basculer une
    /// case, ⌘Z annulait la frappe et laissait la case cochée).
    private func applyTaskToggle(range: NSRange, from oldInfo: ListInfo, to newInfo: ListInfo) {
        guard let storage = textStorage, range.location + range.length <= storage.length else { return }
        storage.addAttribute(.mdListInfo, value: newInfo, range: range)
        StyleRenderer.applyVisualStyle(to: storage, affectedRange: range)
        onTaskToggle?(range, newInfo.checked ?? true)
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyTaskToggle(range: range, from: newInfo, to: oldInfo)
        }
    }
}
