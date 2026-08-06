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
    static let inset: CGFloat = 8

    static let backgroundColor = NSColor.textBackgroundColor
    static let borderColor = NSColor.separatorColor

    /// Hauteur provisoire, modeste, réservée tant que le rendu web n'a pas
    /// encore livré d'image (`MermaidAttachmentFactory.placeholder`) — jamais
    /// une hauteur étalée sur les lignes du source (l'ancien défaut : 220pt).
    static let placeholderHeight: CGFloat = 104

    /// Largeur du cadre de secours (chargement/erreur) — voir
    /// `MermaidAttachmentFactory.frameWidth`, dupliquée ici comme source de
    /// vérité unique pour éviter la dérive des deux constantes.
    static let placeholderWidth: CGFloat = 320

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

    /// `true` si `location` (typiquement `selectedRange().location`) touche
    /// `blockRange` — un bloc mermaid est « ouvert » (source affiché) tant
    /// que le curseur y touche, « fermé » (diagramme peint) sinon. Fonction
    /// pure partagée par `StyleRenderer` (géométrie posée), `EditorTextView`
    /// (hit-test au clic) et `MarkdownLayoutManager` (dessin) : un seul
    /// calcul, jamais deux qui pourraient diverger — même principe que
    /// `TableControlLayout.placementForCursor`, seul point d'entrée partagé
    /// dessin/hit-test.
    static func selectionTouches(_ location: Int, blockRange: NSRange) -> Bool {
        guard location != NSNotFound else { return false }
        return location >= blockRange.location && location <= blockRange.location + blockRange.length
    }
}
