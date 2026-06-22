import Foundation
import SwiftData

struct MatchSuggestion {
    let kind: MeetingKind
    let project: Project?
    let collaborator: Collaborator?
    let confidence: Double  // 0..1

    /// Auto-applies when confidence meets the user-configured threshold.
    func autoApply(threshold: Double) -> Bool { confidence >= threshold }

    static func global(confidence: Double = 0.3) -> MatchSuggestion {
        .init(kind: .global, project: nil, collaborator: nil, confidence: confidence)
    }
}

enum ProjectMatchService {

    // MARK: - Public API

    /// Devine le type de réunion pour un événement calendrier en appliquant
    /// quatre règles ordonnées par priorité décroissante : manager (email
    /// exact), one-to-one (2 participants), projet (fuzzy match du titre,
    /// seuil 0.7), puis fallback `.global`. La première règle satisfaite gagne.
    @MainActor
    static func suggestKind(for event: CalendarMeetingEvent,
                            context: ModelContext,
                            settings: AppSettings) -> MatchSuggestion {

        let userEmail = settings.userEmail.lowercased()
        let attendees = event.attendees

        // 1. Manager — exact email match (empty managerEmail = disabled)
        let mgrEmail = settings.managerEmail.lowercased()
        if !mgrEmail.isEmpty,
           attendees.contains(where: { ($0.email ?? "").lowercased() == mgrEmail }) {
            let collab = findCollaborator(email: mgrEmail, in: context)
            return MatchSuggestion(kind: .manager,
                                   project: nil,
                                   collaborator: collab,
                                   confidence: 1.0)
        }

        // 2. One-to-One — exactly 2 attendees after filtering self
        let others = attendees.filter { ($0.email ?? "").lowercased() != userEmail }
        if attendees.count >= 2, others.count == 1 {
            let otherEmail = (others[0].email ?? "").lowercased()
            if !otherEmail.isEmpty, let collab = findCollaborator(email: otherEmail, in: context) {
                return MatchSuggestion(kind: .oneToOne,
                                       project: nil,
                                       collaborator: collab,
                                       confidence: 1.0)
            }
            return MatchSuggestion(kind: .oneToOne,
                                   project: nil,
                                   collaborator: nil,
                                   confidence: 0.6)
        }

        // 3. Project — fuzzy match title vs Project.name
        if let (proj, score) = bestProjectMatch(title: event.title, in: context), score >= 0.7 {
            return MatchSuggestion(kind: .project,
                                   project: proj,
                                   collaborator: nil,
                                   confidence: score)
        }

        // 4. Fallback
        return .global()
    }

    // MARK: - Fuzzy matching (internal, exposed for tests)

    static func normalizedTokens(_ s: String) -> [String] {
        let folded = s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let allowed = CharacterSet.alphanumerics
        var current = ""
        var tokens: [String] = []
        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Internals

    @MainActor
    private static func findCollaborator(email: String, in context: ModelContext) -> Collaborator? {
        let needle = email.lowercased()
        guard !needle.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Collaborator>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.email.lowercased() == needle }
    }

    /// Retourne le projet dont le nom ressemble le plus au `title`, avec son
    /// score (0..1), ou `nil` si aucun projet n'a de tokens exploitables. Le
    /// score combine le recouvrement de tokens et la similarité Jaro-Winkler
    /// (on garde le max des deux).
    @MainActor
    static func bestProjectMatch(title: String, in context: ModelContext) -> (Project, Double)? {
        let descriptor = FetchDescriptor<Project>()
        let projects = (try? context.fetch(descriptor)) ?? []
        guard !projects.isEmpty else { return nil }

        let titleTokens = normalizedTokens(title)
        let titleSet = Set(titleTokens)
        guard !titleSet.isEmpty else { return nil }

        var best: (Project, Double)?
        for proj in projects {
            let projTokens = normalizedTokens(proj.name)
            let projSet = Set(projTokens)
            guard !projSet.isEmpty else { continue }

            let overlap = Double(titleSet.intersection(projSet).count)
                        / Double(min(titleSet.count, projSet.count))

            let jw = jaroWinkler(titleTokens.joined(separator: " "),
                                  projTokens.joined(separator: " "))

            let score = max(overlap, jw)
            if score > (best?.1 ?? -1) {
                best = (proj, score)
            }
        }
        return best
    }

    /// Similarité Jaro-Winkler entre deux chaînes, dans `0..1` (1 = identiques,
    /// 0 = aucune correspondance). Étend le score de Jaro en bonifiant les
    /// préfixes communs (jusqu'à 4 caractères), ce qui favorise les chaînes
    /// partageant un début identique.
    static func jaroWinkler(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let aChars = Array(a)
        let bChars = Array(b)
        let matchDistance = max(aChars.count, bChars.count) / 2 - 1
        guard matchDistance >= 0 else { return 0.0 }

        var aMatches = [Bool](repeating: false, count: aChars.count)
        var bMatches = [Bool](repeating: false, count: bChars.count)
        var matches = 0
        for i in aChars.indices {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, bChars.count)
            guard start < end else { continue }
            for j in start..<end where !bMatches[j] && aChars[i] == bChars[j] {
                aMatches[i] = true
                bMatches[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0.0 }

        var transpositions = 0
        var k = 0
        for i in aChars.indices where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if aChars[i] != bChars[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        let jaro = (m / Double(aChars.count)
                  + m / Double(bChars.count)
                  + (m - Double(transpositions) / 2.0) / m) / 3.0

        var prefix = 0
        for i in 0..<min(4, aChars.count, bChars.count) {
            if aChars[i] == bChars[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }
}
