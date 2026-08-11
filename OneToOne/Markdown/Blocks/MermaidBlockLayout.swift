import AppKit

/// Géométrie du rendu d'un bloc mermaid **fermé** (diagramme peint,
/// curseur ailleurs) dans l'éditeur.
///
/// Le texte source d'un bloc ```` ```mermaid ```` reste du texte ordinaire
/// dans le storage (voir `StyleRenderer.applyMermaidAttachment`) : ni le
/// parser ni le sérialiseur ne sont touchés par ce chantier. Mais sa hauteur
/// affichée ne doit **jamais** être une réservation étalée sur les lignes du
/// source (`220pt / lineCount`, le défaut mesuré par l'utilisateur : deux
/// lignes de source devenaient deux bandes de 110pt) — elle doit suivre le
/// contenu réel : celle de l'image de l'attachment une fois connue
/// (`MermaidAttachmentFactory`), ou une hauteur provisoire modeste tant que
/// le rendu web (asynchrone) n'a pas encore répondu. Toutes les lignes de
/// source **sauf la première** du bloc sont visuellement écrasées
/// (`hiddenLineMaximumHeight`) : la mise en page tient sur une seule ligne,
/// jamais étalée sur `lineCount` lignes.
enum MermaidBlockLayout {

    /// Marge interne entre le cadre du bloc et le diagramme qui y est inscrit.
    static let horizontalInset: CGFloat = 18
    static let verticalInset: CGFloat = 16
    static let cardCornerRadius: CGFloat = 8

