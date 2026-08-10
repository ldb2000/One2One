import Foundation

/// Le dossier de travail d'une délégation, sur le disque.
///
/// Seule pièce du service à toucher au système de fichiers ; tout le reste est
/// pur. Le dossier est volontairement lisible à l'œil nu : l'auteur peut
/// l'ouvrir dans le Finder pour voir ce que l'agent a lu et ce qu'il a écrit.
struct AgentWorkspaceStore: Sendable {

    let root: URL

    private var exchange: URL { root.appendingPathComponent("echange") }
    private var stateFile: URL { root.appendingPathComponent("etat.json") }

    /// Un dossier par **délégation**, pas par action : confier deux fois la même
    /// action doit donner deux dossiers, jamais écraser le premier travail.
    static func location(runID: UUID, inApplicationSupport support: URL) -> URL {
        support
            .appendingPathComponent("OneToOne", isDirectory: true)
            .appendingPathComponent("Agents", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
    }

    // MARK: - Création

    func create(from plan: [AgentWorkspaceFile]) throws {
        let manager = FileManager.default

        for folder in AgentWorkspacePlan.directories {
            try manager.createDirectory(
                at: root.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        for file in plan {
            let url = root.appendingPathComponent(file.path)
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(file.contents.utf8).write(to: url, options: .atomic)
        }
    }

    func destroy() throws {
        try FileManager.default.removeItem(at: root)
    }

    // MARK: - Le fichier d'état

    func readStateFile() -> Data? {
        try? Data(contentsOf: stateFile)
    }

    /// À appeler **avant** chaque tour : sans cet effacement, un tour qui échoue
    /// laisserait l'état du tour précédent en place et l'application lirait un
    /// livrable périmé comme s'il venait d'être produit.
    func clearStateFile() {
        try? FileManager.default.removeItem(at: stateFile)
    }

    // MARK: - L'échange

    func readQuestion() -> String? {
        let url = exchange.appendingPathComponent("question.md")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func writeAnswer(_ text: String) throws {
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: exchange.appendingPathComponent("reponse.md"), options: .atomic)
    }

    // MARK: - Livrables

    /// Le chemin d'un livrable est relatif au dossier ; `AgentStateContract` a
    /// déjà refusé tout ce qui en sortait.
    func url(for deliverable: AgentDeliverableRef) -> URL {
        root.appendingPathComponent(deliverable.path)
    }
}
