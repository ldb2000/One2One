import AppKit

/// Géométrie du rendu d'un bloc mermaid **ouvert** (curseur dedans, source
/// affiché en édition) — l'état inverse de `MermaidBlockLayout` (bloc
/// fermé, diagramme peint). Interligne normal, gouttière de numéros de
/// ligne, bande d'en-tête discrète (« mermaid » + bouton « Terminé ») —
/// exactement l'état 3 du chantier : plus aucune trace de l'ancienne
/// réservation `220pt / lineCount` (110pt la ligne pour un bloc de deux
/// lignes) qui s'appliquait jusque-là même pendant l'édition.
///
/// Même patron que `TableControlLayout`/`ListMarkerLayout` : constantes +
/// fonctions pures, testables sans vue vivante, un seul calcul de géométrie
/// partagé entre le dessin (`MarkdownLayoutManager`) et le hit-test
/// (`EditorTextView.mermaidDoneButtonRange`).
enum MermaidSourceLayout {

    /// Interligne d'un bloc mermaid en édition — remplace la réservation par
    /// bloc entier de l'état fermé : chaque ligne garde un rendu de code
    /// normal, juste plus aéré que l'interligne compact par défaut (1.0)
    /// pour rester lisible à côté de la gouttière de numéros.
    static let lineHeightMultiple: CGFloat = 1.55

    /// Largeur réservée à gauche pour les numéros de ligne — posée comme
    /// `headIndent`/`firstLineHeadIndent` par `StyleRenderer`, peinte dans la
    /// marge ainsi libérée par `MarkdownLayoutManager.drawMermaidLineNumber`
    /// (même mécanisme que `ListMarkerLayout.textIndent`).
    static let gutterWidth: CGFloat = 34
    static let codeHorizontalPadding: CGFloat = 12
    static let bodyTopPadding: CGFloat = 10
    static let bodyBottomPadding: CGFloat = 10
    static let sourceLineHeight: CGFloat = 20
    static let firstLineBaselineOffset: CGFloat = -18

    /// Hauteur de la bande d'en-tête (« mermaid » + bouton Terminé), réservée
    /// au-dessus de la première ligne du bloc via
    /// `NSParagraphStyle.paragraphSpacingBefore`.
    static let headerHeight: CGFloat = 33

    /// Hauteur maximale de l'**image** dans la bande d'aperçu du bloc ouvert
    /// (hors `previewVerticalPadding`). Un diagramme plus haut est réduit à
    /// l'échelle : sans ce plafond, une carte de 450 pt repousserait le source
    /// sous la ligne de flottaison et on éditerait à l'aveugle.
    static let previewMaximumHeight: CGFloat = 240

