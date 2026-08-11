import Foundation
import SwiftData


@Model
final class Collaborator {
    var stableID: UUID? = nil
    var name: String
    var role: String
    var isArchived: Bool = false
    var photoPath: String = ""
    var photoBookmarkData: Data?
    /// Adresse email du collaborateur, utilisée pour pré-remplir les
    /// destinataires lors de l'export d'un compte-rendu de réunion.
    /// Renseigné automatiquement à partir des invitations Calendar.
    var email: String = ""

    /// Pinning level in the sidebar: 0 = hidden, 1 = favourite, 2 = pinned.
    var pinLevel: Int = 0

    /// Rythme convenu des tête-à-tête (Raw + wrapper — contournement enum
    /// SwiftData). Défaut `aucune` : c'est lui qui décide si un écart se
    /// colore en retard, et l'app ne suppose aucun rythme à la place de
    /// l'utilisateur.
    var oneToOneCadenceRaw: String = OneToOneCadence.aucune.rawValue
    var oneToOneCadence: OneToOneCadence {
        get { OneToOneCadence(rawValue: oneToOneCadenceRaw) ?? .aucune }
        set { oneToOneCadenceRaw = newValue.rawValue }
    }

    /// Entité de rattachement de la personne. `Entity` ne reliait jusqu'ici
    /// que les projets.
    var entity: Entity?

    /// Manager de la personne. `nil` vaut « Moi » — le propriétaire de l'app.
    var manager: Collaborator?

    /// Marks a collaborator created ad-hoc from a meeting (reusable afterwards).
    var isAdhoc: Bool = false

    /// Notes de préparation persistantes pour la prochaine 1:1 / manager.
    /// Drainées dans `Meeting.prepNotes` à la création d'une meeting 1:1/manager
    /// avec ce collab ; repeuplées au carryover des items non cochés post-meeting.
    var standingPrepNotes: String = ""
    var standingPrepUpdatedAt: Date?

    // MARK: - Voice identification (speech-swift WeSpeaker ResNet34)
    /// Empreinte vocale : embedding moyen de 256 Float32 (1024 octets) produit
    /// par le modèle WeSpeaker ResNet34. Comparée par cosinus aux embeddings de
    /// clusters par `SpeakerMatcher` pour rattacher un locuteur à ce collab.
    /// Nil = jamais enrôlé. Mis à jour en EMA (cf. `voicePrintSamples`).
    var voicePrint: Data?
    /// Nombre d'updates EMA agrégées (pondère les mises à jour).
    var voicePrintSamples: Int = 0
    /// Date du dernier update (debug + audit).
    var voicePrintUpdatedAt: Date?


    @Relationship(deleteRule: .nullify, inverse: \ActionTask.collaborator)
    var assignedTasks: [ActionTask] = []

    @Relationship(deleteRule: .nullify, inverse: \Meeting.participants)
    var meetings: [Meeting] = []

    /// Projets où ce collab est désigné Chef de projet (reverse query).
    @Relationship(inverse: \Project.projectManager)
    var projectsAsManager: [Project] = []

    /// Projets où ce collab est désigné Architecte technique (reverse query).
    @Relationship(inverse: \Project.technicalArchitect)
    var projectsAsArchitect: [Project] = []

    init(name: String, role: String = "Architecte", isArchived: Bool = false) {
        self.stableID = UUID()
        self.name = name
        self.role = role
        self.isArchived = isArchived
    }

    /// Retourne `stableID` en backfillant un nouvel UUID si la DB contient `nil`
    /// (cas des collabs créés avant l'ajout du champ).
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    func photoURL() -> URL? {
        guard !photoPath.isEmpty else { return nil }

        if let photoBookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: photoBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolvedURL
            }
        }

        return URL(fileURLWithPath: photoPath)
    }
}



/// Destinataire d'une action : à qui/quoi elle se rapporte.
enum ActionAudience: String, Codable, CaseIterable, Sendable {
    case collaborateur   // déléguée à un collaborateur (assignee = `collaborator`)
    case moi             // pour moi
    case chef            // à remonter à mon manager

    var label: String {
        switch self {
        case .collaborateur: return "Collaborateur"
        case .moi:           return "Moi"
        case .chef:          return "Chef"
        }
    }

    /// Titre de section dans la vue groupée.
    var sectionTitle: String {
        switch self {
        case .collaborateur: return "Déléguées"
        case .moi:           return "Mes actions"
        case .chef:          return "À remonter au chef"
        }
    }

    var systemImage: String {
        switch self {
        case .collaborateur: return "person.2.fill"
        case .moi:           return "person.fill"
        case .chef:          return "arrow.up.forward.circle.fill"
        }
    }
}

