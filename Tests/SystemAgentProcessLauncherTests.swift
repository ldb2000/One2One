import Testing
import Foundation
@testable import OneToOne

/// Couvre `SystemAgentProcessLauncher` — la seule pièce qui lance vraiment un
/// processus. Les tests l'exercent sur des binaires du système (`printf`,
/// `cat`, `env`, `false`, `sleep`) : c'est rapide, déterministe, et sans réseau.
/// Le CLI `claude`, lui, n'est jamais appelé.
struct SystemAgentProcessLauncherTests {

    private func spec(
        _ executable: String,
        _ arguments: [String] = [],
        standardInput: String = "",
        environment: [String: String] = [:],
        workingDirectory: URL = URL(fileURLWithPath: "/tmp")
    ) -> AgentCommandSpec {
        AgentCommandSpec(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            standardInput: standardInput
        )
    }

    private final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func append(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    // MARK: - Sortie standard

    @Test func streamsOneCallbackPerLine() async throws {
        let lines = Lines()
        let result = try await SystemAgentProcessLauncher()
            .run(spec("/usr/bin/printf", ["un\\ndeux\\ntrois\\n"])) { lines.append($0) }

        #expect(lines.all == ["un", "deux", "trois"])
        #expect(result.exitCode == 0)
    }

    @Test func emitsATrailingLineThatHasNoNewline() async throws {
        let lines = Lines()
        _ = try await SystemAgentProcessLauncher()
            .run(spec("/usr/bin/printf", ["sans-fin-de-ligne"])) { lines.append($0) }

        #expect(lines.all == ["sans-fin-de-ligne"])
    }

    @Test func doesNotEmitAnEmptyTrailingLine() async throws {
        let lines = Lines()
        _ = try await SystemAgentProcessLauncher()
            .run(spec("/usr/bin/printf", ["seule\\n"])) { lines.append($0) }

        #expect(lines.all == ["seule"])
    }

    // MARK: - Entrée standard

    @Test func passesTheStandardInputToTheProcess() async throws {
        // Le prompt d'un tour peut être long : il passe par stdin, jamais par
        // les arguments.
        let lines = Lines()
        _ = try await SystemAgentProcessLauncher()
            .run(spec("/bin/cat", standardInput: "Rédige la note.\n")) { lines.append($0) }

        #expect(lines.all == ["Rédige la note."])
    }

    // MARK: - Environnement et dossier

    @Test func appliesTheEnvironmentItWasGiven() async throws {
        let lines = Lines()
        _ = try await SystemAgentProcessLauncher()
            .run(spec("/usr/bin/env", environment: ["CLAUDE_CONFIG_DIR": "/Users/moi/.claude-onetoone"])) {
                lines.append($0)
            }

        #expect(lines.all.contains("CLAUDE_CONFIG_DIR=/Users/moi/.claude-onetoone"))
    }

    @Test func runsInsideTheWorkingDirectory() async throws {
        let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let lines = Lines()
        _ = try await SystemAgentProcessLauncher()
            .run(spec("/bin/pwd", workingDirectory: workspace)) { lines.append($0) }

        // Comparaison sur le chemin résolu : `/tmp` est un lien vers
        // `/private/tmp`, et une URL de dossier porte une barre finale que
        // `pwd` n'écrit pas.
        #expect(lines.all.first.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
                == workspace.resolvingSymlinksInPath().path)
    }

    // MARK: - Échecs

    @Test func reportsANonZeroExitCode() async throws {
        let result = try await SystemAgentProcessLauncher().run(spec("/usr/bin/false")) { _ in }

        #expect(result.exitCode == 1)
    }

    @Test func capturesTheStandardError() async throws {
        let result = try await SystemAgentProcessLauncher()
            .run(spec("/bin/sh", ["-c", "echo 'Invalid API key' >&2; exit 1"])) { _ in }

        #expect(result.standardError.contains("Invalid API key"))
        #expect(result.exitCode == 1)
    }

    @Test func throwsWhenTheBinaryDoesNotExist() async {
        await #expect(throws: (any Error).self) {
            try await SystemAgentProcessLauncher()
                .run(spec("/nowhere/claude")) { _ in }
        }
    }

    // MARK: - Annulation

    @Test func terminatesTheProcessWhenTheTaskIsCancelled() async throws {
        // L'auteur doit pouvoir arrêter un agent parti trop loin sans attendre
        // la fin de son tour.
        let task = Task {
            try await SystemAgentProcessLauncher().run(spec("/bin/sleep", ["30"])) { _ in }
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = Date()
        task.cancel()
        _ = try? await task.value

        #expect(Date().timeIntervalSince(started) < 5)
    }
}
