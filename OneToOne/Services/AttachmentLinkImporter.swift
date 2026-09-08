import Foundation
import AppKit
import SwiftData
import os

private let linkLog = Logger(subsystem: "com.onetoone.app", category: "attachment-link")

/// Les URL collées dans les ressources d'une séance (`⌘⇧V`, spec §1.4 et §4.1).
///
/// **Aucune requête réseau**, jamais : le titre vient de l'URL elle-même —
/// dernier segment du chemin, à défaut le domaine (programme §5, lot 6 :
/// « favicon/titre récupérés hors ligne = domaine seulement »). Aller chercher
/// le `<title>` d'une page ferait sortir l'application de la boucle locale pour
/// un libellé, alors que le §8 de la spec la veut « locale d'abord » et que
/// toute fonction distante doit être signalée.
///
/// La cible est stockée dans `MeetingAttachment.filePath`. Une colonne
/// `linkURL` dédiée aurait créé deux vérités pour la même information, et un
/// `#Predicate` sur l'une n'aurait rien dit de l'autre.
enum AttachmentLinkImporter {

    /// Une URL reconnue et son libellé.
    struct Link: Equatable, Sendable {
        var url: URL
        var title: String
    }

    /// Reconnaît une URL dans un texte collé. Rend `nil` — sans rien créer —
    /// dès que ce n'est pas une adresse web : coller trois lignes de notes ne
    /// doit pas produire une ressource intitulée « trois lignes de notes ».
    static func parse(_ texte: String) -> Link? {
        let propre = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !propre.isEmpty, !propre.contains(where: \.isNewline) else { return nil }
        guard let url = URL(string: propre),
              let schema = url.scheme?.lowercased(),
              ["http", "https"].contains(schema),
              let hote = url.host, !hote.isEmpty else { return nil }
        return Link(url: url, title: title(for: url))
    }

    /// Le libellé : dernier segment du chemin, à défaut le domaine.
    ///
    /// Le segment est décodé (`%20` → espace) et débarrassé de son extension
    /// technique quand elle n'apporte rien (`/board.html` → `board`), mais pas
    /// d'un `.pdf` : un lien vers un PDF distant reste identifiable comme tel.
    static func title(for url: URL) -> String {
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let dernier = segments.last {
            let decode = dernier.removingPercentEncoding ?? dernier
            let ext = URL(fileURLWithPath: decode).pathExtension.lowercased()
            if ["html", "htm", "php", "aspx"].contains(ext) {
                let sansExt = URL(fileURLWithPath: decode).deletingPathExtension().lastPathComponent
                if !sansExt.isEmpty { return sansExt }
            }
            if !decode.isEmpty { return decode }
        }
        let hote = url.host ?? ""
        return hote.hasPrefix("www.") ? String(hote.dropFirst(4)) : hote
    }

    /// L'URL présente dans le presse-papiers, s'il y en a une.
    ///
    /// Lit d'abord les objets `NSURL` (un lien glissé depuis Safari), puis le
    /// texte brut — c'est la même hiérarchie que
    /// `LinkedInPhotoSearch.pasteImageFromClipboard` emploie pour les images.
    @MainActor
    static func fromPasteboard(_ pasteboard: NSPasteboard = .general) -> Link? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if let lien = parse(url.absoluteString) { return lien }
            }
        }
        if let texte = pasteboard.string(forType: .string) {
            return parse(texte)
        }
        return nil
    }

    /// Crée la pièce `link` de la séance. Le fichier n'existe pas : il n'y a
    /// rien à copier, la politique D5 est **sans objet** pour un lien, pas
    /// contournée.
    @MainActor
    @discardableResult
    static func attach(_ lien: Link,
                       to meeting: Meeting,
                       in context: ModelContext) -> MeetingAttachment {
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/"),
                                      kind: AttachmentCopyPolicy.linkKind)
        piece.fileName = lien.title
        piece.filePath = lien.url.absoluteString
        piece.bookmarkData = nil
        piece.scope = .meeting
        piece.mimeType = "text/uri-list"
        piece.byteCount = 0
        piece.addedByName = ownerName(in: context)
        _ = piece.ensuredStableID
        piece.meeting = meeting
        context.insert(piece)
        try? context.save()
        linkLog.info("attach link: \(lien.url.host ?? "?", privacy: .public)")
        return piece
    }

    private static func ownerName(in context: ModelContext) -> String {
        let tous = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        return tous.canonicalSettings?.ownerName ?? ""
    }
}