@Model
final class ActionTask {
    var title: String
    var project: Project?
    var meeting: Meeting?
    var collaborator: Collaborator?
    var dueDate: Date?
    var isCompleted: Bool = false
    var reminderID: String?

    /// Destinataire (Raw + wrapper — contournement enum SwiftData). Défaut : moi.
    var destinataireRaw: String = ActionAudience.moi.rawValue
    var destinataire: ActionAudience {
        get { ActionAudience(rawValue: destinataireRaw) ?? .moi }
        set { destinataireRaw = newValue.rawValue }
    }
    /// Axes Eisenhower (urgent × important).
    var isUrgent: Bool = false
    var isImportant: Bool = false
    /// Charge estimée en pomodoros (1 🍅 = 25 min). 0 = non estimée.
    var pomodoros: Int = 0
    /// Ordre manuel (vues Kanban/Timeline ultérieures).
    var sortOrder: Int = 0

    /// Date à laquelle cette action, née en tête-à-tête, a été **explicitement
    /// reprise** — donc soldée en tant qu'engagement sans avoir été cochée.
    /// `nil` tant qu'elle traîne. Sans objet pour une action née ailleurs.
    var engagementSettledAt: Date? = nil

    /// True when the task was extracted from a 1:1 manager CR.
    var fromManager: Bool = false
    var managerMeeting: Meeting?

    /// Creation and completion timestamps. Optional so existing rows
    /// keep nil and we display "Date inconnue" rather than crashing.
    var createdAt: Date? = nil
    var completedAt: Date? = nil
    /// Quand l'extraction LLM 2e passe renvoie un nom d'assignee qui ne matche
    /// AUCUN collaborator (même via CollaboratorMatcher fuzzy), on stocke le
    /// nom brut ici. L'UI affiche un chip orange "💡 Auto : <nom>" cliquable
    /// qui ouvre la sheet de recherche pré-remplie sur ce nom.
    var unresolvedAssigneeName: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \ActionComment.task)
    var comments: [ActionComment] = []

    init(title: String, dueDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.createdAt = Date()
    }
}

@Model
final class ActionComment {
    var date: Date
    var text: String
    var task: ActionTask?

    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }
}

@Model
final class ProjectAlert {
    var title: String
    var detail: String
    var severityRaw: String  // Critique, Élevé, Modéré, Faible
    var date: Date
    var isResolved: Bool = false
    var project: Project?
    /// Lien vers la réunion qui a soulevé l'alerte (rendu dans la meta-table
    /// du rapport sous forme de callout cream).
    var meeting: Meeting?

    var severity: String { severityRaw }

    init(title: String, detail: String = "", severity: String = "Modéré", date: Date = Date()) {
        self.title = title
        self.detail = detail
        self.severityRaw = severity
        self.date = date
    }
}

/// Une réunion enregistrée : audio, transcription, diarization, rapport généré
/// et préparation. Agrège participants, tâches, alertes et révisions de rapport.
/// Plusieurs `kind` (1:1, manager, projet, global, séance de travail) partagent
/// ce modèle ; certains champs (préparation, locuteurs) ne valent que pour
/// certains kinds.
@Model
final class Meeting {
    /// Stable UUID safe to expose in filenames / external IDs.
    /// SwiftData `persistentModelID` is not usable as a string identifier.
    /// Optional so that lightweight migration on existing rows doesn't apply
    /// the same `UUID()` default to every legacy row — those get `nil` and
    /// are backfilled with unique UUIDs at startup via `repairStoreIfNeeded`.
    var stableID: UUID? = nil
    var title: String
    var date: Date
    var notes: String
    var project: Project?

    // Meeting kind (stored as raw, exposed as MeetingKind)
    var kindRaw: String = MeetingKind.global.rawValue
    var kind: MeetingKind {
        get { MeetingKind(rawValue: kindRaw) ?? .global }
        set { kindRaw = newValue.rawValue }
    }

    // Custom prompt / live note
    var customPrompt: String = ""
    var liveNotes: String = ""

    // Transcription
    var rawTranscript: String = ""
    var mergedTranscript: String = ""

    // Generated report
    var summary: String = ""
    /// Résumé court (≤10 lignes) affiché dans la carte « Résumé » de la Vue
    /// d'ensemble ; généré à la demande via `AIClient`, indépendant du Rapport.
    var shortSummary: String = ""
    var keyPointsJSON: String = "[]"
    var decisionsJSON: String = "[]"
    var openQuestionsJSON: String = "[]"

