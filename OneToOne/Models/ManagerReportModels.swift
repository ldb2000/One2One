import Foundation
import SwiftData

// MARK: - ManagerReportItem
//
// Un point à aborder avec mon manager. Créé soit par sélection (item issu d'une
// transcription / rapport / notes) soit manuellement. Coché pendant le 1:1 manager,
// archivé à la génération du CR.

@Model
final class ManagerReportItem {
    var stableID: UUID = UUID()
    var createdAt: Date = Date()

    // Contenu source brut
    var rawSnippet: String = ""           // phrase exacte sélectionnée
    var contextBefore: String = ""        // ~2 phrases avant
    var contextAfter: String = ""         // ~2 phrases après

    /// Texte rédigé (par IA puis éventuellement édité par l'utilisateur) au
    /// moment de l'ajout : combine snippet + contexte + projet en un texte
    /// autonome et lisible. Affiché dans Suivi manager / Agenda manager à la
    /// place du `rawSnippet` quand non-vide. Utilisé en priorité par
    /// `ManagerCRGenerator.buildPrompt` pour décrire le point.
    var elaboratedText: String = ""

    // Localisation source pour le highlight jaune
    // sourceField ∈ {"transcript", "mergedTranscript", "summary", "notes", "liveNotes"}
    // (transcript = rawTranscript). Pour ajout manuel : sourceField = "manual".
    var sourceField: String = "manual"
    var sourceRangeStart: Int = 0          // offset UTF-16 (NSRange-compatible)
    var sourceRangeLength: Int = 0

    // Classification
    var category: String = "Information"   // valeur dans AppSettings.managerCategories ou libre
    var tag: String = ""
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
}

// MARK: - ManagerMeetingReport
//
// Compte-rendu spécifique généré pour une réunion `kind == .manager`.
// Distinct du `summary` standard du Meeting — permet regen sans écrasement.

@Model
final class ManagerMeetingReport {
    var stableID: UUID = UUID()
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
        self.meeting = meeting
    }
}
