import Testing
import Foundation
@testable import OneToOne

private struct StubAIClient: AIClientProtocol {
    let response: String
    let throwError: Bool
    init(_ response: String, throwError: Bool = false) {
        self.response = response
        self.throwError = throwError
    }
    func send(prompt: String, settings: AppSettings) async throws -> String {
        if throwError {
            throw NSError(domain: "stub", code: -1, userInfo: [NSLocalizedDescriptionKey: "stub error"])
        }
        return response
    }
}

@Suite("ManagerCategoryClassifier")
struct ManagerCategoryClassifierTests {

    @Test("Exact match (case-insensitive) against settings categories")
    func exactMatch() async throws {
        let s = AppSettings()  // default 8 categories
        let client = StubAIClient("Risque")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "Risque")
    }

    @Test("Case-insensitive match")
    func caseInsensitive() async throws {
        let s = AppSettings()
        let client = StubAIClient("rh")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "RH")
    }

    @Test("Strips punctuation and quotes from response")
    func stripsPunctuation() async throws {
        let s = AppSettings()
        let client = StubAIClient("\"Décision\".")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == "Décision")
    }

    @Test("Hors-liste returns nil")
    func unknownCategory() async throws {
        let s = AppSettings()
        let client = StubAIClient("Banana")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }

    @Test("Network/IA error returns nil")
    func errorReturnsNil() async throws {
        let s = AppSettings()
        let client = StubAIClient("", throwError: true)
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }

    @Test("Empty categories list returns nil even if response valid")
    func emptyCategories() async throws {
        let s = AppSettings()
        s.managerCategories = []
        let client = StubAIClient("Risque")
        let result = await ManagerCategoryClassifier.classify(
            snippet: "...",
            projectName: nil,
            settings: s,
            client: client
        )
        #expect(result == nil)
    }
}
