import Foundation

/// Une entrée affichée par `MentionPanel` : soit un collaborateur existant,
/// soit l'entrée de création en fin de liste. Logique pure, testable sans
/// `NSTextView` ni SwiftData.
enum MentionRow: Equatable {
    case candidate(MentionCandidate)
    /// Porte le nom tel que tapé (`query`, **non trimé**) — c'est ce texte
    /// qui est transmis tel quel à la closure de création
    /// (`MentionController.createCollaborator`) si l'entrée est validée ;
    /// `MentionController.apply` ne le trime pas non plus, cohérent avec le
    /// libellé affiché « Créer "<query>" ».
    case create(String)
}

/// Construit les entrées du panneau `@` à partir des candidats déjà
/// filtrés/triés par la closure `searchCollaborators` injectée depuis la
/// couche vue (piège 2 de la spec : la requête part vers SwiftData, ce
/// module n'y touche pas — voir `MentionController`). La seule décision pure
/// qui reste ici : faut-il ajouter l'entrée « Créer … » en fin de liste.
enum MentionCatalog {

    /// `candidates`, plus l'entrée `.create(query)` en fin de liste si (a)
    /// `query` n'est pas vide une fois trimée — impossible de créer un
    /// collaborateur sans nom — et (b) **aucun** candidat n'a exactement ce
    /// nom, comparé insensible à la casse et aux accents via
    /// `slashSearchNormalized` (repli déjà utilisé par le menu `/`, réutilisé
    /// ici tel quel plutôt que réécrit — voir `SlashCommand.swift`).
    ///
    /// Cette exclusion sur correspondance exacte est la garde retenue contre
    /// la création accidentelle d'un doublon (point laissé ouvert par la
    /// spec, tranché ici sans confirmation modale) : taper le nom exact d'un
    /// collaborateur déjà connu ne propose jamais de le recréer — il faut
    /// alors le sélectionner dans la liste. Un nom approchant (ex. « Mari »
    /// quand « Marie Dupont » existe) continue au contraire de proposer la
    /// création, sans quoi il deviendrait impossible de créer quelqu'un dont
    /// le nom est un sous-mot d'un collaborateur existant.
    static func rows(candidates: [MentionCandidate], query: String) -> [MentionRow] {
        var rows = candidates.map(MentionRow.candidate)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        let normalizedQuery = trimmed.slashSearchNormalized
        let hasExactMatch = candidates.contains { $0.name.slashSearchNormalized == normalizedQuery }
        guard !hasExactMatch else { return rows }
        rows.append(.create(query))
        return rows
    }

    /// URL de mention pour `id` : schéma `onetoone`, déjà enregistré et géré
    /// par ce projet pour le callback `MickeyIntegration`
    /// (`callbackScheme = "onetoone"`, hôte `session-done`) — réutilisé ici
    /// avec l'hôte `collaborator`, distinct, plutôt qu'un schéma inédit.
    /// Forme : `onetoone://collaborator/<uuid>`.
    static func mentionURL(for id: UUID) -> URL {
        // `id.uuidString` ne produit que des caractères hex et des tirets,
        // toujours valides dans une URL — la construction ne peut pas échouer.
        URL(string: "onetoone://collaborator/\(id.uuidString)")!
    }

    /// Extrait l'identifiant d'une URL de mention ; `nil` si `url` n'a pas
    /// exactement cette forme (schéma ou hôte différents, chemin sans UUID
    /// valide). Symétrique de `mentionURL(for:)` — pas utilisé par
    /// l'insertion elle-même, mais garantit que le format choisi est bien
    /// résoluble (raison n°3 de la spec pour le choix d'un lien markdown).
    static func collaboratorID(from url: URL) -> UUID? {
        guard url.scheme == "onetoone", url.host == "collaborator" else { return nil }
        let uuidString = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: uuidString)
    }
}
