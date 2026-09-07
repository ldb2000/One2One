import SwiftUI
import SwiftData
import AppKit
import Combine
import os

private let sessionLog = Logger(subsystem: "com.onetoone.app", category: "session-fullscreen")

/// Le rendez-vous entre ce qui **demande** le mode séance plein écran et ce qui
/// sait le **présenter** (spec §2.6, capture `1b-mode-seance.png`).
///
/// Pourquoi un objet partagé plutôt qu'un `@Binding` : la demande part de la
/// pilule audio de `MeetingTopChromeBar` et de l'item de menu `⌃⌘F`
/// (`MeetingCommands`), qui n'ont ni l'un ni l'autre accès au
/// `MeetingScreenModel` — le premier est monté par `MeetingView`, le second
/// vit hors de toute hiérarchie de vues. Faire descendre un binding jusqu'à
/// eux, c'est exactement le prop-drilling que le programme §8 interdit, et
/// c'est en plus une modification de `MeetingView`, que ce lot ne touche pas.
///
/// L'hôte — le modificateur posé sur `MeetingSpaceView` — s'enregistre quand il
/// est en mesure de présenter (mode En séance) ; les demandeurs lisent
/// `peutEntrer` pour se griser, et incrémentent un jeton pour demander.
///
/// **Il sert aussi de passe-plat vers la racine de la fenêtre** (correctif du
/// 2026-09-08) : c'est l'écran qui sait construire le mode séance — il a la
/// réunion, le modèle d'écran et les réglages — mais c'est la racine de la
/// fenêtre qui doit le monter, puisque « aucun chrome » (spec §2.6) veut dire
/// « à la place de la barre du haut de `MeetingView` aussi ».
@MainActor
@Observable
final class SessionFullscreenPresenter {

    static let shared = SessionFullscreenPresenter()

    /// La réunion dont l'écran est en mesure de présenter le mode séance.
    /// `nil` quand aucun écran ne l'est.
    private(set) var hote: UUID?

    /// Jeton de demande. Un jeton et non un booléen : deux `⌃⌘F` de suite
    /// doivent tous deux basculer, or la seconde écriture d'un booléen déjà
    /// vrai ne notifie personne (même raison que
    /// `MeetingScreenModel.noteComposerFocusToken`).
    private(set) var jeton = 0

    /// L'état du mode séance en cours de présentation — `screen.session` de
    /// l'écran qui présente. La racine de la fenêtre s'y branche : c'est lui,
    /// et non `NSWindow`, qui décide de ce qui est à l'écran.
    private(set) var seance: SessionFullscreenState?

    /// La vue du mode séance, construite par l'écran, montée par la racine.
    private(set) var vue: (() -> AnyView)?

    /// La fenêtre où le mode est présenté. Deux fenêtres réunion peuvent être
    /// ouvertes : la racine de l'autre ne doit pas monter cette séance.
    private(set) weak var fenetre: NSWindow?

    private init() {}

    /// Vrai quand une réunion peut passer en plein écran.
    func peutEntrer(_ meetingStableID: UUID?) -> Bool {
        guard let meetingStableID else { return false }
        return hote == meetingStableID
    }

    /// L'écran d'une réunion se déclare capable de présenter, ou renonce.
    ///
    /// Idempotent : appelé depuis `onAppear` et `onChange`, qui se déclenchent
    /// plusieurs fois pour un même écran. Un renoncement ne débranche que
    /// **son** hôte : deux fenêtres réunion ouvertes ne doivent pas se
    /// désenregistrer l'une l'autre.
    func declarerHote(_ meetingStableID: UUID, capable: Bool) {
        if capable {
            hote = meetingStableID
        } else if hote == meetingStableID {
            hote = nil
        }
    }

    /// Demande la bascule. Sans hôte, la demande est ignorée — un raccourci
    /// qui ne fait rien vaut mieux qu'un plein écran vide.
    func demanderBascule() {
        guard hote != nil else {
            sessionLog.info("toggle ignoré : aucun écran en mesure de présenter")
            return
        }
        jeton += 1
    }

    /// L'écran publie son mode séance à la racine de `fenetre`.
    func presenter(dans fenetre: NSWindow,
                   seance: SessionFullscreenState,
                   vue: @escaping () -> AnyView) {
        self.fenetre = fenetre
        self.seance = seance
        self.vue = vue
        sessionLog.info("mode séance publié à la racine de la fenêtre")
    }

    /// Dépublie. Idempotent : appelé par la sortie et par le démontage.
    func retirerLaPresentation() {
        guard seance != nil || vue != nil else { return }
        fenetre = nil
        seance = nil
        vue = nil
        sessionLog.info("mode séance dépublié")
    }

