import Foundation

/// Lance réellement le CLI, par son chemin absolu et sans passer par un shell.
///
/// Le détour par un shell serait fatal sur la machine cible : `claude` y est
/// aliasé dans `~/.zshrc` vers un `echo`. On invoque donc le binaire
/// directement, avec un environnement construit de toutes pièces.
struct SystemAgentProcessLauncher: AgentProcessLauncher {

    func run(
        _ spec: AgentCommandSpec,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> AgentProcessResult {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = spec.environment
        process.currentDirectoryURL = spec.workingDirectory

        let output = Pipe(), errors = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = input

        let lines = LineAccumulator(onLine: onLine)
        let stderrText = TextAccumulator()

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { lines.append(chunk) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { stderrText.append(chunk) }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                    // Écriture différée : un prompt plus gros que le tampon du
                    // tube bloquerait si on l'écrivait avant le démarrage.
                    DispatchQueue.global(qos: .utility).async {
                        if !spec.standardInput.isEmpty {
                            try? input.fileHandleForWriting.write(contentsOf: Data(spec.standardInput.utf8))
                        }
                        try? input.fileHandleForWriting.close()
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // `terminate()` lève une exception ObjC sur un processus jamais
            // lancé : la garde n'est pas décorative.
            if process.isRunning { process.terminate() }
        }

        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if let rest = try? output.fileHandleForReading.readToEnd() { lines.append(rest) }
        if let rest = try? errors.fileHandleForReading.readToEnd() { stderrText.append(rest) }
        lines.flush()

        return AgentProcessResult(
            exitCode: process.terminationStatus,
            standardError: stderrText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Accumulateurs

/// Recompose des lignes complètes à partir des morceaux que rend le tube. Le
/// flux `stream-json` n'a de sens que ligne par ligne, et une lecture arrive
/// rarement sur une frontière de ligne.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func append(_ chunk: Data) {
        var complete: [String] = []

        lock.lock()
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 0x0A) {
            complete.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
            pending = pending[pending.index(after: newline)...]
        }
        lock.unlock()

        complete.forEach(onLine)
    }

    /// Rend la dernière ligne si le processus s'est arrêté sans passer à la ligne.
    func flush() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()

        guard !rest.isEmpty else { return }
        onLine(String(decoding: rest, as: UTF8.self))
    }
}

private final class TextAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) { lock.lock(); storage.append(chunk); lock.unlock() }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: storage, as: UTF8.self)
    }
}
