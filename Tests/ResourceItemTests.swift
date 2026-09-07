import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'adaptateur qui unifie les trois sources du tiroir Ressources (spec §4.1).
///
/// Trois modèles sans parenté — `MeetingAttachment`, `ProjectAttachment`,
/// `SlideCapture` — alimentent la même liste et les mêmes quatre filtres. Sans
/// cet adaptateur, chaque vignette devrait connaître son type d'origine, et les
/// filtres deviendraient trois listes juxtaposées.
@Suite("Ressources : l'adaptateur des trois sources")
@MainActor
struct ResourceItemTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeMeeting(in context: ModelContext, withProject: Bool = false) -> Meeting {
        let reunion = Meeting(title: "R", date: Date(), notes: "")
        context.insert(reunion)
        if withProject {
            let projet = Project(code: "P25_110", name: "S/D", domain: "S/D",
                                 sponsor: "OF", phase: "Réalisation", status: "Yellow")
            context.insert(projet)
            reunion.project = projet
        }
        return reunion
    }

    @discardableResult
    private func addPiece(_ nom: String,
                          kind: String,
                          to reunion: Meeting,
                          in context: ModelContext,
                          pinnedAtT: Double? = nil,
                          addedBy: String = "",
                          octets: Int = 0,
                          citations: Int = 0) -> MeetingAttachment {
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/\(nom)"), kind: kind)
        piece.fileName = nom
        piece.pinnedAtT = pinnedAtT
        piece.addedByName = addedBy
        piece.byteCount = octets
        piece.citationCount = citations
        piece.meeting = reunion
        context.insert(piece)
        return piece
    }

    @discardableResult
    private func addLink(_ nom: String, url: String,
                         to reunion: Meeting, in context: ModelContext) -> MeetingAttachment {
        let piece = addPiece(nom, kind: AttachmentCopyPolicy.linkKind, to: reunion, in: context)
        piece.filePath = url
        return piece
    }

    @discardableResult
    private func addCapture(_ index: Int, t: Double?,
                            to reunion: Meeting, in context: ModelContext) -> SlideCapture {
        // Les captures pendent d'une pièce « lot de captures » (kind `slides`),
        // conteneur à chemin virtuel : c'est la structure existante.
        let lot = (reunion.attachments.first { $0.kind == AttachmentCopyPolicy.slidesKind })
            ?? addPiece("Captures", kind: AttachmentCopyPolicy.slidesKind, to: reunion, in: context)
        let capture = SlideCapture(index: index, capturedAt: Date(),
                                   imagePath: "/tmp/slides/\(index)_Comptes_GitLab.png")
        capture.t = t
        capture.attachment = lot
        context.insert(capture)
        return capture
    }

    // MARK: - Les trois sources

    @Test("Une pièce de séance devient une ligne épinglable et citable")
    func pieceDeSeance() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", kind: "xlsx", to: reunion, in: context,
                             pinnedAtT: 728, addedBy: "Sylvain", octets: 86_016)

        let ligne = ResourceItem(piece)
        #expect(ligne.name == "Chiffrage_Marine_v3.xlsx")
        #expect(ligne.nature == .fichier)
        #expect(ligne.scope == .meeting)
        #expect(ligne.badge == "XLS")
        #expect(ligne.badgeTone == .tableur)
        #expect(ligne.pinnedAtT == 728)
        #expect(ligne.isPinnable)
        #expect(ligne.origin == .pieceDeSeance(piece.ensuredStableID))
    }

    @Test("Une pièce de projet est en lecture seule")
    func pieceDeProjet() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context, withProject: true)
        let piece = ProjectAttachment(url: URL(fileURLWithPath: "/tmp/Devis_partenaire_40k.pdf"))
        piece.project = reunion.project
        context.insert(piece)

        let ligne = ResourceItem(piece)
        #expect(ligne.scope == .project)
        #expect(ligne.badge == "PDF")
        #expect(!ligne.isPinnable)
        #expect(ligne.pinnedAtT == nil)
    }

    @Test("Une capture porte son propre timecode comme épinglage")
    func capture() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let capture = addCapture(1, t: 252, to: reunion, in: context)

        let ligne = ResourceItem(capture)
        #expect(ligne.nature == .capture)
        #expect(ligne.name == "1_Comptes_GitLab.png")
        #expect(ligne.badge == "PNG")
        #expect(ligne.pinnedAtT == 252)
        // Une capture est déjà ancrée dans le temps : on ne l'épingle pas une
        // seconde fois.
        #expect(!ligne.isPinnable)
    }

    @Test("Un lien n'a pas de fichier et ne se présente pas")
    func lien() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addLink("Board GitLab — épiques migration",
                            url: "https://gitlab.example.com/board", to: reunion, in: context)

        let ligne = ResourceItem(piece)
        #expect(ligne.nature == .lien)
        #expect(ligne.badge == "URL")
        #expect(ligne.badgeTone == .lien)
        #expect(ligne.fileURL == nil)
        #expect(ligne.linkURL?.host == "gitlab.example.com")
        #expect(!ligne.isPresentable)
        #expect(!ligne.isPinnable)
        #expect(!ligne.isOrphan)
    }

    // MARK: - Assemblage et filtres

    /// Les chiffres de `3a-tiroir-ressources.png` : `4 séance` et une vignette
    /// par capture.
    @Test("Les trois sources se retrouvent dans une liste unique")
    func assemblage() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context, withProject: true)
        addPiece("Chiffrage_Marine_v3.xlsx", kind: "xlsx", to: reunion, in: context, pinnedAtT: 728)
        addPiece("Devis_partenaire_40k.pdf", kind: "pdf", to: reunion, in: context)
        addPiece("Comptes_GitLab.png", kind: "image", to: reunion, in: context, pinnedAtT: 252)
        addLink("Board GitLab", url: "https://gitlab.example.com/b", to: reunion, in: context)
        addCapture(1, t: 300, to: reunion, in: context)
        addCapture(2, t: nil, to: reunion, in: context)
        for i in 0..<17 {
            let p = ProjectAttachment(url: URL(fileURLWithPath: "/tmp/projet-\(i).pdf"))
            p.project = reunion.project
            context.insert(p)
        }

        let lignes = ResourceItem.all(for: reunion)
        let compteurs = ResourceItem.counts(lignes)
        #expect(compteurs.seance == 4)
        #expect(compteurs.projet == 17)
        // Le lot de captures (kind `slides`) est un conteneur : il ne paraît
        // pas comme ressource, ses PNG oui.
        #expect(ResourceItem.filtered(lignes, by: .captures).count == 2)
        #expect(ResourceItem.filtered(lignes, by: .liens).count == 1)
        #expect(!lignes.contains { $0.kind == AttachmentCopyPolicy.slidesKind })
    }

    @Test("Les épinglées passent devant, par timecode croissant")
    func tri() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        addPiece("tard.pdf", kind: "pdf", to: reunion, in: context, pinnedAtT: 728)
        addPiece("tot.pdf", kind: "pdf", to: reunion, in: context, pinnedAtT: 252)
        addPiece("libre.pdf", kind: "pdf", to: reunion, in: context)

        let noms = ResourceItem.all(for: reunion).map(\.name)
        #expect(noms.prefix(2) == ["tot.pdf", "tard.pdf"])
        #expect(noms.last == "libre.pdf")
    }

    /// Le filtre `Cette séance` écarte les captures : elles ont leur propre
    /// onglet, et la capture 3a annonce `4 séance` sans les compter.
    @Test("Les captures ne comptent pas dans « Cette séance »")
    func capturesHorsSeance() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        addPiece("a.pdf", kind: "pdf", to: reunion, in: context)
        addCapture(1, t: 10, to: reunion, in: context)

        let lignes = ResourceItem.all(for: reunion)
        #expect(ResourceItem.filtered(lignes, by: .seance).map(\.name) == ["a.pdf"])
    }

    // MARK: - Métadonnées

    @Test("La ligne de métadonnées suit la capture")
    func metadonnees() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("Chiffrage_Marine_v3.xlsx", kind: "xlsx", to: reunion, in: context,
                             addedBy: "Sylvain", octets: 86_016)
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        piece.importedAt = Date(timeIntervalSince1970: 1_788_506_520)  // 09:22 Paris

        #expect(ResourceItem(piece).metadata(calendar: calendrier)
                == "Ajouté par Sylvain · 09:22 · 84 Ko")
    }

    @Test("Une pièce citée l'annonce")
    func metadonneesCitations() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context, withProject: true)
        let piece = addPiece("Devis_partenaire_40k.pdf", kind: "pdf", to: reunion, in: context,
                             citations: 3)
        #expect(ResourceItem(piece).metadata().contains("cité 3 fois"))
    }

    @Test("Une capture annonce son timecode")
    func metadonneesCapture() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let capture = addCapture(1, t: 252, to: reunion, in: context)
        #expect(ResourceItem(capture).metadata().contains("Capture écran · épinglé à 04:12"))
    }

    @Test("Sans déposant ni poids, aucun séparateur orphelin")
    func metadonneesMinimales() throws {
        let context = try makeContext()
        let reunion = makeMeeting(in: context)
        let piece = addPiece("a.pdf", kind: "pdf", to: reunion, in: context)
        let texte = ResourceItem(piece).metadata()
        #expect(!texte.hasPrefix("·"))
        #expect(!texte.hasSuffix("·"))
        #expect(!texte.contains("· ·"))
    }

    // MARK: - Identité

    @Test("L'identité d'une pièce de projet est stable")
    func identiteStable() {
        let a = ResourceItem.derivedID(from: "project:/tmp/a.pdf")
        let b = ResourceItem.derivedID(from: "project:/tmp/a.pdf")
        let c = ResourceItem.derivedID(from: "project:/tmp/b.pdf")
        #expect(a == b)
        #expect(a != c)
    }
}
