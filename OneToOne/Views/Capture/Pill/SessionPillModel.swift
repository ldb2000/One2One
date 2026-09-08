import CoreGraphics
import Foundation
import Observation

/// La capture qui vient d'être écrite, telle que la pastille en a besoin.
///
/// Un type nu et non le `SlideCapture` de SwiftData : la pastille n'a besoin que de
/// l'identifiant (pour retrouver l'OCR quand il arrive), du timecode et du chemin de
/// l'image. Le modèle de pilotage se teste ainsi sans store.
struct SessionPillCapture: Equatable, Sendable {
    let id: UUID
    let t: Double?
    let thumbnailPath: String
}

/// Ce que rend un geste de capture depuis la pastille.
enum SessionPillCaptureResult: Equatable, Sendable {
    /// Écrite, insérée dans les notes, prête à être confirmée.
    case captured(SessionPillCapture)
    /// Aucune source n'est configurée : il faut ouvrir le sélecteur, donc la fenêtre.
    case needsSource
    /// La capture a échoué (source perdue, autorisation refusée, écriture impossible).
    case failed(String)
}

/// Ce que la pastille sait faire de la réunion active.
///
/// Un protocole et non le type concret : le critère n° 2 du chantier 4 — « une capture
/// manuelle depuis la pastille ne demande **aucun retour** dans l'application » — se
/// vérifie en comptant les activations d'application, et une doublure est le seul moyen
/// de compter zéro sans piloter le bureau.
@MainActor
protocol SessionPillTarget: AnyObject {

    /// Position sur l'axe temps de la réunion, `nil` quand elle n'en a pas (ni
    /// enregistrement, ni lecture) : le chrono affiche alors `--:--` plutôt que `00:00`.
    var elapsed: Double? { get }

    /// Nombre de captures de la séance.
    var captureCount: Int { get }

    /// Un enregistrement tourne pour cette réunion (point rouge pulsant).
    var isRecording: Bool { get }

    /// Capture, écrit et insère la vignette dans les notes au timecode courant.
    func captureNow() async -> SessionPillCaptureResult

    /// La première ligne d'OCR de cette capture, `nil` tant que Vision n'a pas rendu.
    func firstOCRLine(forCaptureID id: UUID) -> String?

    /// Crée une note au timecode courant. `false` si le texte est vide après analyse.
    @discardableResult
    func createNote(_ text: String) -> Bool

    /// Crée l'action de cette capture (elle apparaît dans le rail).
    @discardableResult
    func createAction(fromCaptureID id: UUID) -> Bool

    /// Ouvre l'application sur le sélecteur de source. **Le seul chemin** qui ramène
    /// l'utilisateur dans la fenêtre, et il n'est pris que sans source configurée.
    func openSourceSelector()
}

/// L'état de la carte de confirmation affichée 4 s sous la pastille (spec §5.4).
struct SessionPillConfirmation: Equatable, Sendable {

    enum Outcome: Equatable, Sendable {
        case captured(SessionPillCapture)
        case failed(String)
    }

    let outcome: Outcome
    /// Première ligne d'OCR, `nil` tant qu'elle n'est pas arrivée.
    var ocrLine: String?
    /// L'extraction est encore en cours : la carte dit « Texte en cours d'extraction… »
    /// plutôt que « Aucun texte extrait », qui serait un verdict prématuré.
    var isExtracting: Bool

    var capture: SessionPillCapture? {
        if case .captured(let capture) = outcome { return capture }
        return nil
    }

    /// L'en-tête de la carte : `CAPTURÉ · 18:42`.
    var header: String {
        switch outcome {
        case .captured(let capture):
            guard let t = capture.t else { return "CAPTURÉ · --:--" }
            return "CAPTURÉ · \(MeetingPlayhead.mmss(t))"
        case .failed:
            return "CAPTURE IMPOSSIBLE"
        }
    }

    /// La ligne de texte extrait, dans ses trois états.
    var textLine: String {
        switch outcome {
        case .failed(let message):
            return message
        case .captured:
            if let ocrLine, !ocrLine.isEmpty { return "« \(ocrLine) »" }
            return isExtracting ? "Texte en cours d'extraction…" : "Aucun texte extrait"
        }
    }

