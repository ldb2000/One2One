import Foundation
import os

private let bm25Log = Logger(subsystem: "com.onetoone.app", category: "rag-bm25")

/// Index lexical BM25 in-memory sur un corpus de `TranscriptChunk`.
/// Reconstruit à chaque requête (pas de persistance) : acceptable tant que
/// le corpus reste modéré (< 50k chunks, cf. `RAGQuery.filtered`).
struct BM25Index {
    private let k1: Double
    private let b: Double
    private let avgDocLength: Double
    private let documentCount: Int
    private let docLengths: [UUID: Int]
    private let docTermFrequencies: [UUID: [String: Int]]
    private let documentFrequency: [String: Int]

    init(chunks: [TranscriptChunk], k1: Double = 1.5, b: Double = 0.75) {
        self.k1 = k1
        self.b = b

        var lengths: [UUID: Int] = [:]
        var termFrequencies: [UUID: [String: Int]] = [:]
        var docFrequency: [String: Int] = [:]

        for chunk in chunks {
            let tokens = Self.tokenize(chunk.text)
            lengths[chunk.chunkId] = tokens.count

            var tf: [String: Int] = [:]
            for token in tokens {
                tf[token, default: 0] += 1
            }
            termFrequencies[chunk.chunkId] = tf

            for term in Set(tf.keys) {
                docFrequency[term, default: 0] += 1
            }
        }

        self.docLengths = lengths
        self.docTermFrequencies = termFrequencies
        self.documentFrequency = docFrequency
        self.documentCount = chunks.count
        let totalLength = lengths.values.reduce(0, +)
        self.avgDocLength = documentCount > 0 ? Double(totalLength) / Double(documentCount) : 0
    }

    /// Score BM25 standard de chaque chunk du corpus pour `query`. Un chunk
    /// sans terme en commun avec la requête est omis (score nul non retourné).
    func score(query: String) -> [UUID: Double] {
        let start = DispatchTime.now()
        defer {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            if elapsedMs > 100 {
                bm25Log.warning("BM25.score a pris \(elapsedMs, privacy: .public) ms sur \(self.documentCount, privacy: .public) chunks")
            }
        }

        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty, documentCount > 0, avgDocLength > 0 else { return [:] }

        var scores: [UUID: Double] = [:]
        for (chunkId, tf) in docTermFrequencies {
            let docLength = Double(docLengths[chunkId] ?? 0)
            var score = 0.0
            for term in queryTerms {
                guard let freq = tf[term], freq > 0 else { continue }
                let df = Double(documentFrequency[term] ?? 0)
                let idf = log((Double(documentCount) - df + 0.5) / (df + 0.5) + 1)
                let numerator = Double(freq) * (k1 + 1)
                let denominator = Double(freq) + k1 * (1 - b + b * (docLength / avgDocLength))
                score += idf * (numerator / denominator)
            }
            if score > 0 {
                scores[chunkId] = score
            }
        }
        return scores
    }

    /// Tokenise `text` : minuscules, split sur les séparateurs non
    /// alphanumériques (Unicode, préserve les accents), retire les stop-words
    /// français/anglais minimaux.
    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let tokens = lowered.components(separatedBy: nonWordCharacters).filter { !$0.isEmpty }
        return tokens.filter { !stopWords.contains($0) }
    }

    private static let nonWordCharacters = CharacterSet.alphanumerics.inverted

    private static let stopWords: Set<String> = [
        // Français
        "le", "la", "les", "un", "une", "des", "de", "du", "au", "aux", "et", "ou",
        "est", "en", "à", "a", "ce", "cet", "cette", "ces", "que", "qui", "quoi",
        "dans", "sur", "pour", "par", "avec", "sans", "se", "sa", "son", "ses",
        "ne", "pas", "plus", "mais", "comme", "tout", "tous", "toute", "toutes",
        "il", "elle", "ils", "elles", "je", "tu", "nous", "vous", "on", "y",
        "d", "l", "qu", "c", "s", "n", "j", "été", "être", "avoir", "fait",
        // Anglais
        "the", "a", "an", "of", "to", "is", "are", "and", "or", "in", "on",
        "for", "with", "by", "this", "that", "these", "those", "it", "its",
        "be", "was", "were", "been", "as", "at", "from", "not", "but", "so",
        "if", "then", "than", "which", "who", "whom", "he", "she", "they",
        "we", "you", "i", "do", "does", "did", "has", "have", "had", "will",
        "would", "can", "could", "should", "may", "might", "must", "shall"
    ]
}
