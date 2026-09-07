import SwiftUI
import SwiftData
import AppKit
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
}

/// La **substitution du contenu de la fenêtre courante** par le mode séance.
///
/// Pas de `WindowGroup` de plus (programme : « pas de nouvelle `WindowGroup` »)
/// et pas un simple `overlay` : un overlay posé sur `MeetingSpaceView` laisse
/// visibles la barre du haut, le badge de préparation et la barre
/// d'enregistrement de `MeetingView` — donc du chrome, ce que la spec §2.6
/// interdit. On remplace donc le `contentView` de la fenêtre, on passe en plein
/// écran, et on restaure à la sortie.
@MainActor
final class SessionWindowSwapper {

    private weak var fenetre: NSWindow?
    private var contenuPrecedent: NSView?
    private var titreVisiblePrecedent = true

    var estPresente: Bool { contenuPrecedent != nil }

    /// Installe `contenu` dans `fenetre` et passe en plein écran.
    func presenter<Contenu: View>(_ contenu: Contenu, dans fenetre: NSWindow) {
        guard !estPresente else { return }
        self.fenetre = fenetre
        contenuPrecedent = fenetre.contentView
        titreVisiblePrecedent = fenetre.titleVisibility == .visible

        let hote = NSHostingView(rootView: contenu)
        hote.frame = fenetre.contentView?.bounds ?? .zero
        fenetre.contentView = hote
        // La barre de titre **est** du chrome : elle disparaît avec le reste.
        fenetre.titleVisibility = .hidden
        fenetre.titlebarAppearsTransparent = true

        if !fenetre.styleMask.contains(.fullScreen) {
            fenetre.toggleFullScreen(nil)
        }
        sessionLog.info("mode séance présenté")
    }

    /// Restaure le contenu d'origine et quitte le plein écran.
    ///
    /// L'ordre importe : on sort du plein écran **avant** de restaurer, sinon
    /// l'ancienne vue est redimensionnée deux fois (une fois à la taille du
    /// plein écran, une fois à celle de la fenêtre) et les colonnes de
    /// `MeetingView` sautent visiblement.
    func retirer() {
        guard let fenetre, let contenuPrecedent else { return }
        if fenetre.styleMask.contains(.fullScreen) {
            fenetre.toggleFullScreen(nil)
        }
        fenetre.contentView = contenuPrecedent
        fenetre.titleVisibility = titreVisiblePrecedent ? .visible : .hidden
        fenetre.titlebarAppearsTransparent = false
        self.contenuPrecedent = nil
        self.fenetre = nil
        sessionLog.info("mode séance retiré")
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
    @State private var swapper = SessionWindowSwapper()
    @State private var fenetre: NSWindow?
    private var presentateur: SessionFullscreenPresenter { .shared }

    func body(content: Content) -> some View {
        content
            .background(WindowReader { fenetre = $0 })
            .onAppear { declarer() }
            .onDisappear {
                presentateur.declarerHote(meeting.ensuredStableID, capable: false)
                sortir()
            }
            .onChange(of: estEligible) { _, _ in declarer() }
            .onChange(of: presentateur.jeton) { _, _ in basculer() }
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

    private func declarer() {
        presentateur.declarerHote(meeting.ensuredStableID, capable: estEligible)
    }

    private func basculer() {
        if screen.session.isPresented { sortir() } else { entrer() }
    }

    private func entrer() {
        guard estEligible, let fenetre else { return }
        screen.session.enter()
        let vue = SessionFullscreenView(
            meeting: meeting,
            screen: screen,
            settings: settings,
            onOpenMeeting: { identifiant, t in ouvrir(identifiant, at: t) },
            onDiarize: onDiarize,
            onReidentify: onReidentify,
            onExit: { sortir() }
        )
        // Le conteneur est repassé explicitement : un `NSHostingView` créé à la
        // main ne descend de personne et n'hériterait d'aucun environnement —
        // les `@Query` de la vue de séance seraient vides.
        swapper.presenter(vue.modelContainer(context.container), dans: fenetre)
    }

    private func sortir() {
        guard screen.session.isPresented || swapper.estPresente else { return }
        screen.session.leave()
        swapper.retirer()
    }

    /// Ouvre la réunion source d'une citation de l'assistant.
    ///
    /// On **sort d'abord** du plein écran : ouvrir une autre réunion derrière
    /// un plein écran qui reste affiché donnerait l'impression que le clic n'a
    /// rien fait.
    private func ouvrir(_ meetingStableID: UUID, at t: Double?) {
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
private struct WindowReader: NSViewRepresentable {
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
    /// substitueraient deux fois le contenu de la même fenêtre, et la seconde
    /// restauration rendrait la première.
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
