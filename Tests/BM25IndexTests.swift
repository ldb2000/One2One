import Foundation
import Testing
@testable import OneToOne

private func makeChunk(_ text: String, order: Int = 0) -> TranscriptChunk {
    TranscriptChunk(text: text, orderIndex: order, sourceType: "meeting")
}

@Suite("BM25Index — tokenisation, IDF, score (B3)")
struct BM25IndexTests {

    @Test("le chunk contenant exactement les mots de la requête remonte en tête")
    func exactMatchRanksFirst() {
        let target = makeChunk("Nous avons discuté du modèle Qwen embed pour la recherche.")
        let chunks = [
            makeChunk("Réunion de suivi budget trimestriel."),
            target,
            makeChunk("Compte rendu du comité de pilotage."),
            makeChunk("Notes diverses sur l'organisation de l'équipe."),
            makeChunk("Retour sur les congés et la logistique du bureau.")
        ]
        let index = BM25Index(chunks: chunks)
        let scores = index.score(query: "Qwen embed")

        let ranked = scores.sorted { $0.value > $1.value }
        #expect(ranked.first?.key == target.chunkId)
    }

    @Test("les stop-words sont filtrés : \"le chat\" ne score que sur \"chat\"")
    func stopWordsAreFiltered() {
        let withChat = makeChunk("Le chat noir traverse la rue.")
        let withoutChat = makeChunk("Un chien brun traverse la rue aussi.")
        let chunks = [withChat, withoutChat]
        let index = BM25Index(chunks: chunks)

        let scoresFull = index.score(query: "le chat")
        let scoresBare = index.score(query: "chat")

        #expect(scoresFull[withChat.chunkId] == scoresBare[withChat.chunkId])
        #expect(scoresFull[withoutChat.chunkId] == nil)
    }

    @Test("l'IDF favorise un mot rare : score plus élevé qu'un mot présent dans tous les chunks")
    func idfFavorsRareTerms() throws {
        let rareChunk = makeChunk("Le projet ProjectXylophone est en cours de livraison.")
        let commonA = makeChunk("Le projet avance bien cette semaine.")
        let commonB = makeChunk("Le projet a pris du retard hier.")
        let commonC = makeChunk("Le projet sera revu la semaine prochaine.")
        let chunks = [rareChunk, commonA, commonB, commonC]
        let index = BM25Index(chunks: chunks)

        let rareScores = index.score(query: "projectxylophone")
        let commonScores = index.score(query: "projet")

        let rareScore = try #require(rareScores[rareChunk.chunkId])
        let commonScoreForSameChunk = try #require(commonScores[rareChunk.chunkId])
        #expect(rareScore > commonScoreForSameChunk)
    }

    @Test("déterminisme : même corpus + même requête → même résultat")
    func deterministicScoring() {
        let chunks = [
            makeChunk("Le socle technique a tenu la charge du pic de trafic."),
            makeChunk("Discussion sur le budget Q3 et les priorités."),
            makeChunk("Le modèle Qwen a été évalué pour la génération de texte."),
            makeChunk("Retour sur l'incident de production de la semaine."),
            makeChunk("Planification de la prochaine itération du produit.")
        ]
        let index = BM25Index(chunks: chunks)

        let first = index.score(query: "modèle Qwen production")
        let second = index.score(query: "modèle Qwen production")

        #expect(first == second)
    }

    @Test("tokenize : minuscule, retire la ponctuation, filtre les stop-words")
    func tokenizeBasics() {
        let tokens = BM25Index.tokenize("Le Chat, et LE CHIEN ! sont amis.")
        #expect(tokens == ["chat", "chien", "sont", "amis"])
    }

    @Test("une requête sans terme signifiant (uniquement des stop-words) ne score aucun chunk")
    func onlyStopWordsYieldsEmptyScores() {
        let chunks = [makeChunk("Le chat noir."), makeChunk("Un chien brun.")]
        let index = BM25Index(chunks: chunks)
        #expect(index.score(query: "le la de").isEmpty)
    }
}
