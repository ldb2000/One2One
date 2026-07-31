import Testing
import SwiftData
import Foundation
@testable import OneToOne

private struct StubTagAIClient: AIClientProtocol {
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

@Suite("TagColorPalette")
struct TagColorPaletteTests {

    @Test("Même nom → même couleur (déterministe)")
    func deterministic() {
        #expect(TagColorPalette.hex(for: "Recrutement") == TagColorPalette.hex(for: "Recrutement"))
    }

    @Test("Casse et accents ne changent pas la couleur")
    func caseAndDiacriticsStable() {
        #expect(TagColorPalette.hex(for: "Sécurité") == TagColorPalette.hex(for: "securite"))
        #expect(TagColorPalette.hex(for: "Budget") == TagColorPalette.hex(for: "  BUDGET  "))
    }

    @Test("L'index reste dans les bornes de la palette")
    func indexInBounds() {
        for name in ["", "a", "Recrutement", "Très long thème avec accents éàü", "🎯"] {
            let i = TagColorPalette.index(for: name)
            #expect(i >= 0 && i < TagColorPalette.hexes.count)
        }
    }

    @Test("Toutes les teintes sont des hex valides")
    func validHexes() {
        for hex in TagColorPalette.hexes {
            #expect(hex.count == 7 && hex.hasPrefix("#"))
        }
    }
}

@Suite("MeetingTagSuggester")
struct MeetingTagSuggesterTests {

    @Test("Réponse en virgules → liste de thèmes")
    func parsesCommaList() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "Point sur le recrutement et le budget.",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("Recrutement, Budget, Roadmap")
        )
        #expect(result == ["Recrutement", "Budget", "Roadmap"])
    }

    @Test("Réponse en puces multi-lignes → liste de thèmes")
    func parsesBulletList() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("- Recrutement\n• Budget\n1. Roadmap\n2) Sécurité")
        )
        #expect(result == ["Recrutement", "Budget", "Roadmap", "Sécurité"])
    }

    @Test("Réutilise la graphie canonique d'un thème existant (casse/accents)")
    func matchesExistingTags() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: ["Sécurité", "Budget"],
            settings: AppSettings(),
            client: StubTagAIClient("securite, BUDGET, Recrutement")
        )
        #expect(result == ["Sécurité", "Budget", "Recrutement"])
    }

    @Test("Dédoublonne les libellés équivalents")
    func dedupes() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("Budget, budget, Budgét")
        )
        #expect(result == ["Budget"])
    }

    @Test("Plafonne à 5 thèmes")
    func capsAtFive() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("a, b, c, d, e, f, g")
        )
        #expect(result.count == MeetingTagSuggester.maxSuggestions)
    }

    @Test("Réponse vide → []")
    func emptyResponse() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("   \n  ")
        )
        #expect(result.isEmpty)
    }

    @Test("Refus explicite du modèle → []")
    func refusal() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("Aucun")
        )
        #expect(result.isEmpty)
    }

    @Test("Phrase bavarde (hors format) écartée")
    func ignoresLongProse() async {
        let prose = "Je ne peux pas déterminer de thème pertinent à partir de ce compte-rendu très court"
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient(prose)
        )
        #expect(result.isEmpty)
    }

    @Test("Source vide → [] sans appel IA")
    func emptySourceSkips() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "   ",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("Budget")
        )
        #expect(result.isEmpty)
    }

    @Test("Erreur IA → []")
    func errorReturnsEmpty() async {
        let result = await MeetingTagSuggester.suggest(
            summary: "…",
            existingTags: [],
            settings: AppSettings(),
            client: StubTagAIClient("", throwError: true)
        )
        #expect(result.isEmpty)
    }

    @Test("sourceText : résumé prioritaire, sinon transcription, tronqué")
    func sourceTextSelection() {
        #expect(MeetingTagSuggester.sourceText(summary: "Résumé", transcript: "Transcript") == "Résumé")
        #expect(MeetingTagSuggester.sourceText(summary: "  ", transcript: "Transcript") == "Transcript")
        let long = String(repeating: "x", count: 9000)
        #expect(MeetingTagSuggester.sourceText(summary: "", transcript: long).count
                == MeetingTagSuggester.maxSourceCharacters)
    }

    @Test("Le prompt embarque les thèmes existants")
    func promptIncludesExisting() {
        let prompt = MeetingTagSuggester.buildPrompt(source: "abc", existingTags: ["Budget", "RH"])
        #expect(prompt.contains("Budget, RH"))
        #expect(prompt.contains("abc"))
    }
}