    /// Snapshot in-flight de la préparation pour cette meeting précise.
    /// Flux complet : (1) DRAIN — à la création / 1re ouverture du tab
    /// Préparation, le pool `standingPrepNotes` du collab (kinds .oneToOne/
    /// .manager) ou du projet (.project) est copié ici une seule fois
    /// (idempotent via `prepDrainDone`). Pour .global/.work, édité directement,
    /// sans pool. (2) PREP — l'utilisateur édite ces notes avant la réunion.
    /// (3) CARRYOVER — en fin de transcription, les items non cochés sont
    /// reversés dans le pool standing (idempotent via `prepCarryoverDone`).
    var prepNotes: String = ""
    var prepGeneratedAt: Date?
    /// Flag idempotence du drain (pool standing → meeting) à la création/
    /// première ouverture du tab Préparation.
    var prepDrainDone: Bool = false
    /// Flag idempotence du carryover (meeting → pool standing) en fin de
    /// transcription.
    var prepCarryoverDone: Bool = false

    // MARK: - Métadonnées d'en-tête rapport
    /// Personnes/équipes mentionnées dans la séance mais non présentes
    /// (affiché dans la meta-table d'en-tête du rapport).
    /// Format libre (ex: "Zied (embarquement) · Nicolas Hauvinet · Travaux McKinsey").
    var referencedAbsent: String = ""
    /// Prochaine échéance / jalon à venir (affiché dans la meta-table).
    /// Format libre (ex: "Partage du modèle avec N. Hauvinet, puis présentation
    /// à la prochaine réunion McKinsey").
    var nextDeadline: String = ""

    // Audio
    /// Marqué comme "à conserver" — exclus du cleanup automatique.
    var keepWavForever: Bool = false
    /// Indique que `wavFilePath` pointe vers un .m4a compressé (AAC 32 kbps mono)
    /// au lieu d'un .wav original.
    var wavIsCompressed: Bool = false
    var wavFilePath: String?
    /// Durée d'enregistrement audio (≠ durée réelle de la réunion).
    var durationSeconds: Int = 0
    /// Durée réelle de la réunion en secondes (event Calendar end-start).
    /// Sert au calcul du temps passé. Fallback sur `durationSeconds` si 0.
    var meetingDurationSeconds: Int = 0

    // Calendar
    var calendarEventID: String = ""
    var calendarEventTitle: String = ""

    // MARK: - Calendar integration (optional — lightweight migration safe)
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var teamsJoinURL: String?

    // Report metadata
    /// Durée de la dernière génération de rapport, en secondes (0 si jamais
    /// généré). Utilisé pour afficher "Rapport ✓ (2:34)" et donner un repère
    /// utilisateur sur le coût IA.
    var reportGenerationDurationSeconds: Double = 0

    // Participant statuses / ad-hoc attendees (JSON-encoded)
    var participantStatusesJSON: String = "{}"
    var adhocAttendeesJSON: String = "[]"

    /// JSON: {clusterID(String): "collabStableID|null"}.
    /// Source de vérité du mapping cluster → Collaborator décidé par
    /// SpeakerMatcher (auto ou manuel). Bulk-re-assign sur correction user.
    var speakerAssignmentsJSON: String = "{}"

    /// JSON: {clusterID(String): {"confidence":Double, "auto":Bool, "ambiguous":Bool, "candidates":[stableID]}}.
    /// Métadonnée UI (badge ✓ auto / ? suggestion).
    var speakerMatchMetaJSON: String = "{}"

    @Relationship(deleteRule: .nullify)
    var participants: [Collaborator] = []

    /// Thèmes libres de la réunion (transverses au projet / type / participants).
    /// Many-to-many `.nullify` : l'inverse est déclaré sur `MeetingTag.meetings`.
    @Relationship(deleteRule: .nullify)
    var tags: [MeetingTag] = []

    @Relationship(deleteRule: .cascade, inverse: \ActionTask.meeting)
    var tasks: [ActionTask] = []

    @Relationship(deleteRule: .cascade, inverse: \MeetingAttachment.meeting)
    var attachments: [MeetingAttachment] = []

    /// Alertes soulevées pendant cette réunion (rendues comme callouts cream
    /// dans le rapport). Extraites par `AIReportService.extractStructured`
    /// puis reliées via `apply(report:)`.
    @Relationship(deleteRule: .cascade, inverse: \ProjectAlert.meeting)
    var meetingAlerts: [ProjectAlert] = []

    @Relationship(deleteRule: .cascade, inverse: \TranscriptChunk.meeting)
    var transcriptChunks: [TranscriptChunk] = []

    /// Segments timestampés (sub-projet D : diarization). Optionnel — vide
    /// pour les meetings transcrits avant l'introduction des segments.
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var transcriptSegments: [TranscriptSegment] = []

    /// Historique des révisions du rapport (Writer/Critique loop). Version
    /// 1 = draft initial, suivantes = post-critique. Cascade delete.
    @Relationship(deleteRule: .cascade, inverse: \ReportRevision.meeting)
    var reportRevisions: [ReportRevision] = []

    // MARK: - Report template (chosen at create, overridable)
    var reportTemplate: ReportTemplate?