    /// `＋ Action depuis la capture` n'a de sens que sur une capture réussie, et le
    /// titre de l'action est la première ligne d'OCR : sans texte, le composeur du rail
    /// prendra le titre de la capture (`CaptureStripModel.title`).
    var offersAction: Bool { capture != nil }
}

/// Tout ce que la pastille **décide**, hors AppKit et hors SwiftUI.
///
/// La leçon de `One2One-specs.md` appliquée telle quelle : sur les vingt-deux défauts
/// corrigés pendant le développement de Teams-Capture, ceux qui ont survécu jusqu'à
/// l'usage réel vivaient dans la couche d'interface, la seule sans tests. Ici la vue ne
/// fait que dessiner et le contrôleur de panneau que redimensionner.
@MainActor
@Observable
final class SessionPillModel {

    /// La réunion active, `nil` quand il n'y en a pas : la pastille est alors masquée.
    var target: (any SessionPillTarget)?

    private(set) var confirmation: SessionPillConfirmation?

    /// Le champ de note est déplié (`✎ Note`, `⌘⇧N`).
    private(set) var isEditingNote = false
    var noteDraft = ""

    /// Vrai une fois le sélecteur ouvert faute de source : `⌘⇧S` répété ne doit pas
    /// ramener l'utilisateur dans la fenêtre à chaque frappe (spec : « ouvre l'app sur
    /// le sélecteur, **une seule fois** »).
    private(set) var didOpenSourceSelector = false

    /// Durée d'affichage de la confirmation (spec §5.4 : 4 s). Injectable : les tests
    /// n'attendent pas quatre secondes.
    private let confirmationDuration: Duration
    /// Sondage de l'OCR : Vision rend son texte après l'écriture du PNG, et rien dans
    /// SwiftData ne réveille un `NSHostingView` posé dans un `NSPanel` de façon fiable.
    /// Sonder est explicite, borné, et testable.
    private let ocrPollInterval: Duration
    private let ocrPollAttempts: Int

    /// La tâche qui referme la confirmation. Retenue pour être annulée à la capture
    /// suivante — sinon la confirmation de la capture n° 1 effacerait celle de la
    /// capture n° 2 quatre secondes plus tard.
    private var confirmationTask: Task<Void, Never>?
    /// Le sondage de l'OCR, **en parallèle** de la fermeture et non avant : enchaîné, il
    /// ajouterait son propre délai aux 4 s de la carte.
    private var ocrTask: Task<Void, Never>?

    init(confirmationDuration: Duration = .seconds(4),
         ocrPollInterval: Duration = .milliseconds(400),
         ocrPollAttempts: Int = 10) {
        self.confirmationDuration = confirmationDuration
        self.ocrPollInterval = ocrPollInterval
        self.ocrPollAttempts = ocrPollAttempts
    }

    // MARK: - Affichage

    /// Le chrono de la pastille. `--:--` sans axe temps : une réunion sans
    /// enregistrement ni lecture n'est pas à `00:00`, elle est hors du temps.
    var timecode: String {
        guard let t = target?.elapsed else { return "--:--" }
        return MeetingPlayhead.mmss(t)
    }

    var captureCount: Int { target?.captureCount ?? 0 }
    var isRecording: Bool { target?.isRecording ?? false }

    var panelHeight: CGFloat {
        sessionPillPanelHeight(hasConfirmation: confirmation != nil, isEditingNote: isEditingNote)
    }

    // MARK: - Capturer

    /// Le geste `◫ Capturer` et `⌘⇧S`.
    ///
    /// Ne rend la main qu'une fois la capture écrite et la confirmation posée ; le
    /// sondage de l'OCR et la fermeture au bout de 4 s continuent dans
    /// `confirmationTask`.
    func capture() async {
        guard let target else { return }
        switch await target.captureNow() {
        case .needsSource:
            // Le seul chemin qui ramène dans la fenêtre, et une seule fois : un
            // raccourci qui réactive l'application à chaque frappe est pire que rien.
            guard !didOpenSourceSelector else { return }
            didOpenSourceSelector = true
            target.openSourceSelector()
        case .failed(let message):
            // Un bouton qui n'a aucun effet visible est le défaut « contrôle sans
            // effet » de `One2One-specs.md` : l'échec s'affiche là où la réussite
            // s'afficherait.
            show(SessionPillConfirmation(outcome: .failed(message), ocrLine: nil, isExtracting: false))
        case .captured(let capture):
            // Une source valide efface le souvenir de l'ouverture du sélecteur : la
            // prochaine fois qu'elle disparaîtra, il faudra pouvoir le réouvrir.
            didOpenSourceSelector = false
            let premiere = target.firstOCRLine(forCaptureID: capture.id)
            show(SessionPillConfirmation(outcome: .captured(capture),
                                         ocrLine: premiere,
                                         isExtracting: premiere == nil),
                 pollingOCRFor: capture.id)
        }
    }

