import Foundation

/// Chaîne de citation (spec §1.3 `Ref`, §8 « chaîne de citation ») : d'où vient
/// un élément dérivé — une action tirée d'une phrase, une note citant une
/// capture — et à quel instant de l'axe temps de la réunion.
///
/// **Stocké sur trois colonnes plates**, jamais en JSON : `sourceKindRaw`,
/// `sourceStableID`, `sourceT`. Un `#Predicate` SwiftData sait filtrer une
/// colonne, pas un blob encodé — « toutes les actions nées de la transcription »
/// doit rester une requête.
struct SourceRef: Codable, Hashable {

    /// Nature de la source. Valeurs brutes de la spec, à ne pas renommer.
    enum Kind: String, Codable, CaseIterable {
        case transcript = "transcript"
        case note       = "note"
        case capture    = "capture"
        case board      = "board"
    }

    var kind: Kind
    /// `stableID` de l'élément source (segment, note, capture, planche).
    var stableID: UUID
    /// Instant sur l'axe temps de la réunion, en secondes. `nil` quand la
    /// source n'est pas horodatée.
    var t: Double?

    init(kind: Kind, stableID: UUID, t: Double? = nil) {
        self.kind = kind
        self.stableID = stableID
        self.t = t
    }
}

/// Adopté par les `@Model` qui portent une source : `ActionTask` et
/// `MeetingNote`. L'accesseur `sourceRef` est écrit **une seule fois**, ici —
/// deux implémentations auraient divergé sur le cas partiel (un `kind` sans
/// identifiant, qu'une restauration incomplète peut produire).
protocol SourceRefCarrying: AnyObject {
    var sourceKindRaw: String? { get set }
    var sourceStableID: UUID? { get set }
    var sourceT: Double? { get set }
}

extension SourceRefCarrying {

    /// Vue typée des trois colonnes. `nil` dès qu'il manque le type ou
    /// l'identifiant : une référence sans cible ne mène nulle part, et l'UI
    /// doit alors ne rien afficher plutôt qu'un lien mort.
    var sourceRef: SourceRef? {
        get {
            guard let raw = sourceKindRaw,
                  let kind = SourceRef.Kind(rawValue: raw),
                  let stableID = sourceStableID else { return nil }
            return SourceRef(kind: kind, stableID: stableID, t: sourceT)
        }
        set {
            sourceKindRaw = newValue?.kind.rawValue
            sourceStableID = newValue?.stableID
            sourceT = newValue?.t
        }
    }
}
