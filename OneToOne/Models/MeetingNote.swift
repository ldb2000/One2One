import Foundation
import SwiftData

// MARK: - Énums de la note horodatée

/// Nature d'une ligne de note (spec §1.3 `Note.kind`). Valeurs brutes
/// persistées, à ne pas renommer.
enum MeetingNoteKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Note ordinaire.
    case note     = "note"
    /// Décision prise en séance.
    case decision = "decision"
    /// Risque soulevé.
    case risk     = "risk"
    /// Retour donné en 1:1 (`③ FEEDBACK`).
    case feedback = "feedback"
    /// Engagement pris à l'oral côté collaborateur (`/promesse`).
    case promise  = "promise"
    /// Demande adressée au manager (`/demande`).
    case request  = "request"
    /// Preuve d'un livrable cité (`/preuve`).
    case proof    = "proof"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .note:     return "Note"
        case .decision: return "Décision"
        case .risk:     return "Risque"
        case .feedback: return "Feedback"
        case .promise:  return "Promesse"
        case .request:  return "Demande"
        case .proof:    return "Preuve"
        }
    }
}

/// Qui a écrit la ligne. L'app est mono-utilisateur : `me` couvre tout hors
/// contexte 1:1, où la distinction manager / collaborateur porte la
/// confidentialité par défaut et l'affichage en deux colonnes.
enum MeetingSide: String, Codable, CaseIterable, Sendable {
    case me           = "me"
    case manager      = "manager"
    case collaborator = "collaborator"
}

// MARK: - MeetingNote

/// Une ligne de note **adressable** de la réunion (spec §1.3 `Note`, D1).
///
/// Pourquoi une table et non des marqueurs `[04:12]` dans `Meeting.liveNotes` :
/// la confidentialité par ligne, le `kind`, la chaîne de citation et
/// `isExportable` exigent des lignes que l'on puisse filtrer et référencer.
/// `liveNotes` reste la source de vérité du **markdown** des réunions de type
/// `Note` et de l'éditeur historique ; à la première ouverture d'une réunion
/// non migrée, son contenu est repris ici en une note `t = 0`
/// (`MeetingNoteStore.importLiveNotesIfNeeded`) **sans être effacé**.
@Model
final class MeetingNote: Confidential, SourceRefCarrying {

    /// Identité externe stable (cible d'un `SourceRef`, d'une URL
    /// `onetoone://`). Optionnelle pour rester compatible avec une migration
    /// légère ; `ensuredStableID` la remplit à la demande.
    var stableID: UUID? = nil

    /// Instant sur l'axe temps de la réunion, en secondes depuis le début de
    /// l'enregistrement (`Meeting.recordingStartedAt`). `0` quand la note ne
    /// vient pas d'une séance enregistrée.
    var t: Double = 0

    var text: String = ""

    var kindRaw: String = MeetingNoteKind.note.rawValue
    var kind: MeetingNoteKind {
        get { MeetingNoteKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    /// Niveau de confidentialité de la ligne (spec §3.2). Défaut `shared` :
    /// c'est `MeetingNoteStore.defaultVisibility(for:)` qui applique le défaut
    /// par type de réunion à la création.
    var visibilityRaw: String = Visibility.shared.rawValue
    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .shared }
        set { visibilityRaw = newValue.rawValue }
    }

    var authorSideRaw: String = MeetingSide.me.rawValue
    var authorSide: MeetingSide {
        get { MeetingSide(rawValue: authorSideRaw) ?? .me }
        set { authorSideRaw = newValue.rawValue }
    }

    // Chaîne de citation — trois colonnes plates, vue typée `sourceRef`
    // (protocole `SourceRefCarrying`).
    var sourceKindRaw: String? = nil
    var sourceStableID: UUID? = nil
    var sourceT: Double? = nil

    /// Ordre d'affichage à `t` égal (plusieurs notes peuvent partager la
    /// seconde, notamment à `t = 0`).
    var orderIndex: Int = 0

    var createdAt: Date = Date()

    var meeting: Meeting?

    init(t: Double = 0,
         text: String = "",
         kind: MeetingNoteKind = .note,
         visibility: Visibility = .shared,
         authorSide: MeetingSide = .me,
         orderIndex: Int = 0,
         createdAt: Date = Date()) {
        self.stableID = UUID()
        self.t = t
        self.text = text
        self.kindRaw = kind.rawValue
        self.visibilityRaw = visibility.rawValue
        self.authorSideRaw = authorSide.rawValue
        self.orderIndex = orderIndex
        self.createdAt = createdAt
    }

    /// Renvoie `stableID` en le remplissant si la ligne précède l'optionnel.
    /// Persiste immédiatement, comme `Meeting.ensuredStableID`.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}
