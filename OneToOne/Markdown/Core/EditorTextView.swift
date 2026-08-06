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

    /// Set by the SwiftUI coordinator to route a clicked link. Returns
    /// `true` if handled (typically an internal `onetoone://…` URL) — a
    /// `false`/`nil` result (no closure, or the closure declined) lets
    /// `clicked(onLink:at:)` fall through to `super`, which opens the link
    /// through the system for an external URL. See `EditorRepresentable`'s
    /// `markdownLinks(handler:)`.
    var onLinkClick: ((URL) -> Bool)?

    /// Set by the SwiftUI coordinator to handle ⌥↑ (`true`) / ⌥↓ (`false`) —
    /// déplacement du bloc portant le curseur (voir `BlockMoveCommands`).
    /// `nil` (le défaut, ex. un `EditorTextView` construit à la main sans
    /// passer par `EditorRepresentable.makeNSView`) laisse `keyDown(with:)`
    /// retomber sur `super`, comportement natif inchangé — même convention
    /// que `onLinkClick`.
    var onOptionVerticalArrow: ((Bool) -> Void)?

    /// Set par le coordinateur SwiftUI pour les opérations de structure sur
    /// un tableau (ajouter/supprimer une ligne ou une colonne, voir
    /// `TableEditCommands`) — déclenchées au clavier plutôt qu'au survol
    /// (« poignées » à la AppFlowy) : `EditorTextView` ne gère que
    /// `mouseDown`, aucune infrastructure de suivi de souris n'existe (même
    /// constat que `onOptionVerticalArrow`). Choix retenu plutôt que des
    /// entrées dans le menu `/` : ces dernières auraient exigé de faire
    /// transiter le contexte curseur (cellule de tableau ou non) à travers
    /// `SlashCatalog.grouped`/`SlashController.updateFilter`, qui ne filtrent
    /// aujourd'hui que par `MarkdownFeature` — un jeu de fonctionnalités
    /// statique, pas une position dans le document — donc un remaniement
    /// plus large pour une surface fonctionnelle équivalente ; le clavier
    /// reprend au contraire tel quel le patron déjà mesuré
    /// d'`onOptionVerticalArrow` (interception avant `doCommandBy:`,
    /// enregistrement manuel de l'inverse auprès d'`undoManager`). Combinaison
    /// ⌘⌥ + flèche (bas = ligne, droite = colonne ; ajout = flèche seule,
    /// suppression = flèche + ⇧) : aucun raccourci existant de ce module ni
    /// des menus de l'app (`Views/Menus/MeetingCommands.swift`) ne l'utilise
    /// — Tab/⇧Tab (indentation de liste) et ⌥↑/⌥↓ (déplacement de bloc)
    /// restent seuls sur leurs combinaisons respectives.
    var onTableEditCommand: ((TableEditCommands.Gesture) -> Void)?

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

    // MARK: - ⌥↑ / ⌥↓ — déplacement de bloc

    /// Code matériel des flèches Haut/Bas — stables quel que soit
    /// l'agencement clavier (contrairement à `charactersIgnoringModifiers`,
    /// qui peut varier). Valeurs `kVK_UpArrow`/`kVK_DownArrow` de
    /// `Carbon.HIToolbox`, recopiées ici pour ne pas importer tout Carbon
    /// pour deux constantes.
    private static let upArrowKeyCode: UInt16 = 0x7E
    private static let downArrowKeyCode: UInt16 = 0x7D
    /// Code matériel de la flèche Droite — voir la doc de
    /// `onTableEditCommand` : ⌘⌥→ ajoute une colonne à droite.
    private static let rightArrowKeyCode: UInt16 = 0x7C

    /// Modificateurs qui distinguent réellement une combinaison — masque
    /// volontairement `.capsLock`/`.numericPad`/`.function`/`.help`, que
    /// macOS pose aussi sur un événement flèche indépendamment de ce que
    /// l'utilisateur tient réellement (mesuré : un ⌥↑ synthétique construit
    /// sans ces flags est bien celui que macOS envoie pour de vrai — voir le
    /// rapport de tâche — comparer `modifierFlags` à `.option` seul, sans ce
    /// masque, échouerait si l'OS les ajoutait).
    private static let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Intercepte ⌥↑/⌥↓ **avant** `interpretKeyEvents:`/`doCommandBy:` :
    /// mesuré (rapport de tâche), la combinaison résout via
    /// `StandardKeyBinding.dict` en DEUX sélecteurs par frappe —
    /// `moveBackward:`+`moveToBeginningOfParagraph:` pour ⌥↑,
    /// `moveForward:`+`moveToEndOfParagraph:` pour ⌥↓ — chacun *partagé* avec
    /// d'autres raccourcis (`^b`/`^a`/`^f`/`^e`) : les intercepter via
    /// `Coordinator.textView(_:doCommandBy:)` détournerait ces derniers
    /// aussi. Consomme systématiquement l'événement dès que `onOptionVerticalArrow`
    /// est présent — y compris aux bords du document (le bloc ne bouge pas,
    /// mais la touche ne doit pas non plus retomber sur la navigation par
    /// paragraphe qu'elle remplace) ; `nil` (pas de closure assignée) laisse
    /// `super` gérer, comportement natif inchangé.
    override func keyDown(with event: NSEvent) {
        if let handler = onOptionVerticalArrow,
           event.modifierFlags.intersection(Self.relevantModifiers) == .option {
            switch event.keyCode {
            case Self.upArrowKeyCode:
                handler(true)
                return
            case Self.downArrowKeyCode:
                handler(false)
                return
            default:
                break
            }
        }
        if let handler = onTableEditCommand,
           event.modifierFlags.intersection(Self.relevantModifiers) == [.command, .option] {
            switch event.keyCode {
            case Self.downArrowKeyCode:
                handler(.addRowBelow)
                return
            case Self.rightArrowKeyCode:
                handler(.addColumnRight)
                return
            default:
                break
            }
        }
        if let handler = onTableEditCommand,
           event.modifierFlags.intersection(Self.relevantModifiers) == [.command, .option, .shift] {
            switch event.keyCode {
            case Self.downArrowKeyCode:
                handler(.deleteRow)
                return
            case Self.rightArrowKeyCode:
                handler(.deleteColumn)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
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
    /// de tâche, puis pour préserver le placement du curseur sur un clic
    /// simple au-dessus d'un lien (voir `suspendingNativeLink`). Délègue au
    /// comportement standard de `NSTextView` dans tous les autres cas — y
    /// compris ⌘-clic sur un lien, qu'AppKit route lui-même vers
    /// `clicked(onLink:at:)` (ci-dessous).
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let gesture = tableControlGesture(at: point) {
            onTableEditCommand?(gesture)
            return
        }
        if toggleTaskMarker(at: point) { return }

        // Mesuré (sonde jetée après mesure, cf. commit) : dans cette
        // configuration TextKit 1 (`NSTextStorage` → `MarkdownLayoutManager`
        // → `NSTextContainer`), le `mouseDown` natif d'AppKit route TOUT
        // clic tombant sur une plage `.link` vers `clicked(onLink:at:)` —
        // simple clic compris, ⌘ ou pas, `isEditable` ou pas — et le
        // curseur ne se déplace jamais dans ce cas (contrairement à un clic
        // hors lien, qui positionne bien le curseur : témoin vérifié dans la
        // même sonde). La croyance répandue qu'un ⌘-clic serait nécessaire
        // en mode éditable ne s'est *pas* vérifiée ici. Sans intervention,
        // un simple clic sur un lien rendrait donc son texte impossible à
        // corriger au clavier — régression explicitement proscrite par ce
        // chantier. On ne neutralise que le cas simple clic + éditable :
        // ⌘-clic doit au contraire atteindre `clicked(onLink:at:)`.
        if isEditable, !event.modifierFlags.contains(.command), let linkRange = nativeLinkRange(at: point) {
            suspendingNativeLink(in: linkRange) {
                super.mouseDown(with: event)
            }
            return
        }

        super.mouseDown(with: event)
    }

    // MARK: - Click handling for links

    /// Plage effective de l'attribut natif `.link` (posé par
    /// `StyleRenderer` à partir de `.mdLink`) sous `point`, ou `nil` si `point`
    /// ne tombe sur aucun lien. Même logique de conversion que
    /// `toggleTaskMarker` : `characterIndexForInsertion`, bornée à
    /// `storage.length - 1`.
    func nativeLinkRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let charIndex = characterIndexForInsertion(at: point)
        let safeIndex = min(charIndex, storage.length - 1)
        guard safeIndex >= 0 else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard storage.attribute(.link, at: safeIndex, effectiveRange: &effectiveRange) != nil else { return nil }
        return effectiveRange
    }

    /// Retire l'attribut natif `.link` sur `range` (jamais `.mdLink`, la
    /// source de vérité markdown que `StyleRenderer` laisse intacte) le
    /// temps d'exécuter `body`, puis le restaure. Utilisé pour qu'un simple
    /// clic sur un lien, en mode éditable, traverse `super.mouseDown` comme
    /// un clic de texte ordinaire (voir le commentaire de `mouseDown`)
    /// plutôt que d'être avalé par la reconnaissance de lien native
    /// d'AppKit. Mutation directe du storage hors `beginEditing`/`endEditing`
    /// — même choix qu'`applyTaskToggle`, pour ne déclencher ni
    /// `textDidChange` ni re-sérialisation pour ce qui n'est qu'un attribut
    /// d'affichage transitoire.
    func suspendingNativeLink(in range: NSRange, _ body: () -> Void) {
        guard let storage = textStorage,
              range.location + range.length <= storage.length,
              let value = storage.attribute(.link, at: range.location, effectiveRange: nil)
        else {
            body()
            return
        }
        storage.removeAttribute(.link, range: range)
        body()
        storage.addAttribute(.link, value: value, range: range)
    }

    /// Ouvre un lien externe via le système. `Coordinator`
    /// (`EditorRepresentable.swift`) n'implémente aucune méthode
    /// `NSTextViewDelegate` liée aux liens (`textView(_:clickedOnLink:at:)`),
    /// donc appeler directement `NSWorkspace` ici équivaut à ce que ferait
    /// `super.clicked(onLink:at:)` par défaut pour une valeur `URL` — sans
    /// perdre de comportement délégué. Extrait en propriété injectable pour
    /// que les tests puissent vérifier qu'un lien décliné par `onLinkClick`
    /// atteint bien ce chemin, sans réellement lancer d'application externe
    /// pendant les tests (voir `Tests/EditorTextViewLinkClickTests.swift`).
    var openExternalLink: (URL) -> Void = { NSWorkspace.shared.open($0) }

    /// Point d'entrée qu'AppKit appelle lui-même dès qu'il reconnaît un clic
    /// sur une plage `.link` (voir le commentaire de `mouseDown` : ceci
    /// couvre aussi bien le mode lecture seule — clic simple — que le
    /// ⌘-clic en mode éditable). Donne d'abord la main à `onLinkClick`
    /// (routage interne, ex. mention `onetoone://collaborator/<uuid>` — voir
    /// `EditorRepresentable.markdownLinks(handler:)`) ; si absent ou décliné
    /// (`false`), retombe sur `openExternalLink` — c'est le chemin normal
    /// pour un lien externe (`https://`, `mailto:`…). Une valeur `link` qui
    /// n'est pas une `URL` retombe directement sur `super`, comportement
    /// natif inchangé (ce chantier ne pose `.link` qu'avec des `URL`, voir
    /// `StyleRenderer`, mais `clicked(onLink:at:)` reste un point d'entrée
    /// public qu'un appelant externe pourrait invoquer avec autre chose).
    override func clicked(onLink link: Any, at charIndex: Int) {
        guard let url = link as? URL else {
            super.clicked(onLink: link, at: charIndex)
            return
        }
        if onLinkClick?(url) == true { return }
        openExternalLink(url)
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

    // MARK: - Click handling for table controls

    /// Contrôle de tableau (voir `TableControlLayout`) sous `point`
    /// (coordonnées de la vue, mêmes que `toggleTaskMarker`), ou `nil` si
    /// aucun n'y est peint. Dérivé de la position du **curseur**
    /// (`selectedRange().location`), pas du point cliqué : les contrôles ne
    /// sont peints que pour la cellule qui porte le curseur (voir
    /// `MarkdownLayoutManager.drawTableControls`) — le hit-test doit tester
    /// exactement le même jeu de rectangles, jamais en dériver un autre
    /// depuis la ligne cliquée. Même schéma de conversion que
    /// `toggleTaskMarker` : retire `textContainerInset` du point vue pour
    /// retomber en coordonnées du conteneur, celles de `TableControlLayout.
    /// Placement`.
    ///
    /// `internal` (pas `private`) pour être exercée directement par les
    /// tests, comme `toggleTaskMarker` — voir sa doc pour la raison (`mouseDown`
    /// réel non pilotable en test, cf. aussi le rapport de tâche : une boucle
    /// de tracking AppKit attendant un `mouseUp` synthétique a bloqué un essai
    /// précédent).
    func tableControlGesture(at point: NSPoint) -> TableEditCommands.Gesture? {
        guard isEditable, let storage = textStorage, storage.length > 0,
              let layoutManager, let container = textContainer
        else { return nil }
        let location = min(selectedRange().location, storage.length - 1)
        guard location >= 0,
              let placement = TableControlLayout.placementForCursor(
                in: storage, at: location, layoutManager: layoutManager, container: container
              )
        else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        return TableControlLayout.gesture(at: containerPoint, in: placement)
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
