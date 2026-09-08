import Foundation
import UniformTypeIdentifiers

/// Tout ce que la politique « copie, jamais référence » (ADR
/// `2026-09-07-pieces-copiees-jamais-referencees.md`, décision D5) décide
/// **sans toucher au disque** : où va la copie, comment elle se nomme, quel
/// type MIME et quelle catégorie porte la pièce, et comment le tiroir la rend
/// (badge, ton, poids).
///
/// Fonctions pures, donc testées avant les vues : la vignette de
/// `3a-tiroir-ressources.png` — `XLS` sur fond vert, `Ajouté par Sylvain ·
/// 09:22 · 84 Ko` — ne doit jamais recalculer son texte elle-même. Un poids
/// formaté dans deux vues finit par se formater de deux façons.
enum AttachmentCopyPolicy {

    // MARK: - Destination

    /// Sous-chemin de la copie, relatif à `Application Support/OneToOne`.
    /// Le dossier voisine `slides/` de la même réunion : tout ce qui appartient
    /// à une séance vit sous `recordings/<uuid>/`.
    static func documentsSubpath(meetingStableID: UUID) -> String {
        "recordings/\(meetingStableID.uuidString)/documents"
    }

    /// Vrai si `path` désigne un fichier **interne** à l'application, donc une
    /// pièce déjà copiée (ou une pièce de projet, copiée de longue date).
    ///
    /// C'est le seul critère de la migration paresseuse et de l'exclusion du
    /// nettoyage des orphelines : on ne stocke pas de drapeau « migrée », qui
    /// pourrait mentir après une restauration de sauvegarde. Le chemin dit la
    /// vérité.
    ///
    /// Un chemin vide n'est **pas** une copie : c'est le cas d'une pièce
    /// `link`, qui n'a aucun fichier.
    static func isCopied(path: String, base: URL = AttachmentImporter.baseDirectory()) -> Bool {
        guard !path.isEmpty else { return false }
        let racine = base.standardizedFileURL.path
        let candidat = URL(fileURLWithPath: path).standardizedFileURL.path
        return candidat == racine || candidat.hasPrefix(racine + "/")
    }

    // MARK: - Nom de fichier

    /// Nom de la copie : `yyyyMMdd-HHmmss_<nom assaini>`. Même forme que le
    /// bucket projet, pour qu'un dossier de sauvegarde soit lisible sans
    /// connaître la provenance des fichiers.
    static func destinationFileName(for fileName: String,
                                    at date: Date = Date(),
                                    timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        let propre = sanitize(fileName).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(f.string(from: date))_\(propre.isEmpty ? "document" : propre)"
    }

    /// Remplace les caractères interdits dans un nom de fichier. Même table
    /// que `AttachmentImporter`, dupliquée ici parce qu'elle y est `private` et
    /// que cette politique doit rester testable sans le copieur.
    static func sanitize(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: illegal).joined(separator: "_")
    }

    // MARK: - MIME et catégorie

    /// Type MIME déduit de l'extension. Rend `""` quand le système ne connaît
    /// pas le type : un MIME inventé serait pire qu'absent (`mimeType` vide
    /// est déjà la valeur par défaut de la colonne).
    static func mimeType(forExtension ext: String) -> String {
        let propre = ext.lowercased()
        guard !propre.isEmpty,
              let type = UTType(filenameExtension: propre),
              let mime = type.preferredMIMEType else { return "" }
        return mime
    }

    /// Catégorie stockée dans `MeetingAttachment.kind`. Reprise **à
    /// l'identique** de l'ancien `MeetingAttachmentService.kindForExtension`,
    /// qui était `private` : la même extension doit continuer de produire la
    /// même valeur, les lignes existantes en dépendent.
    static func kind(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "pdf":                 return "pdf"
        case "pptx", "ppt":         return "pptx"
        case "docx", "doc":         return "docx"
        case "xlsx", "xls", "csv":  return "xlsx"
        case "md", "markdown":      return "markdown"
        case "txt", "text":         return "text"
        case "png", "jpg", "jpeg", "heic", "gif", "tiff": return "image"
        default:                    return "document"
        }
    }

    /// Catégorie d'une URL collée (spec §1.3 : `kind file/link/capture`).
    static let linkKind = "link"
    /// Catégorie d'une capture d'écran remontée dans le tiroir.
    static let captureKind = "capture"
    /// Catégorie historique du lot de captures (`MeetingAttachment.slides`).
    /// Conservée : des lignes existent en base avec cette valeur.
    static let slidesKind = "slides"

    // MARK: - Poids affiché

    /// `84 Ko`, `2,1 Mo` — le texte de la vignette. `nil` quand la taille est
    /// inconnue (`0`, valeur par défaut des lignes antérieures à D5) : le
    /// tiroir omet alors la mention plutôt que d'afficher « 0 o », qui
    /// laisserait croire à un fichier vide.
    static func formattedByteCount(_ bytes: Int) -> String? {
        guard bytes > 0 else { return nil }
        let ko = 1_024.0
        let mo = ko * ko
        let go = mo * ko
        let valeur = Double(bytes)
        // Séparateur décimal français : la virgule. `NumberFormatter` sur la
        // locale courante rendrait le libellé dépendant du poste, or les
        // libellés de l'app sont en français (CLAUDE.md).
        func nombre(_ v: Double, _ decimales: Int) -> String {
            String(format: "%.\(decimales)f", v).replacingOccurrences(of: ".", with: ",")
        }
        if valeur < ko { return "\(bytes) o" }
        if valeur < mo { return "\(Int((valeur / ko).rounded())) Ko" }
        if valeur < go { return "\(nombre(valeur / mo, 1)) Mo" }
        return "\(nombre(valeur / go, 1)) Go"
    }

    // MARK: - Vignette typée

    /// Le fond de l'icône 34 × 40 du tiroir. Cinq tons, un par famille : la
    /// couleur elle-même est nommée dans `One2OneTokens`, jamais ici (règle du
    /// programme §7).
    enum BadgeTone: Hashable, Sendable {
        case tableur
        case image
        case document
        case lien
        case presentation
    }

    /// Les trois lettres de l'icône. `fileName` permet de préférer l'extension
    /// réelle quand elle est plus précise que la catégorie — un `.jpg` reste
    /// `JPG`, un `.csv` reste `CSV`, comme le fait le Finder.
    static func badge(forKind kind: String, fileName: String = "") -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.uppercased()
        switch kind {
        case "xlsx":
            return ["XLS", "XLSX", "CSV"].contains(ext) ? (ext == "XLSX" ? "XLS" : ext) : "XLS"
        case "image", captureKind, slidesKind:
            // Une capture est une image : son badge suit son extension, comme
            // pour un PNG déposé — `Comptes_GitLab.png` porte `PNG` sur la
            // capture `3a-tiroir-ressources.png`.
            return ["PNG", "JPG", "JPEG", "HEIC", "GIF", "TIFF"].contains(ext)
                ? (ext == "JPEG" ? "JPG" : ext)
                : "PNG"
        case "pdf":                     return "PDF"
        case linkKind:                  return "URL"
        case "pptx":                    return "PPT"
        case "markdown":                return "MD"
        case "text":                    return "TXT"
        default:                        return "DOC"
        }
    }

    static func badgeTone(forKind kind: String) -> BadgeTone {
        switch kind {
        case "xlsx":                            return .tableur
        case "image", captureKind, slidesKind:  return .image
        case linkKind:                          return .lien
        case "pptx":                            return .presentation
        default:                                return .document
        }
    }
}
