import Foundation

/// Le catalogue des entrées du menu `/`, leur filtrage par requête et par
/// `MarkdownFeature`, et leur groupement pour l'affichage.
///
/// Hors périmètre (décision utilisateur du 2026-08-04, voir le plan) : les
/// entrées IA, mermaid, draw.io, le bloc de code, les mentions `@`. Les
/// tableaux, initialement hors périmètre de cette même décision, en sont
/// sortis le 2026-08-05 une fois leur rendu en grille livré (commit
/// `fc2234a`) : `.table` ci-dessous comble l'absence de commande pour en
/// insérer un.
enum SlashCatalog {

    /// Toutes les entrées, dans l'ordre déclaré (celui du tableau du plan,
    /// étendu par les commandes `/date` puis `/tableau`) : « Blocs de base »
    /// puis « Média » puis « Insertions ». `SlashCatalog.grouped` ne trie pas
    /// davantage — c'est cet ordre qui apparaît dans le panneau.
    static let all: [SlashCommand] = [
        SlashCommand(
            key: .text,
            label: "Texte",
            keywords: ["texte", "paragraphe", "normal"],
            aliases: ["text", "paragraph"],
            shortcut: nil,
            group: .basicBlocks,
            action: .convertBlock(.paragraph),
            requiredFeature: nil
        ),
        SlashCommand(
            key: .heading1,
            label: "Titre 1",
            keywords: ["titre", "grand titre"],
            aliases: ["h1", "heading1", "heading 1"],
            shortcut: "#",
            group: .basicBlocks,
            action: .convertBlock(.h1),
            requiredFeature: .heading(.h1)
        ),
        SlashCommand(
            key: .heading2,
            label: "Titre 2",
            keywords: ["titre", "sous-titre"],
            aliases: ["h2", "heading2", "heading 2"],
            shortcut: "##",
            group: .basicBlocks,
            action: .convertBlock(.h2),
            requiredFeature: .heading(.h2)
        ),
        SlashCommand(
            key: .heading3,
            label: "Titre 3",
            keywords: ["titre", "sous-titre"],
            aliases: ["h3", "heading3", "heading 3"],
            shortcut: "###",
            group: .basicBlocks,
            action: .convertBlock(.h3),
            requiredFeature: .heading(.h3)
        ),
        SlashCommand(
            key: .bulletList,
            label: "Liste à puces",
            keywords: ["liste", "puce", "puces"],
            aliases: ["bullet", "bulletlist", "ul"],
            shortcut: "-",
            group: .basicBlocks,
            action: .convertList(.bullet),
            requiredFeature: .bulletList
        ),
        SlashCommand(
            key: .orderedList,
            label: "Liste numérotée",
            keywords: ["liste", "numérotée", "ordonnée"],
            aliases: ["ordered", "orderedlist", "ol", "numbered"],
            shortcut: "1.",
            group: .basicBlocks,
            action: .convertList(.ordered),
            requiredFeature: .orderedList
        ),
        SlashCommand(
            key: .taskList,
            label: "Case à cocher",
            keywords: ["case à cocher", "tâche", "checklist"],
            aliases: ["todo", "task", "checkbox"],
            shortcut: "[]",
            group: .basicBlocks,
            action: .convertList(.task),
            requiredFeature: .taskList
        ),
        SlashCommand(
            key: .blockquote,
            label: "Citation",
            keywords: ["citation", "bloc de citation"],
            aliases: ["quote", "blockquote"],
            shortcut: ">",
            group: .basicBlocks,
            action: .convertBlock(.blockquote),
            requiredFeature: .blockquote
        ),
        SlashCommand(
            key: .callout,
            label: "Encadré",
            keywords: ["encadré", "remarque", "astuce", "mise en avant"],
            aliases: ["callout", "note", "tip"],
            shortcut: nil,
            group: .basicBlocks,
            action: .insertCallout,
            requiredFeature: .blockquote
        ),
        SlashCommand(
            key: .thematicBreak,
            label: "Séparateur",
            keywords: ["séparateur", "ligne horizontale", "trait"],
            aliases: ["hr", "divider", "rule"],
            shortcut: "---",
            group: .basicBlocks,
            action: .insertThematicBreak,
            requiredFeature: .thematicBreak
        ),
        SlashCommand(
            key: .table,
            label: "Tableau",
            keywords: ["tableau", "table", "grille"],
            aliases: ["table"],
            shortcut: nil,
            group: .basicBlocks,
            action: .insertTable,
            requiredFeature: nil
        ),
        SlashCommand(
            key: .image,
            label: "Image",
            keywords: ["image", "photo", "illustration"],
            aliases: ["picture", "img"],
            shortcut: nil,
            group: .media,
            action: .insertImage,
            requiredFeature: nil
        ),
        SlashCommand(
            key: .date,
            label: "Date",
            keywords: ["date", "jour", "calendrier"],
            aliases: ["today", "aujourd'hui"],
            shortcut: nil,
            group: .insertions,
            action: .insertDate,
            requiredFeature: nil
        ),
    ]

    /// Entrées visibles pour un jeu de fonctionnalités donné : celles sans
    /// `requiredFeature`, plus celles dont `requiredFeature` est dans
    /// `features`. Préserve l'ordre de `all`.
    static func available(for features: Set<MarkdownFeature>) -> [SlashCommand] {
        all.filter { command in
            guard let required = command.requiredFeature else { return true }
            return features.contains(required)
        }
    }

    /// Entrées visibles pour `features` et correspondant à `query`
    /// (`SlashCommand.matches`), groupées dans l'ordre déclaré de
    /// `SlashCommand.Group`. Les groupes sans entrée après filtrage sont
    /// omis plutôt que renvoyés vides.
    static func grouped(matching query: String, features: Set<MarkdownFeature>) -> [(group: SlashCommand.Group, commands: [SlashCommand])] {
        let candidates = available(for: features).filter { $0.matches(query) }
        return SlashCommand.Group.allCases.compactMap { group in
            let commands = candidates.filter { $0.group == group }
            guard !commands.isEmpty else { return nil }
            return (group, commands)
        }
    }
}
