import XCTest
@testable import OneToOne

/// Caractérise `SlashCommand`/`SlashCatalog` : filtrage par texte (libellé,
/// mots-clés, alias), insensibilité à la casse et aux accents, groupement
/// dans l'ordre déclaré avec omission des groupes vides, et conditionnement
/// des entrées par `MarkdownFeature`.
final class SlashCatalogTests: XCTestCase {

    // MARK: - Filtrage par texte : libellé, mots-clés, alias

    func test_matches_onLabel() {
        let command = command(.blockquote)
        XCTAssertTrue(command.matches("Citation"))
    }

    func test_matches_onKeyword() {
        // "puce" n'apparaît pas dans le libellé « Liste à puces » sous cette
        // forme exacte tokenisée, mais dans les mots-clés déclarés.
        let command = command(.bulletList)
        XCTAssertTrue(command.matches("puce"))
    }

    func test_matches_date_onLabel() {
        XCTAssertTrue(command(.date).matches("date"))
    }

    /// "jour" n'apparaît pas dans le libellé « Date », seulement dans ses
    /// mots-clés déclarés — même forme de preuve que `test_matches_onKeyword`
    /// pour ne pas confondre un match sur le libellé avec un vrai match sur
    /// les mots-clés.
    func test_matches_date_onKeyword() {
        XCTAssertTrue(command(.date).matches("jour"))
        XCTAssertTrue(command(.date).matches("calendrier"))
    }

    func test_matches_onAlias() {
        let command = command(.thematicBreak)
        XCTAssertTrue(command.matches("hr"))
    }

    /// « Tableau » doit se trouver via son libellé (« tableau »), un
    /// mot-clé (« grille », absent du libellé) et son alias (« table »).
    func test_matches_table_onLabelKeywordAndAlias() {
        let command = command(.table)
        XCTAssertTrue(command.matches("tableau"))
        XCTAssertTrue(command.matches("grille"))
        XCTAssertTrue(command.matches("table"))
    }

    func test_matches_noMatch_returnsFalse() {
        let command = command(.blockquote)
        XCTAssertFalse(command.matches("zzz introuvable"))
    }

    /// « Encadré » (callout) doit se trouver via son libellé et un mot-clé
    /// absent du libellé (« astuce ») — même forme de preuve que
    /// `test_matches_table_onLabelKeywordAndAlias`.
    func test_matches_callout_onLabelAndKeyword() {
        let command = command(.callout)
        XCTAssertTrue(command.matches("Encadré"))
        XCTAssertTrue(command.matches("astuce"))
        XCTAssertTrue(command.matches("callout"))
    }

    /// Titres 4/5/6 : trouvables par leur libellé (« Titre 4/5/6 ») et leur
    /// alias (« h4 »/« h5 »/« h6 »), même forme de preuve que pour les titres
    /// 1 à 3 (`test_matches_onLabel`/`test_matches_onAlias`).
    func test_matches_heading4to6_onLabelAndAlias() {
        XCTAssertTrue(command(.heading4).matches("Titre 4"))
        XCTAssertTrue(command(.heading4).matches("h4"))
        XCTAssertTrue(command(.heading5).matches("Titre 5"))
        XCTAssertTrue(command(.heading5).matches("h5"))
        XCTAssertTrue(command(.heading6).matches("Titre 6"))
        XCTAssertTrue(command(.heading6).matches("h6"))
    }

    /// « Bloc de code » : trouvable par son libellé, un mot-clé absent du
    /// libellé (« programmation ») et son alias (« code »).
    func test_matches_codeBlock_onLabelKeywordAndAlias() {
        let command = command(.codeBlock)
        XCTAssertTrue(command.matches("Bloc de code"))
        XCTAssertTrue(command.matches("programmation"))
        XCTAssertTrue(command.matches("code"))
    }

    /// « Emoji » : trouvable par son libellé et un mot-clé absent du libellé
    /// (« smiley »).
    func test_matches_emoji_onLabelAndKeyword() {
        let command = command(.emoji)
        XCTAssertTrue(command.matches("Emoji"))
        XCTAssertTrue(command.matches("smiley"))
        XCTAssertTrue(command.matches("émoticône"))
    }

    /// « Fichier » : trouvable par son libellé, un mot-clé absent du libellé
    /// (« pièce jointe ») et un alias (« pdf ») — même forme de preuve que
    /// `test_matches_table_onLabelKeywordAndAlias`.
    func test_matches_file_onLabelKeywordAndAlias() {
        let command = command(.file)
        XCTAssertTrue(command.matches("Fichier"))
        XCTAssertTrue(command.matches("pièce jointe"))
        XCTAssertTrue(command.matches("pdf"))
    }

