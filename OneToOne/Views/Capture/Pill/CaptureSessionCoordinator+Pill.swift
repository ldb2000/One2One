import CoreGraphics
import Foundation

/// Ce que la pastille flottante ajoute au pilotage de la capture du lot 7.
///
/// Une extension et non des lignes dans `CaptureSessionCoordinator` : le lot 7 est la
/// base de ce lot, et deux lots qui écrivent dans le même fichier se rencontrent à
/// l'intégration. Le coordinateur reste la seule porte d'entrée de la capture — la
/// pastille ne parle jamais directement à `ScreenCaptureService`.
extension CaptureSessionCoordinator {

    /// Y a-t-il une source sur laquelle capturer sans rien demander à l'utilisateur ?
    ///
    /// C'est la question que la pastille doit poser **avant** `captureNow()` : celui-ci
    /// déplie le sélecteur (`state.showPopover = true`) quand il ne trouve rien, ce qui
    /// n'a aucun effet visible depuis une pastille posée sur Teams — le geste
    /// paraîtrait sans effet.
    var pillHasSource: Bool {
        if service.hasOpenSession { return true }
        if screen.capture.selected != nil { return true }
        return screen.capture.options.contains { $0.isActive }
    }

    /// Ouvre une session sur une **zone** tracée à la souris (spec §5.1, source
    /// `Zone à la souris`).
    ///
    /// Clôt la session en cours : une session porte une source figée à sa construction
    /// (écart n° 4 du lot 7), et le cadrage en fait partie.
    ///
    /// La zone est capturée sur l'écran principal : `SessionConfiguration` ne porte pas
    /// d'identifiant d'écran, et `windowID == 0` mène à `DisplayFrameSource()`, qui lit
    /// l'écran que `SCShareableContent` rend en premier.
    func startRegionSession(_ region: NormalizedRect) async {
        if service.hasOpenSession {
            await service.finish()
        }
        let option = CaptureSourceOption(source: .region,
                                          badge: "ZONE",
                                          title: "Zone à la souris",
                                          subtitle: "Zone tracée sur l'écran",
                                          windowID: 0,
                                          isActive: true)
        screen.capture.selected = option
        startRegionSession(on: option, crop: region)
    }

    /// L'ouverture de session avec un cadrage explicite.
    ///
    /// Duplique quatre lignes de `startSession(on:)` — le `crop` y est figé à `.full` et
    /// `timecodeProvider()` y est privé. Recopier le fournisseur de `t` plutôt que
    /// modifier le fichier du lot 7 est le compromis assumé : la règle (« le `t` vient
    /// du `MeetingPlayhead`, jamais de l'horloge de la capture ») est la même, et elle
    /// est testée des deux côtés.
    private func startRegionSession(on option: CaptureSourceOption, crop: NormalizedRect) {
        guard !service.hasOpenSession else { return }
        screen.capture.applyDefaultsIfNeeded(for: meeting.kind)
        let profil = meeting.kind.captureProfile
        let configuration = ScreenCaptureService.SessionConfiguration(
            windowID: option.windowID,
            windowTitle: option.title,
            crop: crop,
            sensitivity: profil.sensitivity,
            source: .region,
            // Une zone tracée à la main ne « change pas de partage » : la détection
            // automatique n'a rien à détecter, et la laisser armée ferait écrire des
            // captures à chaque mouvement de souris derrière la zone.
            detectsAutomatically: false,
            periodicCapture: screen.capture.periodicCapture)
        let playhead = screen.playhead
        do {
            try service.start(configuration: configuration,
                              meeting: meeting,
                              context: context,
                              appendTo: pillLastBatch,
                              // Même règle que `timecodeProvider()` : on calcule
                              // sans publier (cf. `MeetingPlayhead.currentTime`).
                              timecode: { playhead.elapsedIfAny })
        } catch {
            screen.capture.catalogError = error.localizedDescription
        }
    }

    /// Le lot de captures de la séance, comme `startSession(on:)` le choisit : une
    /// seconde session complète le même lot, pour que le compteur de la pastille ne
    /// reparte pas de zéro au milieu d'une séance.
    private var pillLastBatch: MeetingAttachment? {
        meeting.attachments
            .filter { $0.kind == AttachmentCopyPolicy.slidesKind }
            .max { $0.importedAt < $1.importedAt }
    }
}
