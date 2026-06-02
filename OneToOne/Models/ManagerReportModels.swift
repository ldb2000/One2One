import Foundation
import SwiftData

// MARK: - ManagerReportItem
//
// Un point à aborder avec mon manager. Créé soit par sélection (item issu d'une
// transcription / rapport / notes) soit manuellement. Coché pendant le 1:1 manager,
// archivé à la génération du CR.

/// Point à aborder avec le manager. Créé par sélection (issu d'une
/// transcription/rapport/notes) ou manuellement, coché pendant le 1:1 manager,
/// puis archivé (`archivedAt`) à la génération du CR. Les doublons potentiels
/// sont marqués via `duplicateOfStableID`. Persisté via SwiftData.
@Model
final class ManagerReportItem {
    /// Optional — see SwiftData migration caveat. Use `ensuredStableID`
    /// when you need a guaranteed non-nil UUID.
    var stableID: UUID? = nil
    var createdAt: Date = Date()

    // Contenu source brut
    /// Phrase exacte sélectionnée dans la source.
    var rawSnippet: String = ""           // phrase exacte sélectionnée
    /// Contexte (~2 phrases) précédant le snippet, pour préserver le sens.
    var contextBefore: String = ""        // ~2 phrases avant
    /// Contexte (~2 phrases) suivant le snippet, pour préserver le sens.
    var contextAfter: String = ""         // ~2 phrases après

    /// Texte rédigé (par IA puis éventuellement édité par l'utilisateur) au
    /// moment de l'ajout : combine snippet + contexte + projet en un texte
    /// autonome et lisible. Affiché dans Suivi manager / Agenda manager à la
    /// place du `rawSnippet` quand non-vide. Utilisé en priorité par
    /// `ManagerCRGenerator.buildPrompt` pour décrire le point.
    var elaboratedText: String = ""

    // Localisation source pour le highlight jaune
    /// Champ source du snippet, parmi `"transcript"` (= rawTranscript),
    /// `"mergedTranscript"`, `"summary"`, `"notes"`, `"liveNotes"`, ou
    /// `"manual"` pour un ajout manuel.
    var sourceField: String = "manual"
    /// Offset de départ UTF-16 (compatible NSRange) du snippet dans la source.
    var sourceRangeStart: Int = 0          // offset UTF-16 (NSRange-compatible)
    /// Longueur UTF-16 (compatible NSRange) du snippet dans la source.
    var sourceRangeLength: Int = 0

    // Classification
    /// Catégorie de classement : une valeur de `AppSettings.managerCategories`
    /// ou un libellé libre.
    var category: String = "Information"   // valeur dans AppSettings.managerCategories ou libre
    var tag: String = ""
    /// Catégorie proposée par l'IA, conservée pour audit (peut différer de `category`).
    var aiSuggestedCategory: String?       // ce que l'IA a proposé (audit)

    // Saisie utilisateur pendant le 1:1 manager
    var userNotes: String = ""

    // État
    var isCompleted: Bool = false
    var archivedAt: Date?                  // != nil → hors du rapport courant
    var manualOrder: Int = 0
    var isManual: Bool = false

    // Doublon possible (cf. décision Q10-D du spec)
    /// PID d'un autre item considéré comme doublon (overlap > 50% sur la même
    /// source). Stocké en string (UUID stableID de l'autre item) pour rester
    /// migration-friendly — PersistentIdentifier ne sérialise pas bien.
    var duplicateOfStableID: String = ""

    // Relations
    var sourceMeeting: Meeting?
    var archivedInMeeting: Meeting?

    init(rawSnippet: String,
         sourceField: String,
         sourceRangeStart: Int,
         sourceRangeLength: Int,
         sourceMeeting: Meeting?) {
        self.stableID = UUID()
        self.rawSnippet = rawSnippet
        self.sourceField = sourceField
        self.sourceRangeStart = sourceRangeStart
        self.sourceRangeLength = sourceRangeLength
        self.sourceMeeting = sourceMeeting
    }

    /// Convenience init pour ajout manuel (pas de sélection source).
    convenience init(manualSnippet: String, category: String) {
        self.init(rawSnippet: manualSnippet,
                  sourceField: "manual",
                  sourceRangeStart: 0,
                  sourceRangeLength: 0,
                  sourceMeeting: nil)
        self.isManual = true
        self.category = category
    }

    /// Renvoie le `stableID`, en le générant et le persistant (`save()`) au
    /// premier accès s'il était nil (migration). Effet de bord : sauvegarde.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}

// MARK: - ManagerMeetingReport
//
// Compte-rendu spécifique généré pour une réunion `kind == .manager`.
// Distinct du `summary` standard du Meeting — permet regen sans écrasement.

/// Compte-rendu généré pour une réunion `kind == .manager`. Distinct du
/// `summary` standard du Meeting afin de permettre la régénération sans
/// écraser ce dernier. Persisté via SwiftData.
@Model
final class ManagerMeetingReport {
    /// Optional — see SwiftData migration caveat. Use `ensuredStableID`
    /// when you need a guaranteed non-nil UUID.
    var stableID: UUID? = nil
    var generatedAt: Date = Date()
    var generatedSummary: String = ""        // markdown
    var durationSeconds: Double = 0
    var modelUsed: String = ""

    /// Snapshot JSON figé des items abordés au moment de la génération.
    /// Source de vérité pour la regénération (les items physiques peuvent
    /// avoir bougé depuis).
    var itemsSnapshotJSON: String = "[]"

    /// Actions extraites par l'IA (titre, dueDate ISO). Avant matérialisation
    /// en ActionTask via le sheet de revue.
    var extractedActionsJSON: String = "[]"

    var meeting: Meeting?

    init(meeting: Meeting? = nil) {
        self.stableID = UUID()
        self.meeting = meeting
    }

    /// Renvoie le `stableID`, en le générant et le persistant (`save()`) au
    /// premier accès s'il était nil (migration). Effet de bord : sauvegarde.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }
}