    func test_matches_emptyQuery_matchesEverything() {
        for entry in SlashCatalog.all {
            XCTAssertTrue(entry.matches(""), "\(entry.key) devrait matcher une requête vide")
        }
    }

    // MARK: - Insensibilité à la casse et aux accents

    func test_matches_caseInsensitive() {
        let command = command(.blockquote) // libellé "Citation"
        XCTAssertTrue(command.matches("citation"), "minuscule doit trouver « Citation »")
        XCTAssertTrue(command.matches("CITATION"), "majuscules doivent trouver « Citation »")
    }

    func test_matches_accentInsensitive() {
        let command = command(.orderedList) // libellé "Liste numérotée"
        XCTAssertTrue(command.matches("numerotee"), "sans accent doit trouver « Liste numérotée »")
        XCTAssertTrue(command.matches("NUMEROTEE"), "sans accent et en majuscules doit aussi matcher")
    }

    /// Vérifie que la méthode de comparaison replie vraiment les diacritiques
    /// plutôt que de compter sur une coïncidence : deux chaînes qui ne
    /// diffèrent que par un accent doivent produire la même forme repliée.
    func test_slashSearchNormalized_actuallyFoldsAccents() {
        XCTAssertEqual("numérotée".slashSearchNormalized, "numerotee".slashSearchNormalized)
        XCTAssertEqual("Numérotée".slashSearchNormalized, "NUMEROTEE".slashSearchNormalized)
        // Deux mots réellement différents ne doivent pas être confondus par
        // le repli — la normalisation ne doit pas tout écraser vers "".
        XCTAssertNotEqual("citation".slashSearchNormalized, "image".slashSearchNormalized)
    }

    // MARK: - Groupement

    func test_grouped_declaredOrder() {
        let groups = SlashCatalog.grouped(matching: "", features: .full)
        XCTAssertEqual(groups.map(\.group), [.basicBlocks, .media, .insertions])
    }

    func test_grouped_dateQuery_onlyInsertionsGroupSurvives() {
        // "date" ne désigne que l'entrée Date (groupe "Insertions") ; ni
        // "Blocs de base" ni "Média" ne doivent apparaître.
        let groups = SlashCatalog.grouped(matching: "date", features: .full)
        XCTAssertEqual(groups.map(\.group), [.insertions])
    }

    func test_grouped_omitsEmptyGroups() {
        // "titre" ne désigne que les titres (groupe "Blocs de base") ; le
        // groupe "Média" (Image) n'a aucune correspondance et ne doit pas
        // apparaître, même vide.
        let groups = SlashCatalog.grouped(matching: "titre", features: .full)
        XCTAssertEqual(groups.map(\.group), [.basicBlocks])
        XCTAssertFalse(groups.contains { $0.group == .media })
    }

    func test_grouped_onlyMatchingGroupSurvives() {
        // "image" ne désigne que l'entrée Image (groupe "Média") ; le groupe
        // "Blocs de base" ne doit pas apparaître.
        let groups = SlashCatalog.grouped(matching: "image", features: .full)
        XCTAssertEqual(groups.map(\.group), [.media])
    }

    // MARK: - Conditionnement par MarkdownFeature

    func test_available_basicFeature_hidesHeadings() {
        let visible = SlashCatalog.available(for: .basic)
        let keys = Set(visible.map(\.key))
        XCTAssertFalse(keys.contains(.heading1))
        XCTAssertFalse(keys.contains(.heading2))
        XCTAssertFalse(keys.contains(.heading3))
    }

    /// Titres 4/5/6 : chacun conditionné par son propre
    /// `MarkdownFeature.heading(.h4/.h5/.h6)`, pas par un seul cas partagé —
    /// n'activer que `.heading(.h4)` ne doit faire apparaître que « Titre 4 ».
    func test_available_headingFeature_gatesEachLevelIndependently() {
        let visible = SlashCatalog.available(for: [.heading(.h4)])
        let keys = Set(visible.map(\.key))
        XCTAssertTrue(keys.contains(.heading4))
        XCTAssertFalse(keys.contains(.heading5))
        XCTAssertFalse(keys.contains(.heading6))
    }

    func test_available_basicFeature_keepsBulletAndOrderedLists() {
        let visible = SlashCatalog.available(for: .basic)
        let keys = Set(visible.map(\.key))
        XCTAssertTrue(keys.contains(.bulletList))
        XCTAssertTrue(keys.contains(.orderedList))
    }

