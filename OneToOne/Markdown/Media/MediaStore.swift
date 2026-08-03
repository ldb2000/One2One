import AppKit

/// Stockage disque des images collées ou importées dans un éditeur markdown.
/// Les fichiers vivent dans `Application Support/OneToOne/images/`, à côté des
/// enregistrements audio et des sauvegardes.
enum MediaStore {
    static var imagesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OneToOne/images", isDirectory: true)
    }

    static var clipboardHasImage: Bool {
        let pb = NSPasteboard.general
        return pb.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.png.rawValue,
                                                          NSPasteboard.PasteboardType.tiff.rawValue])
    }

    static func saveClipboardImage() -> URL? {
        let pb = NSPasteboard.general

        // Essaie d'abord le PNG, puis le TIFF
        var imageData: Data?
        if let png = pb.data(forType: .png) {
            imageData = png
        } else if let tiff = pb.data(forType: .tiff),
                  let bitmapRep = NSBitmapImageRep(data: tiff),
                  let png = bitmapRep.representation(using: .png, properties: [:]) {
            imageData = png
        }

        guard let data = imageData else { return nil }

        // Compresse si > 2 Mo
        var finalData = data
        if finalData.count > 2_000_000 {
            if let bitmapRep = NSBitmapImageRep(data: data),
               let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                finalData = jpeg
            }
        }

        let isJpeg = finalData.count != data.count
        let ext = isJpeg ? "jpg" : "png"
        let fileName = "img_\(UUID().uuidString).\(ext)"
        let dir = imagesDirectory

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent(fileName)
            try finalData.write(to: fileURL)
            return fileURL
        } catch {
            print("[MediaStore] Failed to save image: \(error)")
            return nil
        }
    }

    static func markdownReference(for imageURL: URL, alt: String = "image") -> String {
        "![\(alt)](\(imageURL.absoluteString))"
    }
}
