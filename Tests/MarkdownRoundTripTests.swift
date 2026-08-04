import XCTest
@testable import OneToOne

final class MarkdownRoundTripTests: XCTestCase {

    /// For each fixture, parse the markdown then serialize it; the output
    /// must equal the input. Normalisations do exist elsewhere in this
    /// module — an image's alt text loses emphasis markers, and an
    /// `MarkdownEscaping.inlineSpecials` character in it gains a backslash —
    /// but `fixtures` avoids triggering them (see the per-fixture comments
    /// below) since an identity check can't express "equal modulo a known
    /// transform". Those two normalisations are instead asserted directly,
    /// with their exact output and its stability on a second pass, in
    /// `test_imageAltNormalizations`.
    private let fixtures: [String] = [
        "Hello world",
        "## Title",
        "hello **bold** word",
        "- a\n- b\n- c",
        "1. one\n2. two",
        "- [ ] todo\n- [x] done",
        // Note: serializer normalises multi-line blockquote (soft break) → single line with space
        "> quote next line — kept as block",
        "[link](https://example.com)",
        "hello `code` inline",
        // Note: serializer normalises *italic* → _italic_
        "Mix _italic_ and **bold** here",
        // Blocs fencés — non couverts jusqu'ici.
        // Pas de ligne vide entre les blocs : `MarkdownParser.appendNewline`
        // n'en émet qu'une seule après chaque bloc, donc `\n\n` en entrée
        // ressortirait en `\n` et ferait échouer le test pour une raison
        // étrangère à ce qu'on cherche à prouver.
        "```swift\nprint(1)\n```",
        "```swift\nlet a = 1\nlet b = 2\nprint(a + b)\n```",
        "```\nsans langage\nsur deux lignes\n```",
        "texte avant\n```json\n{\n  \"a\": 1\n}\n```\ntexte après",
        // Adjacence stricte, sans texte intercalaire. Comme la fixture
        // « texte avant / texte après » ci-dessus, elle exerce le saut du `\n`
        // séparateur dans `MarkdownSerializer.fencedCodeBlock` : supprimer cet
        // incrément fait échouer les deux, avec une ligne vide parasite après
        // la fence fermante.
        "```swift\na\n```\n```json\nb\n```",
        // Ligne vide à l'intérieur du corps — cassé avant le correctif.
        "```\na\n\nb\n```",
        // Corps contenant lui-même une fence de 3 backticks : nécessite une
        // fence englobante plus longue (4) pour ne pas se refermer
        // prématurément et perdre du contenu au reparse.
        "````\n```\nx\n```\n````",
        // Images — l'URL était perdue faute de cas `Image` dans le parser.
        // Les textes alternatifs évitent les caractères de
        // `MarkdownEscaping.inlineSpecials` (`+`, `-`, `_`, `#`, `!`…) : ils
        // ressortiraient échappés (`R+2` → `R\+2`) et feraient échouer le test
        // sur l'échappement plutôt que sur le bug visé.
        "![Plan du R2](file:///Users/x/img_ab12.png)",
        "Avant ![schéma](file:///Users/x/s.png) après",
        "![](file:///Users/x/sansalt.png)",
        // URL déjà percent-encodée en entrée : une entrée littérale accentuée
        // ou espacée ne peut pas round-tripper textuellement, `URL(string:)`
        // la normalise en une forme déjà percent-encodée dès le premier parse
        // — c'est cette forme normalisée qui doit ensuite rester stable.
        "![a](file:///Users/x/sch%C3%A9ma.png)",
        "![a](file:///Users/x/mon%20image.png)",
        // Image enveloppée par du gras ou par un lien : le run porte alors
        // à la fois `mdImageURL` et `mdBold`/`mdLink`.
        "**![a](file:///x.png)**",
        "[![a](file:///x.png)](https://example.com)",
        // Frontières de bloc — matrice mesurée par un test temporaire (tâche 1
        // du plan menu-slash, depuis supprimé) : ces 5 paires, sans ligne
        // vide, se relisent différemment en CommonMark (fusion ou changement
        // de type). La ligne vide est la forme qui doit survivre au round-trip.
        // Une 6e paire (paragraphe → item de liste ordonnée d'ordinal != 1)
        // existe aussi, mais ne peut pas s'exprimer comme une simple chaîne
        // ici : le parser renumérote toujours une liste ordonnée à partir de
        // 1 en entrée, donc "Texte\n\n2. b" reparserait en item d'ordinal 1,
        // pas 2 — voir `test_orderedListItemAfterParagraph_survivesWithBlankLine`
        // ci-dessous, au niveau du storage.
        "Avant\n\nAprès",
        "Avant\n\n---",
        "> Avant\n\nAprès",
        "> Avant\n\n> Après",
        "- Avant\n\nAprès"
    ]

