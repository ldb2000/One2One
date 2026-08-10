import Testing
import Foundation
@testable import OneToOne

/// Couvre `AgentStreamDecoder` — la lecture ligne à ligne de la sortie
/// `--output-format stream-json` du CLI `claude`.
///
/// Règle de fond : **aucune ligne ne doit être fatale**. Une ligne tronquée par
/// un tampon, un type d'événement ajouté par une version ultérieure du CLI, du
/// bruit sur stdout — tout cela est ignoré, jamais remonté en erreur.
struct AgentStreamDecoderTests {

    // MARK: - Ouverture de session

    @Test func readsTheSessionIdFromTheInitEvent() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"system","subtype":"init","session_id":"abc-123","model":"claude-opus-5","tools":["Read"]}
        """)

        #expect(event == .sessionStarted(id: "abc-123", model: "claude-opus-5"))
    }

    @Test func readsAnInitEventWithoutAModel() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"system","subtype":"init","session_id":"abc-123"}
        """)

        #expect(event == .sessionStarted(id: "abc-123", model: nil))
    }

    @Test func ignoresAnInitEventWithoutASessionId() {
        // Sans identifiant, on ne pourrait pas reprendre la session : autant
        // traiter la ligne comme du bruit plutôt que d'inventer un identifiant.
        #expect(AgentStreamDecoder.decode(line: """
        {"type":"system","subtype":"init","model":"claude-opus-5"}
        """) == nil)
    }

    // MARK: - Progression

    @Test func turnsAssistantTextIntoProgress() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Je lis les trois CR."}]}}
        """)

        #expect(event == .progress("Je lis les trois CR."))
    }

    @Test func joinsSeveralTextBlocksOfOneMessage() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"assistant","message":{"content":[
          {"type":"text","text":"Premier point."},
          {"type":"text","text":"Second point."}]}}
        """)

        #expect(event == .progress("Premier point. Second point."))
    }

    @Test func reportsTheToolWhenTheMessageCarriesNoText() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"assistant","message":{"content":[
          {"type":"tool_use","name":"Read","input":{"file_path":"BRIEF.md"}}]}}
        """)

        #expect(event == .toolStarted(name: "Read"))
    }

    @Test func prefersTheTextOverTheToolWhenBothArePresent() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"assistant","message":{"content":[
          {"type":"text","text":"Je rédige la note."},
          {"type":"tool_use","name":"Write","input":{}}]}}
        """)

        #expect(event == .progress("Je rédige la note."))
    }

    @Test func ignoresAnAssistantMessageWithEmptyContent() {
        #expect(AgentStreamDecoder.decode(line: """
        {"type":"assistant","message":{"content":[]}}
        """) == nil)
    }

    // MARK: - Nouvelle tentative de l'API

    @Test func readsAnApiRetry() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"system","subtype":"api_retry","attempt":2,"max_retries":5,
         "retry_delay_ms":1000,"error_status":529,"error":"overloaded"}
        """)

        #expect(event == .retry(attempt: 2, maxAttempts: 5, reason: "overloaded"))
    }

    // MARK: - Fin de tour

    @Test func readsASuccessfulResult() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"result","subtype":"success","is_error":false,
         "result":"La note est prête.","total_cost_usd":0.1234,"session_id":"abc-123"}
        """)

        #expect(event == .finished(text: "La note est prête.", costUSD: 0.1234, isError: false))
    }

    @Test func readsAFailedResult() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"result","subtype":"error_during_execution","is_error":true,
         "result":"Credit balance is too low","total_cost_usd":0}
        """)

        #expect(event == .finished(text: "Credit balance is too low", costUSD: 0, isError: true))
    }

    @Test func treatsAMissingCostAsZero() {
        let event = AgentStreamDecoder.decode(line: """
        {"type":"result","subtype":"success","is_error":false,"result":"fini"}
        """)

        #expect(event == .finished(text: "fini", costUSD: 0, isError: false))
    }

    // MARK: - Robustesse — rien de tout ceci ne doit être fatal

    @Test func ignoresAnEmptyLine() {
        #expect(AgentStreamDecoder.decode(line: "") == nil)
        #expect(AgentStreamDecoder.decode(line: "   \n") == nil)
    }

    @Test func ignoresALineThatIsNotJSON() {
        #expect(AgentStreamDecoder.decode(line: "Warning: 1 MCP server skipped") == nil)
    }

    @Test func ignoresATruncatedLine() {
        #expect(AgentStreamDecoder.decode(line: "{\"type\":\"assistant\",\"mess") == nil)
    }

    @Test func ignoresAnEventTypeItDoesNotKnow() {
        #expect(AgentStreamDecoder.decode(line: """
        {"type":"system","subtype":"plugin_install","status":"started"}
        """) == nil)
        #expect(AgentStreamDecoder.decode(line: """
        {"type":"stream_event","event":{"delta":{"type":"text_delta","text":"a"}}}
        """) == nil)
    }
}
