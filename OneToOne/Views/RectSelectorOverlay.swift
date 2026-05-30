import SwiftUI
import AppKit

struct RectSelectorOverlay: View {
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?

    var onSelected: (CGRect) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onContinuousHover { _ in }

            if let start = startPoint, let current = currentPoint {
                let rect = CGRect(
                    x: min(start.x, current.x),
                    y: min(start.y, current.y),
                    width: abs(start.x - current.x),
                    height: abs(start.y - current.y)
                )

                Rectangle()
                    .fill(Color.blue.opacity(0.2))
                    .overlay(Rectangle().stroke(Color.blue, lineWidth: 2))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.origin.x, y: rect.origin.y)
            }

            VStack {
                Text("Dessinez un rectangle pour définir la zone de capture")
                    .font(.headline)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial))
                    .padding()
                Spacer()
                HStack {
                    Spacer()
                    Text("ESC pour annuler · Entrée pour valider")
                        .font(.caption)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.ultraThinMaterial))
                        .padding()
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startPoint == nil {
                        startPoint = value.startLocation
                    }
                    currentPoint = value.location
                }
                .onEnded { _ in }
        )
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    onCancel()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 { // Enter
                    if let start = startPoint, let current = currentPoint {
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(start.x - current.x),
                            height: abs(start.y - current.y)
                        )
                        if rect.width > 10 && rect.height > 10 {
                            onSelected(rect)
                        }
                    }
                    return nil
                }
                return event
            }
        }
    }
}

/// Sélecteur multi-écrans : ouvre une fenêtre transparente sur CHAQUE
/// `NSScreen`. La validation renvoie le rect en coordonnées locales de
/// l'écran + son `CGDirectDisplayID` pour permettre au caller de passer
/// la bonne `SCDisplay` à ScreenCaptureKit.
class RectSelectorWindow: NSWindow {

    /// Liste partagée des fenêtres ouvertes (une par écran). Tenue en vie
    /// pour qu'aucune ne soit deallocée pendant la sélection ; vidée
    /// quand l'utilisateur valide ou annule.
    private static var activeWindows: [RectSelectorWindow] = []

    static func show(onSelected: @escaping (CGRect, CGDirectDisplayID) -> Void,
                     onCancel: @escaping () -> Void) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            onCancel()
            return
        }

        let finish: () -> Void = {
            for w in activeWindows { w.close() }
            activeWindows.removeAll()
        }

        for screen in screens {
            let displayID = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value ?? 0

            let window = RectSelectorWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .statusBar
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let overlay = RectSelectorOverlay(
                onSelected: { rect in
                    finish()
                    onSelected(rect, CGDirectDisplayID(displayID))
                },
                onCancel: {
                    finish()
                    onCancel()
                }
            )

            window.contentView = NSHostingView(rootView: overlay)
            // setFrame APRÈS la création — sinon l'écran secondaire reçoit
            // un cadre relatif à l'écran principal (origin bottom-left global).
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            activeWindows.append(window)
        }
    }
}
