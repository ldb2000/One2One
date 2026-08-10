import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentCommandBuilder` — les arguments et l'environnement passés au CLI
/// `claude`. Ce sont des faits vérifiables sans lancer quoi que ce soit, et ce
/// sont eux qui décident de l'isolation de l'agent : configuration dédiée,
/// environnement explicite, outils autorisés, dossier de travail.
struct AgentCommandBuilderTests {

    private let home = URL(fileURLWithPath: "/Users/moi")
    private let workspace = URL(fileURLWithPath: "/Users/moi/Library/Application Support/OneToOne/Agents/RUN-1")

    private func config(allowsWeb: Bool = true) -> AgentLaunchConfiguration {
        var c = AgentLaunchConfiguration.standard(home: home)
        c.allowsWeb = allowsWeb
        return c
    }

    private func build(resuming sessionID: String? = nil, allowsWeb: Bool = true) -> AgentCommandSpec {
        AgentCommandBuilder.build(
            prompt: "Rédige la note de cadrage.",
            workspace: workspace,
            resuming: sessionID,
            configuration: config(allowsWeb: allowsWeb)
        )
    }

    // MARK: - Les valeurs par défaut de la machine

    @Test func theStandardConfigurationPointsAtTheDedicatedConfigDirectory() {
        let c = AgentLaunchConfiguration.standard(home: home)

        #expect(c.executable.path == "/Users/moi/.local/bin/claude")
        #expect(c.configDirectory.path == "/Users/moi/.claude-onetoone")
        #expect(c.toolPaths.contains("/opt/homebrew/bin"))   // uv
        #expect(c.allowsWeb)
    }

    // MARK: - Arguments

    @Test func runsHeadlessWithAStreamingJsonOutput() {
        let args = build().arguments

        #expect(args.contains("-p"))
        #expect(args.contains("--output-format"))
        #expect(args.contains("stream-json"))
        #expect(args.contains("--verbose"))   // exigé par stream-json
    }

    @Test func loadsTheSystemPromptFromTheWorkspace() {
        let args = build().arguments
        let index = try! #require(args.firstIndex(of: "--append-system-prompt-file"))

        #expect(args[index + 1] == workspace.appendingPathComponent("AGENT.md").path)
    }

    @Test func letsTheAgentWriteInItsOwnFolderWithoutAsking() {
        let args = build().arguments
        let index = try! #require(args.firstIndex(of: "--permission-mode"))

        #expect(args[index + 1] == "acceptEdits")
    }

    @Test func allowsOnlyTheToolsTheAgentNeeds() {
        let args = build().arguments
        let index = try! #require(args.firstIndex(of: "--allowedTools"))

        #expect(args[index + 1] == "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash(uv run *)")
    }

    @Test func dropsTheWebToolsWhenTheyAreTurnedOff() {
        let args = build(allowsWeb: false).arguments
        let index = try! #require(args.firstIndex(of: "--allowedTools"))

        #expect(args[index + 1] == "Read,Write,Edit,Glob,Grep,Bash(uv run *)")
    }

    // MARK: - Reprise de session

    @Test func doesNotResumeOnTheFirstTurn() {
        #expect(build().arguments.contains("--resume") == false)
    }

    @Test func resumesTheSessionOnLaterTurns() {
        let args = build(resuming: "abc-123").arguments
        let index = try! #require(args.firstIndex(of: "--resume"))

        #expect(args[index + 1] == "abc-123")
    }

    // MARK: - Le prompt ne passe pas par les arguments

    @Test func passesThePromptOnStandardInput() {
        let spec = build()

        // Un prompt peut être long et contenir n'importe quel caractère : le
        // passer en argument, c'est s'exposer aux limites d'`ARG_MAX` et à
        // l'échappement.
        #expect(spec.standardInput == "Rédige la note de cadrage.")
        #expect(spec.arguments.contains("Rédige la note de cadrage.") == false)
    }

    // MARK: - Environnement et isolation

    @Test func runsTheBinaryDirectlyFromTheConfiguredPath() {
        // `claude` est aliasé dans le ~/.zshrc de la machine cible : passer par
        // un shell de connexion lancerait un `echo`, pas l'agent.
        #expect(build().executable.path == "/Users/moi/.local/bin/claude")
    }

    @Test func runsInsideTheWorkspaceFolder() {
        #expect(build().workingDirectory == workspace)
    }

    @Test func usesTheDedicatedConfigDirectory() {
        #expect(build().environment["CLAUDE_CONFIG_DIR"] == "/Users/moi/.claude-onetoone")
    }

    @Test func putsTheToolPathsAheadOfTheSystemOnes() {
        let path = try! #require(build().environment["PATH"])

        #expect(path.hasPrefix("/opt/homebrew/bin:"))
        #expect(path.contains("/usr/bin"))
    }

    @Test func buildsAnExplicitEnvironmentRatherThanInheritingOne() {
        // Hériter de l'environnement de l'app, c'est laisser une variable posée
        // ailleurs changer le comportement de l'agent sans qu'on le sache.
        #expect(build().environment.keys.sorted() == ["CLAUDE_CONFIG_DIR", "HOME", "PATH"])
        #expect(build().environment["HOME"] == "/Users/moi")
    }
}
