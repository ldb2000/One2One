import AppKit
import Foundation

/// Cache mémoire des photos (avatars collaborateurs…). Évite de re-décoder
/// le même fichier disque à chaque render de `body` : un avatar visible dans
/// une liste se décodait sinon une fois par passe de rendu et par item.
///
/// Clé = chemin + date de modif → une photo remplacée sur le même chemin est
/// automatiquement réchargée.
enum ImageCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 256
        return c
    }()

    /// Charge l'image pour `url` depuis le cache, ou la décode et la met en
    /// cache. Retourne `nil` si le fichier est absent/illisible.
    static func image(for url: URL) -> NSImage? {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            ?? nil
        let key = "\(url.path)#\(mtime?.timeIntervalSince1970 ?? 0)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}
