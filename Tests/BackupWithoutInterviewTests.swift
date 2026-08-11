import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// La sauvegarde portait les entretiens. `Interview` supprimé (ADR du
/// 2026-08-11), la clé `interviews` d'une sauvegarde ancienne doit être
/// **ignorée sans erreur** : perdre une ligne vide n'est pas une perte,
/// échouer à restaurer le reste en serait une.
@MainActor
@Suite("Sauvegarde — les entretiens sortent du format, sans casser l'ancien")
struct BackupWithoutInterviewTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func makeBackup(in context: ModelContext) throws -> Data {
        let settings = AppSettings()
        context.insert(settings)
        let collab = Collaborator(name: "Alice Martin", role: "Architecte")
        context.insert(collab)
        try context.save()
        return try BackupService().backup(
            settings: settings, entities: [], projects: [], collaborators: [collab])
    }

    @Test("Une sauvegarde neuve ne porte plus d'entretiens")
    func freshBackupCarriesNoInterviews() throws {
        let data = try makeBackup(in: try makeContext())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["interviews"] == nil)
    }

    /// Le cas qui compte : une sauvegarde d'avant la suppression.
    @Test("Une sauvegarde ancienne, avec sa clé interviews, se restaure quand même")
    func oldBackupWithInterviewsStillRestores() throws {
        let data = try makeBackup(in: try makeContext())
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["interviews"] = [
            ["date": 770_000_000.0, "notes": "Entretien d'avant la suppression",
             "hasAlert": false, "attachments": []]
        ]
        let oldData = try JSONSerialization.data(withJSONObject: json)

        let target = try makeContext()
        try BackupService().restore(from: oldData, into: target)

        let restored = try target.fetch(FetchDescriptor<Collaborator>())
        #expect(restored.contains { $0.name == "Alice Martin" },
                "le reste de la sauvegarde doit revenir, la clé inconnue étant ignorée")
    }
}
