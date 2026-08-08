import Foundation

/// Un bloc de la sonde. Volontairement pauvre : pas de type, pas d'attributs,
/// pas de `Delta`. Le prototype ne prouve rien sur le modèle de document ; y
/// mettre un modèle riche masquerait le vrai sujet derrière du travail
/// confortable.
public struct ProbeBlock: Identifiable, Equatable {

    /// Identité stable : c'est elle qui permet à la pile de vues de réutiliser
    /// le `NSTextView` d'un bloc au lieu de le reconstruire à chaque frappe.
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// Longueur en unités UTF-16, l'unité des `NSRange` d'AppKit.
    public var length: Int { (text as NSString).length }
}
