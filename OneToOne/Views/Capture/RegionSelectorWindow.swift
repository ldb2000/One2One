import AppKit
import SwiftUI

/// La fenêtre de tracé de la « zone à la souris » (spec §5.1).
///
/// `NSPanel` plein écran au niveau `.screenSaver` : au-dessus de Teams en plein écran,
/// au-dessus de la pastille, au-dessus de tout — tracer une zone est le seul moment où
/// l'application prend l'écran entier, et une fenêtre qui passerait sous le contenu
/// partagé rendrait le tracé impossible.
///
/// Elle ne décide rien : la géométrie est dans `RegionSelection`, testée sans bureau.
/// Ce fichier n'est qu'un capteur de souris et d'échappement.
@MainActor
final class RegionSelectorWindow: NSPanel {

    static let shared = RegionSelectorWindow()

    private var onComplete: ((NormalizedRect) -> Void)?

    private convenience init() {
        self.init(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900),
                  styleMask: [.borderless, .nonactivatingPanel],
                  backing: .buffered,
                  defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Suivre l'utilisateur d'un espace à l'autre et se poser sur le plein écran de
        // Teams : même raison que pour la pastille.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Le curseur en croix dit ce qui est attendu : sans lui, l'écran voilé n'a
        // aucune affordance.
        acceptsMouseMovedEvents = true
    }

    /// Un panneau sans barre de titre ne devient pas fenêtre clé par défaut, et `Esc`
    /// n'arriverait alors jamais : le seul moyen d'annuler serait de tracer une zone.
    override var canBecomeKey: Bool { true }

    /// Ouvre le tracé sur l'écran qui porte la souris. `completion` n'est appelée que
    /// sur une zone retenue — annuler ne configure rien.
    func begin(completion: @escaping (NormalizedRect) -> Void) {
        onComplete = completion
        let ecran = Self.screenUnderMouse()
        setFrame(ecran.frame, display: true)
        let vue = RegionSelectorView(
            size: ecran.frame.size,
            onCancel: { [weak self] in self?.finish(nil) },
            onSelect: { [weak self] zone in self?.finish(zone) })
        contentView = NSHostingView(rootView: vue)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    private func finish(_ zone: NormalizedRect?) {
        let rappel = onComplete
        onComplete = nil
        orderOut(nil)
        // La vue hébergée est jetée : elle porte l'état du tracé en cours, et le
        // retrouver au prochain appel dessinerait le rectangle de la fois précédente.
        contentView = nil
        if let zone { rappel?(zone) }
    }

    private static func screenUnderMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

/// Le voile et le rectangle en cours de tracé.
private struct RegionSelectorView: View {

    let size: CGSize
    let onCancel: () -> Void
    let onSelect: (NormalizedRect) -> Void

    @State private var depart: CGPoint?
    @State private var courant: CGPoint?

    var body: some View {
        ZStack {
            One2OneToken.scrim
            if let rect = rectEnCours {
                // La zone retenue est **désignée**, pas assombrie : le voile reste
                // uniforme (une découpe par `blendMode` sur un panneau transparent rend
                // un trou noir, pas une fenêtre sur le bureau) et le cadre `accent/action`
                // dit ce qui sera capturé.
                Rectangle()
                    .fill(One2OneToken.action.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(One2OneToken.action, lineWidth: 2))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            if rectEnCours == nil {
                Text("Tracez la zone à capturer — Échap pour annuler")
                    .font(.plexSans(13, .medium))
                    .foregroundStyle(One2OneToken.darkInk1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(One2OneToken.pillBackground))
            }
        }
        .compositingGroup()
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { valeur in
                    if depart == nil { depart = valeur.startLocation }
                    courant = valeur.location
                }
                .onEnded { valeur in
                    let debut = depart ?? valeur.startLocation
                    depart = nil
                    courant = nil
                    guard let zone = RegionSelection.normalized(from: debut,
                                                                to: valeur.location,
                                                                in: size) else {
                        // Un clic n'est pas une zone : on annule plutôt que d'ouvrir une
                        // session sur quelques pixels.
                        onCancel()
                        return
                    }
                    onSelect(zone)
                }
        )
        .onExitCommand { onCancel() }
    }

    private var rectEnCours: CGRect? {
        guard let depart, let courant else { return nil }
        let rect = RegionSelection.drawnRect(from: depart, to: courant)
        return rect.width > 1 && rect.height > 1 ? rect : nil
    }
}
