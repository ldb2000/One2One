import Foundation

/// Heuristiques de rattachement mail → projet (étage 1 du matching, sans LLM).
/// Trois signaux, le meilleur score gagne :
///   1. continuité de fil (threadTopic déjà rattaché) — confiance 0.95 ;
///   2. sujet ↔ nom/code projet (tokens + Jaro-Winkler, code cité = 0.9) ;
///   3. expéditeur ↔ emails des collaborateurs du projet (bonus +0.2, ou
///      match faible seul à 0.4).
/// Fonctions pures sur des entrées préparées — testables sans ModelContext.
@MainActor
enum MailProjectMatcher {

    struct ProjectEntry: Equatable {
        let code: String
        let name: String
        /// Emails des collaborateurs rattachés, déjà lowercased.
        let collaboratorEmails: [String]
    }

    struct Verdict: Equatable {
        let projectCode: String?
        let confidence: Double
        static let none = Verdict(projectCode: nil, confidence: 0)
    }

    static let threadContinuityConfidence = 0.95
    static let codeInSubjectConfidence = 0.9
    static let senderEmailBonus = 0.2
    static let senderEmailOnlyConfidence = 0.4

    /// Extrait l'adresse email d'un champ expéditeur Mail.app
    /// (« Nom <email> » ou email nu). Retourne nil si aucune adresse.
    static func extractEmail(fromSender sender: String) -> String? {
        if let lt = sender.firstIndex(of: "<"), let gt = sender.firstIndex(of: ">"), lt < gt {
            let inner = String(sender[sender.index(after: lt)..<gt])
                .trimmingCharacters(in: .whitespaces)
            return inner.contains("@") ? inner.lowercased() : nil
        }
        let trimmed = sender.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") ? trimmed.lowercased() : nil
    }

    /// Prépare les entrées de matching depuis les projets actifs.
    static func projectEntries(from projects: [Project]) -> [ProjectEntry] {
        projects.filter { !$0.isArchived }.map { p in
            var emails = p.collaboratorEntries.compactMap { entry in
                entry.collaborator.map { $0.email.lowercased() }
            }
            if let e = p.projectManager?.email.lowercased() { emails.append(e) }
            if let e = p.technicalArchitect?.email.lowercased() { emails.append(e) }
            return ProjectEntry(code: p.code, name: p.name,
                                collaboratorEmails: emails.filter { !$0.isEmpty })
        }
    }

    /// Verdict heuristique pour un mail. `threadProjectCodes` : threadTopic
    /// normalisé lowercased → code projet (fils déjà rattachés).
    static func match(
        subject: String,
        sender: String,
        projects: [ProjectEntry],
        threadProjectCodes: [String: String]
    ) -> Verdict {
        // 1. Continuité de fil.
        let topic = ProjectMailStore.normalizedThreadTopic(for: subject).lowercased()
        if !topic.isEmpty, let code = threadProjectCodes[topic] {
            return Verdict(projectCode: code, confidence: threadContinuityConfidence)
        }

        // 2 + 3. Sujet et expéditeur, meilleur projet gagnant.
        let senderEmail = extractEmail(fromSender: sender)
        let subjectTokens = ProjectMatchService.normalizedTokens(subject)
        let subjectSet = Set(subjectTokens)

        var best = Verdict.none
        for project in projects {
            var score = 0.0

            let nameTokens = ProjectMatchService.normalizedTokens(project.name)
            let nameSet = Set(nameTokens)
            if !subjectSet.isEmpty, !nameSet.isEmpty {
                let overlap = Double(subjectSet.intersection(nameSet).count)
                    / Double(min(subjectSet.count, nameSet.count))
                // ⚠️ jaroWinkler n'est jamais ≈0 entre deux phrases quelconques
                // (0.5–0.65 sur des sujets sans aucun rapport) : il n'est
                // compté que si au moins un token est commun — sinon 0.
                // (Le repo applique la même prudence : bestProjectMatch n'est
                // accepté qu'à ≥ 0.7 côté appelant.)
                if overlap > 0 {
                    let jw = ProjectMatchService.jaroWinkler(
                        subjectTokens.joined(separator: " "),
                        nameTokens.joined(separator: " "))
                    score = max(overlap, jw)
                }
            }

            // Code projet cité tel quel dans le sujet (ex. « [DATA24] … »).
            let codeTokens = Set(ProjectMatchService.normalizedTokens(project.code))
            if !codeTokens.isEmpty, codeTokens.isSubset(of: subjectSet) {
                score = max(score, codeInSubjectConfidence)
            }

            // Expéditeur membre du projet : bonus, ou match faible seul.
            if let email = senderEmail, project.collaboratorEmails.contains(email) {
                score = score > 0 ? min(1.0, score + senderEmailBonus)
                                  : senderEmailOnlyConfidence
            }

            if score > best.confidence {
                best = Verdict(projectCode: project.code, confidence: score)
            }
        }
        return best
    }
}
