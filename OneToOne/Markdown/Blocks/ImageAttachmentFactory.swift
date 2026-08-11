import AppKit

/// Construit — et met en cache — le `NSTextAttachment` affiché à la place d'une
/// image markdown inline. Le cache est indexé par URL pour que le restylage du
/// texte, déclenché à chaque frappe, ne relise pas le fichier sur disque.
enum ImageAttachmentFactory {

    /// Largeur maximale d'affichage des images **ordinaires**. Les images
    /// plus larges sont réduites en conservant leur rapport d'aspect. Reste
    /// volontairement plus petite que la colonne mermaid
    /// (`MermaidBlockLayout.columnWidth`, 960 pt) : un `NSTextAttachment`
    /// d'image est dessiné par TextKit à ses bounds figés, jamais réajusté à
    /// la largeur vivante du conteneur (l'éditeur démarre à 200 pt, sans
    /// défilement horizontal) — une limite à 960 clippait les images dans
    /// les éditeurs courants de 300–600 pt, contrairement aux cartes mermaid
    /// qui, elles, sont réduites au dessin (`MermaidBlockLayout.fittedSize`).
    static let maxWidth: CGFloat = 480

    /// Hauteur du cadre affiché quand la taille de l'image est inexploitable.
    private static let placeholderHeight: CGFloat = 120

    /// `NSCache` est documenté thread-safe par Apple : appeler `attachment(for:)`
    /// et `invalidate()` depuis plusieurs threads ne pose donc pas de problème
    /// réel. Le passage du package en mode langage Swift 6 (concurrence
    /// stricte) demandera néanmoins une annotation explicite ici, car
    /// `NSCache` ne conforme pas à `Sendable`. `countLimit` borne le nombre
    /// d'images décodées gardées en mémoire par un éditeur qui tourne longtemps.
    private static let cache: NSCache<NSURL, NSTextAttachment> = {
        let cache = NSCache<NSURL, NSTextAttachment>()
        cache.countLimit = 64
        return cache
    }()

    /// URLs de fichier pour lesquelles la dernière lecture a échoué (absent ou
    /// illisible). Mémorisées pour ne pas retenter un accès disque à chaque
    /// frappe ; vidées par `invalidate()` comme le cache des attachments.
    private static var failedURLs = Set<URL>()

    /// Renvoie l'attachment correspondant à `url`, ou `nil` si le fichier est
    /// absent ou illisible — auquel cas le caractère `U+FFFC` reste affiché tel
    /// quel et le markdown source demeure intact.
    static func attachment(for url: URL) -> NSTextAttachment? {
        // `NSImage(contentsOf:)` charge une URL distante de façon
        // synchrone — mesuré à plus de 3 s de blocage face à un serveur qui
        // répond lentement. Cette fabrique est appelée depuis le restylage du
        // texte, donc à chaque frappe : seules les URLs de fichier sont donc
        // acceptées ici ; le chargement distant asynchrone est hors périmètre.
        guard url.isFileURL else { return nil }

        // Normalise la clé pour que `file:///a/./b.png` et `file:///a/b.png`
        // partagent la même entrée de cache.
        let key = url.standardizedFileURL

        if let cached = cache.object(forKey: key as NSURL) { return cached }
        if failedURLs.contains(key) { return nil }

        guard let image = NSImage(contentsOf: key) else {
            failedURLs.insert(key)
            return nil
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = displayBounds(for: image.size)
        cache.setObject(attachment, forKey: key as NSURL)
        return attachment
    }

    /// Réduit `size` pour tenir dans `maxWidth` sans déformation. Une taille
    /// dégénérée (largeur ou hauteur nulle) donne un cadre de remplacement.
    /// `size` est exprimée en points (`NSImage.size`), pas en pixels : un PNG
    /// 1000×500 marqué @2x rapporte une taille de 500×250 — correct pour
    /// l'affichage, mais à garder en tête si cette fabrique est un jour
    /// généralisée à des rendus de densités variables (ex. diagrammes).
    static func displayBounds(for size: NSSize) -> NSRect {
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: 0, y: 0, width: maxWidth, height: placeholderHeight)
        }
        guard size.width > maxWidth else {
            return NSRect(origin: .zero, size: size)
        }
        let scale = maxWidth / size.width
        let scaledHeight = max(1, (size.height * scale).rounded())
        return NSRect(x: 0, y: 0, width: maxWidth, height: scaledHeight)
    }

    /// Vide le cache des attachments et l'historique des échecs — à appeler
    /// quand une image est remplacée sur disque.
    static func invalidate() {
        cache.removeAllObjects()
        failedURLs.removeAll()
    }
}
