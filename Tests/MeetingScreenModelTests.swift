import Testing
import Foundation
@testable import OneToOne

/// « Le mode est un état d'écran, pas une donnée. » — programme de refonte §3,
/// à propos de `Meeting.mode`.
///
/// Ce que l'écran de réunion sait de lui-même (quel espace, quel moment, quel
/// brouillon d'action en cours) vivait dans une cinquantaine de `@State` de
/// `MeetingView`, dont huit descendaient en `@Binding` sur deux niveaux. Cette
/// suite fixe le contrat du modèle unique qui les remplace — en particulier ce
/// qui se mémorise d'une ouverture à l'autre, et ce qui ne doit pas.
@Suite("MeetingScreenModel — l'état d'écran d'une réunion")
@MainActor
struct MeetingScreenModelTests {

    /// `UserDefaults` isolé par test : `.standard` polluerait le poste et
    /// rendrait l'ordre des tests significatif.
    private func makeDefaults(_ nom: String = UUID().uuidString) -> UserDefaults {
        let suite = "MeetingScreenModelTests.\(nom)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("À l'ouverture, une réunion jamais vue s'affiche sur l'espace Réunion, en séance")
    func defaultsAreMeetingAndLive() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        #expect(model.space == .meeting)
        #expect(model.mode == .live)
    }

