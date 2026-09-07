import Testing
import Foundation
@testable import OneToOne

/// La politique de stockage des pièces de séance (ADR
/// `2026-09-07-pieces-copiees-jamais-referencees.md`, décision D5).
///
/// Tout ce qui est décidable sans disque ni base vit ici : le sous-dossier de
/// destination, le nom de fichier, le type MIME, la catégorie `kind`, le poids
/// affiché et la vignette typée du tiroir. Les vues n'en recalculent aucun.
@Suite("Politique de copie des pièces")
struct AttachmentCopyPolicyTests {

    private let uuid = UUID(uuidString: "5C1D2E3F-4A5B-6C7D-8E9F-0A1B2C3D4E5F")!

    // MARK: - Destination

    @Test("Le sous-dossier est recordings/<uuid>/documents")
    func sousDossier() {
        #expect(AttachmentCopyPolicy.documentsSubpath(meetingStableID: uuid)
                == "recordings/\(uuid.uuidString)/documents")
    }

    @Test("Le même bucket que l'importeur")
    func bucket() {
        #expect(AttachmentImporter.Bucket.meetingDocuments(meetingStableID: uuid).subpath
                == AttachmentCopyPolicy.documentsSubpath(meetingStableID: uuid))
    }

    /// Une pièce copiée est reconnaissable à son chemin, et c'est ce qui
    /// distingue une ligne migrée d'une ligne encore référencée. Le test fixe
    /// la racine pour ne dépendre d'aucun `Application Support` réel.
    @Test("Une copie se reconnaît à son chemin")
    func detectionDeCopie() {
        let racine = URL(fileURLWithPath: "/tmp/appsupport/OneToOne")
        #expect(AttachmentCopyPolicy.isCopied(
            path: "/tmp/appsupport/OneToOne/recordings/x/documents/a.pdf", base: racine))
        #expect(AttachmentCopyPolicy.isCopied(
            path: "/tmp/appsupport/OneToOne/projects/P25/a.pdf", base: racine))
        #expect(!AttachmentCopyPolicy.isCopied(
            path: "/Users/moi/Downloads/a.pdf", base: racine))
        // Un chemin vide n'est pas une copie : c'est le cas des pièces `link`,
        // qui n'ont pas de fichier du tout.
        #expect(!AttachmentCopyPolicy.isCopied(path: "", base: racine))
    }

    // MARK: - Nom de fichier

    @Test("Le nom porte l'horodatage et reste assaini")
    func nomDeFichier() {
        let date = Date(timeIntervalSince1970: 1_788_506_100)  // 2026-09-04 09:15 Paris
        let nom = AttachmentCopyPolicy.destinationFileName(for: "Chiffrage/Marine:v3.xlsx",
                                                           at: date,
                                                           timeZone: TimeZone(identifier: "Europe/Paris")!)
        #expect(nom == "20260904-091500_Chiffrage_Marine_v3.xlsx")
    }

    @Test("Un nom vide retombe sur « document »")
    func nomVide() {
        let date = Date(timeIntervalSince1970: 0)
        let nom = AttachmentCopyPolicy.destinationFileName(for: "   ", at: date,
                                                           timeZone: TimeZone(identifier: "UTC")!)
        #expect(nom == "19700101-000000_document")
    }

    // MARK: - MIME et catégorie

    @Test("Le MIME vient de l'extension")
    func mime() {
        #expect(AttachmentCopyPolicy.mimeType(forExtension: "pdf") == "application/pdf")
        #expect(AttachmentCopyPolicy.mimeType(forExtension: "PNG") == "image/png")
        #expect(AttachmentCopyPolicy.mimeType(forExtension: "txt") == "text/plain")
        // Une extension inconnue ne produit pas un MIME inventé : le champ
        // reste vide, et `kind` continue de porter la classification.
        #expect(AttachmentCopyPolicy.mimeType(forExtension: "zzzz") == "")
        #expect(AttachmentCopyPolicy.mimeType(forExtension: "") == "")
    }

    @Test("La catégorie couvre les types du tiroir")
    func categorie() {
        #expect(AttachmentCopyPolicy.kind(forExtension: "pdf") == "pdf")
        #expect(AttachmentCopyPolicy.kind(forExtension: "PPTX") == "pptx")
        #expect(AttachmentCopyPolicy.kind(forExtension: "xlsx") == "xlsx")
        #expect(AttachmentCopyPolicy.kind(forExtension: "csv") == "xlsx")
        #expect(AttachmentCopyPolicy.kind(forExtension: "png") == "image")
        #expect(AttachmentCopyPolicy.kind(forExtension: "md") == "markdown")
        #expect(AttachmentCopyPolicy.kind(forExtension: "zzzz") == "document")
    }

    /// Les deux catégories que le lot 6 ajoute (spec §1.3 `Attachment.kind`).
    @Test("Lien et capture sont des catégories à part entière")
    func categoriesDuLot6() {
        #expect(AttachmentCopyPolicy.linkKind == "link")
        #expect(AttachmentCopyPolicy.captureKind == "capture")
    }

    // MARK: - Poids affiché

    /// La capture affiche `84 Ko`. Le poids est un texte de vignette : il se
    /// calcule ici, jamais dans la vue.
    @Test("Le poids se lit comme sur la capture")
    func poids() {
        #expect(AttachmentCopyPolicy.formattedByteCount(0) == nil)
        #expect(AttachmentCopyPolicy.formattedByteCount(-1) == nil)
        #expect(AttachmentCopyPolicy.formattedByteCount(512) == "512 o")
        #expect(AttachmentCopyPolicy.formattedByteCount(86_016) == "84 Ko")
        #expect(AttachmentCopyPolicy.formattedByteCount(1_024) == "1 Ko")
        #expect(AttachmentCopyPolicy.formattedByteCount(2_202_009) == "2,1 Mo")
    }

    // MARK: - Vignette typée

    /// Les quatre vignettes de `3a-tiroir-ressources.png` : `XLS` sur fond
    /// vert, `PNG` gris, `PDF` rose, `URL` bleu.
    @Test("Chaque type a son badge et son fond")
    func badges() {
        #expect(AttachmentCopyPolicy.badge(forKind: "xlsx") == "XLS")
        #expect(AttachmentCopyPolicy.badge(forKind: "image") == "PNG")
        #expect(AttachmentCopyPolicy.badge(forKind: "pdf") == "PDF")
        #expect(AttachmentCopyPolicy.badge(forKind: "link") == "URL")
        #expect(AttachmentCopyPolicy.badge(forKind: "capture") == "IMG")
        #expect(AttachmentCopyPolicy.badge(forKind: "pptx") == "PPT")
        #expect(AttachmentCopyPolicy.badge(forKind: "docx") == "DOC")
        #expect(AttachmentCopyPolicy.badge(forKind: "markdown") == "MD")
        #expect(AttachmentCopyPolicy.badge(forKind: "zzz") == "DOC")
    }

    /// Le badge d'un fichier passe par son extension quand elle est plus
    /// précise que la catégorie : un `.jpg` reste `JPG`, pas `PNG`.
    @Test("L'extension l'emporte sur la catégorie pour les images")
    func badgeDepuisLeNom() {
        #expect(AttachmentCopyPolicy.badge(forKind: "image", fileName: "photo.jpg") == "JPG")
        #expect(AttachmentCopyPolicy.badge(forKind: "image", fileName: "capture.png") == "PNG")
        #expect(AttachmentCopyPolicy.badge(forKind: "xlsx", fileName: "compte.csv") == "CSV")
        #expect(AttachmentCopyPolicy.badge(forKind: "link", fileName: "board") == "URL")
    }

    /// Les cinq tons sont distincts : deux types ne se confondent pas dans le
    /// tiroir. La table de `One2OneTokens` reste la seule à nommer les
    /// couleurs — ici on ne vérifie que l'affectation.
    @Test("Les tons de vignette sont distincts")
    func tons() {
        let tons: [AttachmentCopyPolicy.BadgeTone] = [
            .tableur, .image, .document, .lien, .presentation
        ]
        #expect(Set(tons).count == 5)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "xlsx") == .tableur)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "image") == .image)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "capture") == .image)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "pdf") == .document)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "link") == .lien)
        #expect(AttachmentCopyPolicy.badgeTone(forKind: "pptx") == .presentation)
    }
}
