import Foundation
import Testing
@testable import OneToOne

/// La doublure de la réunion active : elle compte tout ce que la pastille demande, et
/// surtout les **ouvertures de la fenêtre**, qui doivent rester à zéro (critère n° 2 du
/// chantier 4 : « une capture manuelle depuis la pastille ne demande aucun retour dans
/// l'application »).
@MainActor
final class SessionPillTargetDouble: SessionPillTarget {

    var elapsed: Double? = 1_122          // 18:42, le timecode de la maquette 4b
    var captureCount = 3
    var isRecording = true

    /// Ce que rendra le prochain `captureNow()`.
    var nextResult: SessionPillCaptureResult
    /// Le texte que l'OCR finira par rendre, après `ocrDelayedCalls` appels à blanc.
    var ocrText: String?
    var ocrDelayedCalls = 0

    private(set) var captureCalls = 0
    private(set) var ocrCalls = 0
    private(set) var createdNotes: [String] = []
    private(set) var createdActions: [UUID] = []
    private(set) var selectorOpenings = 0
    /// Le nombre d'activations de l'application. La pastille ne doit **jamais**
    /// l'incrémenter sur le chemin d'une capture.
    private(set) var appActivations = 0

    var noteCreationSucceeds = true
    var actionCreationSucceeds = true

    init(nextResult: SessionPillCaptureResult) {
        self.nextResult = nextResult
    }

    func captureNow() async -> SessionPillCaptureResult {
        captureCalls += 1
        return nextResult
    }

    func firstOCRLine(forCaptureID id: UUID) -> String? {
        ocrCalls += 1
        guard ocrCalls > ocrDelayedCalls else { return nil }
        return ocrText
    }

    func createNote(_ text: String) -> Bool {
        guard noteCreationSucceeds else { return false }
        createdNotes.append(text)
        return true
    }

    func createAction(fromCaptureID id: UUID) -> Bool {
        guard actionCreationSucceeds else { return false }
        createdActions.append(id)
        return true
    }

    func openSourceSelector() {
        selectorOpenings += 1
        // Ouvrir le sélecteur, c'est ramener l'utilisateur dans la fenêtre : c'est le
        // seul chemin autorisé à le faire, et la doublure le compte comme tel.
        appActivations += 1
    }
}

/// Ce que la pastille décide : la chaîne de capture, la confirmation, l'OCR qui arrive
/// après, le champ de note, l'action depuis la capture.
@Suite("SessionPillModel")
@MainActor
struct SessionPillModelTests {

    private let capture = SessionPillCapture(
        id: UUID(), t: 1_122, thumbnailPath: "/tmp/slide-3.png")

    private func model(_ double: SessionPillTargetDouble,
                       confirmation: Duration = .seconds(60),
                       interval: Duration = .milliseconds(1),
                       attempts: Int = 20) -> SessionPillModel {
        let modele = SessionPillModel(confirmationDuration: confirmation,
                                      ocrPollInterval: interval,
                                      ocrPollAttempts: attempts)
        modele.target = double
        return modele
    }

    // MARK: - Critère n° 2 : aucun retour dans l'application

    @Test("capturer depuis la pastille n'active jamais l'application")
    func captureNeverActivatesTheApp() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        double.ocrText = "Marine : 21 000 €"
        let modele = model(double)

        await modele.capture()

