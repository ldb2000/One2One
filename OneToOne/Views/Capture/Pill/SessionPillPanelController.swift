import AppKit
import Combine
import Observation
import SwiftUI
import os

private let panelLog = Logger(subsystem: "com.onetoone.app", category: "session-pill")

/// La fenêtre de la pastille : `NSPanel` non activant, au-dessus des autres
/// applications, déplaçable et magnétisée aux coins (spec §5.4).
///
/// `NSPanel` et non une scène SwiftUI : le niveau de fenêtre, le comportement non
/// activant et la présence **au-dessus du plein écran de Teams** ne s'expriment pas
/// autrement sur macOS.
///
/// Copié de `Teams-Capture/Sources/TeamsCapture/Pill/PillPanelController.swift`, avec
/// ses quatre leçons intactes :
/// 1. la vue hébergée n'est bâtie **qu'une fois** — l'état vit dans `SessionPillModel`,
///    pas dans des `@State` que la reconstruction perdrait ;
/// 2. l'état est observé par `withObservationTracking` **réarmé**, donc sans dépendre
///    d'aucune vue vivante : la fenêtre de réunion peut être en plein écran, réduite ou
///    fermée ;
/// 3. la magnétisation passe par un **débounce** de 250 ms sur `didMoveNotification` —
///    AppKit n'a pas de notification « souris relâchée » sur un déplacement de fenêtre ;
/// 4. c'est le contrôleur, et lui seul, qui **agrandit** le panneau quand la
///    confirmation ou le champ de note se déplient.
@MainActor
final class SessionPillPanelController {

    static let shared = SessionPillPanelController()

    let model: SessionPillModel

    private let registry: ActiveMeetingRegistry
    private var panel: SessionPillPanel?
    private var corner: ScreenCorner = .bottomTrailing
    private var currentMeetingID: UUID?
    private var snapTask: Task<Void, Never>?
    // `nonisolated(unsafe)` : lus et écrits uniquement depuis le `MainActor` tant que
    // l'instance vit, mais `deinit` d'une classe `@MainActor` n'est pas lui-même isolé.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    private var recorderSink: AnyCancellable?
    private var isObserving = false

    /// Le mode d'affichage, relu à chaque évaluation : il vit dans `AppSettings`, que
    /// la fenêtre de réglages peut changer alors qu'aucune réunion n'est ouverte.
    var mode: @MainActor () -> SessionPillMode = { .sessionOnly }
    /// Le coin mémorisé, lu une fois au démarrage.
    var storedCorner: @MainActor () -> ScreenCorner = { .bottomTrailing }
    /// Écrit le coin après magnétisation. C'est le **coin** qui est persisté, jamais la
    /// position : un écran débranché replacerait sinon la pastille hors champ.
    var persistCorner: @MainActor (ScreenCorner) -> Void = { _ in }
    /// Ramène l'utilisateur dans l'application, sur le sélecteur de source. Le seul
    /// chemin autorisé à activer l'application (critère n° 2 du chantier 4).
    var openSourceSelector: @MainActor (ActiveMeetingHandle) -> Void = { _ in }

    /// `model` n'a pas de valeur par défaut : une valeur par défaut est évaluée hors du
    /// contexte de l'acteur, et `SessionPillModel` est `@MainActor`.
    init(registry: ActiveMeetingRegistry = .shared, model: SessionPillModel? = nil) {
        self.registry = registry
        self.model = model ?? SessionPillModel()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Cycle de vie

    /// Arme l'observation et applique l'état courant. Idempotent : appelé depuis un
    /// `onAppear`, qui se déclenche plusieurs fois.
    func start() {
        corner = storedCorner()
        guard !isObserving else {
            refresh()
            return
        }
        isObserving = true

        // L'activation de l'application entre dans la règle (`isAppActive`) : sans ces
        // deux notifications, la pastille resterait visible par-dessus la fenêtre qu'on
        // vient de remettre au premier plan.
        for nom in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            let observateur = NotificationCenter.default.addObserver(
                forName: nom, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(observateur)
        }

        // `AudioRecorderService` est un `ObservableObject` Combine et non `@Observable` :
        // `withObservationTracking` ne le voit pas. Sans cet abonnement, un
        // enregistrement démarré depuis le tableau de bord n'afficherait la pastille
        // qu'au prochain changement d'état observé.
        recorderSink = AudioRecorderService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }

        observeState()
        refresh()
    }