    init(title: String = "", date: Date = Date(), notes: String = "") {
        self.stableID = UUID()
        self.title = title
        self.date = date
        self.notes = notes
    }

    /// Returns `stableID`, backfilling a fresh UUID if the row predates the
    /// Optional migration. Persists the backfill immediately.
    var ensuredStableID: UUID {
        if let stableID { return stableID }
        let new = UUID()
        self.stableID = new
        try? modelContext?.save()
        return new
    }

    // MARK: - JSON-backed arrays
    // Façades typées au-dessus des colonnes `*JSON` (array de String encodé).
    // Le stockage reste JSON pour rester migration-safe côté SwiftData.

    /// Tout le texte libre que porte cette réunion, étiqueté.
    ///
    /// **Énumération unique.** Deux lecteurs doivent rester en phase : la
    /// recherche `/cherche` de l'assistant, qui affiche l'étiquette de chaque
    /// occurrence, et `NoteFactory.isDiscardableEmptyNote`, qui n'en lit que
    /// le texte pour décider si une note ne porte rien. Deux listes séparées
    /// avaient déjà divergé — un champ oublié dans l'une rend un texte
    /// introuvable, oublié dans l'autre le fait supprimer sans confirmation.
    /// Un champ texte ajouté à `Meeting` se déclare **ici**, une fois.
    ///
    /// La transcription n'y figure qu'une fois — la fusionnée, ou la brute à
    /// défaut : `/cherche` n'en affiche qu'une, et « la fusionnée sinon la
    /// brute » n'est vide que si les deux le sont, ce dont le prédicat se
    /// contente.
    var textualContent: [(label: String, text: String)] {
        var content: [(label: String, text: String)] = [
            ("titre", title),
            ("rapport", summary),
            ("résumé court", shortSummary),
            ("notes", notes),
            ("notes live", liveNotes),
            ("transcription", mergedTranscript.isEmpty ? rawTranscript : mergedTranscript),
            ("prompt", customPrompt),
            ("calendrier", calendarEventTitle),
            ("préparation", prepNotes),
            ("absents cités", referencedAbsent),
            ("prochaine échéance", nextDeadline)
        ]
        content += keyPoints.map { ("point clé", $0) }
        content += decisions.map { ("décision", $0) }
        content += openQuestions.map { ("question", $0) }
        return content
    }

    /// Points clés du rapport, vue tableau au-dessus de `keyPointsJSON`.
    var keyPoints: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(keyPointsJSON.utf8))) ?? [] }
        set { keyPointsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    /// Décisions prises **avec leur état de solde** — la vue complète de
    /// `decisionsJSON`. Voir `DecisionEntry` pour les deux formes acceptées.
    var decisionEntries: [DecisionEntry] {
        get { (try? JSONDecoder().decode([DecisionEntry].self, from: Data(decisionsJSON.utf8))) ?? [] }
        set { decisionsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    /// Décisions prises, vue tableau au-dessus de `decisionsJSON`. Conservée
    /// telle quelle : la génération de rapport, les gabarits, l'export et
    /// l'assistant la lisent.
    ///
    /// L'écriture **préserve le solde des décisions qui survivent** : la
    /// régénération d'un rapport réécrit la liste en bloc, et un engagement
    /// tenu ressusciterait sinon à chaque rapport.
    var decisions: [String] {
        get { decisionEntries.map(\.text) }
        set {
            let anciens = Dictionary(decisionEntries.map { ($0.text, $0.settledAt) },
                                     uniquingKeysWith: { premier, _ in premier })
            decisionEntries = newValue.map { DecisionEntry(text: $0, settledAt: anciens[$0] ?? nil) }
        }
    }

    /// Solde la décision de rang `index`. Sans effet si le rang n'existe pas.
    func settleDecision(at index: Int, on date: Date = Date()) {
        var entries = decisionEntries
        guard entries.indices.contains(index) else { return }
        entries[index].settledAt = date
        decisionEntries = entries
    }

    /// Questions ouvertes, vue tableau au-dessus de `openQuestionsJSON`.
    var openQuestions: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(openQuestionsJSON.utf8))) ?? [] }
        set { openQuestionsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

    // MARK: - Convenience

    /// Resolved URL for the recorded WAV, nil if the file path is empty.
    var wavFileURL: URL? {
        guard let path = wavFilePath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

extension Meeting {
    enum AudioAvailability {
        case original     // .wav présent
        case compressed   // .m4a présent
        case deleted      // wavFilePath nil ou fichier absent
    }

    var audioAvailability: AudioAvailability {
        guard let path = wavFilePath, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return .deleted
        }
        return wavIsCompressed ? .compressed : .original
    }

    var hasPlayableAudio: Bool { audioAvailability != .deleted }
}
