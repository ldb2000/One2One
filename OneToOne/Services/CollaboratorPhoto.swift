import Foundation
import AppKit
import SwiftData

/// Enregistre la photo d'un collaborateur, quelle que soit sa provenance :
/// fichier choisi, image déposée, presse-papiers.
///
/// Extrait de l'ancienne fiche collaborateur, où les quatre variantes d'une
/// même action occupaient quatre boutons empilés. Une seule implémentation :
/// la feuille d'édition v3 en propose plusieurs chemins, ils aboutissent tous
/// ici.
enum CollaboratorPhoto {

    /// Adopte un fichier **en place**, avec un signet de sécurité : la photo
    /// reste chez l'utilisateur, l'app garde le droit de la relire.
    static func adopt(fileURL: URL, for collaborator: Collaborator) {
        collaborator.photoPath = fileURL.path
        collaborator.photoBookmarkData = try? fileURL.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Recopie des octets d'image dans le dossier de l'app.
    ///
    /// Un nom neuf à chaque enregistrement : deux collaborateurs ne peuvent
    /// pas s'écraser mutuellement, même si leurs identifiants se ressemblent
    /// (données héritées). L'ancienne photo est nettoyée si elle vivait dans
    /// notre dossier, pour ne pas laisser d'orphelins.
    @discardableResult
    static func store(_ data: Data, for collaborator: Collaborator) -> Bool {
        let dossier = URL.applicationSupportDirectory
            .appending(path: "OneToOne", directoryHint: .isDirectory)
            .appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let cible = dossier.appending(path: "\(UUID().uuidString).jpg")
        do {
            try data.write(to: cible, options: .atomic)
            let ancienne = collaborator.photoPath
            if !ancienne.isEmpty, ancienne.hasPrefix(dossier.path), ancienne != cible.path {
                try? FileManager.default.removeItem(atPath: ancienne)
            }
            collaborator.photoPath = cible.path
            collaborator.photoBookmarkData = nil
            return true
        } catch {
            print("[CollaboratorPhoto] enregistrement impossible : \(error)")
            return false
        }
    }

    /// Colle l'image du presse-papiers. Faux — et un bip — s'il n'y en a pas.
    @discardableResult
    static func paste(for collaborator: Collaborator) -> Bool {
        guard let data = LinkedInPhotoSearch.pasteImageFromClipboard() else {
            NSSound.beep()
            return false
        }
        return store(data, for: collaborator)
    }

    /// Ouvre le sélecteur de fichiers et adopte ce qui en sort.
    @MainActor
    @discardableResult
    static func choose(for collaborator: Collaborator) -> Bool {
        let panneau = NSOpenPanel()
        panneau.allowedContentTypes = [.image]
        panneau.allowsMultipleSelection = false
        panneau.prompt = "Choisir"
        guard panneau.runModal() == .OK, let url = panneau.url else { return false }
        adopt(fileURL: url, for: collaborator)
        return true
    }

    static func remove(for collaborator: Collaborator) {
        collaborator.photoPath = ""
        collaborator.photoBookmarkData = nil
    }
}