    /// Pose la confirmation, arme son sondage d'OCR et sa fermeture.
    private func show(_ nouvelle: SessionPillConfirmation, pollingOCRFor captureID: UUID? = nil) {
        confirmationTask?.cancel()
        ocrTask?.cancel()
        confirmation = nouvelle
        if let captureID {
            ocrTask = Task { [weak self] in await self?.pollOCR(for: captureID) }
        }
        confirmationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.confirmationDuration)
            guard !Task.isCancelled else { return }
            self.ocrTask?.cancel()
            // Ne referme que **sa** confirmation : une capture plus récente a déjà
            // annulé cette tâche, mais l'annulation peut arriver pendant le sommeil.
            if self.confirmation?.capture?.id == captureID || captureID == nil {
                self.confirmation = nil
            }
        }
    }

    /// Attend la première ligne d'OCR, sans jamais dépasser son quota d'essais : Vision
    /// peut ne rien rendre du tout (capture sans texte), et une boucle sans borne
    /// tournerait pour la vie du processus.
    private func pollOCR(for captureID: UUID) async {
        guard let target else { return }
        for _ in 0..<ocrPollAttempts {
            if Task.isCancelled { return }
            if let ligne = target.firstOCRLine(forCaptureID: captureID), !ligne.isEmpty {
                if confirmation?.capture?.id == captureID {
                    confirmation?.ocrLine = ligne
                    confirmation?.isExtracting = false
                }
                return
            }
            try? await Task.sleep(for: ocrPollInterval)
        }
        // Quota épuisé : la carte cesse de promettre un texte à venir.
        if confirmation?.capture?.id == captureID {
            confirmation?.isExtracting = false
        }
    }

    /// Referme la confirmation à la main (clic sur la carte).
    func dismissConfirmation() {
        confirmationTask?.cancel()
        ocrTask?.cancel()
        confirmationTask = nil
        ocrTask = nil
        confirmation = nil
    }

    /// Attend la fermeture de la confirmation. **Tests seulement.**
    func waitForConfirmationWorkForTesting() async {
        await confirmationTask?.value
    }

    /// Attend la fin du sondage d'OCR. **Tests seulement.**
    func waitForOCRForTesting() async {
        await ocrTask?.value
    }

    // MARK: - Action depuis la capture

    /// `＋ Action depuis la capture` : l'action apparaît dans le rail, et la carte se
    /// referme — laisser ouverte une carte dont le bouton a déjà servi invite au
    /// doublon.
    @discardableResult
    func createActionFromConfirmation() -> Bool {
        guard let target, let capture = confirmation?.capture else { return false }
        let cree = target.createAction(fromCaptureID: capture.id)
        if cree { dismissConfirmation() }
        return cree
    }

    // MARK: - Note

    /// `✎ Note` et `⌘⇧N` : déplie le champ. Idempotent — deux frappes ne doivent pas
    /// effacer une note à moitié tapée.
    func beginNote() {
        isEditingNote = true
    }

    /// `Esc` : referme le champ **et** jette le brouillon. C'est le geste d'annulation,
    /// pas celui de repli.
    func cancelNote() {
        isEditingNote = false
        noteDraft = ""
    }

    /// `⌘⏎` : crée la note au timecode courant et referme le champ.
    ///
    /// Un brouillon vide ne crée rien et **laisse le champ ouvert** : refermer sur une
    /// frappe sans effet donnerait l'impression que la note est partie.
    @discardableResult
    func submitNote() -> Bool {
        guard let target else { return false }
        let texte = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return false }
        guard target.createNote(texte) else { return false }
        noteDraft = ""
        isEditingNote = false
        return true
    }
}