@Suite("MeetingTag — modèle")
struct MeetingTagModelTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Meeting.self, MeetingTag.self, Project.self, Collaborator.self,
                             ActionTask.self, ActionComment.self, MeetingAttachment.self,
                             TranscriptChunk.self, SlideCapture.self, ProjectAlert.self,
                             TranscriptSegment.self, ReportRevision.self, ReportTemplate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("findOrCreate ne crée pas de doublon (casse/accents ignorés)")
    func findOrCreateNoDuplicate() throws {
        let context = ModelContext(try makeContainer())

        let a = MeetingTag.findOrCreate(name: "Sécurité", in: context)
        try context.save()
        let b = MeetingTag.findOrCreate(name: "securite", in: context)
        let c = MeetingTag.findOrCreate(name: "  SÉCURITÉ ", in: context)
        try context.save()

        #expect(a?.persistentModelID == b?.persistentModelID)
        #expect(a?.persistentModelID == c?.persistentModelID)
        #expect(try context.fetch(FetchDescriptor<MeetingTag>()).count == 1)
        #expect(a?.name == "Sécurité")   // graphie de création conservée
    }

    @Test("findOrCreate refuse un nom vide")
    func findOrCreateRejectsEmpty() throws {
        let context = ModelContext(try makeContainer())
        #expect(MeetingTag.findOrCreate(name: "   ", in: context) == nil)
        #expect(try context.fetch(FetchDescriptor<MeetingTag>()).isEmpty)
    }

    @Test("Nouveau thème : couleur déterministe depuis la palette")
    func autoColor() throws {
        let context = ModelContext(try makeContainer())
        let tag = MeetingTag.findOrCreate(name: "Budget", in: context)
        #expect(tag?.colorHex == TagColorPalette.hex(for: "Budget"))
    }

    @Test("Lier / délier un thème à une réunion (relation inverse)")
    func linkAndUnlink() throws {
        let context = ModelContext(try makeContainer())
        let meeting = Meeting(title: "Comité", date: Date())
        context.insert(meeting)
        let tag = MeetingTag.findOrCreate(name: "Budget", in: context)!
        meeting.tags.append(tag)
        try context.save()

        #expect(tag.meetings.count == 1)

        meeting.tags.removeAll { $0.persistentModelID == tag.persistentModelID }
        try context.save()
        #expect(tag.meetings.isEmpty)
    }

    @Test("Fusion : réunions réaffectées, thème source supprimé")
    func mergeReassignsMeetings() throws {
        let context = ModelContext(try makeContainer())
        let source = MeetingTag.findOrCreate(name: "Recrutement", in: context)!
        let target = MeetingTag.findOrCreate(name: "RH", in: context)!

        let m1 = Meeting(title: "M1", date: Date())
        let m2 = Meeting(title: "M2", date: Date())
        context.insert(m1)
        context.insert(m2)
        m1.tags = [source]
        m2.tags = [source, target]   // déjà taggée cible → pas de doublon après fusion
        try context.save()

        MeetingTag.merge(source: source, into: target, in: context)
        try context.save()

        let tags = try context.fetch(FetchDescriptor<MeetingTag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "RH")
        #expect(m1.tags.map(\.name) == ["RH"])
        #expect(m2.tags.map(\.name) == ["RH"])
        #expect(target.meetings.count == 2)
    }

    @Test("Fusion d'un thème sur lui-même = no-op")
    func mergeIntoSelfIsNoop() throws {
        let context = ModelContext(try makeContainer())
        let tag = MeetingTag.findOrCreate(name: "Budget", in: context)!
        try context.save()

        MeetingTag.merge(source: tag, into: tag, in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<MeetingTag>()).count == 1)
    }

    @Test("Supprimer un thème retire l'étiquette sans supprimer la réunion")
    func deleteTagKeepsMeeting() throws {
        let context = ModelContext(try makeContainer())
        let meeting = Meeting(title: "Comité", date: Date())
        context.insert(meeting)
        let tag = MeetingTag.findOrCreate(name: "Budget", in: context)!
        meeting.tags = [tag]
        try context.save()

        context.delete(tag)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Meeting>()).count == 1)
        #expect(meeting.tags.isEmpty)
    }
}