    func test_allFixturesRoundTrip() {
        for md in fixtures {
            let parsed = MarkdownParser.parse(md)
            let back = MarkdownSerializer.serialize(parsed)
            XCTAssertEqual(back, md, "Round-trip mismatch for: \(md.debugDescription)")
        }
    }

    /// 6e paire à risque, testée au niveau du storage plutôt que par une
    /// chaîne d'aller-retour (cf. commentaire sur `fixtures` ci-dessus) : un
    /// item de liste ordonnée dont l'ordinal n'est pas 1 n'interrompt pas un
    /// paragraphe en CommonMark — son marqueur redevient du texte littéral et
    /// `ListInfo` est perdu au reparse. Atteignable par un geste existant :
    /// `MarkdownBlockCommands.setBlockType(.paragraph, at:)` sur le premier
    /// item d'une liste ordonnée « 1. a / 2. b » laisse « b » avec un
    /// `ListInfo` d'ordinal 2, juste après un paragraphe nu.
    func test_orderedListItemAfterParagraph_survivesWithBlankLine() {
        let storage = NSMutableAttributedString(string: "Texte\nb")
        storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: NSRange(location: 0, length: 5))
        storage.addAttribute(.mdListInfo,
                              value: ListInfo(kind: .ordered, level: 0, index: 2, checked: nil),
                              range: NSRange(location: 6, length: 1))

        let serialized = MarkdownSerializer.serialize(storage)
        XCTAssertEqual(serialized, "Texte\n\n2. b")

        // Le reparse doit garder "b" comme item de liste ordonnée — pas comme
        // texte fusionné dans le paragraphe précédent (le parser renumérote
        // à partir de 1, donc on vérifie le `kind`, pas l'ordinal exact).
        let reparsed = MarkdownParser.parse(serialized)
        let bLocation = (reparsed.string as NSString).range(of: "b").location
        let listInfoAtB = reparsed.attribute(.mdListInfo, at: bLocation, effectiveRange: nil) as? ListInfo
        XCTAssertEqual(listInfoAtB?.kind, .ordered, "\"b\" doit rester un item de liste ordonnée au reparse")
    }

    /// Deux normalisations connues, volontairement exclues de `fixtures` :
    /// - l'emphase dans le texte alternatif d'une image est aplatie —
    ///   `image.plainText` descend dans les enfants sans réémettre leurs
    ///   marqueurs, donc `**gras**` devient simplement `gras` ;
    /// - un caractère de `MarkdownEscaping.inlineSpecials` dans l'alt ressort
    ///   échappé (`+` → `\+`).
    /// Dans les deux cas, la forme obtenue après une passe doit rester
    /// stable à la suivante (pas de dérive supplémentaire au reparse).
    func test_imageAltNormalizations() {
        let boldAlt = MarkdownSerializer.serialize(MarkdownParser.parse("![**gras**](x)"))
        XCTAssertEqual(boldAlt, "![gras](x)")
        let boldAltStable = MarkdownSerializer.serialize(MarkdownParser.parse(boldAlt))
        XCTAssertEqual(boldAltStable, boldAlt, "La normalisation doit être stable dès la 2e passe")

        let plusAlt = MarkdownSerializer.serialize(MarkdownParser.parse("![R+2](x)"))
        XCTAssertEqual(plusAlt, "![R\\+2](x)")
        let plusAltStable = MarkdownSerializer.serialize(MarkdownParser.parse(plusAlt))
        XCTAssertEqual(plusAltStable, plusAlt, "La normalisation doit être stable dès la 2e passe")
    }
}