    static let backgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x1f/255, green: 0x20/255, blue: 0x24/255, alpha: 1)
            : NSColor.white
    }
    static let borderColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.16)
            : NSColor(red: 0xe3/255, green: 0xe0/255, blue: 0xda/255, alpha: 1)
    }
    static let loadingBackgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x22/255, green: 0x23/255, blue: 0x27/255, alpha: 1)
            : NSColor(red: 0xfa/255, green: 0xf8/255, blue: 0xf5/255, alpha: 1)
    }
    static let loadingTextColor = NSColor.secondaryLabelColor
    static let errorBackgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x32/255, green: 0x25/255, blue: 0x25/255, alpha: 1)
            : NSColor(red: 0xfd/255, green: 0xf6/255, blue: 0xf5/255, alpha: 1)
    }
    static let errorBorderColor = NSColor(red: 0xe9/255, green: 0xb8/255, blue: 0xb3/255, alpha: 1)
    static let errorTitleColor = NSColor(red: 0xc0/255, green: 0x39/255, blue: 0x2f/255, alpha: 1)
    static let errorDetailColor = NSColor(red: 0x8a/255, green: 0x3a/255, blue: 0x31/255, alpha: 1)

    /// Hauteur provisoire, modeste, réservée tant que le rendu web n'a pas
    /// encore livré d'image (`MermaidAttachmentFactory.placeholder`) — jamais
    /// une hauteur étalée sur les lignes du source (l'ancien défaut : 220pt).
    static let placeholderHeight: CGFloat = 104

    /// Largeur de la colonne commune aux trois états d'un bloc mermaid
    /// (carte rendue, placeholder de chargement, cadre d'erreur) : celle de
    /// la colonne de texte sur la fenêtre de référence. Constante **propre à
    /// mermaid** — les images ordinaires gardent leur limite distincte
    /// (`ImageAttachmentFactory.maxWidth`, plus petite) : un `NSTextAttachment`
    /// d'image n'est jamais réajusté au conteneur au moment du dessin,
    /// contrairement aux cartes mermaid (`fittedSize` dans
    /// `MarkdownLayoutManager.drawMermaidDiagram`), et déborderait d'un
    /// éditeur plus étroit que cette colonne.
    static let columnWidth: CGFloat = 960

    /// Largeur du cadre de secours (chargement/erreur) — voir
    /// `MermaidAttachmentFactory.frameWidth`, dupliquée ici comme source de
    /// vérité unique pour éviter la dérive des deux constantes. Elle est
    /// volontairement celle de la colonne de texte : le rendu terminé, le
    /// chargement et l'erreur doivent avoir exactement le même cadre que le
    /// source Mermaid ouvert.
    static let placeholderWidth: CGFloat = columnWidth

    /// Hauteur du cadre d'erreur (avec message mermaid) — voir
    /// `MermaidAttachmentFactory.frameHeightWithDetail`.
    static let errorFrameHeight: CGFloat = 132

    /// Hauteur de ligne maximale forcée sur les lignes de source d'un bloc
    /// **fermé** qui ne portent pas la réservation du diagramme (toutes sauf
    /// la première) — écrase leur hauteur naturelle (police de bloc de code
    /// normale) à un filet quasi nul, sans avoir besoin de toucher à leur
    /// police : `NSParagraphStyle.maximumLineHeight` est un plafond dur
    /// (contrairement à `minimumLineHeight`, un plancher), documenté par
    /// Apple comme « clipped to this value » — exactement l'effet voulu.
    /// Valeur non nulle : `maximumLineHeight == 0` est le sentinel APIs
    /// « pas de plafond », pas un plafond à zéro.
    static let hiddenLineMaximumHeight: CGFloat = 1

    /// Nombre de lignes de `source` (comptage des `\n`, plus un). Jamais nul,
    /// même pour un source vide — utilisé par la gouttière de numéros de
    /// ligne du bloc **ouvert** (voir `MermaidSourceLayout`), pas par la
    /// géométrie fermée (qui ne dépend plus du nombre de lignes, justement
    /// pour ne plus y étaler une hauteur réservée).
    static func lineCount(in source: String) -> Int {
        max(1, source.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        })
    }

    /// Hauteur totale du cadre fermé — l'attachment (`MermaidAttachmentFactory`)
    /// porte déjà son propre cadre composé dans l'image elle-même
    /// (`framedDiagram`/`frameImage` : fond, liseré et marge interne y sont
    /// déjà dessinés), donc cette hauteur suit **directement** la taille de
    /// l'image, sans y rajouter de marge une seconde fois — jamais un double
    /// cadre. `nil`, ou une taille dégénérée (pas encore d'image livrée par
    /// le rendu asynchrone), retombe sur `placeholderHeight` — jamais sur
    /// zéro.
    static func closedFrameHeight(forAttachmentSize size: NSSize?) -> CGFloat {
        guard let size, size.height > 0 else { return placeholderHeight }
        return size.height
    }

    /// Largeur totale du cadre fermé — même principe que
    /// `closedFrameHeight`, jamais étalée pour remplir toute la colonne de
    /// texte (voir `MarkdownLayoutManager.drawMermaidDiagram`, qui la
    /// plafonne en plus à la largeur du conteneur).
    static func closedFrameWidth(forAttachmentSize size: NSSize?) -> CGFloat {
        guard let size, size.width > 0 else { return placeholderWidth }
        return size.width
    }

    /// Réduit `size` pour tenir dans `maxWidth`, en conservant son ratio
    /// d'aspect — jamais agrandie. Utilisée par `MarkdownLayoutManager.
    /// drawMermaidDiagram` pour ne jamais laisser un cadre déborder de la
    /// colonne de texte disponible dans un conteneur plus étroit que
    /// `MermaidAttachmentFactory`'s propre plafond (`ImageAttachmentFactory.
    /// maxWidth`) : le dessin peut alors être très légèrement plus petit que
    /// la hauteur réservée par le style (calculée sur la taille native de
    /// l'image, sans connaître la largeur du conteneur au moment du rendu
    /// asynchrone) — un écart mineur (un vide sous le cadre), jamais un
    /// débordement. Taille ou `maxWidth` dégénérée renvoie `size` inchangée.
    static func fittedSize(for size: NSSize, maxWidth: CGFloat) -> NSSize {
        guard size.width > 0, size.height > 0, maxWidth > 0, size.width > maxWidth else { return size }
        let scale = maxWidth / size.width
        return NSSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Barre d'actions (survol diagramme)

    static let actionBarTopMargin: CGFloat = 8
    static let actionBarRightMargin: CGFloat = 8
    static let actionBarPadding: CGFloat = 3
    static let actionBarGap: CGFloat = 2

    static let actionBarBackgroundColor = NSColor(red: 250/255, green: 250/255, blue: 252/255, alpha: 0.92)
    static let actionBarBorderColor = NSColor(red: 0xde/255, green: 0xdb/255, blue: 0xd5/255, alpha: 1)
    static let actionBarBorderWidth: CGFloat = 1
    static let actionBarCornerRadius: CGFloat = 7

    static let actionButtonHeight: CGFloat = 22
    static let actionButtonCornerRadius: CGFloat = 5
    static let actionButtonHoverColor = NSColor(white: 0, alpha: 0.07)
    static let actionButtonFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let actionButtonTextColor = NSColor(red: 0x3c/255, green: 0x3c/255, blue: 0x43/255, alpha: 1)

    static let editButtonLabel = "Modifier"
    static let editButtonPaddingX: CGFloat = 9

    static let separatorWidth: CGFloat = 1
    static let separatorMarginX: CGFloat = 1
    static let separatorMarginY: CGFloat = 3
    static let separatorColor = NSColor(red: 0xe2/255, green: 0xdf/255, blue: 0xd9/255, alpha: 1)

    static let copyButtonWidth: CGFloat = 70

    struct ActionBarGeometry {
        let barRect: NSRect
        let editButtonRect: NSRect
        let separatorRect: NSRect
        let copyButtonRect: NSRect
    }

    static func actionBarGeometry(forDrawnRect drawnRect: NSRect) -> ActionBarGeometry {
        let editLabelSize = (editButtonLabel as NSString).size(withAttributes: [.font: actionButtonFont])
        let editButtonWidth = editLabelSize.width + 2 * editButtonPaddingX
        let barWidth = actionBarPadding + editButtonWidth + actionBarGap + separatorMarginX * 2 + separatorWidth + actionBarGap + copyButtonWidth + actionBarPadding
        let barHeight = actionBarPadding * 2 + actionButtonHeight

        let barX = drawnRect.maxX - actionBarRightMargin - barWidth
        let barY = drawnRect.minY + actionBarTopMargin
        let barRect = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)

        var currentX = barX + actionBarPadding
        let editButtonRect = NSRect(x: currentX, y: barY + actionBarPadding, width: editButtonWidth, height: actionButtonHeight)
        currentX += editButtonWidth + actionBarGap

        currentX += separatorMarginX
        let separatorRect = NSRect(x: currentX, y: barY + actionBarPadding + separatorMarginY, width: separatorWidth, height: actionButtonHeight - separatorMarginY * 2)
        currentX += separatorWidth + separatorMarginX + actionBarGap

        let copyButtonRect = NSRect(x: currentX, y: barY + actionBarPadding, width: copyButtonWidth, height: actionButtonHeight)

        return ActionBarGeometry(barRect: barRect, editButtonRect: editButtonRect, separatorRect: separatorRect, copyButtonRect: copyButtonRect)
    }

    // MARK: - Bouton « Ouvrir le source » (état 4 — cadre d'erreur)

    /// Libellé et police du bouton d'action peint dans le cadre d'erreur
    /// (`MermaidAttachmentFactory.frameImage`) — source de vérité unique
    /// partagée avec le hit-test (`EditorTextView.
    /// mermaidErrorActionButtonRange`), pour que les deux mesurent le texte
    /// à l'identique.
    static let errorActionLabel = "Ouvrir le source"
    static let errorActionFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)

    /// Rectangle du bouton d'action, en coordonnées **natives de l'image**
    /// (origine bas-gauche — voir `NSImage(size:flipped:false)` dans
    /// `MermaidAttachmentFactory.frameImage`, qui pose le bouton à `y: 10`,
    /// donc près du **bas** visuel du cadre). `labelSize` : la taille
    /// mesurée d'`errorActionLabel` avec `errorActionFont`, à fournir par
    /// l'appelant (dessin ou hit-test) — jamais mesurée deux fois avec des
    /// attributs qui pourraient diverger.
    static func errorActionButtonRect(labelSize: NSSize) -> NSRect {
        NSRect(x: 16, y: 12, width: labelSize.width + 20, height: 22)
    }

    /// Convertit `point` (coordonnées **conteneur**, mêmes conventions que
    /// `MarkdownLayoutManager.drawMermaidDiagram`/`origin`) en coordonnées
    /// **natives de l'image** dessinée dans `drawnRect` (la zone où
    /// `drawMermaidDiagram` positionne effectivement l'image, réduite au
    /// besoin par `fittedSize`) — pour hit-tester une zone définie dans le
    /// repère de l'image (`errorActionButtonRect`) depuis un point écran.
    ///
    /// `NSImage.draw(in:)` rend toujours l'image "à l'endroit" quelle que
    /// soit la vue de destination (flippée ou non, voir sa documentation
    /// Apple) : l'axe X se convertit donc directement (mise à l'échelle
    /// seule), l'axe Y s'inverse — le bas de l'image (`y` natif petit,
    /// origine bas-gauche) correspond au bas de `drawnRect` (`y` conteneur
    /// grand, `NSTextView` étant flippée : l'axe y grandit vers le bas de
    /// l'écran). `nil` si `drawnRect`/`imageSize` sont dégénérés (largeur
    /// nulle) — rien à hit-tester.
    static func imageLocalPoint(fromContainerPoint point: NSPoint, drawnRect: NSRect, imageSize: NSSize) -> NSPoint? {
        guard drawnRect.width > 0, imageSize.width > 0 else { return nil }
        let scale = drawnRect.width / imageSize.width
        guard scale > 0 else { return nil }
        return NSPoint(
            x: (point.x - drawnRect.minX) / scale,
            y: (drawnRect.maxY - point.y) / scale
        )
    }

    /// Découpe `range` en sa première ligne (`\n` terminal compris) et le
    /// reste — pure fonction sur `NSString`, partagée par `StyleRenderer`
    /// (répartition des styles ouvert/fermé) et testable sans storage vivant.
    /// `range` sans aucun `\n` (bloc mermaid d'une seule ligne, rare — un
    /// bloc valide a toujours au moins les deux lignes de fences) renvoie
    /// `range` entier comme première ligne et un reste vide.
    static func splitFirstLine(of range: NSRange, in text: NSString) -> (firstLine: NSRange, rest: NSRange) {
        let newline = text.range(of: "\n", options: [], range: range)
        guard newline.location != NSNotFound else {
            return (range, NSRange(location: range.location + range.length, length: 0))
        }
        let firstLineLength = newline.location + newline.length - range.location
        let firstLine = NSRange(location: range.location, length: firstLineLength)
        let restLocation = range.location + firstLineLength
        let rest = NSRange(location: restLocation, length: range.location + range.length - restLocation)
        return (firstLine, rest)
    }

    /// Plage complète du bloc mermaid (`.mdMermaidAttachment`) portant
    /// `location`, ou `nil` si `location` n'en porte aucun.
    ///
    /// `longestEffectiveRange(_:in:)` — jamais le simple `effectiveRange:` —
    /// est impératif ici : `StyleRenderer.applyOpenMermaidGeometry`/
    /// `applyClosedMermaidGeometry` posent un `.paragraphStyle` **différent**
    /// sur la première ligne du bloc et sur le reste, ce qui scinde la
    /// représentation interne du storage en plusieurs runs à cette
    /// frontière — `effectiveRange:` (non « longest ») s'arrête à la
    /// première de ces runs même quand `.mdMermaidAttachment` y porte
    /// exactement la **même** valeur des deux côtés (mesuré : un bloc de 2
    /// lignes de source renvoyait `{location, 9}` au lieu de `{location, 14}`
    /// interrogé au tout début du bloc — voir
    /// `Tests/EditorTextViewMermaidClickTests.swift`). Documentation Apple :
    /// seule la variante « longest » garantit la plage maximale.
    static func blockRange(in storage: NSTextStorage, at location: Int) -> NSRange? {
        guard location >= 0, location < storage.length,
              storage.attribute(.mdMermaidAttachment, at: location, effectiveRange: nil) != nil
        else { return nil }
        var blockRange = NSRange(location: 0, length: 0)
        _ = storage.attribute(
            .mdMermaidAttachment, at: location,
            longestEffectiveRange: &blockRange, in: NSRange(location: 0, length: storage.length)
        )
        return blockRange
    }

    /// `true` si `location` (typiquement `selectedRange().location`) est dans
    /// `blockRange` — un bloc mermaid est « ouvert » (source affiché) tant
    /// que le curseur y touche, « fermé » (diagramme peint) sinon. Les deux
    /// bornes sont **incluses** : un curseur juste après le dernier caractère
    /// du source (flèche droite, Fin, clic en bout de ligne) reste en édition
    /// et une frappe s'ajoute à la fin du source — l'ancienne borne de fin
    /// exclusive refermait le bloc à cette position et rendait la fin du
    /// source inatteignable au clavier. Fermer le bloc demande une position
    /// au-delà du séparateur : c'est là que « Terminé » place le curseur
    /// (voir `doneCaretPlacement`). Fonction
    /// pure partagée par `StyleRenderer` (géométrie posée), `EditorTextView`
    /// (hit-test au clic) et `MarkdownLayoutManager` (dessin) : un seul
    /// calcul, jamais deux qui pourraient diverger — même principe que
    /// `TableControlLayout.placementForCursor`, seul point d'entrée partagé
    /// dessin/hit-test.
    static func selectionTouches(_ location: Int, blockRange: NSRange) -> Bool {
        guard location != NSNotFound else { return false }
        return location >= blockRange.location && location <= blockRange.location + blockRange.length
    }

    /// Plage du bloc mermaid « ouvert » par un curseur à `location`, ou
    /// `nil`. Sonde l'attribut à `location` puis à `location - 1` : à la
    /// borne de fin (incluse par `selectionTouches`), le caractère sous le
    /// curseur est le **séparateur**, qui ne porte pas `.mdMermaidAttachment`
    /// — seule la sonde à `location - 1` retrouve alors le bloc. À utiliser
    /// partout où le bloc est cherché **depuis la sélection** (bouton
    /// « Terminé », bascule de géométrie) ; les hit-tests au point de clic
    /// continuent d'utiliser `blockRange(in:at:)` directement.
    static func openBlockRange(in storage: NSTextStorage, selection location: Int) -> NSRange? {
        guard location != NSNotFound, storage.length > 0 else { return nil }
        for probe in [min(location, storage.length - 1), location - 1]
        where probe >= 0 && probe < storage.length {
            if let range = blockRange(in: storage, at: probe),
               selectionTouches(location, blockRange: range) {
                return range
            }
        }
        return nil
    }

    /// Position du curseur après un clic sur « Terminé » : la première
    /// position **au-delà** du séparateur qui suit le bloc — la borne de fin
    /// étant incluse dans l'état ouvert, sortir du bloc exige de dépasser ce
    /// séparateur. `insertsSeparator` signale qu'aucun caractère ne suit le
    /// bloc (fin de document) : l'appelant doit insérer un `\n` avant de
    /// poser le curseur, sinon aucune position fermée n'existe.
    static func doneCaretPlacement(
        afterBlock blockRange: NSRange, storageLength: Int
    ) -> (location: Int, insertsSeparator: Bool) {
        let end = NSMaxRange(blockRange)
        return (end + 1, end >= storageLength)
    }
}
