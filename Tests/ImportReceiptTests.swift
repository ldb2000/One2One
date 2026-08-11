import Testing
import SwiftData
import Foundation
@testable import OneToOne

/// L'import de document produisait un `Interview` de type « Import PDF » :
/// un reçu invisible, qui ne vivait que pour servir d'ancre au retour arrière.
/// `Interview` supprimé (ADR du 2026-08-11), le reçu devient ce qu'il aurait
/// dû être — une note, tagguée, donc listée, cherchable et retrouvable.
@Suite("Import de document — le reçu est une note tagguée")
struct ImportReceiptTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        ))
    }

    private func makeExtracted() throws -> ExtractedData {
        let json = """
        {"projects": [{"code": "P25_900", "name": "Refonte SI", "domain": "Courtage",
                       "phase": "Build", "status": "En cours", "comment": "Budget à surveiller"}],
         "collaborators": [{"name": "Alice Martin", "role": "Architecte"}],
         "summary": "Revue trimestrielle"}
        """
        return try JSONDecoder().decode(ExtractedData.self, from: Data(json.utf8))
    }

    @Test("Le reçu est une note, titrée du fichier et porteuse du texte extrait")
    func receiptIsANoteNamedAfterTheFile() throws {
        let context = try makeContext()
        let result = AIIngestionService().applyExtractedData(
            try makeExtracted(), fileName: "revue-trimestrielle.pdf", in: context)

        #expect(result.receipt.kind == .note)
        #expect(result.receipt.title.contains("revue-trimestrielle.pdf"))
        #expect(!result.receipt.liveNotes.isEmpty)
    }

    /// Le tag est ce qui remplace le type d'entretien : il rend l'ensemble des
    /// imports retrouvable d'un seul filtre, sans modèle dédié.
    @Test("Le reçu porte le thème « Import »")
    func receiptCarriesTheImportTag() throws {
        let context = try makeContext()
        let result = AIIngestionService().applyExtractedData(
            try makeExtracted(), fileName: "revue.pdf", in: context)

        #expect(result.receipt.tags.contains { $0.name == "Import" })
    }

    /// Le retour arrière de l'import supprime le reçu et ce qui y pend : les
    /// actions de suivi doivent donc être rattachées au reçu, pas ailleurs.
    @Test("Les actions de suivi pendent au reçu")
    func followUpTasksHangOnTheReceipt() throws {
        let context = try makeContext()
        let result = AIIngestionService().applyExtractedData(
            try makeExtracted(), fileName: "revue.pdf", in: context)

        #expect(!result.receipt.tasks.isEmpty, "le commentaire de projet produit une action de suivi")
    }

    @Test("Le reçu n'est pas compté comme une réunion tenue")
    func receiptIsNotHeldTime() throws {
        let context = try makeContext()
        let result = AIIngestionService().applyExtractedData(
            try makeExtracted(), fileName: "revue.pdf", in: context)

        #expect(MeetingStatsScope.held([result.receipt]).isEmpty)
    }
}
