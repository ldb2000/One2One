import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentWorkspaceStore` — la seule pièce du service qui touche au
/// disque. Chaque test travaille dans son propre dossier temporaire, qu'il
/// détruit en sortant.
struct AgentWorkspaceStoreTests {

    private func makeStore() throws -> (AgentWorkspaceStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-store-\(UUID().uuidString)")
        return (AgentWorkspaceStore(root: root), root)
    }

    private func destroy(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    private func text(_ url: URL, _ path: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - Emplacement

    @Test func placesEachRunInItsOwnFolder() {
        let support = URL(fileURLWithPath: "/Users/moi/Library/Application Support")
        let id = UUID(uuidString: "0BF3A0F6-8A5C-4C3E-9E3B-6C2B7F1D2E44")!

        #expect(AgentWorkspaceStore.location(runID: id, inApplicationSupport: support).path
                == "/Users/moi/Library/Application Support/OneToOne/Agents/0BF3A0F6-8A5C-4C3E-9E3B-6C2B7F1D2E44")
    }

    // MARK: - Création

    @Test func writesEveryFileOfThePlan() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }

        try store.create(from: [
            AgentWorkspaceFile(path: "BRIEF.md", contents: "Ma demande"),
            AgentWorkspaceFile(path: "contexte/reunions/001-point.md", contents: "Le CR")
        ])

        #expect(text(root, "BRIEF.md") == "Ma demande")
        #expect(text(root, "contexte/reunions/001-point.md") == "Le CR")
    }

    @Test func createsTheFoldersTheAgentWillFill() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }

        try store.create(from: [])

        for folder in AgentWorkspacePlan.directories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(folder).path, isDirectory: &isDirectory
            )
            #expect(exists && isDirectory.boolValue, "dossier manquant : \(folder)")
        }
    }

    // MARK: - Le fichier d'état

    @Test func readsNothingWhenTheStateFileIsAbsent() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [])

        #expect(store.readStateFile() == nil)
    }

    @Test func readsTheStateFileTheAgentWrote() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [AgentWorkspaceFile(path: "etat.json", contents: #"{"etat":"livrable"}"#)])

        let data = try #require(store.readStateFile())
        #expect(try AgentStateContract.read(data).state == .deliverable)
    }

    @Test func clearsTheStateFileBeforeATurn() throws {
        // Sans cet effacement, un tour qui échoue laisserait l'état du tour
        // précédent en place et l'application lirait un livrable périmé.
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [AgentWorkspaceFile(path: "etat.json", contents: "{}")])

        store.clearStateFile()

        #expect(store.readStateFile() == nil)
    }

    @Test func clearingAnAbsentStateFileIsHarmless() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [])

        store.clearStateFile()   // ne doit rien lever

        #expect(store.readStateFile() == nil)
    }

    // MARK: - L'échange

    @Test func readsTheQuestionTheAgentLeft() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [
            AgentWorkspaceFile(path: "echange/question.md", contents: "Quel montant ?\n")
        ])

        #expect(store.readQuestion() == "Quel montant ?")
    }

    @Test func readsNoQuestionWhenTheAgentLeftNone() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [])

        #expect(store.readQuestion() == nil)
    }

    @Test func writesTheAnswerWhereTheAgentWillLookForIt() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [])

        try store.writeAnswer("Le budget est de 120 k€.")

        #expect(text(root, "echange/reponse.md") == "Le budget est de 120 k€.")
    }

    @Test func replacesThePreviousAnswer() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }
        try store.create(from: [])

        try store.writeAnswer("Première réponse")
        try store.writeAnswer("Seconde réponse")

        #expect(text(root, "echange/reponse.md") == "Seconde réponse")
    }

    // MARK: - Livrables

    @Test func resolvesADeliverableAgainstTheWorkspace() throws {
        let (store, root) = try makeStore()
        defer { destroy(root) }

        let url = store.url(for: AgentDeliverableRef(
            path: "livrables/note.docx", kind: .docx, title: "Note"
        ))

        #expect(url.path == root.appendingPathComponent("livrables/note.docx").path)
    }

    // MARK: - Destruction

    @Test func destroysTheWholeFolder() throws {
        let (store, root) = try makeStore()
        try store.create(from: [AgentWorkspaceFile(path: "BRIEF.md", contents: "x")])

        try store.destroy()

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }
}
