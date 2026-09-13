import Foundation

/// Les cinq derniers projets ouverts, tels que la barre latérale les listera
/// (section « RÉCENTS » de la capture `2b-sidebar-variante-arbre-replie.png`).
///
/// **Pourquoi une chaîne et non un tableau.** `@AppStorage` ne stocke pas de
/// `[UUID]` (constat §2.20 de la spec) ; la décision **D4** retient donc une
/// chaîne d'UUID séparés par des virgules sous la clé `projects.recentIDs`, et
/// range toute la logique ici : le format n'est jamais manipulé dans une vue.
///
/// Un `enum` namespace de fonctions pures, comme le veut la convention du
/// dépôt : rien à instancier, rien à synchroniser, et une liste bornée qui se
/// vérifie sans monter d'écran.
enum RecentProjects {

    /// La clé `@AppStorage` de la liste (D4).
    static let key = "projects.recentIDs"

    /// Nombre de projets retenus. Au-delà, le plus anciennement ouvert tombe.
    static let max = 5

    /// Le séparateur du format persisté.
    private static let separator = ","

    /// Inscrit `id` en tête de la liste et rend la chaîne à persister.
    ///
    /// - Le projet déjà présent **remonte** au lieu d'être dupliqué : la liste
    ///   des récents est un ordre d'usage, pas un journal.
    /// - La chaîne rendue est normalisée (bornée, sans doublon ni fragment
    ///   illisible), même si celle reçue ne l'était pas.
    static func push(_ id: UUID, into raw: String) -> String {
        var ids = self.ids(from: raw)
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        return ids.prefix(max)
            .map(\.uuidString)
            .joined(separator: separator)
    }

    /// Lit la liste persistée, du plus récemment ouvert au plus ancien.
    ///
    /// Tolérante par construction : un fragment illisible (réglage édité à la
    /// main, format antérieur) est ignoré sans faire disparaître les
    /// identifiants valides qui l'entourent.
    static func ids(from raw: String) -> [UUID] {
        var vus = Set<UUID>()
        var resultat: [UUID] = []
        for fragment in raw.split(separator: separator, omittingEmptySubsequences: true) {
            let nettoye = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = UUID(uuidString: nettoye), !vus.contains(id) else { continue }
            vus.insert(id)
            resultat.append(id)
            if resultat.count == max { break }
        }
        return resultat
    }
}
