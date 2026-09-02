import Foundation

// MARK: - Le lanceur, injectable

struct AgentProcessResult: Sendable {
    let exitCode: Int32
    let standardError: String
}

/// Lance la commande et rend chaque ligne de sa sortie standard.
///
/// Protocole plutôt qu'appel direct à `Process` : c'est ce qui permet de
/// vérifier la machine à états sur un flux enregistré, sans dépendre du réseau,
/// d'un abonnement ou d'une version du CLI.
protocol AgentProcessLauncher: Sendable {
    /// `onLine` s'échappe : le lanceur réel l'appelle depuis la file de lecture
    /// du tube, pas depuis la pile de l'appelant.
    func run(
        _ spec: AgentCommandSpec,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> AgentProcessResult
}

// MARK: - Issues d'un tour

enum AgentTurnFailure: Error, Equatable, Sendable {
    /// Le binaire n'a pas pu être lancé (absent, droits, chemin faux).
    case launchFailed(String)
    /// Le CLI a rendu un code non nul — le message est sa sortie d'erreur.
    case exited(code: Int32, message: String)
    /// Le tour a rendu la main sans jamais émettre son événement `result`.
    case noResult
    /// Le tour s'est terminé, mais en signalant lui-même une erreur.
    case reportedError(String)
}

enum AgentTurnOutcome: Equatable, Sendable {
    case delivered(AgentTurnReport)
    case awaitingAnswer(question: String)
    case blocked(reason: String?)
    /// `etat.json` manque ou est inexploitable. **On ne perd pas le travail** :
    /// le texte final est remonté tel quel et l'auteur tranche.
    case needsReview(text: String?)
    case failed(AgentTurnFailure)
}

struct AgentTurnResult: Sendable {
    let outcome: AgentTurnOutcome
    /// Conservé même en cas d'échec : sans lui, `--resume` serait impossible et
    /// tout le travail du tour serait perdu.
    let sessionID: String?
    let costUSD: Double
    let lastProgress: String?
}

// MARK: - Le tour

/// Exécute un tour d'agent et en décide l'issue.
///
/// Ne lance jamais d'exception : tout, y compris un binaire introuvable, se
/// traduit en `AgentTurnOutcome`. L'appelant a donc un seul chemin à traiter.
struct AgentTurnRunner: Sendable {

    let launcher: AgentProcessLauncher
    /// Lit `etat.json` dans le dossier de travail — `nil` s'il n'existe pas.
    let readStateFile: @Sendable () -> Data?
    /// Notifié à chaque événement du flux, pour la progression affichée.
    let onEvent: (@Sendable (AgentStreamEvent) -> Void)?

    init(
        launcher: AgentProcessLauncher,
        readStateFile: @escaping @Sendable () -> Data?,
        onEvent: (@Sendable (AgentStreamEvent) -> Void)? = nil
    ) {
        self.launcher = launcher
        self.readStateFile = readStateFile
        self.onEvent = onEvent
    }

    func run(
        prompt: String,
        workspace: URL,
        resuming sessionID: String?,
        configuration: AgentLaunchConfiguration
    ) async -> AgentTurnResult {

        let spec = AgentCommandBuilder.build(
            prompt: prompt, workspace: workspace,
            resuming: sessionID, configuration: configuration
        )

        let collector = StreamCollector(onEvent: onEvent)

        do {
            let process = try await launcher.run(spec) { collector.consume($0) }
            let seen = collector.snapshot()

            if process.exitCode != 0 {
                return seen.result(.failed(.exited(code: process.exitCode, message: process.standardError)))
            }
            guard let finish = seen.finish else {
                return seen.result(.failed(.noResult))
            }
            if finish.isError {
                return seen.result(.failed(.reportedError(finish.text ?? "")))
            }
            return seen.result(readOutcome(fallbackText: finish.text))

        } catch {
            return collector.snapshot().result(.failed(.launchFailed(String(describing: error))))
        }
    }

    // MARK: - Détail

    private func readOutcome(fallbackText: String?) -> AgentTurnOutcome {
        guard let data = readStateFile(),
              let report = try? AgentStateContract.read(data) else {
            return .needsReview(text: fallbackText)
        }

        switch report.state {
        case .question:
            // Le contrat garantit une question non vide sur cet état.
            return .awaitingAnswer(question: report.question ?? "")
        case .deliverable:
            return .delivered(report)
        case .blocked:
            return .blocked(reason: report.summary)
        }
    }
}

// MARK: - Accumulation du flux

/// Ce que le flux a appris pendant le tour. Isolé dans une classe parce que la
/// fermeture passée au lanceur est `@Sendable` et doit écrire quelque part.
private final class StreamCollector: @unchecked Sendable {

    struct Snapshot {
        var sessionID: String?
        var costUSD: Double = 0
        var lastProgress: String?
        var finish: (text: String?, isError: Bool)?

        func result(_ outcome: AgentTurnOutcome) -> AgentTurnResult {
            AgentTurnResult(
                outcome: outcome, sessionID: sessionID,
                costUSD: costUSD, lastProgress: lastProgress
            )
        }
    }

    private let lock = NSLock()
    private var state = Snapshot()
    private let onEvent: (@Sendable (AgentStreamEvent) -> Void)?

    init(onEvent: (@Sendable (AgentStreamEvent) -> Void)?) { self.onEvent = onEvent }

    func consume(_ line: String) {
        guard let event = AgentStreamDecoder.decode(line: line) else { return }
        onEvent?(event)

        lock.lock()
        defer { lock.unlock() }
        switch event {
        case .sessionStarted(let id, _):
            state.sessionID = id
        case .progress(let text):
            state.lastProgress = text
        case .toolStarted(let name):
            state.lastProgress = name
        case .retry:
            break
        case .finished(let text, let cost, let isError):
            state.costUSD = cost
            state.finish = (text, isError)
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}
