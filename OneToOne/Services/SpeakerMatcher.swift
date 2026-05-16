import Foundation
import SwiftData

/// Staged cosine matching of cluster embeddings against Collaborator
/// voiceprints. See spec §5.4 and §5.5.
enum SpeakerMatcher {

    static let autoThreshold: Double = 0.75
    static let suggestThreshold: Double = 0.60
    static let ambiguousDelta: Double = 0.02

    struct Assignment {
        let collaborator: Collaborator?
        let confidence: Double
        let auto: Bool
        let candidates: [(Collaborator, Double)]
        let ambiguous: Bool
    }

    /// Returns one Assignment per clusterID. Missing clusterID = no candidate.
    @MainActor
    static func match(clusterEmbeddings: [Int: [Float]],
                       meeting: Meeting,
                       in context: ModelContext) -> [Int: Assignment] {
        let participants = Set(meeting.participants
            .filter { !$0.isArchived }
            .map { $0.persistentModelID })

        let descriptor = FetchDescriptor<Collaborator>(
            predicate: #Predicate<Collaborator> { !$0.isArchived }
        )
        let all = (try? context.fetch(descriptor)) ?? []
        let enrolled = all.filter { $0.voicePrint != nil && $0.voicePrintSamples > 0 }

        var out: [Int: Assignment] = [:]
        for (clusterID, embedding) in clusterEmbeddings {
            out[clusterID] = matchOne(embedding: embedding,
                                      enrolled: enrolled,
                                      participants: participants)
        }
        return out
    }

    private static func matchOne(embedding: [Float],
                                  enrolled: [Collaborator],
                                  participants: Set<PersistentIdentifier>) -> Assignment {
        // Pass 1: participants, threshold suggest (0.60).
        var pool1: [(Collaborator, Double)] = []
        for c in enrolled where participants.contains(c.persistentModelID) {
            guard let vp = c.voicePrint else { continue }
            let cos = cosine(embedding, decode(vp))
            if cos >= suggestThreshold {
                pool1.append((c, cos))
            }
        }
        pool1.sort { $0.1 > $1.1 }

        if !pool1.isEmpty {
            return assemble(candidates: pool1)
        }

        // Pass 2: non-participants, threshold auto (0.75 strict).
        var pool2: [(Collaborator, Double)] = []
        for c in enrolled where !participants.contains(c.persistentModelID) {
            guard let vp = c.voicePrint else { continue }
            let cos = cosine(embedding, decode(vp))
            if cos >= autoThreshold {
                pool2.append((c, cos))
            }
        }
        pool2.sort { $0.1 > $1.1 }

        if !pool2.isEmpty {
            return assemble(candidates: pool2)
        }

        return Assignment(collaborator: nil, confidence: 0, auto: false, candidates: [], ambiguous: false)
    }

    private static func assemble(candidates: [(Collaborator, Double)]) -> Assignment {
        let top = candidates[0]
        let ambiguous: Bool
        if candidates.count >= 2 {
            let second = candidates[1]
            ambiguous = top.1 >= autoThreshold
                && second.1 >= autoThreshold
                && (top.1 - second.1) < ambiguousDelta
        } else {
            ambiguous = false
        }
        let auto = top.1 >= autoThreshold && !ambiguous
        return Assignment(
            collaborator: top.0,
            confidence: top.1,
            auto: auto,
            candidates: Array(candidates.prefix(3)),
            ambiguous: ambiguous
        )
    }

    // MARK: - EMA voiceprint update

    /// Apply running-mean EMA update to a Collaborator's voiceprint with a
    /// newly-observed cluster embedding. Only called from manual labelling
    /// (never on auto-match). See spec §5.5.
    @MainActor
    static func applyEMAUpdate(to collaborator: Collaborator,
                                newEmbedding: [Float],
                                in context: ModelContext) {
        precondition(newEmbedding.count == 256, "embedding must be 256-dim")
        if collaborator.voicePrint == nil || collaborator.voicePrintSamples == 0 {
            collaborator.voicePrint = encode(newEmbedding)
            collaborator.voicePrintSamples = 1
        } else {
            let old = decode(collaborator.voicePrint!)
            let n = Double(collaborator.voicePrintSamples)
            var updated = [Float](repeating: 0, count: 256)
            for i in 0..<256 {
                updated[i] = Float((Double(old[i]) * n + Double(newEmbedding[i])) / (n + 1))
            }
            collaborator.voicePrint = encode(updated)
            collaborator.voicePrintSamples += 1
        }
        collaborator.voicePrintUpdatedAt = Date()
        try? context.save()
    }

    // MARK: - Cosine + codec

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        let n = min(a.count, b.count)
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        guard denom > 1e-9 else { return 0 }
        return Double(dot / denom)
    }

    static func encode(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
