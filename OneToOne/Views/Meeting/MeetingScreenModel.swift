import Foundation
import Observation

/// Tout ce que l'écran de réunion sait de lui-même : quel espace est affiché,
/// à quel moment de la réunion on se trouve, et le brouillon d'action en cours
/// de saisie.
///
/// Remplace les `@State` de `MeetingView` qui descendaient en `@Binding` sur
/// deux niveaux (`MeetingView` → `OverviewDashboard` → `ActionsPanel`) : le
/// programme de refonte interdit désormais tout `@Binding` traversant plus d'un
/// niveau, et cette classe est l'unique porteuse de cet état.
///
/// Ce qui est **mémorisé** d'une ouverture à l'autre : l'espace et le mode, par
/// réunion, dans `UserDefaults`. Le mode est un état d'écran, pas une donnée :
/// il n'a pas de colonne dans `Meeting` (programme §3). Ce qui n'est **pas**
/// mémorisé : le brouillon d'action et les bascules d'affichage, qui repartent
/// des défauts à chaque ouverture — exactement comme les `@State` qu'ils
/// remplacent.
@MainActor
@Observable
final class MeetingScreenModel {

    /// Les trois espaces de la spec §1.1. Valeurs brutes stables : elles sont
    /// écrites dans `UserDefaults`, donc on ne les renomme pas sans migration.
    enum Space: String, CaseIterable, Sendable {
        case meeting
        case report
        case resources

        /// Libellé de la barre d'espaces (capture `1a-cockpit.png`). Le cas
        /// particulier de la note passe par
        /// `MeetingSpaceRouting.meetingSpaceLabel(for:)`, qui connaît le type.
        var label: String {
            switch self {
            case .meeting:   return "Réunion"
            case .report:    return "Rapport"
            case .resources: return "Ressources"
            }
        }
    }

    /// Le sous-mode temporel de la spec §1.1. Il ne change pas la navigation,
    /// il change la disposition par défaut et le focus clavier.
    enum Mode: String, CaseIterable, Sendable {
        case prepare
        case live
        case review

        /// Libellé du sélecteur segmenté (capture `1a-cockpit.png`).
        var label: String {
            switch self {
            case .prepare: return "Préparer"
            case .live:    return "En séance"
            case .review:  return "Relire"
            }
        }
    }

    // MARK: - Espace et moment

    var space: Space = .meeting {
        didSet { persistSpace() }
    }

    var mode: Mode = .live {
        didSet { persistMode() }
    }

    // MARK: - Brouillon d'action

    var newTaskTitle = ""
    var selectedCollaborator: Collaborator?
    var showNewTaskDueDate = false
    var newTaskDueDate: Date?
    var newTaskAudience: ActionAudience = .moi
    var newTaskUrgent = false
    var newTaskImportant = false
    var newTaskPomodoros = 0
    /// Le défaut malin du destinataire n'est appliqué qu'une fois par écran
    /// (cf. `MeetingView.applyActionDraftDefaultsIfNeeded`).
    var didApplyActionDefaults = false

    // MARK: - Brouillon de note

    /// Le texte en cours dans le composeur de note, pas encore validé.
    ///
    /// Vit ici et non dans la vue parce que le critère d'acceptation n° 4 du
    /// chantier 1 l'exige : « le passage Préparer → En séance → Relire ne perd
    /// aucune saisie en cours ». Un `@State` de la colonne de notes serait
    /// détruit avec elle au changement de mode ; le brouillon d'action, lui,
    /// avait déjà déménagé pour la même raison.
    ///
    /// Non persisté : une note à moitié écrite est une intention du moment,
    /// pas une donnée. Le composeur qui la consomme arrive au lot 2.
    var pendingNoteText = ""

    // MARK: - Bascules d'affichage

    /// Affiche les locuteurs dans la transcription.
    var showSpeakers = true
    /// La barre de lecture audio est dépliée.
    var showPlayback = false
    /// La transcription suit la tête de lecture. Consommé à partir du lot 2 ;
    /// porté ici parce que c'est un état d'écran et qu'il n'a pas d'autre
    /// domicile.
    var follow = true

    // MARK: - Tête de lecture

    /// La tête de lecture **de cette réunion**, créée au premier accès.
    ///
    /// Le lot 0B l'avait confiée à un registre statique borné en LRU
    /// (`MeetingPlayhead.for(meeting:)`), faute de propriétaire : `MeetingView`
    /// est une `struct` qui ne peut rien retenir sans initialiseur explicite.
    /// Ce modèle-là est ce propriétaire — un par réunion ouverte, détruit avec
    /// l'écran. Plus de registre global, donc plus d'éviction à contretemps ni
    /// de lecteur qui joue sans surface pour l'arrêter.
    /// `@ObservationIgnored` : l'instance est créée paresseusement **dans le
    /// getter**, qui peut être appelé pendant un rendu. Observée, cette
    /// écriture invaliderait la vue en cours de calcul. Ce qui doit être
    /// observé, c'est la tête de lecture elle-même (`@Observable` de son côté),
    /// pas la case qui la retient.
    @ObservationIgnored private var storedPlayhead: MeetingPlayhead?

    var playhead: MeetingPlayhead {
        if let storedPlayhead { return storedPlayhead }
        // Sans rattachement, la tête de lecture reçoit tout de même un
        // identifiant : elle est alors purement locale, jamais partagée.
        let nouvelle = MeetingPlayhead(meetingStableID: meetingID ?? UUID())
        storedPlayhead = nouvelle
        return nouvelle
    }