    /// Observe, sans passer par aucune vue, l'état dont dépendent la visibilité et la
    /// taille du panneau.
    ///
    /// `withObservationTracking` ne se déclenche qu'une fois par enregistrement, d'où le
    /// réarmement récursif. Ce `onChange` est en outre appelé **avant** que la valeur
    /// observée ait fini de changer — la relire à cet instant verrait encore l'ancienne —
    /// d'où le saut par une `Task`, exécutée après coup sur le `MainActor`.
    private func observeState() {
        withObservationTracking {
            _ = registry.handles.count
            _ = registry.activeHandle?.meetingStableID
            _ = registry.activeHandle?.isSessionFullscreen
            // La confirmation et le champ de note dictent la hauteur du panneau, et la
            // vue n'a aucun moyen de redimensionner la fenêtre.
            _ = model.confirmation
            _ = model.isEditingNote
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                self.observeState()
            }
        }
    }

    /// Relit la règle et ordonne, masque ou redimensionne le panneau.
    func refresh() {
        bindTarget()
        if shouldPresentPill(mode: mode(),
                             conditions: registry.pillConditions,
                             isAppActive: NSApp.isActive) {
            present()
            // Après `present()` : c'est lui qui peut créer le panneau, et une taille ne
            // s'applique qu'à une fenêtre qui existe.
            applyPanelSize()
            syncKeyState()
        } else {
            close()
        }
    }

    /// Le panneau n'accepte le clavier que pendant la saisie d'une note.
    ///
    /// Un panneau non activant qui deviendrait fenêtre clé au premier clic volerait le
    /// focus à Teams — on cliquerait `◫ Capturer` et la frappe suivante n'irait plus
    /// dans la réunion. Mais un champ de texte dans une fenêtre qui ne peut pas devenir
    /// clé ne reçoit **aucune** touche : `✎ Note` serait un contrôle mort. D'où le
    /// basculement, exactement pendant la saisie.
    private func syncKeyState() {
        guard let panel else { return }
        panel.acceptsKey = model.isEditingNote
        if model.isEditingNote {
            // `makeKey` sur un `.nonactivatingPanel` donne le clavier à la pastille sans
            // activer l'application : la fenêtre de Teams reste en place.
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isKeyWindow {
            panel.resignKey()
            panel.orderFrontRegardless()
        }
    }

    /// Branche la pastille sur la réunion active, et **seulement** quand elle change :
    /// reconstruire la cible à chaque évaluation jetterait la confirmation en cours.
    @discardableResult
    private func bindTarget() -> MeetingPillTarget? {
        guard let handle = registry.activeHandle else {
            if currentMeetingID != nil {
                currentMeetingID = nil
                model.target = nil
                model.dismissConfirmation()
                model.cancelNote()
            }
            return nil
        }
        if currentMeetingID == handle.meetingStableID, let cible = model.target as? MeetingPillTarget {
            return cible
        }
        currentMeetingID = handle.meetingStableID
        // Changer de réunion referme la confirmation et le champ : ils parlaient de
        // l'autre séance.
        model.dismissConfirmation()
        model.cancelNote()
        let cible = MeetingPillTarget(handle: handle) { [weak self] poignee in
            self?.openSourceSelector(poignee)
        }
        model.target = cible
        return cible
    }

    // MARK: - Les raccourcis globaux

    /// `⌘⇧S` — capture la source configurée. `⌥` enfoncé bascule sur le tracé d'une
    /// zone : c'est le geste le plus proche de « choisis ce que je montre », et il
    /// n'occupe pas un second raccourci global.
    func captureShortcut() {
        guard bindTarget() != nil else {
            panelLog.info("⌘⇧S ignoré : aucune réunion active")
            return
        }
        if NSEvent.modifierFlags.contains(.option) {
            selectRegion()
            return
        }
        Task { await model.capture() }
    }

    /// `⌘⇧N` — déplie le champ de note de la pastille au timecode courant.
    ///
    /// Si la pastille est masquée (mode « jamais », ou hors séance), le champ n'aurait
    /// nulle part où s'afficher : le raccourci ouvre alors la pastille pour la durée de
    /// la saisie plutôt que de ne rien faire.
    func noteShortcut() {
        guard bindTarget() != nil else {
            panelLog.info("⌘⇧N ignoré : aucune réunion active")
            return
        }
        model.beginNote()
        present()
        applyPanelSize()
        syncKeyState()
    }

    /// Ouvre le tracé de zone, puis ouvre la session dessus.
    func selectRegion() {
        guard let cible = bindTarget() else { return }
        RegionSelectorWindow.shared.begin { [weak self] zone in
            Task { @MainActor in
                await cible.useRegion(zone)
                // Tracer une zone est une demande de capture : ne pas capturer tout de
                // suite laisserait un geste sans effet visible.
                await self?.model.capture()
            }
        }
    }

    // MARK: - Le panneau

    private func present() {
        if let panel {
            panel.orderFrontRegardless()
            snap(panel)
            return
        }

        let contenu = FloatingPill(model: model, onSelectRegion: { [weak self] in self?.selectRegion() })
        let panel = SessionPillPanel(
            contentRect: NSRect(x: 0, y: 0, width: One2OneToken.pillWidth, height: One2OneToken.pillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        // Suivre l'utilisateur d'un espace à l'autre et rester visible par-dessus le
        // plein écran de Teams : sans ça, la pastille disparaît dès qu'un partage
        // commence — c'est-à-dire au moment précis où elle sert.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: contenu)
        panel.orderFrontRegardless()
        self.panel = panel
        snap(panel)

        // Il n'existe pas de notification AppKit « relâchement de la souris » sur un
        // déplacement de fenêtre — seule `didMoveNotification`, qui se déclenche en
        // continu pendant tout le glisser. `scheduleSnap()` simule donc le relâchement
        // par un débounce : chaque mouvement repousse l'échéance.
        let observateur = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSnap() }
        }
        observers.append(observateur)
        panelLog.info("pastille présentée")
    }

    /// Retire le panneau de l'écran **sans le détruire** : la vue hébergée est bâtie une
    /// seule fois, et remettre `panel` à `nil` forcerait une reconstruction — et
    /// perdrait le focus du champ de note — au prochain affichage.
    private func close() {
        guard panel != nil else { return }
        // Un débounce en attente aimanterait un panneau retiré de l'écran, sur une
        // taille qui n'est peut-être plus la sienne au retour.
        snapTask?.cancel()
        snapTask = nil
        panel?.orderOut(nil)
    }

    /// Accorde la hauteur du panneau à ce qui est déplié, puis réaimante.
    ///
    /// Le `snap` qui suit n'est pas une précaution : `snap(_:)` calcule l'origine depuis
    /// `panel.frame.size`, et `setContentSize` laisse l'origine (le coin **bas**-gauche)
    /// où elle est. Sans réaimantation, une pastille posée en haut d'écran grandirait
    /// vers le haut et sortirait du cadre visible.
    private func applyPanelSize() {
        guard let panel else { return }
        let hauteur = model.panelHeight
        guard abs(panel.frame.height - hauteur) > 0.5 else { return }
        panel.setContentSize(NSSize(width: One2OneToken.pillWidth, height: hauteur))
        snap(panel)
    }

    private func scheduleSnap() {
        snapTask?.cancel()
        snapTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let panel = self.panel else { return }
            let cadre = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            self.corner = ScreenCorner.nearest(
                to: CGPoint(x: panel.frame.midX, y: panel.frame.midY), in: cadre)
            self.persistCorner(self.corner)
            self.snap(panel)
        }
    }

    private func snap(_ panel: NSPanel) {
        let cadre = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origine = corner.origin(for: panel.frame.size, in: cadre, inset: One2OneToken.pillInset)
        // `setFrameOrigin` déclenche lui-même `didMoveNotification`, qui replanifierait
        // un débounce : ne bouger que si la cible diffère réellement. Sur un écran
        // normal la position aimantée est un point fixe de `nearest` ; ce n'est plus
        // vrai sur un écran plus petit que la pastille, où cette garde est ce qui arrête
        // réellement la boucle.
        guard abs(origine.x - panel.frame.origin.x) > 1 || abs(origine.y - panel.frame.origin.y) > 1 else {
            return
        }
        panel.setFrameOrigin(origine)
    }
}

/// Le panneau de la pastille.
///
/// Une sous-classe pour une seule raison : `canBecomeKey` est faux sur un `NSPanel`
/// `.borderless`, et un champ de texte dans une fenêtre qui ne peut pas devenir clé ne
/// reçoit aucune touche. Le droit est donné **pendant la saisie d'une note** seulement
/// (cf. `syncKeyState()`), pour ne pas voler le clavier de Teams au premier clic.
final class SessionPillPanel: NSPanel {

    var acceptsKey = false

    override var canBecomeKey: Bool { acceptsKey }

    /// Une pastille n'est jamais la fenêtre principale : elle n'a ni titre, ni menu, ni
    /// document. Le dire explicitement évite qu'un `makeKey` la fasse passer pour la
    /// fenêtre de travail de l'application.
    override var canBecomeMain: Bool { false }
}
