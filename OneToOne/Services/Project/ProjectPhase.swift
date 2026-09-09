import Foundation

/// Les quatre listes de valeurs d'un projet — phase, statut, type, niveau de
/// risque (décision **D14**).
///
/// **Elles ne sont pas persistées.** `Project.phase`, `.status`, `.projectType`
/// et `.riskLevel` restent des `String` libres : l'import xlsx du portfolio
/// externe y écrit ce que le portfolio contient, et le semis historique y écrit
/// `"Réalisation"` (constat §2.7 de la spec). Ces enums nomment les valeurs
/// **connues** pour que les listes en dur de `DetailsViews.swift` et de
/// `Sidebar.swift` cessent de les répéter ; toute autre valeur rend `nil`, et
/// s'affiche alors en badge neutre — jamais un plantage, jamais une valeur
/// réécrite dans le dos de l'utilisateur.
///
/// La convention du dépôt (`…Raw: String` + wrapper calculé) ne s'applique pas
/// ici : il n'y a pas de colonne à envelopper, seulement une chaîne libre à
/// interpréter. D'où `init?(raw:)` plutôt qu'un `init?(rawValue:)` strict.

// MARK: - Interprétation tolérante

/// Ce que les quatre listes partagent : un libellé, la table de leurs libellés,
/// et une lecture insensible à la casse, aux accents et aux espaces de bord.
protocol ProjectValueList: CaseIterable, Equatable {
    /// Le libellé exact, tel qu'il s'écrit dans la colonne persistée et à
    /// l'écran.
    var label: String { get }
}

extension ProjectValueList {

    /// Les libellés, dans l'ordre des cas.
    static var allLabels: [String] { allCases.map(\.label) }

    /// Clé de comparaison : casse et accents repliés, espaces de bord retirés.
    /// Même normalisation que `MeetingTag.normalizedKey`, pour la même raison —
    /// « modere » et « Modéré » désignent le même niveau.
    static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Lit une valeur persistée. `nil` pour toute valeur hors table.
    static func from(raw: String) -> Self? {
        let clef = normalizedKey(raw)
        guard !clef.isEmpty else { return nil }
        return allCases.first { normalizedKey($0.label) == clef }
    }
}

// MARK: - Phase

/// Phase d'un projet. Les quatre valeurs de la maquette et des listes en dur
/// (`Sidebar.swift`, `DetailsViews.swift`).
enum ProjectPhase: String, CaseIterable, Sendable, ProjectValueList {
    case cadrage
    case design
    case build
    case run

    var label: String {
        switch self {
        case .cadrage: return "Cadrage"
        case .design:  return "Design"
        case .build:   return "Build"
        case .run:     return "Run"
        }
    }

    init?(raw: String) {
        guard let cas = Self.from(raw: raw) else { return nil }
        self = cas
    }
}

// MARK: - Statut

/// Statut d'un projet. Les valeurs persistées sont **anglaises** — c'est ce que
/// l'import xlsx écrit depuis toujours, et les renommer casserait le store.
enum ProjectStatus: String, CaseIterable, Sendable, ProjectValueList {
    case green
    case yellow
    case red
    case unknown

    var label: String {
        switch self {
        case .green:   return "Green"
        case .yellow:  return "Yellow"
        case .red:     return "Red"
        case .unknown: return "Unknown"
        }
    }

    /// Libellé français affiché dans l'en-tête à pilules de la capture 1d
    /// (« Au vert »). Distinct de `label`, qui est la valeur persistée.
    var displayLabel: String {
        switch self {
        case .green:   return "Au vert"
        case .yellow:  return "À surveiller"
        case .red:     return "En alerte"
        case .unknown: return "Statut inconnu"
        }
    }

    init?(raw: String) {
        guard let cas = Self.from(raw: raw) else { return nil }
        self = cas
    }
}

// MARK: - Type

/// Type d'un projet, tel que la ligne `P25_112 · Métier` de la capture 1a
/// l'affiche.
enum ProjectType: String, CaseIterable, Sendable, ProjectValueList {
    case metier
    case transverse
    case technique

    var label: String {
        switch self {
        case .metier:     return "Métier"
        case .transverse: return "Transverse"
        case .technique:  return "Technique"
        }
    }

    init?(raw: String) {
        guard let cas = Self.from(raw: raw) else { return nil }
        self = cas
    }
}

// MARK: - Risque

/// Niveau de risque d'un projet. L'ordre des cas est celui de la **gravité
/// croissante** : c'est lui que lira le filtre « Risque ≥ Modéré » de la
/// capture 1a (lot 2).
///
/// La teinte n'est pas ici : elle vit dans `RiskLevelTint.swift`, table unique
/// partagée avec `MeetingKPI.Level.teinte` (décision **D2** — « Faible » reste
/// `ink4`).
enum RiskLevel: String, CaseIterable, Sendable, ProjectValueList {
    case faible
    case modere
    case eleve
    case critique

    var label: String {
        switch self {
        case .faible:   return "Faible"
        case .modere:   return "Modéré"
        case .eleve:    return "Élevé"
        case .critique: return "Critique"
        }
    }

    /// Rang de gravité, croissant. `0` pour le moindre.
    var severity: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    init?(raw: String) {
        guard let cas = Self.from(raw: raw) else { return nil }
        self = cas
    }
}
