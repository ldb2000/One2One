import CoreGraphics
import Foundation
import SwiftData
import os

private let captureCoordLog = Logger(subsystem: "com.onetoone.app", category: "capture-ui")

/// Ce qui relie le sélecteur, la pilule d'état et la bande de captures au
/// service : catalogue des sources, ouverture de session, geste manuel.
///
/// Vit ici et non dans les vues, pour la raison mesurée dans
/// `One2One-specs.md` : sur les vingt-deux défauts corrigés pendant le
/// développement de Teams-Capture, ceux qui ont survécu jusqu'à l'usage réel
/// vivaient dans la couche d'interface, la seule sans tests. Les vues n'ont
/// donc que du dessin.
///
/// Valeur (`struct`) reconstruite à chaque rendu : elle ne retient rien —
/// l'état est dans `CaptureState`, la session dans `ScreenCaptureService`.
@MainActor
struct CaptureSessionCoordinator {

    let meeting: Meeting
    let screen: MeetingScreenModel
    let service: ScreenCaptureService
    let context: ModelContext

    private var state: CaptureState { screen.capture }

    // MARK: - Catalogue

    /// Reconstruit les lignes du sélecteur. Traduit le refus d'autorisation en
    /// état affichable : aucune boîte de dialogue en séance (spec §5.2).
    func refreshOptions() async {
        // Les bascules doivent montrer les défauts du type **avant** toute
        // session : un sélecteur qui annonce « à chaque changement de partage »
        // sur un 1:1, où rien n'écrit tout seul, mentirait.
        state.applyDefaultsIfNeeded(for: meeting.kind)
        state.isLoadingOptions = true
        defer { state.isLoadingOptions = false }
        do {
            let fenetres = try await WindowCatalog.shareableWindows(excludingAppNames: [])
            state.permissionDenied = false
            state.catalogError = nil
            state.refresh(options: options(from: fenetres))
        } catch let erreur as SlideCaptureError where erreur == .screenRecordingDenied {
            state.permissionDenied = true
            state.catalogError = nil
            state.refresh(options: CaptureSourceCatalog.options(teams: .init(), zoom: .init()))
        } catch {
            state.permissionDenied = false
            // `noShareableWindows` n'est pas une panne : l'écran entier reste
            // proposable, le sélecteur ne doit pas se vider.
            let estVide = (error as? SlideCaptureError) == .noShareableWindows
            state.catalogError = estVide ? nil : error.localizedDescription
            state.refresh(options: CaptureSourceCatalog.options(teams: .init(), zoom: .init()))
        }
    }

    /// Les lignes du sélecteur pour un ensemble de fenêtres. Séparée de l'appel
    /// système pour rester lisible : tout ce qui décide est dans
    /// `CaptureSourceCatalog`, testé à part.
    private func options(from fenetres: [ShareableWindow]) -> [CaptureSourceOption] {
        // Prénoms seuls : Teams nomme le partage par le prénom (« Partage de
        // Sylvain »), pas par le nom complet.
        let prenoms = meeting.participants.compactMap {
            $0.name.split(separator: " ").first.map(String.init)
        }.filter { !$0.isEmpty }
        let titreTeams = CaptureSourceCatalog
            .meetingWindow(in: fenetres, bundleIdentifiers: CaptureSourceCatalog.teamsBundleIdentifiers)?
            .title ?? ""
        // « Un partage est en cours » = le détecteur voit l'image bouger sur la
        // session ouverte (décision D7). Sans session, on ne peut rien affirmer.
        let bouge = service.isCapturing && service.isContentMoving
        let teams = CaptureSourceCatalog.teamsState(
            windows: fenetres,
            sharerName: CaptureSourceCatalog.sharerName(fromTitle: titreTeams, among: prenoms),
            isSharing: bouge && service.configuration?.source == .teams)
        let zoom = CaptureSourceCatalog.zoomState(
            windows: fenetres,
            isSharing: bouge && service.configuration?.source == .zoom)
        return CaptureSourceCatalog.options(teams: teams, zoom: zoom)
    }

    // MARK: - Choix de la source

    /// Retient une source et ouvre la session dessus.
    ///
    /// Changer de source en cours de séance **clôt** le lot courant et en ouvre
    /// un autre : une session porte une source, figée à sa construction, et
    /// laisser croire qu'on peut la changer à chaud donnerait un sélecteur qui
    /// confirme un choix sans effet (défaut « contrôle sans effet » de
    /// `One2One-specs.md`).
    func select(_ option: CaptureSourceOption) async {
        let dejaSurCetteSource = service.hasOpenSession && service.configuration?.source == option.source
        state.selected = option
        guard !dejaSurCetteSource else { return }
        if service.hasOpenSession {
            await service.finish()
        }
        startSession(on: option)
    }

