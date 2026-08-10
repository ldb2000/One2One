import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentTurnRunner` — la machine à états d'un tour d'agent : lancer,
/// lire le flux, décider de la suite.
///
/// Aucun test n'appelle le vrai CLI : le lanceur est injecté et rejoue un flux
/// enregistré. Un test qui lancerait `claude` serait lent, coûteux, et vert ou
/// rouge selon l'état du réseau.
struct AgentTurnRunnerTests {

    // MARK: - Doublure de lanceur

    private final class Recorder: @unchecked Sendable {
        var spec: AgentCommandSpec?
        var events: [AgentStreamEvent] = []
    }

    private struct FakeLauncher: AgentProcessLauncher {
        var lines: [String] = []
        var exitCode: Int32 = 0
        var standardError: String = ""
        var throwsOnLaunch: Error?
        let recorder: Recorder

        func run(
            _ spec: AgentCommandSpec,
            onLine: @escaping @Sendable (String) -> Void
        ) async throws -> AgentProcessResult {
            recorder.spec = spec
            if let throwsOnLaunch { throw throwsOnLaunch }
            lines.forEach(onLine)
            return AgentProcessResult(exitCode: exitCode, standardError: standardError)
        }
    }

    // MARK: - Flux enregistrés

    private let initLine = #"{"type":"system","subtype":"init","session_id":"S-1","model":"claude-opus-5"}"#
    private let sayLine = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Je rédige."}]}}"#
    private func resultLine(cost: Double = 0.25, isError: Bool = false, text: String = "Terminé.") -> String {
        #"{"type":"result","subtype":"success","is_error":\#(isError),"result":"\#(text)","total_cost_usd":\#(cost)}"#
    }

    private func run(
        lines: [String],
        exitCode: Int32 = 0,
        standardError: String = "",
        throwsOnLaunch: Error? = nil,
        stateFile: String? = nil,
        resuming: String? = nil
    ) async -> (AgentTurnResult, Recorder) {
        let recorder = Recorder()
        let runner = AgentTurnRunner(
            launcher: FakeLauncher(
                lines: lines, exitCode: exitCode, standardError: standardError,
                throwsOnLaunch: throwsOnLaunch, recorder: recorder
            ),
            readStateFile: { stateFile.map { Data($0.utf8) } },
            onEvent: { event in recorder.events.append(event) }
        )

        let result = await runner.run(
            prompt: "Rédige la note.",
            workspace: URL(fileURLWithPath: "/tmp/RUN-1"),
            resuming: resuming,
            configuration: .standard(home: URL(fileURLWithPath: "/Users/moi"))
        )
        return (result, recorder)
    }

    // MARK: - Les trois issues nominales

    @Test func deliversWhenTheAgentSaysTheWorkIsReady() async {
        let (result, _) = await run(
            lines: [initLine, sayLine, resultLine()],
            stateFile: #"{"etat":"livrable","livrables":[{"fichier":"livrables/n.docx","type":"docx","titre":"Note"}]}"#
        )

        guard case .delivered(let report) = result.outcome else {
            Issue.record("issue inattendue : \(result.outcome)"); return
        }
        #expect(report.deliverables.first?.title == "Note")
        #expect(result.sessionID == "S-1")
        #expect(result.costUSD == 0.25)
    }

    @Test func waitsForAnAnswerWhenTheAgentAsksAQuestion() async {
        let (result, _) = await run(
            lines: [initLine, resultLine()],
            stateFile: #"{"etat":"question","question":"Quel montant ?"}"#
        )

        #expect(result.outcome == .awaitingAnswer(question: "Quel montant ?"))
    }

    @Test func reportsWhenTheAgentDeclaresItselfBlocked() async {
        let (result, _) = await run(
            lines: [initLine, resultLine()],
            stateFile: #"{"etat":"bloque","resume":"Les CR sont vides."}"#
        )

        #expect(result.outcome == .blocked(reason: "Les CR sont vides."))
    }

    // MARK: - On ne perd jamais le travail

    @Test func asksForAReviewWhenTheStateFileIsMissing() async {
        let (result, _) = await run(lines: [initLine, resultLine(text: "J'ai écrit la note.")], stateFile: nil)

        #expect(result.outcome == .needsReview(text: "J'ai écrit la note."))
    }

    @Test func asksForAReviewWhenTheStateFileIsBroken() async {
        let (result, _) = await run(
            lines: [initLine, resultLine(text: "J'ai écrit la note.")],
            stateFile: #"{"etat": "#
        )

        #expect(result.outcome == .needsReview(text: "J'ai écrit la note."))
    }

    @Test func asksForAReviewWhenTheStateFileCarriesAnUnknownState() async {
        let (result, _) = await run(
            lines: [initLine, resultLine(text: "fini")],
            stateFile: #"{"etat":"termine"}"#
        )

        #expect(result.outcome == .needsReview(text: "fini"))
    }

    // MARK: - Échecs

    @Test func failsWhenTheBinaryCannotBeLaunched() async {
        struct Missing: Error {}
        let (result, _) = await run(lines: [], throwsOnLaunch: Missing())

        guard case .failed(.launchFailed) = result.outcome else {
            Issue.record("issue inattendue : \(result.outcome)"); return
        }
    }

    @Test func failsOnANonZeroExitAndKeepsTheStandardError() async {
        let (result, _) = await run(
            lines: [initLine],
            exitCode: 1,
            standardError: "Invalid API key",
            stateFile: #"{"etat":"livrable"}"#
        )

        #expect(result.outcome == .failed(.exited(code: 1, message: "Invalid API key")))
    }

    @Test func failsWhenTheRunItselfReportsAnError() async {
        let (result, _) = await run(
            lines: [initLine, resultLine(isError: true, text: "Credit balance too low")]
        )

        #expect(result.outcome == .failed(.reportedError("Credit balance too low")))
    }

    @Test func failsWhenTheTurnEndsWithoutAResult() async {
        // Le CLI tué en cours de route sort en 0 sans jamais émettre `result`.
        let (result, _) = await run(lines: [initLine, sayLine])

        #expect(result.outcome == .failed(.noResult))
    }

    @Test func keepsTheSessionIdEvenWhenTheTurnFails() async {
        // Sans lui, la reprise par `--resume` serait perdue et tout le travail
        // du tour avec elle.
        let (result, _) = await run(lines: [initLine], exitCode: 1, standardError: "boom")

        #expect(result.sessionID == "S-1")
    }

    // MARK: - Câblage

    @Test func forwardsTheStreamEventsSoTheUiCanFollow() async {
        let (_, recorder) = await run(lines: [initLine, sayLine, resultLine()], stateFile: #"{"etat":"livrable"}"#)

        #expect(recorder.events.contains(.progress("Je rédige.")))
        #expect(recorder.events.contains(.sessionStarted(id: "S-1", model: "claude-opus-5")))
    }

    @Test func keepsTheLastProgressLineForTheJobLabel() async {
        let (result, _) = await run(lines: [initLine, sayLine, resultLine()], stateFile: #"{"etat":"livrable"}"#)

        #expect(result.lastProgress == "Je rédige.")
    }

    @Test func handsTheResumedSessionToTheLauncher() async {
        let (_, recorder) = await run(lines: [initLine, resultLine()], stateFile: #"{"etat":"livrable"}"#, resuming: "S-0")

        let args = try! #require(recorder.spec?.arguments)
        let index = try! #require(args.firstIndex(of: "--resume"))
        #expect(args[index + 1] == "S-0")
    }

    @Test func runsInsideTheWorkspaceItWasGiven() async {
        let (_, recorder) = await run(lines: [initLine, resultLine()], stateFile: #"{"etat":"livrable"}"#)

        #expect(recorder.spec?.workingDirectory == URL(fileURLWithPath: "/tmp/RUN-1"))
    }
}
