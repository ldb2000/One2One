import AppKit
import Foundation

/// L'insertion d'une pièce ou d'une capture **sur** la planche (spec §7.2 :
/// « `Insérer` place l'image comme objet verrouillé de la planche, une copie
/// locale, jamais une référence externe »).
///
/// Trois exigences, tenues ici plutôt que dans la vue :
///
/// 1. **Copie, jamais référence** (spec §8, D5) : l'image est réécrite dans
///    `recordings/<réunion>/boards/assets/<stableID>.png`. Supprimer
///    l'original ne casse pas la planche — c'est le critère n° 3 du chantier 6,
///    et il a son test.
/// 2. **≤ 2 048 px sur le grand côté** (spec §7.4) : une capture d'écran 5K
///    insérée telle quelle ferait 8 Mo dans la scène et écroulerait le rendu.
/// 3. **Verrouillée** : un fond de plan qu'on déplace par mégarde à chaque
///    trait est inutilisable.
enum BoardImageInsertion {

    /// Borne du grand côté (spec §7.4).
    static let maxDimension = 2_048

    /// Sous-dossier des images d'une planche, sous le dossier `boards/` de la
    /// réunion.
    static let assetsFolder = "assets"

    enum Failure: Error, LocalizedError {
        case unreadable(String)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadable(let nom): return "Image illisible : \(nom)"
            case .encodingFailed:      return "Conversion de l'image impossible"
            }
        }
    }

    /// Ce que l'insertion a produit.
    struct Copied {
        /// Le fichier écrit dans la réunion.
        var url: URL
        /// Chemin relatif au dossier de la réunion, comme `Board.scenePath`.
        var relativePath: String
        /// Identifiant du fichier dans la scène (`fileId` de l'élément).
        var fileID: String
        /// Taille après redimensionnement.
        var size: CGSize
        /// `data:image/png;base64,…` — ce que la page reçoit. La scène ne
        /// contient donc **aucun chemin** vers le disque.
        var dataURL: String
    }

    // MARK: - Redimensionnement

    /// La taille bornée au grand côté. Une image plus petite n'est **pas**
    /// agrandie : on ne fabrique pas des pixels.
    static func fittedSize(_ size: CGSize, limit: Int = maxDimension) -> CGSize {
        let borne = Double(limit)
        let grand = max(size.width, size.height)
        guard grand > borne, grand > 0 else { return size }
        let facteur = borne / grand
        return CGSize(width: (size.width * facteur).rounded(),
                      height: (size.height * facteur).rounded())
    }

    /// Chemin relatif du fichier copié. `@MainActor` parce que
    /// `BoardStore.folderName` l'est : les deux chemins doivent nommer le même
    /// dossier, et le recopier en littéral serait la première divergence.
    @MainActor
    static func relativePath(fileID: String) -> String {
        "\(BoardStore.folderName)/\(assetsFolder)/\(fileID).png"
    }

    // MARK: - Copie

    /// Copie l'image dans la réunion, redimensionnée et convertie en PNG.
    ///
    /// Accepte tout ce qu'`NSImage` sait lire — dont un PDF, dont la première
    /// page est rendue : la pièce `Archi_cible_Cléva.pdf` de la capture est
    /// insérable sans qu'on écrive un convertisseur.
    @MainActor
    static func copy(source: URL,
                     meetingStableID: UUID,
                     store: BoardStore,
                     fileID: String = UUID().uuidString) throws -> Copied {
        guard let image = NSImage(contentsOf: source) else {
            throw Failure.unreadable(source.lastPathComponent)
        }

        let cible = fittedSize(image.size)
        guard let png = pngData(from: image, size: cible) else {
            throw Failure.encodingFailed
        }

        let relatif = relativePath(fileID: fileID)
        let destination = store.url(meetingStableID: meetingStableID, relativePath: relatif)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)

        return Copied(url: destination,
                      relativePath: relatif,
                      fileID: fileID,
                      size: cible,
                      dataURL: "data:image/png;base64,\(png.base64EncodedString())")
    }

    /// Rendu PNG à la taille demandée. Passe par un `NSBitmapImageRep` explicite
    /// plutôt que par `image.tiffRepresentation` : sans lui, le
    /// redimensionnement serait ignoré et l'image partirait à sa taille
    /// d'origine.
    private static func pngData(from image: NSImage, size: CGSize) -> Data? {
        let largeur = max(1, Int(size.width))
        let hauteur = max(1, Int(size.height))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: largeur,
                                         pixelsHigh: hauteur,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: largeur, height: hauteur)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let contexte = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = contexte
        image.draw(in: NSRect(x: 0, y: 0, width: largeur, height: hauteur),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        contexte.flushGraphics()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Élément de scène

    /// L'élément `image` **verrouillé** à ajouter à la scène.
    static func element(fileID: String,
                        size: CGSize,
                        at origin: CGPoint,
                        id: String = UUID().uuidString) -> [String: Any] {
        [
            "id": id,
            "type": "image",
            "x": origin.x, "y": origin.y,
            "width": size.width, "height": size.height,
            "angle": 0,
            "strokeColor": "transparent",
            "backgroundColor": "transparent",
            "fillStyle": "solid",
            "strokeWidth": 1,
            "strokeStyle": "solid",
            "roughness": 0,
            "opacity": 100,
            "groupIds": [],
            "frameId": NSNull(),
            "roundness": NSNull(),
            "seed": abs(id.hashValue % 100_000),
            "version": 1,
            "versionNonce": abs(fileID.hashValue % 100_000),
            "isDeleted": false,
            "boundElements": NSNull(),
            "updated": 1,
            "link": NSNull(),
            // Le point de tout : une pièce insérée est un fond de plan.
            "locked": true,
            "fileId": fileID,
            "status": "saved",
            "scale": [1, 1],
        ]
    }

    /// L'élément, sérialisé pour le pont.
    static func elementJSON(fileID: String,
                            size: CGSize,
                            at origin: CGPoint,
                            id: String = UUID().uuidString) -> String {
        let objet = element(fileID: fileID, size: size, at: origin, id: id)
        guard let data = try? JSONSerialization.data(withJSONObject: [objet],
                                                     options: [.sortedKeys]),
              let texte = String(data: data, encoding: .utf8)
        else { return "[]" }
        return texte
    }
}