    /// Ouvre la session de capture sur la source retenue. Sans effet si une
    /// session est déjà ouverte.
    func startSession(on option: CaptureSourceOption) {
        guard !service.hasOpenSession else { return }
        // Les défauts du type, s'ils n'ont pas déjà été appliqués : un 1:1
        // n'attend aucun slide, un atelier en attend en continu. Appliqués ici
        // et pas à la construction du modèle d'écran, parce que c'est ici
        // qu'on en a besoin — et une seule fois, pour ne pas écraser une
        // bascule que l'utilisateur vient de toucher.
        state.applyDefaultsIfNeeded(for: meeting.kind)
        let profil = meeting.kind.captureProfile
        let configuration = ScreenCaptureService.SessionConfiguration(
            windowID: option.windowID,
            windowTitle: option.title,
            crop: .full,
            sensitivity: profil.sensitivity,
            source: option.source,
            detectsAutomatically: state.detectsAutomatically && option.supportsAutomaticDetection,
            periodicCapture: state.periodicCapture)
        do {
            try service.start(configuration: configuration,
                              meeting: meeting,
                              context: context,
                              appendTo: lastBatch,
                              timecode: timecodeProvider())
        } catch {
            state.catalogError = error.localizedDescription
            captureCoordLog.error("session de capture non ouverte : \(error.localizedDescription)")
        }
    }

    /// Le lot de captures de la séance, s'il existe déjà : une seconde session
    /// dans la même réunion complète le même lot, pour que la bande et le
    /// compteur ne repartent pas de zéro au milieu d'une séance.
    private var lastBatch: MeetingAttachment? {
        meeting.attachments
            .filter { $0.kind == AttachmentCopyPolicy.slidesKind }
            .max { $0.importedAt < $1.importedAt }
    }

    /// Le fournisseur de `t` : l'axe **audio** de la réunion.
    ///
    /// Rend `nil` quand la réunion n'a pas d'axe temps — ni enregistrement en
    /// cours, ni lecture, ni durée connue : la capture est alors écrite sans
    /// `t` plutôt qu'à `00:00`, où son marqueur désignerait un instant où rien
    /// ne s'est passé.
    private func timecodeProvider() -> ScreenCaptureService.TimecodeProvider {
        let playhead = screen.playhead
        // `elapsedIfAny` calcule sans publier : ce fournisseur est appelé depuis
        // la boucle de capture, et écrire `t` hors du battement réveillerait
        // toutes les surfaces qui le lisent à chaque image capturée.
        return { playhead.elapsedIfAny }
    }

    // MARK: - Capture

    /// Le geste manuel : `Capturer maintenant`, `⌘⇧S`, ou la tuile de la bande.
    /// Ouvre la session au besoin, puis écrit.
    @discardableResult
    func captureNow() async -> Bool {
        if !service.hasOpenSession {
            guard let option = state.selected ?? state.options.first(where: \.isActive) else {
                state.showPopover = true
                return false
            }
            state.selected = option
            startSession(on: option)
        }
        let ecrit = await service.captureNow()
        if ecrit { refreshMarkers() }
        return ecrit
    }

    /// Ce que fait `⌘⇧S` (spec §5.1) : le sélecteur la première fois, une
    /// capture directe ensuite.
    func handleShortcut() async {
        switch CaptureState.shortcutOutcome(selected: state.selected, sourceLost: service.isSourceLost) {
        case .openSelector:
            state.showPopover = true
            await refreshOptions()
        case .captureNow:
            await captureNow()
        }
    }

    /// Remet les repères de la frise à jour : une capture qui n'apparaîtrait
    /// pas sur la frise ne serait pas « retrouvable depuis la frise »
    /// (critère n° 3 du chantier 4).
    func refreshMarkers() {
        screen.playhead.markers = MeetingTimelineMarkers.allMarkers(for: meeting)
    }

    // MARK: - Bascules

    func setAutomaticDetection(_ enabled: Bool) {
        state.setAutomaticDetection(enabled)
        service.setAutomaticDetection(enabled)
    }

    func setPeriodicCapture(_ enabled: Bool) {
        let intervalle = enabled ? CaptureState.periodicInterval : nil
        state.setPeriodicCapture(intervalle)
        service.setPeriodicCapture(intervalle)
    }

    // MARK: - Dérivations d'affichage

    /// L'état de la pilule de la barre du haut.
    var pill: CapturePillState {
        CaptureState.pill(sessionOpen: service.hasOpenSession,
                          sourceLost: service.isSourceLost,
                          source: service.configuration?.source ?? state.selected?.source,
                          count: captureCount,
                          automatic: service.configuration?.detectsAutomatically ?? false)
    }

    /// Toutes les captures de la réunion, du plus ancien au plus récent.
    /// Depuis les lots de captures (`MeetingAttachment.slides`) et non depuis
    /// la session courante : la bande doit montrer la séance entière, y compris
    /// ce qui a été capturé avant une reprise d'écran.
    var captures: [SlideCapture] {
        CaptureStripModel.sorted(meeting.attachments.flatMap(\.slides))
    }

    var captureCount: Int { meeting.attachments.reduce(0) { $0 + $1.slides.count } }
}
