import AppKit

/// Construit — et met en cache — le `NSTextAttachment` affiché à la place d'une
/// image markdown inline. Le cache est indexé par URL pour que le restylage du
/// texte, déclenché à chaque frappe, ne relise pas le fichier sur disque.
enum ImageAttachmentFactory {

    /// Largeur maximale d'affichage. Les images plus larges sont réduites en
    /// conservant leur rapport d'aspect.
    static let maxWidth: CGFloat = 480

    /// Hauteur du cadre affiché quand la taille de l'image est inexploitable.
    private static let placeholderHeight: CGFloat = 120

    /// `NSCache` est documenté thread-safe par Apple : appeler `attachment(for:)`
    /// et `invalidate()` depuis plusieurs threads ne pose donc pas de problème
    /// réel. Le passage du package en mode langage Swift 6 (concurrence
    /// stricte) demandera néanmoins une annotation explicite ici, car
    /// `NSCache` ne conforme pas à `Sendable`.
    private static let cache = NSCache<NSURL, NSTextAttachment>()

    /// Renvoie l'attachment correspondant à `url`, ou `nil` si le fichier est
    /// absent ou illisible — auquel cas le caractère `U+FFFC` reste affiché tel
    /// quel et le markdown source demeure intact.
    static func attachment(for url: URL) -> NSTextAttachment? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = displayBounds(for: image.size)
        cache.setObject(attachment, forKey: url as NSURL)
        return attachment
    }

    /// Réduit `size` pour tenir dans `maxWidth` sans déformation. Une taille
    /// dégénérée (largeur ou hauteur nulle) donne un cadre de remplacement.
    static func displayBounds(for size: NSSize) -> NSRect {
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: 0, width: maxWidth, height: placeholderHeight)
        }
        guard size.width > maxWidth else {
            return NSRect(origin: .zero, size: size)
        }
        let scale = maxWidth / size.width
        return NSRect(x: 0, y: 0, width: maxWidth, height: (size.height * scale).rounded())
    }

    /// Vide le cache — à appeler quand une image est remplacée sur disque.
    static func invalidate() {
        cache.removeAllObjects()
    }
}
