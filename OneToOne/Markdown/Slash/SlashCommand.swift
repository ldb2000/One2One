import Foundation

/// Une entrée du menu `/` : conversion ou insertion de bloc proposée à la
/// frappe. Structure de conception reprise d'AppFlowy (`slash-menu-options.ts` :
/// clé, libellé, mots-clés, alias, raccourci, groupe, filtrage contextuel) —
/// pas de code repris, AppFlowy étant en TypeScript sous licence AGPL.
///
/// Logique pure : aucune dépendance à `NSTextView`/`NSTextStorage`. `action`
/// décrit *quoi* faire sans l'exécuter — `SlashController` (tâche 5)
/// interprète cette valeur contre le storage réel.
struct SlashCommand: Identifiable, Equatable {

    /// Identifiant stable d'une entrée, indépendant de son libellé affiché.
    enum Key: String, Hashable, CaseIterable {
        case text
        case heading1, heading2, heading3
        case bulletList, orderedList, taskList
        case blockquote
        case thematicBreak
        case image
    }

    /// Groupe d'affichage. L'ordre des cas est l'ordre d'affichage dans le
    /// panneau (tâche 4) : `CaseIterable` synthétise `allCases` dans l'ordre
    /// de déclaration ci-dessous, pas question de le trier autrement.
    enum Group: String, CaseIterable, Equatable {
        case basicBlocks
        case media

        /// En-tête affiché au-dessus des entrées du groupe.
        var title: String {
            switch self {
            case .basicBlocks: return "Blocs de base"
            case .media: return "Média"
            }
        }
    }

    /// Ce que fait une entrée, sans l'exécuter. `.convertBlock`/`.convertList`
    /// correspondent chacune à un appel direct de `MarkdownBlockCommands` sur
    /// la ligne du curseur. `.insertThematicBreak` et `.insertImage` ne sont
    /// **pas** des conversions : `MarkdownBlockCommands.setBlockType` refuse
    /// `.thematicBreak` dans son type `LineBlockType` depuis le commit
    /// `f20b979` — appliqué à une ligne existante, le séparateur en détruisait
    /// le contenu inline à la sérialisation (`emitParagraph` renvoie `"---"`
    /// sans jamais lire `inline`). Le séparateur doit donc être **inséré**
    /// comme nouvelle ligne portant `.mdBlockType = .thematicBreak`, sans
    /// toucher à la ligne du curseur ; `SlashController` (tâche 5) réalise
    /// cette insertion. `.insertImage` n'est pas davantage une conversion —
    /// c'est une action asynchrone (ouvrir un sélecteur de fichier, puis
    /// appeler `EditorTextView.insertImagePlaceholder`) que `SlashController`
    /// pilotera ; modélisée ici sans être implémentée.
    enum Action: Equatable {
        case convertBlock(MarkdownBlockCommands.LineBlockType)
        case convertList(ListInfo.Kind)
        case insertThematicBreak
        case insertImage
    }

    let key: Key
    /// Libellé affiché, en français.
    let label: String
    /// Mots-clés de recherche complémentaires au libellé (synonymes français).
    let keywords: [String]
    /// Alias de recherche (abréviations, termes anglais/markdown courants —
    /// ex. `h1`, `todo`).
    let aliases: [String]
    /// Raccourci affiché à droite de l'entrée (`#`, `##`, `-`…). `nil` quand
    /// l'entrée n'a pas d'équivalent markdown littéral à montrer.
    let shortcut: String?
    let group: Group
    let action: Action
    /// Fonctionnalité requise pour que l'entrée soit proposée. `nil` signifie
    /// qu'aucun `MarkdownFeature` ne la conditionne : c'est le cas pour
    /// « Texte » (le paragraphe est l'état de base, pas une fonctionnalité
    /// optionnelle) et pour « Image » (`MarkdownFeature` ne modélise que la
    /// syntaxe markdown ; le collage d'image existant — `EditorTextView.paste`
    /// — n'est déjà conditionné par aucune fonctionnalité).
    let requiredFeature: MarkdownFeature?

    var id: Key { key }

    /// Vrai si `query` désigne cette entrée : comparaison insensible à la
    /// casse et aux accents sur le libellé, les mots-clés puis les alias.
    /// Une requête vide (juste après avoir tapé `/`) matche tout.
    func matches(_ query: String) -> Bool {
        let needle = query.slashSearchNormalized
        guard !needle.isEmpty else { return true }
        if label.slashSearchNormalized.contains(needle) { return true }
        if keywords.contains(where: { $0.slashSearchNormalized.contains(needle) }) { return true }
        if aliases.contains(where: { $0.slashSearchNormalized.contains(needle) }) { return true }
        return false
    }
}

extension String {
    /// Forme repliée pour la recherche du menu `/` : sans casse ni diacritique,
    /// pour que « numerotee » retrouve « numérotée ». `folding` avec
    /// `locale: nil` applique une transformation Unicode indépendante de la
    /// locale utilisateur — vérifié : `"numérotée".folding([.diacriticInsensitive,
    /// .caseInsensitive], locale: nil) == "numerotee".folding(...)`.
    var slashSearchNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
