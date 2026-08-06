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

    /// Répertoire des fichiers quelconques joints depuis l'entrée « Fichier »
    /// du menu `/` — distinct d'`imagesDirectory` : une image collée n'a pas
    /// de nom d'origine à préserver (d'où `img_<UUID>.<ext>`), un fichier
    /// joint si, et c'est ce nom que `saveFile(from:)` conserve sur disque.
    static var attachmentsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OneToOne/attachments", isDirectory: true)
    }

    /// Copie `sourceURL` (un fichier quelconque choisi via le sélecteur de
    /// l'entrée « Fichier ») dans `attachmentsDirectory` et renvoie l'URL de
    /// la copie — jamais l'URL d'origine : celle-ci peut être déplacée ou
    /// supprimée par l'utilisateur après l'insertion, ce qui casserait le
    /// lien inséré dans la note (même raison d'être que la copie déjà faite
    /// par `saveClipboardImage` pour les images).
    ///
    /// Chaque fichier est placé dans un sous-dossier nommé d'un `UUID`
    /// (`attachmentsDirectory/<UUID>/nom-original.ext`) plutôt que renommé
    /// `<UUID>.ext` comme `saveClipboardImage` : ça préserve le nom
    /// d'origine tel quel dans `destination.lastPathComponent` — c'est ce nom
    /// que l'appelant (`SlashController.insertFile`) utilise comme libellé du
    /// lien markdown inséré — tout en garantissant l'absence de collision
    /// entre deux fichiers joints portant le même nom.
    ///
    /// `nil` si la copie échoue (source illisible, disque plein…).
    static func saveFile(from sourceURL: URL) -> URL? {
        let destinationDirectory = attachmentsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destination = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            print("[MediaStore] Failed to save file: \(error)")
            return nil
        }
    }
}