    func test_available_basicFeature_hidesTaskListAndBlockquoteAndThematicBreak() {
        let visible = SlashCatalog.available(for: .basic)
        let keys = Set(visible.map(\.key))
        XCTAssertFalse(keys.contains(.taskList))
        XCTAssertFalse(keys.contains(.blockquote))
        XCTAssertFalse(keys.contains(.thematicBreak))
    }

    func test_available_basicFeature_hidesCodeBlock() {
        let visible = SlashCatalog.available(for: .basic)
        XCTAssertFalse(Set(visible.map(\.key)).contains(.codeBlock))
    }

    func test_available_codeBlockFeature_showsCodeBlock() {
        let visible = SlashCatalog.available(for: [.codeBlock])
        XCTAssertTrue(Set(visible.map(\.key)).contains(.codeBlock))
    }

    /// « Encadré » partage la fonctionnalité `.blockquote` : c'est la même
    /// citation, juste préfixée d'un emoji (voir la doc de
    /// `SlashCommand.Action.insertCallout`) — pas de raison de la conditionner
    /// séparément.
    func test_available_basicFeature_hidesCallout() {
        let visible = SlashCatalog.available(for: .basic)
        XCTAssertFalse(Set(visible.map(\.key)).contains(.callout))
    }

    func test_available_blockquoteFeature_showsCallout() {
        let visible = SlashCatalog.available(for: [.blockquote])
        XCTAssertTrue(Set(visible.map(\.key)).contains(.callout))
    }

    func test_available_fullFeature_showsEverything() {
        let visible = SlashCatalog.available(for: .full)
        XCTAssertEqual(Set(visible.map(\.key)), Set(SlashCommand.Key.allCases))
    }

    func test_available_emptyFeatureSet_stillShowsUnconditionalEntries() {
        // "Texte", "Image", "Date", "Tableau", "Emoji" et "Fichier" ne sont
        // conditionnées par aucun MarkdownFeature (`MarkdownFeature` ne
        // compte aucun cas `.table` ni `.emoji`, cf. la doc de
        // `SlashCommand.requiredFeature`).
        let visible = SlashCatalog.available(for: [])
        let keys = Set(visible.map(\.key))
        XCTAssertTrue(keys.contains(.text))
        XCTAssertTrue(keys.contains(.image))
        XCTAssertTrue(keys.contains(.date))
        XCTAssertTrue(keys.contains(.table))
        XCTAssertTrue(keys.contains(.emoji))
        XCTAssertTrue(keys.contains(.file))
    }

    /// « Tableau » appartient au groupe « Blocs de base », comme le
    /// séparateur (même nature : une insertion de bloc entier, pas une
    /// conversion) — pas à « Insertions » (réservé aux insertions
    /// ponctuelles de texte, ex. Date) ni à « Média ».
    func test_table_belongsToBasicBlocksGroup() {
        XCTAssertEqual(command(.table).group, .basicBlocks)
    }

    /// « Encadré » appartient au groupe « Blocs de base », comme la citation
    /// dont il dérive.
    func test_callout_belongsToBasicBlocksGroup() {
        XCTAssertEqual(command(.callout).group, .basicBlocks)
    }

    /// « Bloc de code » appartient au groupe « Blocs de base », comme le
    /// séparateur et le tableau (même nature : une insertion de bloc entier).
    func test_codeBlock_belongsToBasicBlocksGroup() {
        XCTAssertEqual(command(.codeBlock).group, .basicBlocks)
    }

    /// « Emoji » appartient au groupe « Insertions », comme « Date » — une
    /// insertion ponctuelle de texte, ni un bloc de base ni un média.
    func test_emoji_belongsToInsertionsGroup() {
        XCTAssertEqual(command(.emoji).group, .insertions)
    }

    /// « Fichier » appartient au groupe « Média », comme « Image » — une
    /// pièce jointe copiée dans le stockage de l'app, pas une insertion de
    /// texte ponctuelle.
    func test_file_belongsToMediaGroup() {
        XCTAssertEqual(command(.file).group, .media)
    }

    // MARK: - Helpers

    private func command(_ key: SlashCommand.Key) -> SlashCommand {
        guard let found = SlashCatalog.all.first(where: { $0.key == key }) else {
            XCTFail("Entrée \(key) absente du catalogue")
            fatalError("unreachable")
        }
        return found
    }
}
