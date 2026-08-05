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
        "- Avant\n\nAprès",
        // Imbrication de listes — défaut A du plan parser-pertes-de-données
        // (tâche 2) : `emitList` aplatissait tous les niveaux à 0.
        "- a\n  - b\n    - c",
        // Deux items imbriqués au même niveau puis retour au niveau 0 —
        // garde contre un correctif qui ne gérerait que l'unique enfant
        // imbriqué.
        "- a\n  - b\n  - c\n- d",
        // État des cases à cocher imbriquées — défaut B du plan, le plus
        // grave : `b` non cochée ressortait cochée, l'état du parent
        // écrasant celui de l'enfant.
        "- [x] a\n  - [ ] b\n- [x] c",
        // Tableaux GFM et blocs HTML — commit 07bff42, passthrough sur
        // `markup.range` (cf. `MarkdownParser.emitRawBlock`/`literalSource`) :
        // un run unique portant le markdown source littéral, réémis tel quel
        // par `MarkdownSerializer.rawBlock(in:at:ns:)`.
        "| A | B |\n|---|---|\n| 1 | 2 |",
        // Alignement de colonnes : seule la préservation de `markup.range`
        // fait passer ce cas — `Markup.format()` (l'autre option du plan)
        // réduit `|:---|---:|` à `|-|-|` (mesuré directement sur `Table`,
        // voir le rapport de vérification), ce qui aurait fait échouer cette
        // fixture si le passthrough s'appuyait sur `format()`.
        "| A | B |\n|:---|---:|\n| 1 | 2 |",
        "<div>bloc</div>",
        "<div>\nbloc\nsur trois\nlignes\n</div>",
        // Contient un `-` (`MarkdownEscaping.inlineSpecials`) : si le
        // passthrough du bloc HTML était désactivé, ce texte tomberait dans
        // le chemin générique d'échappement inline et ressortirait
        // `ligne\-avec\-tirets` — cette fixture le détecterait, contrairement
        // aux deux ci-dessus dont le contenu ne contient aucun caractère
        // spécial.
        "<div>\nligne-avec-tirets\n</div>",
        // Tableau collé (sans ligne vide) à un voisin qui n'est pas un
        // paragraphe nu : titre, séparateur, bloc de code. Dans ces trois
        // cas, le tableau n'« interrompt » aucun paragraphe et
        // `Table.range` reste correct. Volontairement absent d'ici : un
        // tableau collé à un paragraphe (avant *ou* après une ligne vide) —
        // mesuré cassé, voir les deux tests `test_KNOWN_DEFECT_*` plus bas.
        "# Titre\n| A | B |\n|---|---|\n| 1 | 2 |",
        "```\ncode\n```\n| A | B |\n|---|---|\n| 1 | 2 |",
        "---\n| A | B |\n|---|---|\n| 1 | 2 |",
        // Bloc HTML précédé ou suivi d'un paragraphe, sans ligne vide : sûr
        // dans les deux sens, contrairement au tableau. `HTMLBlock.range`
        // reste correct même quand le bloc interrompt directement un
        // paragraphe (mesuré : `Paragraph.range` et `HTMLBlock.range`
        // corrects tous les deux, alors que pour un `Table` dans la même
        // position `Paragraph.range` devient `nil` et `Table.range`
        // remonte jusqu'au paragraphe précédent — voir le rapport).
        "Avant\n<div>\nbloc\n</div>",
        "<div>\nbloc\n</div>\nAprès",
        // Une ligne de texte nu qui suit un tableau sans ligne vide n'ouvre
        // pas un nouveau bloc : GFM l'absorbe comme une rangée de données
        // supplémentaire (une cellule, le reste vide) — un seul bloc du
        // point de vue de CommonMark, donc rien à séparer et rien à casser.
        "| A | B |\n|---|---|\n| 1 | 2 |\nAprès",
        // Deux tableaux collés sans ligne vide : la seconde ligne
        // `|---|---|` n'est pas relue comme un nouvel en-tête, seulement
        // comme une rangée de plus — un seul bloc `.rawBlock`, que
        // `longestEffectiveRange` doit regrouper malgré les `\n` internes.
        "| A |\n|---|\n| 1 |\n| C |\n|---|\n| 2 |"
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

    // MARK: - Défaut connu, non corrigé — tableau qui interrompt un paragraphe

    /// **Défaut mesuré, non corrigé par 07bff42** : un tableau GFM qui suit
    /// directement un paragraphe, sans ligne vide, fait dupliquer le texte
    /// du paragraphe dans le corps brut du tableau.
    ///
    /// Cause : côté `swift-markdown`, quand un `Table` « interrompt » un
    /// `Paragraph` (le paragraphe s'arrête, le tableau démarre, sans ligne
    /// vide entre les deux), `Paragraph.range` devient `nil` et
    /// `Table.range` remonte à tort jusqu'au **début de la ligne du
    /// paragraphe** plutôt qu'à la première ligne propre du tableau — mesuré
    /// directement sur l'arbre `Document` : pour
    /// `"Avant\n| A | B |\n|---|---|\n| 1 | 2 |"`, `Table.range` vaut
    /// `1:1..<4:10` (devrait commencer en ligne 2). `MarkdownParser.
    /// literalSource(for:)` découpe alors `source` sur cette plage erronée
    /// et embarque « Avant » une seconde fois dans le run `.rawBlock`, en
    /// plus du run `.paragraph` qui le porte déjà correctement.
    ///
    /// Ce n'est pas un bug de ce module au sens strict (le passthrough fait
    /// ce qu'il annonce : réémettre tel quel ce que `markup.range` désigne),
    /// mais une hypothèse implicite du plan — que `markup.range` est fiable
    /// — qui ne tient pas dans ce cas précis. Non détecté par la mesure sur
    /// les 119 notes réelles de 07bff42 (mesure de caractères *perdus*, pas
    /// *dupliqués*), mais **confirmé présent sur une vraie note** lors de la
    /// vérification qui a suivi ce commit : `liveNotes` pk=158 — le débrief
    /// « Restitution Hogan » cité dans 07bff42 lui-même comme le cas le plus
    /// lourd (10 926 caractères) — a un paragraphe suivi d'une ligne vide
    /// puis d'un tableau ; un second aller-retour dessus reproduit
    /// exactement cette duplication (cf.
    /// `test_KNOWN_DEFECT_blankLineBeforeTable_lostThenCorruptsOnSecondPass`
    /// juste en dessous). Une seule occurrence sur les 119 notes actuelles,
    /// mais sur la note la plus citée du correctif.
    ///
    /// `XCTExpectFailure` : si ce test se met à réussir sans qu'on y ait
    /// touché, c'est que le comportement de `swift-markdown` ou de ce module
    /// a changé — retirer le marqueur et comprendre pourquoi plutôt que de
    /// le laisser filer en silence.
    func test_KNOWN_DEFECT_tableInterruptingParagraph_duplicatesText() {
        XCTExpectFailure("Table.range de swift-markdown remonte jusqu'au paragraphe interrompu — voir commentaire ci-dessus") {
            let md = "Avant\n| A | B |\n|---|---|\n| 1 | 2 |"
            let back = MarkdownSerializer.serialize(MarkdownParser.parse(md))
            XCTAssertEqual(back, md, "« Avant » ne doit apparaître qu'une fois")
        }
    }

    /// Corollaire du défaut ci-dessus, sur une entrée **bien formée** cette
    /// fois : une note d'origine avec une ligne vide propre entre le
    /// paragraphe et le tableau. Rien ne se perd au premier aller-retour —
    /// mais la ligne vide protectrice disparaît (`needsBlankLine` ne traite
    /// pas `(plainParagraph, rawBlock)` comme une paire à risque, `.rawBlock`
    /// se comportant comme `.other`), ce qui expose le second aller-retour
    /// au défaut de duplication ci-dessus. Une note avec un tableau bien
    /// séparé de son paragraphe précédent se corrompt donc dès la deuxième
    /// édition, pas la première.
    func test_KNOWN_DEFECT_blankLineBeforeTable_lostThenCorruptsOnSecondPass() {
        let md = "Texte\n\n| A | B |\n|---|---|\n| 1 | 2 |"
        let firstPass = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        XCTAssertEqual(firstPass, "Texte\n| A | B |\n|---|---|\n| 1 | 2 |",
                       "La ligne vide protectrice disparaît dès le premier aller-retour")

        XCTExpectFailure("le second passage retombe dans test_KNOWN_DEFECT_tableInterruptingParagraph_duplicatesText") {
            let secondPass = MarkdownSerializer.serialize(MarkdownParser.parse(firstPass))
            XCTAssertEqual(secondPass, firstPass, "« Texte » ne doit pas être dupliqué au second passage")
        }
    }
}
