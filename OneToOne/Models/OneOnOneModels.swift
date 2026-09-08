import Foundation
import SwiftData

// MARK: - Énums du domaine 1:1

/// Les deux côtés d'un fil 1:1. `MeetingSide.me` n'a pas cours ici : un
/// engagement ou un sujet d'ordre du jour appartient toujours à l'un des deux
/// rôles, quel que soit celui que j'endosse.
enum OneOnOneSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case manager      = "manager"
    case collaborator = "collaborator"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manager:      return "Manager"
        case .collaborator: return "Collaborateur"
        }
    }
}

/// Cycle de vie d'un engagement (spec §1.3 `Commitment.state`).
enum CommitmentState: String, Codable, CaseIterable, Identifiable, Sendable {
    case open   = "open"
    case kept   = "kept"
    case missed = "missed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open:   return "En cours"
        case .kept:   return "Tenu"
        case .missed: return "Manqué"
        }
    }
}

/// Cycle de vie d'un sujet d'ordre du jour (spec §1.3 `AgendaItem.state`).
enum AgendaItemState: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo     = "todo"
    case done     = "done"
    case deferred = "deferred"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo:     return "À traiter"
        case .done:     return "Traité"
        case .deferred: return "Reporté"
        }
    }
}

/// Nature d'un sujet d'ordre du jour (spec §6.2).
///
/// Une **demande** est un sujet qui attend une réponse : la colonne
/// `MES DEMANDES EN COURS` de la capture `5a` n'est pas une seconde table,
/// c'est un filtre sur l'ordre du jour. Séparer les deux aurait obligé à
/// synchroniser deux listes que l'utilisateur voit comme une seule.
enum AgendaItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case topic   = "topic"
    case request = "request"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topic:   return "Sujet"
        case .request: return "Demande"
        }
    }
}

/// Où en est une demande (spec §6.2). Libellés exacts de la capture `5a`.
enum RequestStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Posée, jamais reprise par le manager.
    case pending = "pending"
    /// Prise en compte, réponse annoncée mais pas rendue.
    case waiting = "waiting"
    case granted = "granted"
    case refused = "refused"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "Sans réponse"
        case .waiting: return "En attente"
        case .granted: return "Accordé"
        case .refused: return "Refusé"
        }
    }
}

// MARK: - Le fil

/// Le fil des tête-à-tête avec une personne (spec §1.3 `OneOnOneThread`, D3).
///
/// Créé **paresseusement** au premier 1:1 d'un collaborateur (lot 10) :
/// `Meeting` et `Collaborator` sont déjà des objets « dieu », y verser
/// l'ordre du jour, les engagements, l'humeur et les objectifs en colonnes JSON
/// rendrait tout calcul de fil impossible à requêter.
///
/// Les réunions du fil ne sont pas une relation : elles se déduisent de
/// `Meeting.participants` et du `kind` (lot 10, `OneOnOneThreadStore`), ce qui
/// évite un second endroit à tenir en phase avec les participants.
@Model
final class OneOnOneThread {

    var stableID: UUID? = nil

    var collaborator: Collaborator?

    /// Le rôle que **j'endosse** dans ce fil : `manager` pour un `.oneToOne`,
    /// `collaborator` pour un `.manager` (D4 : déduit du type, jamais saisi).
    var myRoleRaw: String = OneOnOneSide.manager.rawValue
    var myRole: OneOnOneSide {
        get { OneOnOneSide(rawValue: myRoleRaw) ?? .manager }
        set { myRoleRaw = newValue.rawValue }
    }

