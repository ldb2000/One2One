import Foundation
import CryptoKit

/// Cache disque + mémoire de l'image rendue pour un diagramme Mermaid. Le
/// moteur natif stocke du PNG ; le fallback JavaScript stocke du SVG.
///
/// Clé = empreinte du **source et de l'apparence** (`isDark`). Les couleurs
/// d'un diagramme mermaid dépendent du thème passé à `mermaid.initialize` —
/// et l'apparence système bascule automatiquement clair/sombre selon
/// l'heure. Un cache indifférent à l'apparence resservirait, un soir, un
/// diagramme aux couleurs claires sur fond sombre (ou l'inverse le matin
/// suivant) plutôt que de relancer le rendu.
enum MermaidRenderCache {
    /// À incrémenter lorsque la configuration visuelle envoyée à Mermaid
    /// change, afin de ne pas resservir une image produite avec l'ancien thème.
    private static let rendererVersion = "v8-native-beautiful-mermaid"

    private static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 64
        return cache
    }()

    static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OneToOne/render-cache", isDirectory: true)
    }

    /// `source` = corps mermaid brut (sans les fences ```` ``` ````).
    static func key(source: String, isDark: Bool) -> String {
        let themeTag = isDark ? "dark" : "light"
        let digest = SHA256.hash(data: Data("\(rendererVersion)\n\(themeTag)\n\(source)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cachedRenderData(forKey key: String) -> Data? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached as Data
        }
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        return data
    }

    static func store(_ renderData: Data, forKey key: String) {
        memoryCache.setObject(renderData as NSData, forKey: key as NSString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try renderData.write(to: fileURL(forKey: key))
        } catch {
            print("[MermaidRenderCache] Échec écriture cache : \(error)")
        }
    }

    private static func fileURL(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).render")
    }

    /// Vide le cache mémoire (pas le disque) — utilisé par les tests pour
    /// repartir d'un état propre entre exemples, comme
    /// `ImageAttachmentFactory.invalidate()`.
    static func invalidateMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