    /// Vrai quand la racine de `fenetre` doit monter le mode séance.
    ///
    /// La condition porte sur `seance.isPresented`, c'est-à-dire sur
    /// `screen.session` de l'écran : le plein écran d'AppKit est une
    /// conséquence, pas la cause. Confondre les deux est précisément ce qui a
    /// rendu l'écran 1b invisible (recette du 2026-09-07).
    func estAffiche(dans fenetre: NSWindow?) -> Bool {
        guard let fenetre, self.fenetre === fenetre else { return false }
        return seance?.isPresented == true && vue != nil
    }
}

/// Le **plein écran natif** de la fenêtre courante, et rien de plus.
///
/// Le lot 4 substituait ici le `contentView` de la fenêtre. C'était la cause du
/// défaut n° 1 de la recette du 2026-09-07 : `NSWindow.contentView = …` détache
/// l'ancienne vue **synchroniquement**, SwiftUI fait alors partir le
/// `onDisappear` de l'écran qui commandait la bascule — donc son `sortir()`,
/// donc la restauration du cockpit — *avant* que `toggleFullScreen` ne soit
/// appelé. La fenêtre partait en plein écran avec l'ancien contenu, la barre de
/// titre masquée par la ligne qui suivait la restauration : exactement ce que
/// la recette a constaté. Le contenu est désormais choisi par la racine SwiftUI
/// (`sessionFullscreenHost`) ; il ne reste à AppKit que ce que SwiftUI ne sait
/// pas faire — le plein écran.
@MainActor
final class SessionWindowFullscreen {

    private weak var fenetre: NSWindow?
    private var titreVisiblePrecedent: NSWindow.TitleVisibility = .visible
    private var titreTransparentPrecedent = false

    var estEntre: Bool { fenetre != nil }

    /// Prend la main sur `fenetre`. `demanderLePleinEcran` est faux quand la
    /// fenêtre y va déjà d'elle-même (item natif « Activer le mode plein
    /// écran », bouton vert) : redemander la bascule la ferait ressortir.
    func entrer(_ fenetre: NSWindow, demanderLePleinEcran: Bool) {
        guard self.fenetre == nil else { return }
        self.fenetre = fenetre
        titreVisiblePrecedent = fenetre.titleVisibility
        titreTransparentPrecedent = fenetre.titlebarAppearsTransparent
        // La barre de titre **est** du chrome : elle disparaît avec le reste.
        fenetre.titleVisibility = .hidden
        fenetre.titlebarAppearsTransparent = true
        if demanderLePleinEcran, !fenetre.styleMask.contains(.fullScreen) {
            fenetre.toggleFullScreen(nil)
        }
        sessionLog.info("plein écran pris (demandé : \(demanderLePleinEcran, privacy: .public))")
    }

    /// Rend la fenêtre à son état d'avant. `rendreLePleinEcran` est faux quand
    /// c'est la fenêtre qui en sort d'elle-même.
    func sortir(rendreLePleinEcran: Bool) {
        guard let fenetre else { return }
        self.fenetre = nil
        if rendreLePleinEcran, fenetre.styleMask.contains(.fullScreen) {
            fenetre.toggleFullScreen(nil)
        }
        fenetre.titleVisibility = titreVisiblePrecedent
        fenetre.titlebarAppearsTransparent = titreTransparentPrecedent
        sessionLog.info("plein écran rendu")
    }
}

// MARK: - Le modificateur

/// Le point d'entrée du mode séance, posé **une seule fois**, sur
/// `MeetingSpaceView`.
private struct SessionFullscreenModifier: ViewModifier {

    @Bindable var meeting: Meeting
    let screen: MeetingScreenModel
    let settings: AppSettings
    /// Vrai quand l'écran est en mesure de présenter (mode En séance).
    let estEligible: Bool
    let onOpenMeeting: (PersistentIdentifier) -> Void
    let onDiarize: () -> Void
    let onReidentify: () -> Void

    @Environment(\.modelContext) private var context
    @State private var plein = SessionWindowFullscreen()
    @State private var fenetre: NSWindow?
    private var presentateur: SessionFullscreenPresenter { .shared }

