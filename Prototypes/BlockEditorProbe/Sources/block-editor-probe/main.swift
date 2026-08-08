import AppKit

// Point d'entrée de la sonde. Exécutable SwiftPM nu : pas de bundle `.app`,
// donc `setActivationPolicy(.regular)` et `activate` sont indispensables pour
// obtenir une fenêtre au premier plan et le clavier.
let arguments = CommandLine.arguments

/// Valeur entière d'une option `--nom valeur`.
func intOption(_ name: String, default fallback: Int) -> Int {
    guard let position = arguments.firstIndex(of: name),
          arguments.indices.contains(position + 1),
          let value = Int(arguments[position + 1]) else { return fallback }
    return value
}

let mode: ProbeMode = arguments.contains("--scale") ? .scale : .interactive
let blockCount = intOption("--blocks", default: mode == .scale ? 200 : 12)

let application = NSApplication.shared
application.setActivationPolicy(.regular)
// `main.swift` est un contexte non isolé au sens du compilateur, mais il
// s'exécute forcément sur le thread principal au lancement du processus,
// avant tout usage de la concurrence structurée : `assumeIsolated` est donc
// sûr ici, et nécessaire pour construire un délégué `@MainActor`.
let delegate = MainActor.assumeIsolated {
    ProbeAppDelegate(mode: mode, blockCount: blockCount)
}
application.delegate = delegate
application.mainMenu = ProbeMenu.make()
application.activate(ignoringOtherApps: true)
application.run()
