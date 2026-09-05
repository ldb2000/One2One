import Testing
import Foundation
@testable import OneToOne

@Suite("MailLLMClassifier — parsing et classification")
@MainActor
struct MailLLMClassifierTests {
    @Test("Un endpoint distant ne reçoit pas de mail sans activation explicite")
    func remoteMailRequiresOptIn() async throws {
        let settings = AppSettings(provider: .openRouter)
        var called = false
        let denied = await MailLLMClassifier.classify(
            subject: "Privé", sender: "a@b.c", preview: "Contenu privé", candidates: [], settings: settings,
            generate: { _ in called = true; return #"{"projectCode":null,"confidence":0}"# })
        #expect(!called)
        #expect(denied == .unavailable)
        settings.allowRemoteMailClassification = true
        _ = await MailLLMClassifier.classify(
            subject: "Privé", sender: "a@b.c", preview: "Contenu privé", candidates: [], settings: settings,
            generate: { _ in called = true; return #"{"projectCode":null,"confidence":0}"# })
        #expect(called)
    }

    @Test("Un serveur LM Studio sur le réseau suit aussi la règle des mails distants")
    func networkLMStudioIsRemote() async {
        let settings = AppSettings(apiEndpoint: "http://192.168.1.20:1234/v1", modelName: "local-model", provider: .lmStudio)
        var called = false
        _ = await MailLLMClassifier.classify(
            subject: "Privé", sender: "a@b.c", preview: "Contenu privé", candidates: [], settings: settings,
            generate: { _ in called = true; return "{}" })
        #expect(!called)
    }

    private let codes: Set<String> = ["REFSI", "DATA24"]
    private let candidates = [
        MailLLMClassifier.Candidate(code: "REFSI", name: "Refonte SI Courtage",
                                    collaborators: ["alice@april.com"]),
        MailLLMClassifier.Candidate(code: "DATA24", name: "Plateforme Data",
                                    collaborators: ["bob@april.com"]),
    ]

    @Test("JSON strict")
    func jsonStrict() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "REFSI", "confidence": 0.8}"#,
                                               knownCodes: codes)
        #expect(v == MailProjectMatcher.Verdict(projectCode: "REFSI", confidence: 0.8))
    }

    @Test("Fences markdown et texte autour")
    func fencesMarkdown() {
        let raw = """
        Voici mon analyse :
        ```json
        {"projectCode": "DATA24", "confidence": 0.55}
        ```
        """
        let v = MailLLMClassifier.parseVerdict(raw, knownCodes: codes)
        #expect(v == MailProjectMatcher.Verdict(projectCode: "DATA24", confidence: 0.55))
    }

    @Test("projectCode null → verdict sans projet")
    func codeNull() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": null, "confidence": 0.9}"#,
                                               knownCodes: codes)
        #expect(v?.projectCode == nil)
    }

    @Test("Code inconnu → traité comme aucun projet")
    func codeInconnu() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "HALLUCINATION", "confidence": 0.9}"#,
                                               knownCodes: codes)
        #expect(v?.projectCode == nil)
    }

    @Test("Confiance bornée à [0, 1]")
    func confianceBornee() {
        let v = MailLLMClassifier.parseVerdict(#"{"projectCode": "REFSI", "confidence": 7}"#,
                                               knownCodes: codes)
        #expect(v?.confidence == 1.0)
    }

    @Test("JSON invalide → nil")
    func jsonInvalide() {
        #expect(MailLLMClassifier.parseVerdict("désolé, je ne peux pas", knownCodes: codes) == nil)
    }

    @Test("Le prompt contient les candidats (code, nom, collaborateurs) et exige un JSON")
    func promptComplet() {
        let p = MailLLMClassifier.buildPrompt(subject: "Su", sender: "a@b.c",
                                              preview: "Pv", candidates: candidates)
        #expect(p.contains("REFSI"))
        #expect(p.contains("Plateforme Data"))
        #expect(p.contains("bob@april.com"))
        #expect(p.contains("projectCode"))
        #expect(p.contains("Su"))
    }

    @Test("classify passe par generate injecté et parse le résultat")
    func classifyAvecStub() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in #"{"projectCode": "REFSI", "confidence": 0.7}"# }
        )
        #expect(r == .verdict(MailProjectMatcher.Verdict(projectCode: "REFSI", confidence: 0.7)))
    }

    @Test("Réponse inexploitable → .unparseable (le mail sera ignoré)")
    func classifyInexploitable() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in "désolé, je ne peux pas répondre en JSON" }
        )
        #expect(r == .unparseable)
    }

    @Test("LLM indisponible → .unavailable (repli heuristique)")
    func classifyErreur() async {
        let settings = AppSettings()
        let r = await MailLLMClassifier.classify(
            subject: "Su", sender: "a@b.c", preview: "Pv",
            candidates: candidates, settings: settings,
            generate: { _ in throw NSError(domain: "stub", code: -1) }
        )
        #expect(r == .unavailable)
    }
}