    func body(content: Content) -> some View {
        content
            .background(SessionWindowReader { fenetre = $0 })
            .onAppear { declarer() }
            .onDisappear {
                presentateur.declarerHote(meeting.ensuredStableID, capable: false)
                sortir()
            }
            .onChange(of: estEligible) { _, _ in declarer() }
            .onChange(of: presentateur.jeton) { _, _ in basculer() }
            // La fenêtre peut partir en plein écran sans nous : l'item natif
            // « Activer le mode plein écran » du menu Affichage porte le même
            // `⌃⌘F` que la spec §2.6 et le menu Réunion, et AppKit cherche ses
            // équivalents clavier dans l'ordre des menus. Le bouton vert de la
            // barre de titre fait de même. Dans les deux cas, le mode séance
            // suit : sinon la fenêtre s'agrandit sur le cockpit, ce qui est le
            // symptôme même qu'on corrige.
            .onReceive(NotificationCenter.default.publisher(
                for: NSWindow.willEnterFullScreenNotification)) { notification in
                guard estMaFenetre(notification) else { return }
                presenter(demanderLePleinEcran: false)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSWindow.willExitFullScreenNotification)) { notification in
                guard estMaFenetre(notification) else { return }
                sortir(rendreLePleinEcran: false)
            }
            // `⌃⌘F` : le raccourci vit aussi ici, pour fonctionner sans passer
            // par le menu. L'item de `MeetingCommands` reste la découverte.
            .overlay {
                Button("") { presentateur.demanderBascule() }
                    .keyboardShortcut("f", modifiers: [.control, .command])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }

    private func estMaFenetre(_ notification: Notification) -> Bool {
        guard let fenetre, let objet = notification.object as? NSWindow else { return false }
        return objet === fenetre
    }

    private func declarer() {
        presentateur.declarerHote(meeting.ensuredStableID, capable: estEligible)
    }

    private func basculer() {
        if screen.session.isPresented { sortir() } else { presenter(demanderLePleinEcran: true) }
    }

    /// Entre dans le mode : l'état bascule, la vue est publiée à la racine de
    /// la fenêtre, et le plein écran est demandé — dans cet ordre. Aucune vue
    /// AppKit n'est déplacée : c'est SwiftUI qui substitue le contenu.
    private func presenter(demanderLePleinEcran: Bool) {
        guard estEligible, let fenetre, !screen.session.isPresented else { return }
        screen.session.enter()
        // Le conteneur est repassé explicitement : la racine qui montera cette
        // vue peut appartenir à une scène dont le contexte n'est pas celui-ci,
        // et les `@Query` de la vue de séance seraient alors vides.
        let container = context.container
        let ouvrir = self.ouvrir
        let sortir = self.sortir
        presentateur.presenter(dans: fenetre, seance: screen.session) {
            AnyView(
                SessionFullscreenView(
                    meeting: meeting,
                    screen: screen,
                    settings: settings,
                    onOpenMeeting: { identifiant, t in ouvrir(identifiant, t) },
                    onDiarize: onDiarize,
                    onReidentify: onReidentify,
                    onExit: { sortir(true) }
                )
                .modelContainer(container)
            )
        }
        plein.entrer(fenetre, demanderLePleinEcran: demanderLePleinEcran)
    }

    private func sortir(rendreLePleinEcran: Bool = true) {
        guard screen.session.isPresented || plein.estEntre else { return }
        screen.session.leave()
        presentateur.retirerLaPresentation()
        plein.sortir(rendreLePleinEcran: rendreLePleinEcran)
    }

    /// Ouvre la réunion source d'une citation de l'assistant.
    ///
    /// On **sort d'abord** du plein écran : ouvrir une autre réunion derrière
    /// un plein écran qui reste affiché donnerait l'impression que le clic n'a
    /// rien fait.
    private func ouvrir(_ meetingStableID: UUID, _ t: Double?) {
        let descripteur = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.stableID == meetingStableID }
        )
        guard let cible = try? context.fetch(descripteur).first else {
            sessionLog.info("source sans réunion : \(meetingStableID.uuidString, privacy: .public)")
            return
        }
        sortir()
        onOpenMeeting(cible.persistentModelID)
    }
}

/// Remonte la `NSWindow` qui héberge la vue. Une vue SwiftUI ne connaît pas sa
/// fenêtre ; `NSViewRepresentable` est le seul chemin, et il faut attendre que
/// la vue soit dans la hiérarchie (`viewDidMoveToWindow`).
struct SessionWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let vue = ReportingView()
        vue.onWindow = onWindow
        return vue
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReportingView)?.onWindow = onWindow
    }

    private final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

extension View {
    /// Branche le mode séance plein écran sur cet écran (spec §2.6).
    ///
    /// Une seule pose dans l'application, sur `MeetingSpaceView` : deux poses
    /// publieraient deux modes séance pour la même fenêtre, et le second
    /// masquerait le premier.
    func sessionFullscreen(meeting: Meeting,
                           screen: MeetingScreenModel,
                           settings: AppSettings,
                           estEligible: Bool,
                           onOpenMeeting: @escaping (PersistentIdentifier) -> Void,
                           onDiarize: @escaping () -> Void,
                           onReidentify: @escaping () -> Void) -> some View {
        modifier(SessionFullscreenModifier(meeting: meeting,
                                           screen: screen,
                                           settings: settings,
                                           estEligible: estEligible,
                                           onOpenMeeting: onOpenMeeting,
                                           onDiarize: onDiarize,
                                           onReidentify: onReidentify))
    }
}