    /// Cale la tête de lecture sur l'état réel de la réunion : si son
    /// enregistrement tourne, l'axe repart de `recordingStartedAt` — sinon les
    /// notes posées après une réouverture d'écran seraient horodatées à zéro.
    func attachPlayhead(meeting: Meeting) {
        let tete = playhead
        guard let startedAt = meeting.recordingStartedAt,
              AudioRecorderService.shared.isRecording(for: meeting.ensuredStableID) else { return }
        tete.beginRecording(startedAt: startedAt)
    }

    // MARK: - Saisies éphémères des surfaces filles

    /// Nom en cours de saisie dans la modale de gestion des participants.
    var newAdhocName = ""
    /// Thèmes proposés par l'IA, en attente d'acceptation. Éphémères, non
    /// persistés : régénérés à chaque rapport ou à la demande, jamais appliqués
    /// d'office.
    var suggestedTagNames: [String] = []

    // MARK: - Mémorisation

    private let defaults: UserDefaults
    private var meetingID: UUID?
    /// Vrai pendant la relecture de `UserDefaults` : `didSet` ne doit pas
    /// réécrire la valeur qu'on vient d'en lire.
    private var isRestoring = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let prefix = "onetoone.meetingScreen"

    static func spaceKey(for meetingID: UUID) -> String {
        "\(prefix).space.\(meetingID.uuidString)"
    }

    static func modeKey(for meetingID: UUID) -> String {
        "\(prefix).mode.\(meetingID.uuidString)"
    }

    /// Rattache le modèle à une réunion et relit l'espace et le mode mémorisés.
    ///
    /// Idempotent : appelé depuis `.onAppear`, qui peut se déclencher plusieurs
    /// fois pour un même écran. Un second appel pour la même réunion ne relit
    /// rien — sinon il écraserait le choix que l'utilisateur vient de faire.
    func attach(meetingID: UUID) {
        guard self.meetingID != meetingID else { return }
        self.meetingID = meetingID
        // Une tête de lecture créée avant le rattachement porte un identifiant
        // d'emprunt : elle est jetée pour que `playhead.meetingStableID` dise
        // toujours la vérité (c'est lui qui nomme les fichiers et les journaux).
        if let ancienne = storedPlayhead, ancienne.meetingStableID != meetingID {
            ancienne.player.pause()
            storedPlayhead = nil
        }
        isRestoring = true
        space = Space(rawValue: defaults.string(forKey: Self.spaceKey(for: meetingID)) ?? "") ?? .meeting
        mode = Mode(rawValue: defaults.string(forKey: Self.modeKey(for: meetingID)) ?? "") ?? .live
        isRestoring = false
    }

    private func persistSpace() {
        guard !isRestoring, let meetingID else { return }
        defaults.set(space.rawValue, forKey: Self.spaceKey(for: meetingID))
    }

    private func persistMode() {
        guard !isRestoring, let meetingID else { return }
        defaults.set(mode.rawValue, forKey: Self.modeKey(for: meetingID))
    }

    // MARK: - Brouillon

    /// Vide le brouillon après création d'une action, **sans** toucher au
    /// destinataire ni au collaborateur choisi : le composeur doit rester prêt
    /// à saisir la ligne suivante pour la même personne.
    func resetActionDraft() {
        newTaskTitle = ""
        newTaskDueDate = nil
        showNewTaskDueDate = false
        newTaskUrgent = false
        newTaskImportant = false
        newTaskPomodoros = 0
    }

    // MARK: - Lot 2 : notes ↔ transcription

    /// Filtre de nature de la colonne de notes. `nil` = tout est affiché.
    ///
    /// Alimenté par la carte Décisions du bandeau d'indicateurs (spec §2.3 :
    /// « Clic = filtre les notes sur `kind:'decision'` »). État d'écran, non
    /// persisté : un filtre retrouvé trois jours plus tard passerait pour une
    /// colonne vide.
    var noteFilter: MeetingNoteKind?

    /// Intention « ouvrir le composeur d'action prérempli » (spec §2.4).
    ///
    /// Posée par `/action` dans le composeur de notes et par `＋ Action` sur un
    /// segment de transcription. Le rail qui la consomme — et qui animera
    /// l'insertion en tête — arrive au lot 3 ; d'ici là, `requestAction`
    /// préremplit le composeur existant, et la source reste lisible ici.
    var pendingActionDraft: ActionFromPhrase.Draft?

    /// Jeton de focus du composeur de notes, incrémenté par `⌘⇧N`.
    ///
    /// Un jeton et non un booléen : deux `⌘⇧N` de suite doivent tous les deux
    /// rendre le clavier au champ, or la seconde écriture d'un booléen déjà
    /// vrai ne notifie personne.
    private(set) var noteComposerFocusToken = 0

    /// Embeddings du dernier passage de diarisation, par cluster.
    ///
    /// Vivait en `@State` dans `MeetingView`, entre la fonction qui lance la
    /// diarisation et le badge de locuteur qui met à jour le voiceprint (EMA).
    /// Le badge a déménagé au lot 2 (`TranscriptSpeakerTools`) : le cache doit
    /// donc vivre là où les deux le voient.
    var lastDiarizationEmbeddings: [Int: [Float]] = [:]

    /// Demande le focus du composeur de notes.
    func focusNoteComposer() {
        noteComposerFocusToken += 1
    }

    /// Pose l'intention de créer une action depuis une phrase et préremplit le
    /// composeur du rail.
    func requestAction(from draft: ActionFromPhrase.Draft) {
        pendingActionDraft = draft
        newTaskTitle = draft.title
    }

    /// Active le filtre de notes sur `kind`, ou le retire si c'est déjà lui.
    /// Un filtre qu'on ne sait pas relâcher est un cul-de-sac.
    func toggleNoteFilter(_ kind: MeetingNoteKind) {
        noteFilter = (noteFilter == kind) ? nil : kind
    }
}
