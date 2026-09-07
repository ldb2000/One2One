import Foundation

/// Le découpage d'une ligne de note en texte et **mentions** `@Prénom`, pour
/// que la colonne de notes du mode séance rende `@Yann` en pilule (capture
/// `1b-mode-seance.png` : « Timing de reprise à définir. Qui donne le feu
/// vert ? `@Yann` »).
///
/// Pourquoi une fonction pure et non un `AttributedString` construit dans la
/// vue : la règle intéressante n'est pas la pilule, c'est **ce qui en est
/// une**. `@Yann` en est une, `laurent@april.com` n'en est pas (le `@` y est
/// au milieu d'un mot), et `@Inconnu` n'en est pas non plus tant qu'aucun
/// collaborateur ne porte ce nom — peindre en bleu une personne qui n'existe
/// pas donne l'illusion d'une notification qui n'aura pas lieu.
///
/// La reconnaissance du nom est déléguée à `CollaboratorMentionSource.search`,
/// la même que celle de l'éditeur markdown : un prénom reconnu ici doit être
/// reconnu là, sinon le même texte s'afficherait différemment selon l'écran.
/// Ce lot n'ajoute **que le rendu** : aucune saisie assistée, aucun panneau de
/// complétion dans la colonne de notes.
enum SessionMentionRuns {

    /// Un fragment de ligne.
    enum Run: Sendable, Equatable {
        /// Du texte ordinaire.
        case texte(String)
        /// Une mention reconnue : le nom **sans** son `@`.
        case mention(String)

        /// Le texte tel qu'il s'écrit, mention comprise. Sert au test de
        /// non-perte : la concaténation des fragments doit rendre la ligne
        /// d'origine, au caractère près.
        var brut: String {
            switch self {
            case .texte(let valeur):   return valeur
            case .mention(let nom):    return "@\(nom)"
            }
        }
    }

    /// Caractères admis dans un nom mentionné : lettres, chiffres, tiret,
    /// apostrophe et point (`@Jean-Luc`, `@O'Neil`, `@J.Martin`). L'espace en
    /// est exclu : une mention `@Pierre Yves` s'écrirait sur deux mots, et
    /// avaler le mot suivant transformerait « @Yann demande » en une personne
    /// nommée « Yann demande ».
    private static func estAdmis(_ caractere: Character) -> Bool {
        caractere.isLetter || caractere.isNumber
            || caractere == "-" || caractere == "'" || caractere == "."
    }

    /// Découpe `texte` en fragments. `estUneMention` décide si un candidat est
    /// une mention reconnue — la vue y branche le catalogue de collaborateurs.
    ///
    /// Fragments contigus de même nature fusionnés : deux `.texte` de suite ne
    /// seraient qu'un détail d'implémentation exposé aux tests.
    static func runs(in texte: String,
                     estUneMention: (String) -> Bool) -> [Run] {
        var resultat: [Run] = []
        var courant = ""
        var index = texte.startIndex

        func viderLeTexte() {
            guard !courant.isEmpty else { return }
            resultat.append(.texte(courant))
            courant = ""
        }

        while index < texte.endIndex {
            let caractere = texte[index]
            // Un `@` n'ouvre une mention qu'en début de ligne ou après un
            // caractère qui n'appartient pas à un mot : sinon `a@b` en
            // produirait une.
            let precedentEstUnMot: Bool
            if index == texte.startIndex {
                precedentEstUnMot = false
            } else {
                precedentEstUnMot = estAdmis(texte[texte.index(before: index)])
            }

            guard caractere == "@", !precedentEstUnMot else {
                courant.append(caractere)
                index = texte.index(after: index)
                continue
            }

            var apres = texte.index(after: index)
            var nom = ""
            while apres < texte.endIndex, estAdmis(texte[apres]) {
                nom.append(texte[apres])
                apres = texte.index(after: apres)
            }
            // Un nom peut finir par une ponctuation collée (`@Yann.`) : le
            // point final appartient à la phrase, pas à la personne.
            while let dernier = nom.last, dernier == "." || dernier == "'" {
                nom.removeLast()
                apres = texte.index(before: apres)
            }

            if !nom.isEmpty, estUneMention(nom) {
                viderLeTexte()
                resultat.append(.mention(nom))
                index = apres
            } else {
                courant.append(caractere)
                index = texte.index(after: index)
            }
        }

        viderLeTexte()
        return resultat
    }

    /// Vrai si `nom` désigne un collaborateur connu.
    ///
    /// `CollaboratorMentionSource.search` filtre par sous-chaîne normalisée
    /// (accents repliés) : on exige donc en plus que le nom du candidat
    /// **commence** par le mot mentionné, sinon `@a` reconnaîtrait tout le
    /// monde.
    @MainActor
    static func estConnu(_ nom: String, parmi collaborateurs: [Collaborator]) -> Bool {
        let cible = nom.slashSearchNormalized
        guard !cible.isEmpty else { return false }
        return CollaboratorMentionSource.search(nom, in: collaborateurs).contains { candidat in
            candidat.name.slashSearchNormalized.hasPrefix(cible)
                || candidat.name
                    .split(separator: " ")
                    .contains { String($0).slashSearchNormalized.hasPrefix(cible) }
        }
    }
}
