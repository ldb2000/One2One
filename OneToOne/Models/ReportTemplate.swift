import Foundation
import SwiftData

enum ReportTemplateKind: String, CaseIterable, Identifiable {
    case general, oneToOne, manager
    case copil, cosui, codir
    case preparation, restitution
    case workshop
    /// Note d'escalade vers les RH / le N+1 (décision D9). La seule catégorie
    /// dont l'audience est `.hr`, et donc la seule sortie qui emporte les
    /// lignes `escalated`.
    case escalade
    case metier, initiative, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:    return "Global"
        case .oneToOne:   return "1:1 Collaborateur"
        case .manager:    return "1:1 Manager"
        case .copil:      return "COPIL"
        case .cosui:      return "COSUI"
        case .codir:      return "CODIR"
        case .preparation: return "Préparation"
        case .restitution: return "Restitution / Démo"
        case .workshop:   return "Séance de travail / Workshop"
        case .escalade:   return "Escalade"
        case .metier:     return "Métier"
        case .initiative: return "Initiative"
        case .custom:     return "Personnalisé"
        }
    }

    var sfSymbol: String {
        switch self {
        case .general:    return "doc.text"
        case .oneToOne:   return "person.2.fill"
        case .manager:    return "person.crop.square.filled.and.at.rectangle"
        case .copil:      return "rectangle.3.group"
        case .cosui:      return "list.bullet.rectangle"
        case .codir:      return "building.columns"
        case .preparation: return "checklist"
        case .restitution: return "play.rectangle"
        case .workshop:   return "person.3.sequence"
        case .escalade:   return "exclamationmark.shield"
        case .metier:     return "briefcase"
        case .initiative: return "lightbulb"
        case .custom:     return "slider.horizontal.3"
        }
    }
}

extension ReportTemplateKind {

    /// À qui le rapport de cette catégorie s'adresse (spec §8, « filtre de
    /// confidentialité unique »).
    ///
    /// L'audience n'est **pas** la règle de sortie — celle-là vit dans
    /// `ConfidentialityFilter.isExportable`, écrite une seule fois — c'est son
    /// paramètre. Et c'est le gabarit choisi qui la détermine, pas le type de
    /// réunion : le même 1:1 produit un compte-rendu pour le collaborateur ou
    /// une note d'escalade pour les RH selon le gabarit, et les deux ne
    /// laissent pas sortir les mêmes lignes.
    ///
    /// Table exhaustive et sans `default` : une catégorie ajoutée doit obliger
    /// à trancher, jamais retomber sur l'audience la plus large.
    var audience: Audience {
        switch self {
        case .oneToOne: return .collaborator
        case .manager:  return .manager
        case .escalade: return .hr
        case .general, .copil, .cosui, .codir, .preparation,
             .restitution, .workshop, .metier, .initiative, .custom:
            return .projectTeam
        }
    }
}

/// L'audience effective d'une génération de rapport : celle du gabarit choisi,
/// ou celle du type de réunion quand aucun gabarit ne l'est (`Auto` dans le
/// sélecteur du chrome).
enum ReportAudience {

    static func forTemplate(_ template: ReportTemplate?, meeting: Meeting) -> Audience {
        template?.kind.audience ?? ConfidentialityFilter.audience(for: meeting.kind)
    }
}

/// Ordered section a ReportTemplate asks the AI to produce.
struct TemplateSection: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var hint: String
}

enum HistoryMode: String, CaseIterable, Identifiable {
    case none, lastN, rag, hybrid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:   return "Aucun"
        case .lastN:  return "N derniers résumés"
        case .rag:    return "RAG sémantique"
        case .hybrid: return "Hybride (résumés + RAG)"
        }
    }
}

/// Gabarit de rapport piloté par l'IA : préambule, corps de prompt et sections
/// ordonnées que `AIReportService` demande au LLM de produire, ainsi que la
/// stratégie d'historique (résumés / RAG). Peut être fourni par l'app
/// (`isBuiltIn`) ou créé par l'utilisateur.
@Model
final class ReportTemplate {
    /// Optional — SwiftData migration caveat. Use `ensuredStableID`.
    var stableID: UUID? = nil
    var name: String
    var kindRaw: String
    var promptBody: String
    /// Préambule système injecté en tête du prompt de génération. Permet de
    /// personnaliser le ton/rôle de l'assistant par template. Default = ancien
    /// préambule hardcoded de `AIReportService.generate`.
    var preamble: String = "Tu es l'assistant de synthèse de OneToOne."
    var sectionsJSON: String
    var historyModeRaw: String = HistoryMode.none.rawValue
    var historyN: Int = 0
    var historyK: Int = 0
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var createdAt: Date? = nil
    var updatedAt: Date? = nil

    init(name: String,
         kind: ReportTemplateKind,
         promptBody: String = "",
         preamble: String = "Tu es l'assistant de synthèse de OneToOne.",
         sections: [TemplateSection] = [],
         historyMode: HistoryMode = .none,
         historyN: Int = 0,
         historyK: Int = 0,
         isBuiltIn: Bool = false) {
        self.stableID = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.promptBody = promptBody
        self.preamble = preamble
        self.sectionsJSON = Self.encodeSections(sections)
        self.historyModeRaw = historyMode.rawValue
        self.historyN = historyN
        self.historyK = historyK
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Renvoie `stableID` en backfillant un nouvel UUID si la DB contient `nil`
    /// (lignes antérieures à l'ajout du champ). Persiste immédiatement.
    /// Contrairement à `stableID` (Optional, brut), garantit une valeur non nil.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    /// Accès typé à `kindRaw` (catégorie du template). Fallback `.custom` si la
    /// valeur stockée est inconnue.
    var kind: ReportTemplateKind {
        get { ReportTemplateKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    /// Accès typé à `historyModeRaw` : stratégie d'historique injectée au prompt
    /// (aucune / N derniers résumés / RAG / hybride). Fallback `.none`.
    var historyMode: HistoryMode {
        get { HistoryMode(rawValue: historyModeRaw) ?? .none }
        set { historyModeRaw = newValue.rawValue }
    }

    /// Sections ordonnées du rapport, vue typée au-dessus de `sectionsJSON`.
    /// Le setter touche `updatedAt` (horodatage de dernière modification).
    var sections: [TemplateSection] {
        get { Self.decodeSections(sectionsJSON) }
        set { sectionsJSON = Self.encodeSections(newValue); updatedAt = Date() }
    }

    // MARK: - JSON helpers

    private static func encodeSections(_ items: [TemplateSection]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func decodeSections(_ raw: String) -> [TemplateSection] {
        guard let data = raw.data(using: .utf8),
              let items = try? JSONDecoder().decode([TemplateSection].self, from: data) else {
            return []
        }
        return items
    }
}
