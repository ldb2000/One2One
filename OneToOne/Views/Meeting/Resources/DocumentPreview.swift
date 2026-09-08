import SwiftUI
import PDFKit
import AppKit

/// L'aperçu d'un document dans la zone « À l'écran » (spec §4.2).
///
/// Trois cas, dans cet ordre : un PDF est rendu page par page par `PDFKit`,
/// une image est chargée telle quelle, et **tout le reste affiche une invite**
/// — jamais un cadre vide. Un `.xlsx` ou un `.pptx` n'a pas d'aperçu
/// disponible hors de l'application qui le produit ; le dire est plus utile
/// que d'afficher un rectangle blanc dont personne ne sait s'il charge encore.
///
/// `PDFKit` est employé pour **rendre une page en image**, pas comme visionneur
/// (`PDFView`) : la scène de prévisualisation est un document centré et figé
/// à la page courante, pas un lecteur avec ses propres barres de défilement et
/// ses gestes de zoom, qui se disputeraient le défilement de la colonne.
enum DocumentPreview {

    /// Ce qu'un fichier sait montrer.
    enum Kind: Equatable {
        case pdf(pageCount: Int)
        case image
        case unavailable
    }

    /// Extensions dont `NSImage` sait charger un aperçu.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp"
    ]

    /// Classe le fichier. **Fonction pure au sens utile** : elle ne lit le
    /// disque que pour compter les pages d'un PDF, et rend `unavailable` sans
    /// exception pour un fichier absent ou illisible.
    static func kind(for url: URL?) -> Kind {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return .unavailable }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                return .unavailable
            }
            return .pdf(pageCount: document.pageCount)
        }
        if imageExtensions.contains(ext) {
            return NSImage(contentsOf: url) != nil ? .image : .unavailable
        }
        return .unavailable
    }

    /// Nombre de pages, `1` pour tout ce qui n'est pas un PDF paginé.
    static func pageCount(for url: URL?) -> Int {
        if case .pdf(let n) = kind(for: url) { return n }
        return 1
    }

    /// Rend la page `page` (1-indexée) d'un PDF en image, à la largeur
    /// demandée. `nil` si la page n'existe pas.
    static func render(pdf url: URL, page: Int, width: CGFloat) -> NSImage? {
        guard let document = PDFDocument(url: url),
              page >= 1, page <= document.pageCount,
              let pdfPage = document.page(at: page - 1) else { return nil }
        let bounds = pdfPage.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let echelle = width / bounds.width
        let taille = CGSize(width: width, height: (bounds.height * echelle).rounded())
        return pdfPage.thumbnail(of: taille, for: .mediaBox)
    }
}

/// La scène de prévisualisation : conteneur colonne, document **centré**,
/// légende « Aperçu — les participants voient la même page » **sous** le
/// document (spec §4.2 : « jamais en absolu par-dessus »).
///
/// La légende est sous le document et non superposée pour une raison
/// pratique : posée par-dessus, elle masquerait le bas de la page — c'est-à-dire
/// souvent le total d'un chiffrage, exactement ce qu'on est en train de
/// montrer.
struct DocumentPreviewScene: View {
    let url: URL?
    let page: Int
    /// Le nom, pour le repli sans aperçu.
    let fileName: String
    let badge: String
    let tone: AttachmentCopyPolicy.BadgeTone
    /// Le calque d'annotation, superposé au document quand il est actif.
    var annotation: AnnotationOverlay.Model?

    /// La légende de la spec, mot pour mot.
    static let caption = "Aperçu — les participants voient la même page"

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            document
            Text(Self.caption)
                .font(.plexMono(10.5))
                .foregroundStyle(One2OneToken.inkMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(One2OneToken.bgApp)
    }

    @ViewBuilder
    private var document: some View {
        GeometryReader { geo in
            let largeur = min(geo.size.width, 720)
            HStack {
                Spacer(minLength: 0)
                contenu(largeur: largeur)
                    .frame(maxWidth: largeur)
                    .background(One2OneToken.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: One2OneToken.radiusPreview, style: .continuous)
                            .strokeBorder(One2OneToken.cardBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: One2OneToken.radiusPreview,
                                                style: .continuous))
                    .overlay {
                        if let annotation {
                            AnnotationOverlay(model: annotation)
                        }
                    }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func contenu(largeur: CGFloat) -> some View {
        switch DocumentPreview.kind(for: url) {
        case .pdf:
            if let url, let image = DocumentPreview.render(pdf: url, page: page, width: largeur * 2) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                indisponible
            }
        case .image:
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                indisponible
            }
        case .unavailable:
            indisponible
        }
    }

    /// Le repli : l'icône typée, le nom, et la raison. Un cadre vide laisserait
    /// croire à un chargement qui n'arrive jamais.
    private var indisponible: some View {
        VStack(spacing: 9) {
            ResourceTypeIcon(badge: badge, tone: tone)
            Text(fileName)
                .font(.plexSans(12, .medium))
                .foregroundStyle(One2OneToken.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Aperçu indisponible — le document reste partagé et citable")
                .font(.plexSans(11))
                .foregroundStyle(One2OneToken.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
    }
}