        #expect(double.captureCalls == 1)
        #expect(double.appActivations == 0)
        #expect(double.selectorOpenings == 0)
        #expect(modele.confirmation?.capture == capture)
        #expect(modele.confirmation?.header == "CAPTURÉ · 18:42")
    }

    @Test("sans source configurée, le sélecteur ne s'ouvre qu'une fois")
    func selectorOpensOnlyOnce() async {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)

        await modele.capture()
        await modele.capture()
        await modele.capture()

        #expect(double.captureCalls == 3)
        #expect(double.selectorOpenings == 1)
        // Rien à confirmer : il n'y a pas eu de capture.
        #expect(modele.confirmation == nil)

        // Une source retrouvée réarme le sélecteur pour la prochaine disparition.
        double.nextResult = .captured(capture)
        await modele.capture()
        double.nextResult = .needsSource
        await modele.capture()
        #expect(double.selectorOpenings == 2)
    }

    @Test("un échec de capture s'affiche : un bouton sans effet visible est un défaut")
    func failureIsShown() async {
        let double = SessionPillTargetDouble(nextResult: .failed("Source perdue"))
        let modele = model(double)

        await modele.capture()

        #expect(modele.confirmation?.header == "CAPTURE IMPOSSIBLE")
        #expect(modele.confirmation?.textLine == "Source perdue")
        #expect(modele.confirmation?.offersAction == false)
        #expect(double.appActivations == 0)
    }

    // MARK: - L'OCR arrive après

    @Test("la carte annonce l'extraction en cours, puis affiche la première ligne")
    func ocrArrivesLater() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        double.ocrText = "Marine : 21 000 €"
        // Le premier appel (celui de `capture()`) et les deux suivants rendent `nil`.
        double.ocrDelayedCalls = 3
        let modele = model(double)

        await modele.capture()
        #expect(modele.confirmation?.isExtracting == true)
        #expect(modele.confirmation?.textLine == "Texte en cours d'extraction…")

        await modele.waitForOCRForTesting()
        #expect(modele.confirmation?.ocrLine == "Marine : 21 000 €")
        #expect(modele.confirmation?.isExtracting == false)
        #expect(modele.confirmation?.textLine == "« Marine : 21 000 € »")
    }

    @Test("un OCR qui ne rend rien cesse de promettre un texte à venir")
    func ocrNeverArrives() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        double.ocrText = nil
        let modele = model(double, attempts: 3)

        await modele.capture()
        await modele.waitForOCRForTesting()

        #expect(modele.confirmation?.isExtracting == false)
        #expect(modele.confirmation?.textLine == "Aucun texte extrait")
    }

    @Test("la confirmation se referme d'elle-même")
    func confirmationClosesItself() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        let modele = model(double, confirmation: .zero, attempts: 1)

        await modele.capture()
        #expect(modele.confirmation != nil)
        await modele.waitForConfirmationWorkForTesting()
        #expect(modele.confirmation == nil)
    }

    // MARK: - Hauteur du panneau

    @Test("la hauteur du panneau suit la confirmation et le champ de note")
    func panelHeightFollowsState() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        let modele = model(double)
        #expect(modele.panelHeight == One2OneToken.pillHeight)

        modele.beginNote()
        #expect(modele.panelHeight == sessionPillPanelHeight(hasConfirmation: false, isEditingNote: true))

        await modele.capture()
        #expect(modele.panelHeight == sessionPillPanelHeight(hasConfirmation: true, isEditingNote: true))

        modele.cancelNote()
        modele.dismissConfirmation()
        #expect(modele.panelHeight == One2OneToken.pillHeight)
    }

    // MARK: - Note

    @Test("⌘⏎ crée la note au timecode courant et referme le champ")
    func noteIsCreated() {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)

        modele.beginNote()
        modele.noteDraft = "  Reprise AP à chiffrer  "
        #expect(modele.submitNote())

        #expect(double.createdNotes == ["Reprise AP à chiffrer"])
        #expect(modele.noteDraft.isEmpty)
        #expect(modele.isEditingNote == false)
        #expect(double.appActivations == 0)
    }

    @Test("un brouillon vide ne crée rien et laisse le champ ouvert")
    func emptyNoteKeepsTheField() {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)

        modele.beginNote()
        modele.noteDraft = "   "
        #expect(modele.submitNote() == false)
        #expect(double.createdNotes.isEmpty)
        #expect(modele.isEditingNote)
    }

    @Test("Esc jette le brouillon ; deux ✎ Note de suite ne l'effacent pas")
    func escapeDiscardsAndBeginIsIdempotent() {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)

        modele.beginNote()
        modele.noteDraft = "à moitié tapé"
        modele.beginNote()
        #expect(modele.noteDraft == "à moitié tapé")

        modele.cancelNote()
        #expect(modele.isEditingNote == false)
        #expect(modele.noteDraft.isEmpty)
    }

    // MARK: - Action depuis la capture

    @Test("＋ Action depuis la capture crée l'action et referme la carte")
    func actionFromCapture() async {
        let double = SessionPillTargetDouble(nextResult: .captured(capture))
        let modele = model(double)

        await modele.capture()
        #expect(modele.createActionFromConfirmation())

        #expect(double.createdActions == [capture.id])
        #expect(modele.confirmation == nil)
        #expect(double.appActivations == 0)
    }

    @Test("sans confirmation, l'action ne se crée pas")
    func noActionWithoutConfirmation() {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)
        #expect(modele.createActionFromConfirmation() == false)
        #expect(double.createdActions.isEmpty)
    }

    // MARK: - Chrono et compteur

    @Test("le chrono vient de l'axe temps de la réunion, `--:--` quand elle n'en a pas")
    func timecode() {
        let double = SessionPillTargetDouble(nextResult: .needsSource)
        let modele = model(double)
        #expect(modele.timecode == "18:42")
        #expect(modele.captureCount == 3)
        #expect(modele.isRecording)

        double.elapsed = nil
        #expect(modele.timecode == "--:--")

        // Sans réunion active, la pastille ne prétend ni chrono ni compteur.
        modele.target = nil
        #expect(modele.timecode == "--:--")
        #expect(modele.captureCount == 0)
        #expect(modele.isRecording == false)
    }
}
