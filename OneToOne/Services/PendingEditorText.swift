import Foundation
import AppKit

/// Le markdown qu'un éditeur porte **à l'écran**, quel que soit ce que le
/// modèle contient déjà.
///
/// L'éditeur markdown ne propage pas la frappe au binding immédiatement : il
/// sérialise puis écrit après un débounce (0,3 s par défaut, cf.
/// `MarkdownTextEditor`), en annulant l'écriture précédente à chaque touche.
/// Son démontage ne vide pas l'écriture en attente. Tout ce qui juge une
/// réunion sur son modèle **à la fermeture de l'écran** juge donc un état qui
/// peut avoir jusqu'à un débounce de retard — et pour
/// `NoteFactory.isDiscardableEmptyNote`, ce retard vaut la suppression, sans
/// confirmation, du texte qu'on vient de taper.
///
/// Passe par `MarkdownEditorRegistry`, où l'éditeur s'enregistre sous son
/// `editorID` : c'est le seul accès à l'éditeur vivant depuis une vue qui ne
/// le possède pas.
@MainActor
enum PendingEditorText {

    /// Le markdown affiché par l'éditeur enregistré sous `editorID`, ou `nil`
    /// s'il n'y en a aucun — écran non monté, ou déjà démonté.
    static func onScreen(editorID: String) -> String? {
        guard !editorID.isEmpty,
              let textView = MarkdownEditorRegistry.shared.textView(for: editorID),
              let storage = textView.textStorage
        else { return nil }
        return MarkdownSerializer.serialize(storage)
    }
}
