import AppKit

/// Géométrie du rendu d'un bloc mermaid dans l'éditeur.
///
/// Le texte source d'un bloc ```` ```mermaid ```` reste du texte ordinaire
/// dans le storage (voir `StyleRenderer.applyMermaidAttachment`) : ni le
/// parser ni le sérialiseur ne sont touchés par ce chantier. La hauteur
/// réservée au diagramme doit donc être connue **de façon synchrone**, dès
/// l'application du style — bien avant que le rendu web (asynchrone,
/// `MermaidRenderer`) ne livre l'image réelle — en la répartissant sur les
/// lignes du texte source via `NSParagraphStyle.minimumLineHeight`.
enum MermaidBlockLayout {

    /// Hauteur totale réservée pour un bloc mermaid, répartie entre ses
    /// lignes de source (voir `minimumLineHeight`). Compromis assumé, pas une
    /// contrainte du diagramme réel : un diagramme complexe écrit en peu de
    /// lignes de source y sera à l'étroit — redimensionné pour tenir
    /// (`fittedRect`), jamais rogné. Valeur généreuse (proche de
    /// `ImageAttachmentFactory.maxWidth`, l'ordre de grandeur déjà retenu
    /// pour les images inline) pour rester lisible dans le cas courant.
    static let reservedHeight: CGFloat = 220

    /// Marge interne entre le cadre du bloc et le diagramme qui y est inscrit.
    static let inset: CGFloat = 8

    static let backgroundColor = NSColor.textBackgroundColor
    static let borderColor = NSColor.separatorColor

    /// Nombre de lignes de `source` (comptage des `\n`, plus un). Jamais nul,
    /// même pour un source vide : un bloc édité jusqu'à le vider ne doit pas
    /// produire de division par zéro dans `minimumLineHeight`.
    static func lineCount(in source: String) -> Int {
        max(1, source.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        })
    }

    /// Répartit `reservedHeight` sur `lineCount` lignes — `minimumLineHeight`
    /// s'applique par ligne de paragraphe, pas par bloc entier (voir la doc
    /// de tête).
    static func minimumLineHeight(forLineCount lineCount: Int) -> CGFloat {
        reservedHeight / CGFloat(max(1, lineCount))
    }

    /// Rectangle où inscrire `imageSize` à l'intérieur de `containerRect` en
    /// conservant son ratio d'aspect (« letterbox »), centré. Un `imageSize`
    /// ou `containerRect` dégénéré (largeur ou hauteur nulle) renvoie
    /// `containerRect` tel quel plutôt qu'un rectangle infini/`NaN`.
    static func fittedRect(for imageSize: NSSize, in containerRect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerRect.width > 0, containerRect.height > 0
        else { return containerRect }

        let scale = min(containerRect.width / imageSize.width, containerRect.height / imageSize.height)
        let fittedWidth = imageSize.width * scale
        let fittedHeight = imageSize.height * scale
        let x = containerRect.minX + (containerRect.width - fittedWidth) / 2
        let y = containerRect.minY + (containerRect.height - fittedHeight) / 2
        return NSRect(x: x, y: y, width: fittedWidth, height: fittedHeight)
    }
}