    /// Miroir en jours de `Collaborator.oneToOneCadence` : le fil garde la
    /// cadence convenue au moment où il est créé, l'annuaire reste la source de
    /// vérité. `0` = aucune cadence convenue (rien n'est jamais en retard).
    var cadenceDays: Int = 0

    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Commitment.thread)
    var commitments: [Commitment] = []

    @Relationship(deleteRule: .cascade, inverse: \OneOnOneAgendaItem.thread)
    var agendaItems: [OneOnOneAgendaItem] = []

    @Relationship(deleteRule: .cascade, inverse: \MoodEntry.thread)
    var moodEntries: [MoodEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \OneOnOneObjective.thread)
    var objectives: [OneOnOneObjective] = []

    init(collaborator: Collaborator? = nil,
         myRole: OneOnOneSide = .manager,
         cadenceDays: Int = 0,
         createdAt: Date = Date()) {
        self.stableID = UUID()
        self.collaborator = collaborator
        self.myRoleRaw = myRole.rawValue
        self.cadenceDays = cadenceDays
        self.createdAt = createdAt
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - Engagement

/// Un engagement réciproque du fil (spec §1.3 `Commitment`).
///
/// Remplace, **pour les nouveaux fils seulement**, la dérivation de
/// `EngagementLedger` (qui lit `DecisionEntry.settledAt` et
/// `ActionTask.engagementSettledAt`). L'ancien mécanisme reste lu en
/// « Historique » : convertir automatiquement ferait apparaître deux fois le
/// même engagement dans les compteurs.
@Model
final class Commitment: Confidential {

    var stableID: UUID? = nil

    var thread: OneOnOneThread?

    var text: String = ""

    /// Qui doit tenir l'engagement.
    var ownerSideRaw: String = OneOnOneSide.manager.rawValue
    var ownerSide: OneOnOneSide {
        get { OneOnOneSide(rawValue: ownerSideRaw) ?? .manager }
        set { ownerSideRaw = newValue.rawValue }
    }

    var dueAt: Date?

    var stateRaw: String = CommitmentState.open.rawValue
    var state: CommitmentState {
        get { CommitmentState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }

    var promisedAt: Date = Date()

    /// Date du solde — celle où l'engagement est passé `kept` ou `missed`
    /// (lot 10, colonne à valeur par défaut).
    ///
    /// Sans elle, « TENUS DEPUIS LE DERNIER 1:1 » (capture 2a) ne se calcule
    /// pas : l'état seul ne dit pas *quand*. `nil` sur un engagement encore
    /// ouvert, et sur les lignes semées avant l'ajout de la colonne —
    /// `CommitmentLedger.settlementDate(of:)` retombe alors sur `promisedAt`.
    var settledAt: Date?

    /// Réunion où l'engagement a été pris. Relation `.nullify` sans inverse sur
    /// `Meeting` : c'est une trace de provenance, pas un contenu que la
    /// suppression d'une réunion doit emporter.
    var promisedInMeeting: Meeting?

    var deferralCount: Int = 0

    var visibilityRaw: String = Visibility.shared.rawValue
    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .shared }
        set { visibilityRaw = newValue.rawValue }
    }

    /// Action matérialisant l'engagement, quand il en a une.
    var linkedAction: ActionTask?

    /// Rang de la décision de `Meeting.decisionsJSON` dont l'engagement est
    /// issu. Un rang et non un identifiant : les décisions sont un tableau de
    /// chaînes dans une colonne JSON, sans identité propre.
    var linkedDecisionIndex: Int?

    init(text: String = "",
         ownerSide: OneOnOneSide = .manager,
         dueAt: Date? = nil,
         state: CommitmentState = .open,
         promisedAt: Date = Date(),
         visibility: Visibility = .shared) {
        self.stableID = UUID()
        self.text = text
        self.ownerSideRaw = ownerSide.rawValue
        self.dueAt = dueAt
        self.stateRaw = state.rawValue
        self.promisedAt = promisedAt
        self.visibilityRaw = visibility.rawValue
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - Ordre du jour

/// Un sujet d'ordre du jour co-construit (spec §1.3 `AgendaItem`).
///
/// `ManagerReportItem` n'est **pas** fusionné avec ce modèle : il porte la
/// provenance en offsets UTF-16 dans les notes du 1:1 manager et alimente le
/// flux de compte-rendu existant, qui reste en service.
@Model
final class OneOnOneAgendaItem: Confidential {

    var stableID: UUID? = nil

    var thread: OneOnOneThread?

    var text: String = ""

    var addedBySideRaw: String = OneOnOneSide.manager.rawValue
    var addedBySide: OneOnOneSide {
        get { OneOnOneSide(rawValue: addedBySideRaw) ?? .manager }
        set { addedBySideRaw = newValue.rawValue }
    }

    var order: Int = 0

    var stateRaw: String = AgendaItemState.todo.rawValue
    var state: AgendaItemState {
        get { AgendaItemState(rawValue: stateRaw) ?? .todo }
        set { stateRaw = newValue.rawValue }
    }

    var visibilityRaw: String = Visibility.shared.rawValue
    var visibility: Visibility {
        get { Visibility(rawValue: visibilityRaw) ?? .shared }
        set { visibilityRaw = newValue.rawValue }
    }

    var createdAt: Date = Date()

    // MARK: Demande (lot 10, spec §6.2)
    //
    // Quatre colonnes **à valeur par défaut** : aucune nouvelle version de
    // schéma, la table est déclarée en V3 et la migration reste légère. Un
    // sujet ordinaire les ignore (`topic` / `pending` / `nil` / `0`).

    var kindRaw: String = AgendaItemKind.topic.rawValue
    var kind: AgendaItemKind {
        get { AgendaItemKind(rawValue: kindRaw) ?? .topic }
        set { kindRaw = newValue.rawValue }
    }

    /// N'a de sens que pour un `kind == .request`.
    var requestStatusRaw: String = RequestStatus.pending.rawValue
    var requestStatus: RequestStatus {
        get { RequestStatus(rawValue: requestStatusRaw) ?? .pending }
        set { requestStatusRaw = newValue.rawValue }
    }

    /// Date de la **demande**, distincte de `createdAt` : une demande posée en
    /// juillet peut être ressaisie en septembre, et c'est son ancienneté
    /// d'origine qui la fait passer en `report` (spec §6.2, 60 jours).
    var requestedAt: Date?

    /// Nombre de relances (« relancé 2 fois » de la capture `5a`).
    var remindedCount: Int = 0

    /// Réunion où le sujet a été traité (provenance, `.nullify` sans inverse).
    var meeting: Meeting?
    /// Réunion vers laquelle le sujet non traité a migré (`AgendaCarryover`).
    var deferredToMeeting: Meeting?

    init(text: String = "",
         addedBySide: OneOnOneSide = .manager,
         order: Int = 0,
         state: AgendaItemState = .todo,
         visibility: Visibility = .shared,
         kind: AgendaItemKind = .topic,
         requestStatus: RequestStatus = .pending,
         requestedAt: Date? = nil) {
        self.stableID = UUID()
        self.text = text
        self.addedBySideRaw = addedBySide.rawValue
        self.order = order
        self.stateRaw = state.rawValue
        self.visibilityRaw = visibility.rawValue
        self.kindRaw = kind.rawValue
        self.requestStatusRaw = requestStatus.rawValue
        self.requestedAt = requestedAt
        self.createdAt = Date()
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - Humeur

/// Un cran de moral relevé en séance (spec §1.3 `moodHistory`).
///
/// **Saisie humaine uniquement** : jamais déduit par le LLM d'une
/// transcription. Une humeur inventée par un modèle serait versée dans un
/// historique que l'utilisateur croit avoir écrit.
@Model
final class MoodEntry {

    var stableID: UUID? = nil

    var thread: OneOnOneThread?
    /// Réunion où le relevé a été fait (`.nullify` sans inverse : provenance).
    var meeting: Meeting?

    /// De 1 (au plus bas) à 5 (au mieux). Borné à la construction et par
    /// `clampedValue` à la lecture, pour qu'une restauration douteuse ne casse
    /// pas l'histogramme.
    var value: Int = 3
    var clampedValue: Int { min(5, max(1, value)) }

    var recordedAt: Date = Date()

    init(value: Int = 3, recordedAt: Date = Date()) {
        self.stableID = UUID()
        self.value = min(5, max(1, value))
        self.recordedAt = recordedAt
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - Objectif

/// Un objectif suivi dans le fil (spec §1.3 `objectives`).
@Model
final class OneOnOneObjective {

    var stableID: UUID? = nil

    var thread: OneOnOneThread?

    var label: String = ""

    /// Progression en pourcentage, 0 à 100.
    var progress: Int = 0
    var clampedProgress: Int { min(100, max(0, progress)) }

    var reviewAt: Date?
    var order: Int = 0
    var createdAt: Date = Date()

    init(label: String = "",
         progress: Int = 0,
         reviewAt: Date? = nil,
         order: Int = 0) {
        self.stableID = UUID()
        self.label = label
        self.progress = min(100, max(0, progress))
        self.reviewAt = reviewAt
        self.order = order
        self.createdAt = Date()
    }

    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}