    @Test("L'espace et le mode choisis sont retrouvés à la réouverture de la même réunion")
    func spaceAndModeArePersistedPerMeeting() {
        let defaults = makeDefaults()
        let id = UUID()

        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.space = .resources
        premier.mode = .review

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.space == .resources)
        #expect(second.mode == .review)
    }

    @Test("Deux réunions ne partagent pas leur espace ni leur mode")
    func memoryIsPerMeeting() {
        let defaults = makeDefaults()
        let premiere = UUID(), seconde = UUID()

        let a = MeetingScreenModel(defaults: defaults)
        a.attach(meetingID: premiere)
        a.space = .report
        a.mode = .prepare

        let b = MeetingScreenModel(defaults: defaults)
        b.attach(meetingID: seconde)
        #expect(b.space == .meeting)
        #expect(b.mode == .live)
    }

    @Test("Une valeur mémorisée illisible ne casse rien : on retombe sur le défaut")
    func corruptStoredValueFallsBack() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set("espace-inconnu", forKey: MeetingScreenModel.spaceKey(for: id))
        defaults.set(42, forKey: MeetingScreenModel.modeKey(for: id))

        let model = MeetingScreenModel(defaults: defaults)
        model.attach(meetingID: id)
        #expect(model.space == .meeting)
        #expect(model.mode == .live)
    }

    @Test("`attach` est idempotent et ne réécrit pas ce qui vient d'être choisi")
    func attachIsIdempotent() {
        // `.onAppear` peut se déclencher plusieurs fois pour un même écran :
        // un second `attach` qui relirait `UserDefaults` écraserait le choix
        // que l'utilisateur vient de faire.
        let defaults = makeDefaults()
        let id = UUID()
        let model = MeetingScreenModel(defaults: defaults)
        model.attach(meetingID: id)
        model.mode = .review
        model.attach(meetingID: id)
        #expect(model.mode == .review)
    }

    /// Critère du lot 1 (« changement de mode sans perte de saisie ») : le
    /// brouillon ne dépend pas du mode, donc changer de mode ne peut pas le
    /// vider. Le test le fige dès maintenant, avant que la vue existe.
    @Test("Changer d'espace ou de mode ne touche pas au brouillon d'action en cours")
    func changingModeKeepsTheDraft() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.newTaskTitle = "Chiffrer la fin de migration Marine"
        model.newTaskUrgent = true
        model.newTaskPomodoros = 2

        model.mode = .review
        model.space = .report

        #expect(model.newTaskTitle == "Chiffrer la fin de migration Marine")
        #expect(model.newTaskUrgent)
        #expect(model.newTaskPomodoros == 2)
    }

    @Test("Le brouillon d'action n'est pas mémorisé d'une ouverture à l'autre")
    func draftIsNotPersisted() {
        let defaults = makeDefaults()
        let id = UUID()
        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.newTaskTitle = "Ne doit pas survivre"

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.newTaskTitle.isEmpty)
    }

    @Test("`resetActionDraft` remet le brouillon à zéro mais garde le destinataire choisi")
    func resetKeepsAudience() {
        // Après création d'une action, le composeur du rail doit rester prêt à
        // en saisir une autre pour la même personne : vider le destinataire
        // obligerait à le re-choisir à chaque ligne.
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.newTaskTitle = "Vérifier l'état des comptes GitLab"
        model.newTaskDueDate = Date()
        model.showNewTaskDueDate = true
        model.newTaskUrgent = true
        model.newTaskImportant = true
        model.newTaskPomodoros = 4
        model.newTaskAudience = .collaborateur

        model.resetActionDraft()

        #expect(model.newTaskTitle.isEmpty)
        #expect(model.newTaskDueDate == nil)
        #expect(model.showNewTaskDueDate == false)
        #expect(model.newTaskUrgent == false)
        #expect(model.newTaskImportant == false)
        #expect(model.newTaskPomodoros == 0)
        #expect(model.newTaskAudience == .collaborateur)
    }

    @Test("Les bascules d'affichage ont les défauts de l'écran actuel")
    func displayTogglesKeepCurrentDefaults() {
        // Aucun changement visuel dans ce lot : les défauts sont exactement
        // ceux des `@State` retirés de `MeetingView`.
        let model = MeetingScreenModel(defaults: makeDefaults())
        #expect(model.showSpeakers)
        #expect(model.showPlayback == false)
        #expect(model.follow)
    }

    @Test("Les clés de mémorisation portent l'identifiant de la réunion")
    func keysCarryTheMeetingID() {
        let id = UUID()
        #expect(MeetingScreenModel.spaceKey(for: id).contains(id.uuidString))
        #expect(MeetingScreenModel.modeKey(for: id).contains(id.uuidString))
        #expect(MeetingScreenModel.spaceKey(for: id) != MeetingScreenModel.modeKey(for: id))
    }

    @Test("Sans réunion rattachée, un choix d'espace n'écrit rien dans les préférences")
    func nothingIsWrittenBeforeAttach() {
        // `@State private var screen = MeetingScreenModel()` est construit
        // avant que `.onAppear` connaisse la réunion : une écriture à ce
        // moment-là irait sous une clé sans propriétaire.
        let defaults = makeDefaults()
        let model = MeetingScreenModel(defaults: defaults)
        model.space = .report
        #expect(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("onetoone.meetingScreen") } == false)
    }

    // MARK: - Tête de lecture (lot 1)

    @Test("La tête de lecture appartient au modèle d'écran : une par réunion")
    func playheadBelongsToScreen() {
        // Reprend l'écart n° 1 du lot 0B : le registre statique de
        // `MeetingPlayhead` disparaît, chaque écran porte la tête de lecture
        // de sa réunion.
        let a = MeetingScreenModel(defaults: makeDefaults())
        a.attach(meetingID: UUID())
        let premiere = a.playhead
        #expect(a.playhead === premiere)          // deux accès, une instance

        let b = MeetingScreenModel(defaults: makeDefaults())
        b.attach(meetingID: UUID())
        #expect(b.playhead !== premiere)          // deux réunions, deux têtes
    }

    @Test("La tête de lecture porte le stableID de la réunion rattachée")
    func playheadCarriesTheMeetingID() {
        let id = UUID()
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: id)
        #expect(model.playhead.meetingStableID == id)
    }

    // MARK: - Critère d'acceptation n° 4 (chantier 1)

    @Test("Préparer → En séance → Relire ne perd ni le brouillon d'action ni le texte en cours")
    func modeChangeKeepsDrafts() {
        // « Le passage Préparer → En séance → Relire ne perd aucune saisie en
        // cours. » Le mode ne change que la disposition (spec §2.2) : il ne
        // remet rien à zéro, et c'est ce test qui l'empêche de le faire un
        // jour par inadvertance.
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.newTaskTitle = "Chiffrer la fin de migration"
        model.newTaskUrgent = true
        model.newTaskPomodoros = 2
        model.pendingNoteText = "40k déjà payés, rien de finalisé"

        for mode in [MeetingScreenModel.Mode.prepare, .live, .review, .prepare] {
            model.mode = mode
            #expect(model.newTaskTitle == "Chiffrer la fin de migration")
            #expect(model.newTaskUrgent)
            #expect(model.newTaskPomodoros == 2)
            #expect(model.pendingNoteText == "40k déjà payés, rien de finalisé")
        }
        // Même exigence en changeant d'espace : le composeur de note reste
        // rempli quand on va voir le rapport et qu'on revient.
        for space in MeetingScreenModel.Space.allCases {
            model.space = space
            #expect(model.newTaskTitle == "Chiffrer la fin de migration")
            #expect(model.pendingNoteText == "40k déjà payés, rien de finalisé")
        }
    }

    @Test("Le texte en cours n'est pas mémorisé d'une ouverture à l'autre")
    func pendingNoteIsNotPersisted() {
        // Une note à moitié écrite est une intention du moment, pas une
        // donnée : elle ne doit pas ressusciter trois jours plus tard.
        let defaults = makeDefaults()
        let id = UUID()
        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.pendingNoteText = "en cours"

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.pendingNoteText.isEmpty)
    }

    @Test("Un marqueur posé sur la tête de lecture y reste, trié")
    func markerIsKept() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        model.attach(meetingID: UUID())
        model.playhead.addMarker(at: 30, kind: .note)
        model.playhead.addMarker(at: 10, kind: .decision)
        #expect(model.playhead.markers.map(\.t) == [10, 30])
        #expect(model.playhead.marker(at: 10.2)?.kind == .decision)
    }

    // MARK: - Lot 2 : filtre de notes, intention d'action, jeton de focus

    @Test("Le filtre de notes bascule sur la même nature")
    func filtreDeNotes() {
        // Le KPI Décisions du bandeau (spec §2.3 : « Clic = filtre les notes
        // sur kind:'decision' ») doit pouvoir se déclencher **et** se
        // relâcher : un filtre qu'on ne sait pas retirer est un cul-de-sac.
        let model = MeetingScreenModel(defaults: makeDefaults())
        #expect(model.noteFilter == nil)
        model.toggleNoteFilter(.decision)
        #expect(model.noteFilter == .decision)
        model.toggleNoteFilter(.decision)
        #expect(model.noteFilter == nil)
        model.toggleNoteFilter(.risk)
        #expect(model.noteFilter == .risk)
        model.toggleNoteFilter(.decision)
        #expect(model.noteFilter == .decision, "une autre nature remplace le filtre")
    }

    @Test("Une action demandée depuis une phrase préremplit le composeur du rail")
    func intentionDAction() {
        let model = MeetingScreenModel(defaults: makeDefaults())
        let brouillon = ActionFromPhrase.draft(phrase: "il faut vérifier les droits.",
                                               segmentID: UUID(), t: 252,
                                               speakerName: "Laurent Deberti")
        model.requestAction(from: brouillon)
        #expect(model.pendingActionDraft == brouillon)
        #expect(model.newTaskTitle == "Vérifier les droits")
        #expect(model.pendingActionDraft?.sourceRef.t == 252)
    }

    @Test("Le filtre et l'intention ne sont pas mémorisés d'une ouverture à l'autre")
    func intentionNonPersistee() {
        let defaults = makeDefaults()
        let id = UUID()
        let premier = MeetingScreenModel(defaults: defaults)
        premier.attach(meetingID: id)
        premier.toggleNoteFilter(.decision)
        premier.requestAction(from: ActionFromPhrase.draft(phrase: "chiffrer",
                                                           segmentID: UUID(), t: 0,
                                                           speakerName: nil))

        let second = MeetingScreenModel(defaults: defaults)
        second.attach(meetingID: id)
        #expect(second.noteFilter == nil)
        #expect(second.pendingActionDraft == nil)
    }

    @Test("Le focus du composeur de notes passe par un jeton, pas par un booléen")
    func jetonDeFocus() {
        // Un booléen ne permettrait pas deux ⌘⇧N de suite : la seconde pression
        // ne changerait rien et le composeur ne reprendrait pas le clavier.
        let model = MeetingScreenModel(defaults: makeDefaults())
        let depart = model.noteComposerFocusToken
        model.focusNoteComposer()
        model.focusNoteComposer()
        #expect(model.noteComposerFocusToken == depart + 2)
    }

    @Test("Le suivi de la transcription part actif")
    func suiviParDefaut() {
        #expect(MeetingScreenModel(defaults: makeDefaults()).follow)
    }
}
