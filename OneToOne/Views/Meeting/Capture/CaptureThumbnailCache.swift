import CoreGraphics
import Foundation
import ImageIO

/// Cache mémoire des vignettes de captures (132 × 76 sur la bande, 56 × 36
/// dans une note).
///
/// Sans lui, la bande relirait et redécoderait un PNG plein écran à chaque
/// rendu SwiftUI, pour chaque vignette : une séance de vingt captures rendrait
/// la colonne principale visiblement lente. Les vignettes sont créées par
/// `CGImageSourceCreateThumbnailAtIndex`, qui décode à la taille demandée sans
/// jamais monter l'image entière en mémoire.
///
/// Cache **borné** (64 entrées, éviction du plus ancien accès) : une réunion
/// longue ne doit pas retenir toutes ses captures en mémoire. La clé porte la
/// date de modification du fichier, pour qu'une capture réécrite au même
/// chemin ne serve pas une vignette périmée.
@MainActor
final class CaptureThumbnailCache {

    static let shared = CaptureThumbnailCache()

    /// Côté maximal de la vignette décodée, en pixels : deux fois la plus
    /// grande taille d'affichage (132 px), pour rester net sur un écran Retina.
    /// `nonisolated` : lue par le décodage, qui est pur.
    nonisolated static let maximumPixelSize = 264

    private struct Key: Hashable {
        let path: String
        let modifiedAt: TimeInterval
    }

    private var images: [Key: CGImage] = [:]
    /// Ordre d'accès, du plus ancien au plus récent.
    private var order: [Key] = []
    private let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    /// La vignette du fichier, décodée à la demande. `nil` si le fichier a
    /// disparu ou n'est pas décodable — la bande affiche alors un cadre muet
    /// plutôt que de laisser croire à une capture illisible qui serait là.
    func thumbnail(forPath path: String) -> CGImage? {
        guard !path.isEmpty else { return nil }
        let attributs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let date = attributs?[.modificationDate] as? Date else { return nil }
        let key = Key(path: path, modifiedAt: date.timeIntervalSince1970)

        if let image = images[key] {
            touch(key)
            return image
        }
        guard let image = Self.makeThumbnail(path: path) else { return nil }
        images[key] = image
        touch(key)
        evictIfNeeded()
        return image
    }

    /// Oublie une entrée : appelé quand une capture est supprimée, pour ne pas
    /// garder en mémoire l'image d'un fichier qui n'existe plus.
    func forget(path: String) {
        let clefs = images.keys.filter { $0.path == path }
        for clef in clefs {
            images[clef] = nil
            order.removeAll { $0 == clef }
        }
    }

    func removeAll() {
        images.removeAll()
        order.removeAll()
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        while order.count > capacity, let plusAncien = order.first {
            order.removeFirst()
            images[plusAncien] = nil
        }
    }

    /// Décodage à la taille de la vignette. `nonisolated` : c'est du travail
    /// pur, sans état partagé.
    nonisolated static func makeThumbnail(path: String,
                                          maximumPixelSize: Int = maximumPixelSize) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
