import SwiftUI

/// Métadonnée alignée à droite, colorée par son urgence — « 12 j », « 27/07 »,
/// « 6 semaines » dans les captures. La couleur porte l'information ; le libellé
/// reste court.
public struct MetaValue: View {

    public let texte: String
    public let urgence: Urgence
    public let largeurMinimale: CGFloat

    public init(texte: String, urgence: Urgence, largeurMinimale: CGFloat = 52) {
        self.texte = texte
        self.urgence = urgence
        self.largeurMinimale = largeurMinimale
    }

    public var body: some View {
        Text(texte)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.couleur(urgence))
            .frame(minWidth: largeurMinimale, alignment: .trailing)
    }
}
