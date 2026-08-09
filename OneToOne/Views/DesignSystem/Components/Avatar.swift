import SwiftUI

/// Pastille d'initiales, telle que les captures la montrent en tête de ligne
/// et dans les listes de collaborateurs.
public struct Avatar: View {

    public let nom: String

    public init(nom: String) {
        self.nom = nom
    }

    /// Initiales d'un nom : première lettre du premier mot, première lettre du
    /// dernier. Un seul mot ne donne qu'une initiale.
    public static func initiales(de nom: String) -> String {
        let mots = nom.split(separator: " ").filter { !$0.isEmpty }
        guard let premier = mots.first else { return "" }
        let debut = String(premier.prefix(1))
        guard mots.count > 1, let dernier = mots.last else { return debut.uppercased() }
        return (debut + String(dernier.prefix(1))).uppercased()
    }

    public var body: some View {
        Text(Self.initiales(de: nom))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppTheme.textePrincipal)
            .frame(width: 22, height: 22)
            .background(Circle().fill(AppTheme.separateur))
            .help(nom)
    }
}
