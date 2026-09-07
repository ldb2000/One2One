import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// Le jeu de démonstration du lot 6 doit tomber **exactement** sur les
/// chiffres de `3a-tiroir-ressources.png` : `4 séance`, `17 projet`, deux
/// épinglées, un lien, et une pièce citée trois fois. Sans ce test, la recette
/// visuelle compare l'écran à une maquette dont les nombres ont dérivé, et on
/// ne sait plus lequel des deux a tort.
@Suite("Jeu de démonstration — les ressources du lot 6")
@MainActor
struct RefonteDemoSeedLot6Tests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// Une racine temporaire : le semis écrit de vrais fichiers, et il ne doit
    /// jamais toucher au stockage réel de l'utilisateur.
    private func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("onetoone-seed6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("Les compteurs du tiroir sont ceux de la capture")
    func compteurs() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let reunion = RefonteDemoSeed.seedLot6(in: context, base: base)
        let lignes = ResourceItem.all(for: reunion)
        let compteurs = ResourceItem.counts(lignes)

        #expect(compteurs.seance == 4)
        #expect(compteurs.projet == 17)
        #expect(ResourceItem.filtered(lignes, by: .liens).count == 1)
    }

    @Test("Deux pièces sont épinglées, à 04:12 et 12:08")
    func epinglees() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let reunion = RefonteDemoSeed.seedLot6(in: context, base: base)

        #expect(reunion.pinnedAttachments.count == 2)
        #expect(reunion.pinnedAttachments.compactMap(\.pinnedAtT) == [252, 728])
        #expect(reunion.pinnedAttachments.map(\.fileName)
                == ["Comptes_GitLab.png", "Chiffrage_Marine_v3.xlsx"])
        #expect(MeetingTimelineMarkers.pinMarkers(for: reunion).count == 2)
    }

    /// Une vignette qui pointe un fichier absent s'affiche orpheline : la
    /// recette montrerait quatre invites de reliaison au lieu du tiroir.
    @Test("Aucune pièce semée n'est orpheline")
    func aucuneOrpheline() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let reunion = RefonteDemoSeed.seedLot6(in: context, base: base)
        let lignes = ResourceItem.all(for: reunion)

        #expect(!lignes.isEmpty)
        #expect(lignes.allSatisfy { !$0.isOrphan })
        // Et toutes sont copiées : le semis respecte D5 comme un vrai import.
        for piece in reunion.attachments where piece.kind != AttachmentCopyPolicy.linkKind {
            #expect(AttachmentCopyPolicy.isCopied(path: piece.filePath, base: base))
        }
    }

    @Test("Les métadonnées de la vignette présentée sont celles de la capture")
    func metadonneesDeLaCapture() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let reunion = RefonteDemoSeed.seedLot6(in: context, base: base)
        let chiffrage = try #require(
            reunion.attachments.first { $0.fileName == "Chiffrage_Marine_v3.xlsx" })
        let ligne = ResourceItem(chiffrage)

        #expect(ligne.badge == "XLS")
        #expect(ligne.badgeTone == .tableur)
        #expect(ligne.metadata().contains("Ajouté par Sylvain"))
        #expect(ligne.metadata().contains("84 Ko"))

        let devis = try #require(
            reunion.attachments.first { $0.fileName == "Devis_partenaire_40k.pdf" })
        #expect(ResourceItem(devis).metadata().contains("cité 3 fois"))
    }

    @Test("Le pied du rapport part sur les deux cases par défaut")
    func piedDuRapport() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let reunion = RefonteDemoSeed.seedLot6(in: context, base: base)
        #expect(reunion.reportAttachmentOptions == .defaults)
        #expect(MeetingSharingState.presentCount(for: reunion) == 6)
    }

    /// Une commande de menu peut être cliquée deux fois.
    @Test("Semer deux fois ne duplique rien")
    func idempotence() throws {
        let context = try makeContext()
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let premier = RefonteDemoSeed.seedLot6(in: context, base: base)
        let compte = premier.attachments.count
        let second = RefonteDemoSeed.seedLot6(in: context, base: base)

        #expect(premier.persistentModelID == second.persistentModelID)
        #expect(second.attachments.count == compte)
        #expect(second.project?.attachments.count == 17)
    }
}
