import AppKit
import ProbeCore

enum ProbeMode {
    case interactive
    case scale
}

/// Fenêtre de la sonde, construite programmatiquement — pas de bundle `.app`,
/// pas de nib.
@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {

    private let mode: ProbeMode
    private let blockCount: Int
    private var window: NSWindow?
    private var coordinator: SelectionCoordinator?

    init(mode: ProbeMode, blockCount: Int) {
        self.mode = mode
        self.blockCount = blockCount
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if mode == .scale {
            ScaleHarness.run(blockCount: blockCount)
            NSApp.terminate(nil)
            return
        }
        openWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func openWindow() {
        let coordinator = SelectionCoordinator(document: ProbeDocument(texts: SampleText.blocks(count: blockCount)))
        let stack = BlockStackView(coordinator: coordinator)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 620))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = stack
        stack.setFrameSize(NSSize(width: scroll.contentSize.width, height: 400))
        stack.autoresizingMask = [.width]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Sonde — éditeur par blocs (\(blockCount) blocs)"
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)

        coordinator.attach(stack: stack)

        self.window = window
        self.coordinator = coordinator
    }
}

/// Texte de remplissage. Volontairement en français, avec accents : le premier
/// « ê » mal saisi se verrait tout de suite.
enum SampleText {

    private static let lines = [
        "Le prototype ne prouve rien sur le modèle de document.",
        "Chaque bloc est une vue autonome — c'est tout ce qu'on teste ici.",
        "Un être humain doit pouvoir taper « forêt », « cœur », « à côté ».",
        "La sélection traversante est le vrai risque de la réécriture.",
        "L'undo doit être global, jamais bloc par bloc.",
        "Le collage multi-lignes crée un bloc par ligne."
    ]

    static func blocks(count: Int) -> [String] {
        (0..<max(count, 1)).map { index in
            "\(index + 1). \(lines[index % lines.count])"
        }
    }
}
