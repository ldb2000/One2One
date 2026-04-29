import SwiftUI
import AppKit

struct RectSelectorOverlay: View {
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    
    var onSelected: (CGRect) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background semi-transparent
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onContinuousHover { _ in
                    // Just to capture mouse if needed, but we use Gesture
                }
            
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
                .onEnded { _ in
                    // Selection remains until validation or cancellation
                }
        )
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    onCancel()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 { // Enter / Return
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

class RectSelectorWindow: NSWindow {
    static func show(onSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
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
        
        let contentView = RectSelectorOverlay(
            onSelected: { rect in
                window.close()
                // On convertit les coordonnées locales SwiftUI (top-left) en coordonnées écran Cocoa (bottom-left)
                // En fait, ScreenCaptureKit utilise le système de coordonnées écran (0,0 en haut à gauche pour SCDisplay).
                // Les coordonnées SwiftUI ici sont déjà relatives à l'écran si la fenêtre couvre l'écran.
                onSelected(rect)
            },
            onCancel: {
                window.close()
                onCancel()
            }
        )
        
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }
}