    /// Marge au-dessus et en dessous de l'image d'aperçu, à l'intérieur de la
    /// bande.
    static let previewVerticalPadding: CGFloat = 12

    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    static let frameBackgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x1f/255, green: 0x20/255, blue: 0x24/255, alpha: 1)
            : NSColor(red: 0xfc/255, green: 0xfb/255, blue: 0xf9/255, alpha: 1)
    }
    static let headerBackgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0x28/255, green: 0x29/255, blue: 0x2e/255, alpha: 1)
            : NSColor(red: 0xf5/255, green: 0xf3/255, blue: 0xef/255, alpha: 1)
    }
    static let borderColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.18)
            : NSColor(red: 0xd4/255, green: 0xd1/255, blue: 0xcb/255, alpha: 1)
    }
    static let dividerColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(red: 0xe4/255, green: 0xe1/255, blue: 0xdb/255, alpha: 1)
    }
    static let gutterBackgroundColor = NSColor.labelColor.withAlphaComponent(0.018)

    static let gutterColor = NSColor.tertiaryLabelColor
    static let gutterFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    static let headerLabelColor = NSColor.secondaryLabelColor
    static let headerLabelFont = NSFont.systemFont(ofSize: 10.5, weight: .semibold)

    static let doneButtonFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    static let doneButtonWidth: CGFloat = 70
    static let doneButtonHeight: CGFloat = 22
    /// Marge entre le bouton « Terminé » et le bord droit du conteneur.
    static let doneButtonTrailingMargin: CGFloat = 8

    // MARK: - Bornes du texte (piège `lineFragmentRect` / `lineFragmentUsedRect`)

    /// Bornes verticales du **texte** d'un bloc mermaid ouvert, en
    /// coordonnées conteneur : sommet de la première ligne de source
    /// (`top`), bas de la dernière (`bottom`).
    ///
    /// Ce type existe pour rendre **impossible** l'erreur qui l'a motivé. En
    /// TextKit 1, `lineFragmentRect` **inclut** l'espace réservé par
    /// `paragraphSpacingBefore` (en haut) et par `paragraphSpacing` (en bas) :
    /// le fragment commence au sommet de l'espace réservé, pas du texte. Seul
    /// `lineFragmentUsedRect` commence au sommet du texte. Mesuré (script
    /// `.superpowers/sdd/2026-08-08-aeration-blocs-mermaid/mesure-textkit.swift`),
    /// pour un paragraphe « Intro » à `paragraphSpacing = 28` suivi d'un bloc
    /// ouvert à `paragraphSpacingBefore = 307` :
    ///
    ///     Intro      frag.minY=  0.0  h= 44.0 | used.minY=  0.0  h=16.0
    ///     graph TD   frag.minY= 44.0  h=323.0 | used.minY=351.0  h=16.0
    ///
    /// Ancrer la bande (en-tête + aperçu + cadre) sur `frag.minY` la peignait
    /// donc 307 pt trop haut, par-dessus le bloc précédent. Symétriquement,
    /// dériver le bas du cadre de `frag.maxY` enfermait dans la carte les
    /// 28 pt d'écart qu'`StyleRenderer.applyBlockSpacing` pose pour l'en
    /// *séparer*.
    ///
    /// Plus aucune fonction de cette géométrie n'accepte un `NSRect` de
    /// ligne : elles prennent toutes un `SourceTextBounds`, dont le seul
    /// constructeur accessible au code de production est
    /// `textBounds(forBlockRange:layoutManager:)` — qui lit
    /// `lineFragmentUsedRect`. Passer un rect de fragment par inadvertance ne
    /// compile plus.
    struct SourceTextBounds {
        let top: CGFloat
        let bottom: CGFloat

        fileprivate init(top: CGFloat, bottom: CGFloat) {
            self.top = top
            self.bottom = bottom
        }
    }

    /// Bornes du texte du bloc `blockRange` d'après la mise en page réelle —
    /// **le** point d'entrée de la géométrie du bloc ouvert, partagé par le
    /// dessin du cadre, le dessin de l'en-tête et le hit-test de « Terminé »
    /// (même principe qu'`previewHeight(in:blockRange:containerWidth:)` pour
    /// la hauteur de bande : deux calculs divergents rendraient « Terminé »
    /// incliquable).
    ///
    /// Suppose la mise en page assurée pour la plage visée — c'est le cas de
    /// tous ses appelants (dessin en cours, ou vue déjà affichée).
    static func textBounds(forBlockRange blockRange: NSRange, layoutManager: NSLayoutManager) -> SourceTextBounds {
        let firstGlyph = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let lastCharacter = max(blockRange.location, NSMaxRange(blockRange) - 1)
        let lastGlyph = layoutManager.glyphIndexForCharacter(at: lastCharacter)
        let first = layoutManager.lineFragmentUsedRect(forGlyphAt: firstGlyph, effectiveRange: nil)
        let last = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
        return SourceTextBounds(top: first.minY, bottom: last.maxY)
    }

    /// Bornes fabriquées à la main, **réservées aux tests** de géométrie pure
    /// (relations algébriques entre en-tête, aperçu et cadre, sans vue
    /// vivante) — même patron que `StyleRenderer.
    /// applyOpenMermaidGeometryForTesting`. Le code de production passe
    /// toujours par `textBounds(forBlockRange:layoutManager:)`.
    static func sourceTextBoundsForTesting(top: CGFloat, bottom: CGFloat) -> SourceTextBounds {
        SourceTextBounds(top: top, bottom: bottom)
    }

    // MARK: - Bande d'aperçu figé

    /// Taille à laquelle dessiner l'aperçu d'un bloc **ouvert** : l'image de
    /// l'attachment réduite **deux fois**, ratio conservé à chaque étape —
    /// d'abord à `containerWidth` (comme le fait déjà le dessin du bloc
    /// fermé, voir `MarkdownLayoutManager.drawMermaidDiagram`), puis à
    /// `previewMaximumHeight` si elle dépasse encore. Jamais agrandie.
    /// `NSSize.zero` quand il n'y a pas encore d'image.
    static func previewImageSize(forAttachmentSize size: NSSize?, containerWidth: CGFloat) -> NSSize {
        guard let size, size.width > 0, size.height > 0, containerWidth > 0 else { return .zero }
        let widthFitted = MermaidBlockLayout.fittedSize(for: size, maxWidth: containerWidth)
        guard widthFitted.height > previewMaximumHeight else { return widthFitted }
        let scale = previewMaximumHeight / widthFitted.height
        return NSSize(width: widthFitted.width * scale, height: previewMaximumHeight)
    }

    /// Hauteur **totale** réservée à la bande d'aperçu, paddings compris —
    /// `0` quand l'attachment n'a pas encore d'image : le cadre garde alors
    /// son allure d'origine (en-tête directement au-dessus du source).
    ///
    /// `containerWidth` est un paramètre ici, pas seulement dans
    /// `previewRect` : sans lui, une image plus large que le conteneur serait
    /// réduite au dessin mais pas dans la hauteur réservée — un vide sous
    /// l'aperçu.
    static func previewHeight(forAttachmentSize size: NSSize?, containerWidth: CGFloat) -> CGFloat {
        let scaled = previewImageSize(forAttachmentSize: size, containerWidth: containerWidth)
        guard scaled.height > 0 else { return 0 }
        return scaled.height + previewVerticalPadding * 2
    }

    /// Point d'entrée **unique** de la hauteur d'aperçu depuis un bloc vivant :
    /// le dessin du cadre, le dessin de l'en-tête et le hit-test du bouton
    /// « Terminé » l'appellent tous les trois, et `StyleRenderer` réserve la
    /// même valeur. Deux calculs divergents mettraient « Terminé » hors de sa
    /// zone cliquable — même principe que `TableControlLayout.placementForCursor`.
    static func previewHeight(in storage: NSTextStorage, blockRange: NSRange, containerWidth: CGFloat) -> CGFloat {
        guard blockRange.location >= 0, blockRange.location < storage.length,
              let attachment = storage.attribute(
                .mdMermaidAttachment, at: blockRange.location, effectiveRange: nil
              ) as? NSTextAttachment
        else { return 0 }
        return previewHeight(forAttachmentSize: attachment.image?.size, containerWidth: containerWidth)
    }

    /// Rectangle où peindre l'image d'aperçu, en coordonnées **conteneur** —
    /// centré horizontalement, juste sous la bande d'en-tête. `NSRect.zero`
    /// quand il n'y a pas d'image : rien à peindre.
    static func previewRect(above textBounds: SourceTextBounds, containerWidth: CGFloat, imageSize: NSSize?) -> NSRect {
        let scaled = previewImageSize(forAttachmentSize: imageSize, containerWidth: containerWidth)
        guard scaled.height > 0 else { return .zero }
        let band = scaled.height + previewVerticalPadding * 2
        let header = headerRect(above: textBounds, containerWidth: containerWidth, previewHeight: band)
        return NSRect(
            x: (containerWidth - scaled.width) / 2,
            y: header.maxY + previewVerticalPadding,
            width: scaled.width,
            height: scaled.height
        )
    }

    /// Rectangle du bouton « Terminé », en coordonnées **conteneur** (mêmes
    /// conventions que `TableControlLayout.Placement` : sans le décalage
    /// `origin`/`textContainerInset` qu'ajoute chaque appelant) — dans la
    /// bande d'en-tête, aligné à droite. `previewHeight` : voir
    /// `headerRect(above:containerWidth:previewHeight:)`.
    static func doneButtonRect(above textBounds: SourceTextBounds, containerWidth: CGFloat, previewHeight: CGFloat) -> NSRect {
        let header = headerRect(above: textBounds, containerWidth: containerWidth, previewHeight: previewHeight)
        let y = header.minY + (headerHeight - doneButtonHeight) / 2
        let x = containerWidth - doneButtonWidth - doneButtonTrailingMargin
        return NSRect(x: x, y: y, width: doneButtonWidth, height: doneButtonHeight)
    }

    /// Rectangle de la bande d'en-tête (fond/label « mermaid »), sur toute la
    /// largeur du conteneur. Elle reste **en haut** du cadre : la bande
    /// d'aperçu (`previewHeight`, 0 s'il n'y en a pas) s'insère entre elle et
    /// la première ligne de source, et l'en-tête remonte d'autant. C'est ce
    /// qui l'empêche de paraître coiffer la carte du bloc précédent.
    ///
    /// L'espace total ainsi occupé au-dessus du **texte** de la première ligne
    /// est exactement le `paragraphSpacingBefore` que pose
    /// `StyleRenderer.applyOpenMermaidGeometry` : `headerHeight +
    /// previewHeight + bodyTopPadding`. D'où l'ancrage sur
    /// `SourceTextBounds.top` (rect *used*) et non sur le sommet du fragment,
    /// qui *contient* déjà cette réservation — voir la doc de
    /// `SourceTextBounds`.
    static func headerRect(above textBounds: SourceTextBounds, containerWidth: CGFloat, previewHeight: CGFloat) -> NSRect {
        NSRect(
            x: 0,
            y: textBounds.top - bodyTopPadding - previewHeight - headerHeight,
            width: containerWidth,
            height: headerHeight
        )
    }

    /// Cadre complet de la carte. Le bas suit le **texte** de la dernière
    /// ligne (`SourceTextBounds.bottom`) : le fragment, lui, contient l'écart
    /// inter-blocs qu'`StyleRenderer.applyBlockSpacing` pose ensuite
    /// (`max(paragraphSpacing, 28)`), et l'enfermer dans le cadre laisserait
    /// 38 pt de vide en bas de la carte pour un écart visible nul en dessous.
    static func frameRect(
        textBounds: SourceTextBounds, containerWidth: CGFloat, previewHeight: CGFloat
    ) -> NSRect {
        let header = headerRect(above: textBounds, containerWidth: containerWidth, previewHeight: previewHeight)
        return NSRect(
            x: 0,
            y: header.minY,
            width: containerWidth,
            height: max(0, textBounds.bottom + bodyBottomPadding - header.minY)
        )
    }

    /// Zone du **source** (fond + gouttière de numéros de ligne) : elle
    /// commence sous la bande d'aperçu, jamais sous l'en-tête seul — sinon la
    /// gouttière serait peinte derrière le diagramme.
    static func bodyRect(
        textBounds: SourceTextBounds, containerWidth: CGFloat, previewHeight: CGFloat
    ) -> NSRect {
        let header = headerRect(above: textBounds, containerWidth: containerWidth, previewHeight: previewHeight)
        let top = header.maxY + previewHeight
        return NSRect(
            x: 0,
            y: top,
            width: containerWidth,
            height: max(0, textBounds.bottom + bodyBottomPadding - top)
        )
    }

    /// Origine (coordonnées conteneur) du numéro de ligne `index` (0-based
    /// dans le bloc), aligné à droite dans la gouttière, centré verticalement
    /// sur la ligne.
    ///
    /// `usedRect` — le rect du **texte** de la ligne
    /// (`lineFragmentUsedRect`), jamais son fragment : sur la première ligne
    /// d'un bloc ouvert, le fragment englobe aussi l'en-tête et la bande
    /// d'aperçu réservés par `paragraphSpacingBefore` (mesuré : 323 pt de
    /// fragment pour 16 pt de texte), et le « 1 » se retrouverait centré en
    /// plein milieu du diagramme. Voir la doc de `SourceTextBounds`.
    static func lineNumberOrigin(usedRect: NSRect, numberSize: NSSize) -> NSPoint {
        NSPoint(
            x: gutterWidth - 7 - numberSize.width,
            y: usedRect.minY + (usedRect.height - numberSize.height) / 2
        )
    }

    static func sourceLineRect(for index: Int, usedRect: NSRect) -> NSRect {
        // Le rect *used* TextKit est désormais la ligne de code elle-même ;
        // l'en-tête est réservé par `paragraphSpacingBefore`, pas en gonflant
        // la hauteur de la première ligne (ce qui gonflait le curseur) — cette
        // réservation vit donc dans le *fragment*, hors du rect *used*.
        return usedRect
    }
}
