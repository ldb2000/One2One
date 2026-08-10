import Foundation

/// Où trouver le CLI, sous quelle identité le faire tourner, et ce qu'on
/// l'autorise à faire.
struct AgentLaunchConfiguration: Equatable, Sendable {
    /// Le binaire `claude`, désigné par son chemin absolu.
    var executable: URL
    /// `CLAUDE_CONFIG_DIR` — une configuration **dédiée**, distincte de celles
    /// de l'auteur, pour que l'agent n'hérite ni de ses plugins, ni de ses
    /// skills, ni de ses hooks, ni de son `CLAUDE.md`.
    var configDirectory: URL
    var home: URL
    /// Dossiers ajoutés en tête de `PATH` — `uv` y vit.
    var toolPaths: [String]
    /// Recherche et lecture web. Sans elles l'agent ne peut pas se documenter
    /// sur un sujet qu'il ne connaît que par les CR.
    var allowsWeb: Bool

    /// Les valeurs relevées sur la machine cible (cf. la spec du 2026-08-10).
    static func standard(home: URL) -> AgentLaunchConfiguration {
        AgentLaunchConfiguration(
            executable: home.appendingPathComponent(".local/bin/claude"),
            configDirectory: home.appendingPathComponent(".claude-onetoone"),
            home: home,
            toolPaths: ["/opt/homebrew/bin"],
            allowsWeb: true
        )
    }
}

/// Tout ce qu'il faut pour lancer un tour, sans rien décider de plus.
struct AgentCommandSpec: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL
    let standardInput: String
}

/// Compose la ligne de commande d'un tour d'agent.
///
/// Fonction pure : elle ne lit ni le disque, ni l'environnement du processus.
/// C'est ce qui permet de vérifier l'isolation de l'agent par des tests plutôt
/// que par une inspection à l'exécution.
enum AgentCommandBuilder {

    /// Outils toujours accordés : lire et écrire dans le dossier de travail, y
    /// chercher, et lancer les scripts Office via `uv` (aucune installation
    /// permanente, aucun venv à gérer).
    private static let baseTools = ["Read", "Write", "Edit", "Glob", "Grep"]
    private static let webTools = ["WebSearch", "WebFetch"]
    private static let officeTool = "Bash(uv run *)"

    static func build(
        prompt: String,
        workspace: URL,
        resuming sessionID: String?,
        configuration: AgentLaunchConfiguration
    ) -> AgentCommandSpec {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",                         // exigé par stream-json
            "--append-system-prompt-file", workspace.appendingPathComponent("AGENT.md").path,
            "--permission-mode", "acceptEdits",
            "--allowedTools", allowedTools(configuration)
        ]

        if let sessionID { arguments += ["--resume", sessionID] }

        return AgentCommandSpec(
            executable: configuration.executable,
            arguments: arguments,
            environment: environment(configuration),
            workingDirectory: workspace,
            standardInput: prompt
        )
    }

    // MARK: - Détail

    private static func allowedTools(_ configuration: AgentLaunchConfiguration) -> String {
        (baseTools + (configuration.allowsWeb ? webTools : []) + [officeTool]).joined(separator: ",")
    }

    /// Environnement construit de zéro. On n'hérite pas de celui de l'app :
    /// une variable posée ailleurs changerait le comportement de l'agent sans
    /// qu'on puisse le reproduire.
    private static func environment(_ configuration: AgentLaunchConfiguration) -> [String: String] {
        let systemPaths = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return [
            "HOME": configuration.home.path,
            "PATH": (configuration.toolPaths + systemPaths).joined(separator: ":"),
            "CLAUDE_CONFIG_DIR": configuration.configDirectory.path
        ]
    }
}
