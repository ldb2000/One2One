import Foundation
import SwiftData

/// Un projet du portfolio. La plupart des métadonnées (domaine, sponsor, phase,
/// budgets, dates, risques…) sont sourcées d'un portfolio externe importé depuis
/// un fichier xlsx et rafraîchies à chaque réimport ; les champs de pilotage
/// interne (notes, préparation, pièces jointes, FK collaborateurs) sont saisis
/// dans l'app et préservés entre les imports.
@Model
final class Project {
    var code: String
    var name: String
    var isArchived: Bool = false
    var domain: String
    var sponsor: String
    var projectType: String
    var phase: String // Cadrage, Design, Build, Run, etc.
    var status: String // Green, Yellow, Red
    /// Chef de projet (responsable fonctionnel) — nom libre, sourcé du
    /// portfolio externe lors de l'import xlsx. Champ d'affichage indépendant
    /// de la FK `projectManager` (qui, elle, relie un `Collaborator` connu).
    var chefDeProjet: String = ""
    /// Architecte technique — nom libre, sourcé du portfolio externe. Champ
    /// d'affichage indépendant de la FK `technicalArchitect`.
    var architecte: String = ""
    var projectDeliveryDate: Date?
    var designEndDeadline: Date?
    var plannedDays: Double?
    var businessPlanningStatus: String?
    var comment: String?
    var followUpNotes: String?
    var cespPlanningStatus: String?
    var technicalSpecStatus: String?
    var comment2: String?
    var additionalInfo: String?
    var buildRetex: String?
    
    // Budgets
    var budgetDeliver: Double?
    var budgetInit: Double?
    var budgetRev: Double?
    var budgetCons: Double?
    var percentConsoCharge: Double?
    
    // Dates
    var startDate: Date?
    var endDateInitial: Date?
    var endDateRevised: Date?
    
    // Progressions
    var productionDeliveryProgress: Double?
    var planningProgress: Double?
    
    // Risques
    var riskLevel: String?  // Critique, Élevé, Modéré, Faible
    var riskDescription: String?
    var keyPoints: [String] = []

    // Technical Documents
    var hasDAT: Bool = false
    var datLink: URL?
    var hasDIT: Bool = false
    var ditLink: URL?

    var entity: Entity?

    /// Chef de projet — Optional FK vers un `Collaborator` connu de l'app
    /// (pendant relationnel du champ libre `chefDeProjet`). Affiché dans
    /// ProjectDetailView § Informations Générales et utilisé pour
    /// la reverse query depuis la fiche collab.
    var projectManager: Collaborator?

    /// Architecte technique du projet — Optional FK vers un `Collaborator`
    /// (pendant relationnel du champ libre `architecte`).
    /// Cas d'usage : dans un 1:1 avec un collab architecte, on liste
    /// automatiquement tous les projets où il endosse ce rôle.
    var technicalArchitect: Collaborator?

    /// Notes de planning en texte libre. Substituées au token `{{project.planning}}`
    /// dans les templates de rapport (résolu via `meeting.project` par
    /// `ReportTemplating`, cf. templates COPIL/COSUI). Vide → token remplacé
    /// par une chaîne vide.
    var planningText: String = ""

    /// Identifiant stable pour les tokens inter-fenêtres (WindowGroup).
    /// `nil` sur les lignes antérieures — backfillé au lancement de l'app.
    var stableID: UUID? = nil

    /// Pool de notes de préparation persistantes pour la prochaine réunion
    /// projet (kind `.project`). Drainé dans `Meeting.prepNotes` à la création
    /// d'une réunion liée à ce projet, puis repeuplé au carryover des items non
    /// cochés en fin de transcription (cf. `Meeting.prepNotes`).
    var standingPrepNotes: String = ""
    var standingPrepUpdatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ActionTask.project)
    var tasks: [ActionTask] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectAlert.project)
    var alerts: [ProjectAlert] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectAttachment.project)
    var attachments: [ProjectAttachment] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectInfoEntry.project)
    var infoEntries: [ProjectInfoEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectCollaboratorEntry.project)
    var collaboratorEntries: [ProjectCollaboratorEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectMail.project)
    var mails: [ProjectMail] = []

    @Relationship(deleteRule: .cascade, inverse: \Note.project)
    var notes: [Note] = []

    /// Règles d'affectation agenda → projet : supprimées avec le projet.
    @Relationship(deleteRule: .cascade, inverse: \AgendaProjectRule.project)
    var agendaRules: [AgendaProjectRule] = []

    init(code: String, name: String, domain: String, sponsor: String = "", projectType: String = "Métier", phase: String, status: String = "Unknown") {
        self.code = code
        self.name = name
        self.domain = domain
        self.sponsor = sponsor
        self.projectType = projectType
        self.phase = phase
        self.status = status
        self.stableID = UUID()
    }

    /// Renvoie `stableID` en backfillant un nouvel UUID si la DB contient `nil`
    /// (cas des projets créés avant l'ajout du champ). Persiste immédiatement.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

/// Entrée du journal d'informations d'un projet (note datée).
/// `category` est une chaîne libre servant au filtrage/affichage : valeurs
/// usuelles "Information" (défaut) et "REX" (retour d'expérience, surligné en
/// orange et exploité par le chatbot).
@Model
final class ProjectInfoEntry {
    var date: Date
    var content: String
    var category: String
    var project: Project?

    init(date: Date = Date(), content: String = "", category: String = "Information") {
        self.date = date
        self.content = content
        self.category = category
    }
}

/// Note ou action liée à un collaborateur dans le contexte d'un projet.
/// `kind` est une chaîne libre distinguant les deux types saisis dans l'UI :
/// "Information collaborateur" (note) et "Action collaborateur" (tâche, suivie
/// via `isCompleted`).
@Model
final class ProjectCollaboratorEntry {
    var date: Date
    var content: String
    var kind: String
    var isCompleted: Bool
    var collaborator: Collaborator?
    var project: Project?

    init(date: Date = Date(), content: String = "", kind: String = "Information collaborateur", isCompleted: Bool = false) {
        self.date = date
        self.content = content
        self.kind = kind
        self.isCompleted = isCompleted
    }
}

@Model
final class ProjectAttachment {
    var fileName: String
    var filePath: String
    var bookmarkData: Data?
    var category: String
    var comment: String
    var importedAt: Date
    var project: Project?

    init(url: URL, category: String = "Document", comment: String = "", importedAt: Date = Date()) {
        self.fileName = url.lastPathComponent
        self.filePath = url.path
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        self.category = category
        self.comment = comment
        self.importedAt = importedAt
    }

    func resolvedURL() -> URL {
        guard let bookmarkData else {
            return URL(fileURLWithPath: filePath)
        }

        var isStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return resolvedURL
        }

        return URL(fileURLWithPath: filePath)
    }
}
