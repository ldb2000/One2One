import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentStateContract` — la lecture d'`etat.json`, le fichier que l'agent
/// écrit à la fin de chaque tour pour dire ce qu'il a fait et ce qu'il attend.
///
/// Les clés JSON sont en français : c'est un contrat passé à un agent qu'on
/// instruit en français (cf. la spec du 2026-08-10). Les symboles Swift restent
/// en anglais, conformément à `CLAUDE.md`.
struct AgentStateContractTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: - Les trois états nominaux

    @Test func readsAQuestionTurn() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "question", "question": "Quel budget dois-je annoncer ?" }
        """))

        #expect(report.state == .question)
        #expect(report.question == "Quel budget dois-je annoncer ?")
        #expect(report.deliverables.isEmpty)
    }

    @Test func readsADeliverableTurn() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "livrable",
          "resume": "Note rédigée à partir des trois CR.",
          "livrables": [
            { "fichier": "livrables/note.docx", "type": "docx", "titre": "Note de cadrage" }
          ] }
        """))

        #expect(report.state == .deliverable)
        #expect(report.summary == "Note rédigée à partir des trois CR.")
        #expect(report.deliverables == [
            AgentDeliverableRef(path: "livrables/note.docx", kind: .docx, title: "Note de cadrage")
        ])
    }

    @Test func readsABlockedTurn() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "bloque", "resume": "Le CR du 3 août est vide." }
        """))

        #expect(report.state == .blocked)
    }

    @Test func readsTheAssumptionsTheAgentDeclares() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "livrable", "hypotheses": ["CR du 3 août retenu", "Budget supposé stable"] }
        """))

        #expect(report.assumptions == ["CR du 3 août retenu", "Budget supposé stable"])
    }

    // MARK: - Ce qui doit échouer

    @Test func rejectsBrokenJSON() {
        #expect(throws: AgentStateContract.Failure.unreadable) {
            try AgentStateContract.read(data("{ \"etat\": "))
        }
    }

    @Test func rejectsAMissingState() {
        #expect(throws: AgentStateContract.Failure.missingField("etat")) {
            try AgentStateContract.read(data("{ \"resume\": \"fini\" }"))
        }
    }

    @Test func rejectsAnUnknownState() {
        #expect(throws: AgentStateContract.Failure.unknownState("termine")) {
            try AgentStateContract.read(data("{ \"etat\": \"termine\" }"))
        }
    }

    @Test func rejectsAQuestionTurnWithoutAQuestion() {
        #expect(throws: AgentStateContract.Failure.missingField("question")) {
            try AgentStateContract.read(data("{ \"etat\": \"question\" }"))
        }
    }

    // MARK: - Confinement au dossier de travail

    @Test func rejectsADeliverableEscapingTheWorkspace() {
        #expect(throws: AgentStateContract.Failure.pathOutsideWorkspace("../../.ssh/id_rsa")) {
            try AgentStateContract.read(data("""
            { "etat": "livrable",
              "livrables": [{ "fichier": "../../.ssh/id_rsa", "type": "md", "titre": "x" }] }
            """))
        }
    }

    @Test func rejectsAnAbsoluteDeliverablePath() {
        #expect(throws: AgentStateContract.Failure.pathOutsideWorkspace("/etc/passwd")) {
            try AgentStateContract.read(data("""
            { "etat": "livrable",
              "livrables": [{ "fichier": "/etc/passwd", "type": "md", "titre": "x" }] }
            """))
        }
    }

    // MARK: - Tolérance

    @Test func keepsADeliverableWhoseKindIsUnknown() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "livrable",
          "livrables": [{ "fichier": "livrables/plan.dwg", "type": "dwg", "titre": "Plan" }] }
        """))

        #expect(report.deliverables == [
            AgentDeliverableRef(path: "livrables/plan.dwg", kind: .attachment, title: "Plan")
        ])
    }

    @Test func fallsBackToTheFileNameWhenTheTitleIsMissing() throws {
        let report = try AgentStateContract.read(data("""
        { "etat": "livrable",
          "livrables": [{ "fichier": "livrables/note.docx", "type": "docx" }] }
        """))

        #expect(report.deliverables.first?.title == "note.docx")
    }
}
