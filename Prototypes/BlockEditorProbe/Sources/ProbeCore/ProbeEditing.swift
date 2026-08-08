import Foundation

/// Les gestes destructifs de la sonde. Chacun se ramène à une seule
/// `ProbeDocument.replace` — c'est tout l'intérêt : un seul endroit peut se
/// tromper.
public enum ProbeEditing {

    /// Frappe et collage. Un `\n` dans `text` scinde ; plusieurs produisent
    /// un bloc par ligne.
    @discardableResult
    public static func insertText(_ text: String,
                                  in document: inout ProbeDocument,
                                  selection: ProbeSelection) -> ProbePosition {
        document.replace(selection, with: text)
    }

    /// ⏎ : scinde au curseur, après avoir supprimé la sélection s'il y en a une.
    @discardableResult
    public static func insertNewline(in document: inout ProbeDocument,
                                     selection: ProbeSelection) -> ProbePosition {
        document.replace(selection, with: "\n")
    }

    /// ⌫ : supprime la sélection, sinon une séquence composée, sinon fusionne
    /// avec le bloc précédent.
    @discardableResult
    public static func deleteBackward(in document: inout ProbeDocument,
                                      selection: ProbeSelection) -> ProbePosition {
        guard selection.isCollapsed else {
            return document.replace(selection, with: "")
        }
        let caret = document.clamped(selection.head)
        let previous = document.position(before: caret)
        guard previous != caret else { return caret }
        return document.replace(ProbeSelection(anchor: previous, head: caret), with: "")
    }

    /// ⌦ : symétrique de ⌫ — remonte le bloc suivant quand le curseur est en
    /// fin de bloc.
    @discardableResult
    public static func deleteForward(in document: inout ProbeDocument,
                                     selection: ProbeSelection) -> ProbePosition {
        guard selection.isCollapsed else {
            return document.replace(selection, with: "")
        }
        let caret = document.clamped(selection.head)
        let next = document.position(after: caret)
        guard next != caret else { return caret }
        return document.replace(ProbeSelection(anchor: caret, head: next), with: "")
    }
}
