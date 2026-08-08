import AppKit

/// Menu minimal. Il existe pour une seule raison : router ⌘Z, ⌘⇧Z, ⌘A, ⌘X, ⌘C
/// et ⌘V par la chaîne des répondants, comme une vraie application — c'est la
/// seule façon honnête de tester si l'undo peut être repris au niveau du
/// conteneur.
enum ProbeMenu {

    static func make() -> NSMenu {
        let root = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quitter la sonde",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        root.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rétablir",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner",
                         action: #selector(NSResponder.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu
        root.addItem(editItem)

        return root
    }
}
