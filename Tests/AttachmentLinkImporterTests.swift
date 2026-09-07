import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Les URL collées dans les ressources (`⌘⇧V`, spec §1.4 et §4.1).
///
/// La contrainte structurante est négative : **aucune requête réseau**. Le
/// libellé se déduit de l'URL — dernier segment, à défaut le domaine — parce
/// qu'aller chercher le `<title>` d'une page ferait sortir l'app de la boucle
/// locale pour un libellé, ce que le §8 interdit sans le signaler.
@Suite("Liens collés dans les ressources")
struct AttachmentLinkImporterTests {

    // MARK: - Reconnaissance

    @Test("Une URL http(s) est reconnue")
    func urlReconnue() {
        #expect(AttachmentLinkImporter.parse("https://gitlab.example.com/board")?.url.absoluteString
                == "https://gitlab.example.com/board")
        #expect(AttachmentLinkImporter.parse("  http://intra/wiki/CI-CD  ") != nil)
    }

    /// Refuser plutôt que de deviner : coller trois lignes de notes ne doit pas
    /// produire une ressource intitulée « trois lignes de notes ».
    @Test("Ce qui n'est pas une adresse web est refusé")
    func refus() {
        #expect(AttachmentLinkImporter.parse("") == nil)
        #expect(AttachmentLinkImporter.parse("   ") == nil)
        #expect(AttachmentLinkImporter.parse("Le chiffrage v3 annonce 21 000 €") == nil)
        #expect(AttachmentLinkImporter.parse("about:blank") == nil)
        #expect(AttachmentLinkImporter.parse("file:///Users/moi/a.pdf") == nil)
        #expect(AttachmentLinkImporter.parse("mailto:a@b.c") == nil)
        #expect(AttachmentLinkImporter.parse("https://") == nil)
        // Un bloc multi-lignes n'est pas une URL, même s'il en contient une.
        #expect(AttachmentLinkImporter.parse("note\nhttps://a.com/b") == nil)
    }

    // MARK: - Libellé

    @Test("Le libellé est le dernier segment du chemin")
    func libelleSegment() {
        #expect(AttachmentLinkImporter.parse("https://gitlab.example.com/board")?.title == "board")
        #expect(AttachmentLinkImporter.parse("https://x.com/a/b/Chiffrage%20v3")?.title
                == "Chiffrage v3")
        #expect(AttachmentLinkImporter.parse("https://x.com/a/b/")?.title == "b")
    }

    @Test("À défaut de chemin, le domaine")
    func libelleDomaine() {
        #expect(AttachmentLinkImporter.parse("https://gitlab.example.com")?.title
                == "gitlab.example.com")
        #expect(AttachmentLinkImporter.parse("https://www.example.com/")?.title == "example.com")
        #expect(AttachmentLinkImporter.parse("https://x.com/?q=1")?.title == "x.com")
    }

    /// Une extension technique n'apporte rien au libellé ; un `.pdf` distant,
    /// si — il dit ce qu'on va ouvrir.
    @Test("Les extensions techniques disparaissent, pas les autres")
    func libelleExtensions() {
        #expect(AttachmentLinkImporter.parse("https://x.com/board.html")?.title == "board")
        #expect(AttachmentLinkImporter.parse("https://x.com/index.php")?.title == "index")
        #expect(AttachmentLinkImporter.parse("https://x.com/devis.pdf")?.title == "devis.pdf")
    }

    // MARK: - Création de la pièce

    @Test("La pièce créée est un lien, sans fichier ni copie")
    @MainActor
    func creation() throws {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let settings = AppSettings()
        settings.ownerName = "Yann"
        context.insert(settings)
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)

        let lien = try #require(AttachmentLinkImporter.parse("https://gitlab.example.com/board"))
        let piece = AttachmentLinkImporter.attach(lien, to: reunion, in: context)

        #expect(piece.kind == AttachmentCopyPolicy.linkKind)
        #expect(piece.fileName == "board")
        #expect(piece.filePath == "https://gitlab.example.com/board")
        #expect(piece.addedByName == "Yann")
        #expect(piece.bookmarkData == nil)
        #expect(piece.byteCount == 0)
        #expect(piece.scope == .meeting)
        // Aucun fichier n'existe : la politique de copie est sans objet pour un
        // lien, pas contournée.
        #expect(!piece.isOrphan)
        #expect(piece.linkURL?.host == "gitlab.example.com")

        let ligne = ResourceItem(piece)
        #expect(ligne.nature == .lien)
        #expect(ligne.badge == "URL")
        #expect(!ligne.isPresentable)
    }
}
