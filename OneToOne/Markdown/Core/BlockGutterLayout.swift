import AppKit

/// Géométrie de la gouttière de bloc (poignée `⠿` + bouton `+`) et du cadre
/// de sélection d'un bloc entier — peints par `MarkdownLayoutManager.
/// drawBlockGutter` / `drawBlockSelection`, hit-testés par
/// `EditorTextView.blockGutterHit(at:)`. Les deux appellent
/// `iconsFrame(for:)` et `bodyFrame(for:)` : **un seul** calcul de
/// géométrie, jamais deux qui pourraient diverger — même schéma que
/// `TableControlLayout` / `ListMarkerLayout` (constantes + fonctions pures,
/// testables sans vue vivante).
///
/// Layout de la colonne d'édition (spec Screen 4 — design_handoff_editor_blocs) :
///
///     [ gouttière 58px ][ corps du bloc, flex:1 ]
///        +   ⠿  (12px right padding)
///
/// La gouttière n'appartient jamais au contenu : elle vit dans les 58 px que
/// `EditorTextView.commonInit` réserve via `textContainerInset.width = 58`.
/// Le corps du bloc est peint dans la zone où TextKit dessine réellement le
/// texte. Les deux zones ne se recouvrent jamais — invariant qui permettra,
/// step 4, aux contrôles ligne/colonne du tableau de coexister avec la
/// manipulation du bloc sans conflit de cible de clic.
enum BlockGutterLayout {

    /// Largeur totale réservée à la gouttière, incluant `iconRightPadding`.
    static let width: CGFloat = 58
    /// Padding entre la dernière icône et le bord du corps du bloc.
    static let iconRightPadding: CGFloat = 12
    /// Taille cible des boutons `+` / `⠿` (spec : 17×22 px, arrondi 4 px).
    static let iconWidth: CGFloat = 17
    static let iconHeight: CGFloat = 22
    /// Écart entre les deux icônes (spec `gap: 3px`).
    static let iconGap: CGFloat = 3

    /// Rayon d'arrondi du cadre de sélection (spec `border-radius: 6px`).
    static let bodyCornerRadius: CGFloat = 6
    /// Épaisseur du cadre de sélection (spec `1.5 px solid #0a6cff`).
    static let selectionBorderWidth: CGFloat = 1.5
    /// Padding intérieur autour du texte quand le cadre de sélection est
    /// visible — pour que la bordure ne colle pas aux glyphes.
    static let bodyPadding = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)

    // MARK: - Couleurs (design tokens du handoff)

    /// Accent / sélection.
    static let accentColor = NSColor(red: 0x0a/255, green: 0x6c/255, blue: 0xff/255, alpha: 1)
    /// Fond de sélection de bloc (spec `#f4f8ff`).
    static let selectionFillColor = NSColor(red: 0xf4/255, green: 0xf8/255, blue: 0xff/255, alpha: 1)
    /// Fond de survol (spec `rgba(0,0,0,.018)` — quasi imperceptible mais suffisant à l'œil).
    static let hoverFillColor = NSColor(white: 0, alpha: 0.018)
    /// Couleur du glyphe `⠿` (spec `rgba(0,0,0,.42)`).
    static let handleGlyphColor = NSColor(white: 0, alpha: 0.42)
    /// Couleur du glyphe `+` (spec `rgba(0,0,0,.35)`).
    static let plusGlyphColor = NSColor(white: 0, alpha: 0.35)
    /// Fond des boutons au survol (spec `rgba(0,0,0,.06)`).
    static let iconHoverFillColor = NSColor(white: 0, alpha: 0.06)

    /// Police du glyphe `⠿` (spec `12px/1 ui-monospace`).
    static var handleGlyphFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }
    /// Police du glyphe `+` (spec `13px/1` system).
    static var plusGlyphFont: NSFont { NSFont.systemFont(ofSize: 13) }

    // MARK: - Zones de clic

    /// Rectangle englobant tous les fragments de ligne d'une plage de bloc,
    /// en coordonnées **conteneur** (avant application de `textContainerOrigin`).
    /// Retourne `nil` si la plage est vide ou hors du storage.
    static func containerRect(for range: NSRange,
                               layoutManager: NSLayoutManager,
                               container: NSTextContainer) -> NSRect? {
        guard range.length > 0 else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        guard bounding.width > 0, bounding.height > 0 else { return nil }
        return bounding
    }

    /// Rectangle où peindre les icônes `+` `⠿` de la gouttière pour le bloc
    /// dont `bodyRect` est le rect englobant (en coordonnées **vue**, cf.
    /// `containerRect` + `textContainerOrigin`).
    ///
    /// La gouttière est à GAUCHE du corps du bloc, alignée sur son premier
    /// fragment de ligne. `plus` puis `handle` de gauche à droite, séparés
    /// par `iconGap`, terminés par `iconRightPadding` avant le corps.
    static func iconsFrame(forBodyRect bodyRect: NSRect) -> (plus: NSRect, handle: NSRect) {
        let handleMaxX = bodyRect.minX - iconRightPadding
        let handleMinX = handleMaxX - iconWidth
        let plusMinX = handleMinX - iconGap - iconWidth

        // Aligne verticalement les icônes sur la première ligne du bloc :
        // top-aligned avec 2 px de marge (spec `padding: 2px 12px 0 0`),
        // pas centré sur le bloc entier — sinon les blocs multi-lignes
        // afficheraient la poignée au milieu, incompréhensible.
        let iconY = bodyRect.minY + 2

        let plus = NSRect(x: plusMinX, y: iconY, width: iconWidth, height: iconHeight)
        let handle = NSRect(x: handleMinX, y: iconY, width: iconWidth, height: iconHeight)
        return (plus, handle)
    }

    /// Cadre étendu autour du corps du bloc pour dessiner le fond+bordure de
    /// sélection — dépasse légèrement les glyphes via `bodyPadding` pour ne
    /// pas coller à la première lettre.
    static func selectionFrame(forBodyRect bodyRect: NSRect) -> NSRect {
        NSRect(
            x: bodyRect.minX - bodyPadding.left,
            y: bodyRect.minY - bodyPadding.top,
            width: bodyRect.width + bodyPadding.left + bodyPadding.right,
            height: bodyRect.height + bodyPadding.top + bodyPadding.bottom
        )
    }

    // MARK: - Hit-test

    /// Zone cliquée dans la gouttière d'un bloc.
    enum HitZone: Equatable {
        case handle  // clic sur `⠿` → sélectionne le bloc
        case plus    // clic sur `+` → insère un bloc (step 4 : décidera au-dessus/en dessous)
    }

    /// Hit-test d'un clic dans la gouttière. `point` est en coordonnées vue.
    /// `bodyRect` est le rectangle du corps du bloc (aussi en coordonnées vue).
    /// Retourne `nil` si le clic n'atteint ni `+` ni `⠿`.
    static func hitTest(point: NSPoint, bodyRect: NSRect) -> HitZone? {
        let icons = iconsFrame(forBodyRect: bodyRect)
        if icons.handle.contains(point) { return .handle }
        if icons.plus.contains(point) { return .plus }
        return nil
    }
}
