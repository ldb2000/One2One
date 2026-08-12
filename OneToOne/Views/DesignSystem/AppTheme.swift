import SwiftUI

/// Jetons du langage visuel de l'application, lus sur les captures de design.
///
/// Patron : `enum` de constantes statiques, comme `MeetingTheme`.
///
/// ⚠️ Les valeurs de couleur sont **lues sur les images** des captures. En cas
/// d'écart avec les fichiers sources de Claude Design, le fichier source prime.
public enum AppTheme {

    // MARK: - Couleurs de fond

    /// Fond de fenêtre : barre latérale, pourtour.
    public static let fondCreme = Color(red: 0.937, green: 0.929, blue: 0.910)
    /// Fond de contenu : listes, tableaux, cartes.
    public static let fondContenu = Color(nsColor: .textBackgroundColor)
    /// Teinte des lignes alternées, très légère.
    public static let ligneAlternee = Color(red: 0.984, green: 0.980, blue: 0.973)
    /// Séparateur fin entre les lignes.
    public static let separateur = Color.secondary.opacity(0.15)

    // MARK: - Couleurs de texte

    public static let textePrincipal = Color.primary
    public static let texteSecondaire = Color.secondary

    // MARK: - Couleurs sémantiques

    /// Bleu système des verbes et des liens. Même valeur que le handoff éditeur
    /// (`#0a6cff`) : ne pas la dupliquer sous un autre nom.
    public static let verbe = Color(red: 0.039, green: 0.424, blue: 1.0)
    // Les quatre valeurs ci-dessous ont été alignées le 2026-08-12 sur la spec
    // de la fiche collaborateur v3, plus récente et écrite avec ses valeurs
    // exactes. Elles étaient auparavant lues sur les captures de la vitrine
    // Actions, d'où un écart de teinte sur des rôles identiques : le « rouge
    // d'urgence » n'était pas le même d'un écran à l'autre, alors que les deux
    // s'ouvrent depuis la même barre latérale. `FicheTokens` les reprend au
    // lieu de les redéfinir — un rôle, une valeur, un nom.
    /// `#D9483F`
    public static let urgenceForte = Color(red: 0.851, green: 0.282, blue: 0.247)
    /// `#C9762F`
    public static let urgenceMoyenne = Color(red: 0.788, green: 0.463, blue: 0.184)
    /// `#3F9D6B`
    public static let nominal = Color(red: 0.247, green: 0.616, blue: 0.420)
    /// `#7A5CD6`
    public static let accentManager = Color(red: 0.478, green: 0.361, blue: 0.839)

    /// Couleur d'affichage d'une échéance, d'après sa seule urgence.
    public static func couleur(_ urgence: Urgence) -> Color {
        switch urgence {
        case .forte: return urgenceForte
        case .moyenne: return urgenceMoyenne
        case .aVenir, .sansEcheance: return texteSecondaire
        }
    }

    // MARK: - Typographie

    public static let titreEcran = Font.system(size: 28, weight: .semibold)
    /// Intitulé de section : petites capitales.
    /// L'interlettrage élargi n'est pas descriptible sur un `Font` — c'est un
    /// réglage de `Text`/`View` (`.tracking(_:)`), pas une propriété de police ;
    /// il devra être appliqué au site d'usage le jour où ce jeton sera consommé.
    /// Couleur grise : à la charge du consommateur (`AppTheme.texteSecondaire`).
    public static let intituleSection = Font.system(size: 11, weight: .semibold).smallCaps()
    public static let titreLigne = Font.system(size: 15, weight: .semibold)
    public static let sousTitre = Font.system(size: 12)
    /// Codes projet, horaires, noms de commande.
    public static let chasseFixe = Font.system(size: 12, design: .monospaced)

    // MARK: - Espacements

    public static let margeContenu: CGFloat = 24
    public static let hauteurLigne: CGFloat = 44
    public static let rayonPilule: CGFloat = 6
}
