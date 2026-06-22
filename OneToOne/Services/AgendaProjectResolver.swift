import Foundation
import SwiftData

/// Résultat de la résolution « titre d'événement → projet » :
/// - `.rule` : règle manuelle (projet ou « Ignoré ») — prioritaire ;
/// - `.suggested` : fuzzy match automatique (affiché distinctement dans l'UI) ;
/// - `.none` : aucun rattachement.
enum AgendaProjectAssignment {
    case rule(AgendaProjectRule)
    case suggested(Project, Double)
    case none

    /// Projet effectif (règle ou suggestion), nil si ignoré/non affecté.
    var project: Project? {
        switch self {
        case .rule(let rule): return rule.isIgnored ? nil : rule.project
        case .suggested(let project, _): return project
        case .none: return nil
        }
    }

    var isIgnored: Bool {
        if case .rule(let rule) = self { return rule.isIgnored }
        return false
    }
}

/// Résolution des projets pour les événements d'agenda et CRUD des règles
/// `AgendaProjectRule`. Précédence : règle manuelle exacte (titre normalisé)
/// > suggestion fuzzy (`ProjectMatchService.bestProjectMatch`, seuil 0.7) > rien.
enum AgendaProjectResolver {

    /// Seuil minimal du fuzzy match pour proposer une suggestion automatique
    /// (aligné sur la règle « projet » de `ProjectMatchService.suggestKind`).
    static let suggestionThreshold = 0.7

    /// Clé de matching d'un titre : tokens normalisés (minuscules, sans
    /// diacritiques ni ponctuation) joints par espace.
    static func normalizedKey(_ title: String) -> String {
        ProjectMatchService.normalizedTokens(title).joined(separator: " ")
    }

    // MARK: - Index de résolution

    /// Index préchargé (règles + projets) pour résoudre N titres sans refaire
    /// un fetch SwiftData par événement. À reconstruire quand les règles changent.
    struct Index {
        let rulesByKey: [String: AgendaProjectRule]
        let context: ModelContext

        @MainActor
        func resolve(title: String) -> AgendaProjectAssignment {
            let key = normalizedKey(title)
            if let rule = rulesByKey[key] {
                // Règle orpheline (projet supprimé, non ignorée) → non affecté.
                if !rule.isIgnored && rule.project == nil { return .none }
                return .rule(rule)
            }
            if let (project, score) = ProjectMatchService.bestProjectMatch(title: title, in: context),
               score >= suggestionThreshold {
                return .suggested(project, score)
            }
            return .none
        }
    }

    @MainActor
    static func makeIndex(context: ModelContext) -> Index {
        let rules = (try? context.fetch(FetchDescriptor<AgendaProjectRule>())) ?? []
        var byKey: [String: AgendaProjectRule] = [:]
        for rule in rules where !rule.normalizedTitleKey.isEmpty {
            byKey[rule.normalizedTitleKey] = rule
        }
        return Index(rulesByKey: byKey, context: context)
    }

    /// Règle exacte pour un titre, ou nil. Pour les résolutions ponctuelles
    /// (import d'un événement) ; préférer `makeIndex` pour les listes.
    @MainActor
    static func rule(for title: String, context: ModelContext) -> AgendaProjectRule? {
        let key = normalizedKey(title)
        guard !key.isEmpty else { return nil }
        let descriptor = FetchDescriptor<AgendaProjectRule>(
            predicate: #Predicate<AgendaProjectRule> { $0.normalizedTitleKey == key }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - CRUD des règles

    /// Crée ou écrase la règle pour ce titre. `project == nil && !ignored`
    /// équivaut à retirer la règle. Met aussi à jour les `Meeting` importées
    /// du même titre normalisé (kind `.project` ou sans projet uniquement —
    /// on ne touche pas aux 1:1/manager).
    @MainActor
    static func setRule(title: String, project: Project?, ignored: Bool, context: ModelContext) {
        guard project != nil || ignored else {
            removeRule(for: title, context: context)
            return
        }
        let key = normalizedKey(title)
        guard !key.isEmpty else { return }

        let rule: AgendaProjectRule
        if let existing = Self.rule(for: title, context: context) {
            rule = existing
        } else {
            rule = AgendaProjectRule(normalizedTitleKey: key, displayTitle: title)
            context.insert(rule)
        }
        rule.displayTitle = title
        rule.project = project
        rule.isIgnored = ignored

        if let project {
            applyProject(project, toMeetingsMatching: key, context: context)
        }
    }

    @MainActor
    static func removeRule(for title: String, context: ModelContext) {
        if let existing = rule(for: title, context: context) {
            context.delete(existing)
        }
    }

    // MARK: - Internals

    /// Propage le projet d'une nouvelle règle aux réunions déjà importées dont
    /// le titre matche : réunions projet (mise à jour du projet) et réunions
    /// globales sans projet (reclassées). Les 1:1/manager/architecture ne sont
    /// jamais réécrites.
    @MainActor
    private static func applyProject(_ project: Project,
                                     toMeetingsMatching key: String,
                                     context: ModelContext) {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        for meeting in meetings where normalizedKey(meeting.title) == key {
            guard meeting.kind == .project || (meeting.kind == .global && meeting.project == nil) else { continue }
            meeting.kind = .project
            meeting.project = project
        }
    }
}
