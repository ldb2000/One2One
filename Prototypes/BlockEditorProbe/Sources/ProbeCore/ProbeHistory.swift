import Foundation

/// Un état complet de l'éditeur : le document et la sélection.
public struct ProbeSnapshot: Equatable {

    public var document: ProbeDocument
    public var selection: ProbeSelection

    public init(document: ProbeDocument, selection: ProbeSelection) {
        self.document = document
        self.selection = selection
    }
}

/// Historique **par instantanés**, au-dessus des vues.
///
/// Chaque `NSTextView` a son propre `UndoManager` ; laissés actifs, ils
/// annuleraient bloc par bloc, dans l'ordre où l'utilisateur a visité les
/// blocs plutôt que dans l'ordre des modifications. La sonde les désactive
/// tous (`allowsUndo = false`) et enregistre ici l'état **avant** chaque
/// mutation.
///
/// Volontairement sans fusion des frappes consécutives : un ⌘Z par caractère
/// suffit à prouver que l'undo est global. La fusion est un raffinement, pas
/// une question ouverte.
public final class ProbeHistory {

    private var undoStack: [ProbeSnapshot] = []
    private var redoStack: [ProbeSnapshot] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// À appeler avec l'état **avant** la mutation, juste avant de l'appliquer.
    public func record(_ snapshot: ProbeSnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    public func undo(current: ProbeSnapshot) -> ProbeSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public func redo(current: ProbeSnapshot) -> ProbeSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
