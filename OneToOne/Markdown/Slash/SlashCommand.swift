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
        case heading4, heading5, heading6
        case bulletList, orderedList, taskList
        case blockquote
        case callout
        case codeBlock
        case thematicBreak
        case image
        case date
        case table
        case emoji
        case file
    }

    /// Groupe d'affichage. L'ordre des cas est l'ordre d'affichage dans le
    /// panneau (tâche 4) : `CaseIterable` synthétise `allCases` dans l'ordre
    /// de déclaration ci-dessous, pas question de le trier autrement.
    enum Group: String, CaseIterable, Equatable {
        case basicBlocks
        case media
        /// Insertions ponctuelles de texte qui ne sont ni un bloc de base ni
        /// un média — « Date » puis « Emoji ». Groupe séparé plutôt que
        /// rattaché à `.media` : ni une date ni un emoji ne sont un média, et
        /// `.media`/« Média » reste fidèle à son seul contenu actuel (Image).
        case insertions

        /// En-tête affiché au-dessus des entrées du groupe.
        var title: String {
            switch self {
            case .basicBlocks: return "Blocs de base"
            case .media: return "Média"
            case .insertions: return "Insertions"
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
    /// pilotera ; modélisée ici sans être implémentée. `.insertDate` suit le
    /// même principe qu'`.insertImage` (action asynchrone : ouvrir un
    /// sélecteur, puis insérer le résultat au point du curseur) mais insère
    /// du **texte brut** — la date choisie, formatée — plutôt qu'un
    /// placeholder attribué ; voir `SlashController.insertDate`. `.insertTable`
    /// est, comme `.insertThematicBreak`, une insertion synchrone d'un bloc
    /// entier plutôt qu'une conversion : un tableau n'a pas d'équivalent
    /// `MarkdownBlockCommands.LineBlockType` (`setBlockType` ne sait muter
    /// qu'une ligne existante en un type qui tient sur une seule ligne —
    /// un tableau, lui, est une grille de plusieurs paragraphes-cellules).
    /// Voir `SlashController.insertTable`. `.insertCallout` (« Encadré »)
    /// n'est pas davantage une simple conversion : c'est une citation
    /// (`MarkdownBlockCommands.LineBlockType.blockquote`, mécanisme inchangé)
    /// précédée du texte littéral `"💡 "` — `SlashController.applyCallout`
    /// insère ce préfixe puis délègue à `applyBlockConversion(.blockquote, …)`
    /// pour poser `.mdBlockType` sur la ligne entière, préfixe compris. Aucun
    /// nouveau `BlockType`/`LineBlockType` : un encadré sérialise en
    /// `"> 💡 texte"`, une citation ordinaire dont `BlockquoteRuleLayout`
    /// peint déjà le filet — l'emoji est ce qui la distingue visuellement
    /// d'une citation, pas un attribut séparé. `.insertCodeBlock` (« Bloc de
    /// code ») est, comme `.insertThematicBreak`, une insertion synchrone
    /// d'un bloc entier : `.codeBlock` est volontairement absent de
    /// `MarkdownBlockCommands.LineBlockType` (voir sa doc — appliqué à une
    /// ligne existante, il en perdrait l'inline à la sérialisation) et ne
    /// peut donc pas être une conversion. `SlashController.insertCodeBlock`
    /// insère un fence vide (un espace-placeholder pré-sélectionné, seul
    /// contenu qui survit à un aller-retour markdown — un corps réellement
    /// vide ne le survivrait pas, voir sa doc) sur le modèle
    /// d'`insertThematicBreak`. Aucune coloration syntaxique — hors périmètre.
    /// `.presentEmojiPicker` (« Emoji ») n'insère rien lui-même : il ouvre le
    /// sélecteur système (`NSApp.orderFrontCharacterPalette(nil)`, cf.
    /// `SlashController.presentCharacterPalette`), qui tape directement dans
    /// le premier répondant une fois un emoji choisi — hors du contrôle de ce
    /// module, même mécanisme que le collage/la frappe normale. Comme
    /// `.insertImage`/`.insertDate`, modélisé ici sans texte à produire :
    /// contrairement à eux, pas de sélection intermédiaire dont le résultat
    /// (URL, date) reviendrait à `SlashController` — la palette n'a aucun
    /// callback (limite connue, voir la doc de `SlashController.
    /// presentEmojiPicker`).
    enum Action: Equatable {
        case convertBlock(MarkdownBlockCommands.LineBlockType)
        case convertList(ListInfo.Kind)
        case insertCallout
        case insertThematicBreak
        case insertCodeBlock
        case insertImage
        case insertDate
        case insertTable
        case presentEmojiPicker
        /// « Fichier » : ouvre un sélecteur de fichier quelconque (pas limité
        /// aux images, contrairement à `.insertImage`), copie le fichier
        /// choisi dans le stockage de l'app (`MediaStore.saveFile`) et insère
        /// un **lien markdown** `[nom-du-fichier](url)` — pas un placeholder
        /// image : un fichier joint n'a pas de rendu visuel, voir
        /// `SlashController.insertFile`.
        case insertFile
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
    /// optionnelle), pour « Image » (`MarkdownFeature` ne modélise que la
    /// syntaxe markdown ; le collage d'image existant — `EditorTextView.paste`
    /// — n'est déjà conditionné par aucune fonctionnalité) et pour « Date »
    /// (même raisonnement qu'« Image » : la date insérée est du texte brut,
    /// aucune syntaxe markdown ne l'accompagne — rien à conditionner). Même
    /// cas pour « Tableau » : `MarkdownFeature` ne compte aucun cas `.table`
    /// (le rendu en grille — `MarkdownParser`/`MarkdownSerializer`/
    /// `StyleRenderer`, commit `fc2234a` — traite déjà tout tableau GFM
    /// inconditionnellement, sans jamais consulter de jeu de fonctionnalités)
    /// ; ajouter un tel cas pour gater uniquement cette entrée du menu
    /// dépasserait le périmètre de cette tâche (catalogue + insertion).
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
