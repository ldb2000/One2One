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
        // Tableaux GFM — un vrai tableau `NSTextTable` depuis le chantier
        // "grille éditable" : chaque cellule est un paragraphe distinct
        // portant `.mdTableCell` (`MarkdownParser.emitTable`), pas un run
        // unique de source littérale. `MarkdownSerializer` (fonction
        // `tableBlock`) reconstruit les lignes `| … |` avec un espacement
        // canonique (`| --- | --- |`, espaces autour de chaque cellule) —
        // ces fixtures sont donc écrites directement dans cette forme
        // normalisée, comme `"Mix _italic_ …"` plus haut pour la même
        // raison (une entrée `|---|---|` sans espaces resérialiserait avec
        // espaces, cassant une simple comparaison d'identité — couvert par
        // `test_tableFormattingNormalizes_toCanonicalSpacing` plus bas, qui
        // vérifie explicitement cette normalisation et sa stabilité).
        //
        // Tableau simple, une seule ligne de corps, en fin de "document"
        // (cette fixture ne contient rien d'autre).
        "| A | B |\n| --- | --- |\n| 1 | 2 |",
        // Alignement des trois natures GFM sur une même table : aucun (col
        // 1), gauche explicite (col 2, `:---`), centré (col 3, `:---:`),
        // droite (col 4, `---:`) — `TableCellInfo.Alignment` doit
        // distinguer "aucun" de "gauche explicite", sérialisés différemment
        // (`---` vs `:---`) bien qu'affichés identiquement.
        "| A | B | C | D |\n| --- | :--- | :---: | ---: |\n| 1 | 2 | 3 | 4 |",
        // Colonne vide : la cellule (0, 1) de la première rangée de corps
        // n'a aucun contenu inline — zéro caractère entre ses deux `|`, un
        // espace de chaque côté au round-trip (`" | " + "" + " | "`, cf.
        // `tableBlock`'s `rowLine`). Volontairement **pas** en toute dernière
        // cellule du tableau : une cellule vide qui termine à la fois sa
        // rangée et le document entier ne porte plus aucun caractère du
        // tout, `.mdTableCell` posé sur une plage de longueur nulle — un
        // défaut mesuré ne casse alors *rien de visible* ici (la ligne
        // restante, vide, est absorbée par le nettoyage de fin de
        // `MarkdownSerializer.serialize`, qui retire toujours une dernière
        // ligne vide) alors qu'il corromprait le tableau si la cellule vide
        // n'était pas la toute dernière — cf. `Après` juste après, dans une
        // rangée suivante, qui exerce ce cas et détecterait la régression.
        "| A | B | C |\n| --- | --- | --- |\n| 1 |  | 3 |\n| 4 | 5 | 6 |",
        // Cellule contenant du gras — la structure inline d'une cellule
        // (`emitInline(cell.children, into:)`, côté parser) est la même que
        // pour un paragraphe normal, seul le conteneur diffère.
        "| A | B |\n| --- | --- |\n| **bold** | 2 |",
        // `|` littéral dans une cellule : doit rester échappé (`\|`), sinon
        // relu comme frontière de colonne au reparse et coupé en deux
        // cellules — `emitInline(…, escapingPipes: true)`, cf.
        // `MarkdownSerializer.tableBlock`.
        "| A | B |\n| --- | --- |\n| a\\|b | 2 |",
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
        // paragraphe nu : titre, séparateur, bloc de code — sûr dans les
        // trois cas (un tableau GFM interrompt un titre/séparateur/bloc de
        // code sans ambiguïté). Le cas "collé à un paragraphe nu" est
        // volontairement absent d'ici (round-trip texte à texte, cf.
        // commentaire sur `fixtures`) : couvert au niveau storage par
        // `test_tableInterruptingParagraph_doesNotDuplicateText` plus bas,
        // avec vérification sur trois passes.
        "# Titre\n| A | B |\n| --- | --- |\n| 1 | 2 |",
        "```\ncode\n```\n| A | B |\n| --- | --- |\n| 1 | 2 |",
        "---\n| A | B |\n| --- | --- |\n| 1 | 2 |",
        // Bloc HTML précédé ou suivi d'un paragraphe, sans ligne vide : sûr
        // dans les deux sens (`HTMLBlock.range` reste correct même quand le
        // bloc interrompt directement un paragraphe — mesuré, cf.
        // `MarkdownParser.correctedRange`, dont le correctif ne s'applique
        // qu'aux `Table` : les blocs HTML n'en ont jamais eu besoin).
        "Avant\n<div>\nbloc\n</div>",
        "<div>\nbloc\n</div>\nAprès",
        // Une ligne de texte nu qui suit un tableau sans ligne vide n'ouvre
        // pas un nouveau bloc : GFM l'absorbe comme une rangée de données
        // supplémentaire (une cellule, la/les autre(s) vide(s)) — un seul
        // tableau du point de vue de CommonMark, donc rien à séparer et
        // rien à casser. Écrit directement dans sa forme canonique de
        // sortie (`| Après |  |`, deuxième cellule vide) pour la même
        // raison que les autres fixtures de tableau ci-dessus.
        "| A | B |\n| --- | --- |\n| 1 | 2 |\n| Après |  |",
        // Deux tableaux collés sans ligne vide : la seconde ligne
        // `|---|` n'est relue par `swift-markdown` que comme une rangée de
        // plus (seule la toute première ligne suivant l'en-tête peut être
        // un séparateur) — un seul `Table` à l'arbre, que `emitTable`
        // convertit en une seule grille de 4 rangées de corps. Le texte
        // littéral `"---"` de la rangée `C` ressort en tiret cadratin
        // (`—`) : normalisation typographique de `swift-markdown` déjà
        // présente sur tout texte brut (mesurée aussi hors tableau, ex.
        // `"a --- b"` → `"a — b"`), pas un effet du tableau.
        "| A |\n| --- |\n| 1 |\n| C |\n| — |\n| 2 |"
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

    // MARK: - Tableau qui interrompt un paragraphe

    /// **Historique** : avant le chantier "grille éditable", un tableau GFM
    /// suivant directement un paragraphe (sans ligne vide) faisait dupliquer
    /// le texte du paragraphe dans le corps brut du tableau — bug de
    /// `swift-markdown` où `Table.range.lowerBound.line` remonte à tort
    /// jusqu'au début du paragraphe interrompu (`Paragraph.range` devient
    /// `nil`), que `MarkdownParser.emitRawBlock`/`literalSource(for:)`
    /// prenait pour argent comptant en découpant `source` sur cette plage
    /// trop large. Corrigé alors par `correctedRange(for:)`, qui recalcule la
    /// ligne de départ d'un `Table` à partir de sa ligne de fin.
    ///
    /// Depuis ce chantier, `MarkdownParser.emitTable` ne consulte plus du
    /// tout `Table.range`/`literalSource` — il marche `table.head`/
    /// `table.body.rows` structurellement (cellule par cellule) — donc ce
    /// bug de plage source ne peut plus l'atteindre : ce test documente que
    /// la duplication reste absente pour la raison structurelle actuelle, pas
    /// seulement pour l'ancienne correction de plage (`correctedRange`
    /// reste en place, inchangée, pour les blocs HTML qui l'utilisent
    /// encore).
    ///
    /// Mesuré sur une vraie note lors de la vérification qui a suivi
    /// 07bff42 : `liveNotes` pk=158 — le débrief « Restitution Hogan »
    /// (10 927 caractères, 4 tableaux) — a un paragraphe suivi d'une ligne
    /// vide puis d'un tableau ; un second aller-retour dessus reproduisait
    /// exactement cette duplication à l'époque du bug.
    func test_tableInterruptingParagraph_doesNotDuplicateText() {
        let md = "Avant\n| A | B |\n|---|---|\n| 1 | 2 |"
        let firstPass = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        XCTAssertEqual(firstPass, "Avant\n| A | B |\n| --- | --- |\n| 1 | 2 |",
                       "« Avant » ne doit apparaître qu'une fois")

        let secondPass = MarkdownSerializer.serialize(MarkdownParser.parse(firstPass))
        XCTAssertEqual(secondPass, firstPass, "Idempotent dès le premier aller-retour")

        let thirdPass = MarkdownSerializer.serialize(MarkdownParser.parse(secondPass))
        XCTAssertEqual(thirdPass, secondPass, "Le troisième passage doit rester identique au deuxième (idempotence)")
    }

    /// Corollaire du test ci-dessus, sur une entrée avec une ligne vide
    /// propre entre le paragraphe et le tableau. Rien ne se perd au premier
    /// aller-retour — la ligne vide protectrice disparaît bien
    /// (`needsBlankLine` ne traite pas `(plainParagraph, table)` comme une
    /// paire à risque, un tableau se comportant comme `.other` — même
    /// frontière que l'ancien passthrough `.rawBlock`, volontairement
    /// inchangée : un tableau GFM interrompt un paragraphe sans ambiguïté,
    /// aucune ligne vide n'est nécessaire pour la relecture). Le second
    /// aller-retour, qui retombe dans le même cas que
    /// `test_tableInterruptingParagraph_doesNotDuplicateText`, reste stable
    /// au lieu de dupliquer « Texte ».
    func test_blankLineBeforeTable_survivesSecondPass() {
        let md = "Texte\n\n| A | B |\n|---|---|\n| 1 | 2 |"
        let firstPass = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        XCTAssertEqual(firstPass, "Texte\n| A | B |\n| --- | --- |\n| 1 | 2 |",
                       "La ligne vide protectrice disparaît dès le premier aller-retour")

        let secondPass = MarkdownSerializer.serialize(MarkdownParser.parse(firstPass))
        XCTAssertEqual(secondPass, firstPass, "« Texte » ne doit pas être dupliqué au second passage")

        let thirdPass = MarkdownSerializer.serialize(MarkdownParser.parse(secondPass))
        XCTAssertEqual(thirdPass, secondPass, "Le troisième passage doit rester identique au deuxième (idempotence)")
    }

    // MARK: - Rendu en grille NSTextTable (fixtures dédiées)

    /// L'espacement canonique de sortie (`| --- | --- |`, espaces autour de
    /// chaque cellule et de chaque marqueur d'alignement) diffère de la
    /// mise en forme d'origine (`|---|---|`, sans espaces) qu'une vraie note
    /// peut contenir — `MarkdownSerializer` reconstruit les lignes `| … |`
    /// depuis les cellules, il ne recopie plus le texte source littéral.
    /// Documente explicitement cette normalisation (contenu identique,
    /// forme différente) et sa stabilité dès la première passe — les
    /// fixtures de `fixtures` ci-dessus l'esquivent en étant déjà écrites
    /// dans la forme canonique, comme `Mix _italic_ …` le fait pour
    /// `*italic*` → `_italic_`.
    func test_tableFormattingNormalizes_toCanonicalSpacing() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let firstPass = MarkdownSerializer.serialize(MarkdownParser.parse(md))
        XCTAssertEqual(firstPass, "| A | B |\n| --- | --- |\n| 1 | 2 |")

        let secondPass = MarkdownSerializer.serialize(MarkdownParser.parse(firstPass))
        XCTAssertEqual(secondPass, firstPass, "Stable dès la première passe")
    }

    /// Paire à risque découverte en vérifiant `live/meeting_158.md` (débrief
    /// Hogan, 4 tableaux) sur trois passes : un paragraphe qui suit un
    /// tableau sans ligne vide est absorbé par GFM comme rangée de données
    /// supplémentaire du tableau (un paragraphe uniligne, sans `|`, satisfait
    /// quand même le patron d'une rangée à une seule cellule). Invisible
    /// avant ce chantier — l'ancien passthrough `.rawBlock` d'un tableau
    /// rendait cette absorption structurelle invisible en sortie (le texte
    /// littéral restait identique en apparence). Construit le storage
    /// directement (comme `test_orderedListItemAfterParagraph_survivesWithBlankLine`)
    /// plutôt que de parser une chaîne : un texte source équivalent serait
    /// déjà lu par `swift-markdown` comme un tableau à 3 rangées, pas deux
    /// blocs distincts — ce test vise la protection à la sérialisation, pas
    /// le comportement du parser sur une entrée déjà fusionnée.
    func test_tableFollowedByParagraph_getsBlankLineToStayDistinct() {
        let storage = NSMutableAttributedString()
        let tableID = UUID()
        func cell(_ text: String, row: Int, column: Int) -> NSAttributedString {
            let info = TableCellInfo(tableID: tableID, row: row, column: column, columnCount: 2, alignment: nil)
            return NSAttributedString(string: text + "\n", attributes: [.mdTableCell: info])
        }
        storage.append(cell("A", row: 0, column: 0))
        storage.append(cell("B", row: 0, column: 1))
        storage.append(cell("1", row: 1, column: 0))
        storage.append(cell("2", row: 1, column: 1))
        storage.append(NSAttributedString(string: "Après"))

        let serialized = MarkdownSerializer.serialize(storage)
        XCTAssertEqual(serialized, "| A | B |\n| --- | --- |\n| 1 | 2 |\n\nAprès",
                       "une ligne vide doit séparer le tableau du paragraphe qui le suit")

        // Le reparse doit garder "Après" comme paragraphe autonome — pas
        // absorbé comme rangée du tableau.
        let reparsed = MarkdownParser.parse(serialized)
        let apresLocation = (reparsed.string as NSString).range(of: "Après").location
        XCTAssertNil(reparsed.attribute(.mdTableCell, at: apresLocation, effectiveRange: nil),
                    "\"Après\" ne doit pas être absorbé comme cellule du tableau")

        let secondPass = MarkdownSerializer.serialize(reparsed)
        XCTAssertEqual(secondPass, serialized, "Stable dès la première passe")
    }

    /// Symétrique du test ci-dessus, découverte sur `live/meeting_157.md` :
    /// un tableau qui suit directement un item de liste (sans ligne vide)
    /// n'est jamais reconnu comme `Table` par `swift-markdown` — continuation
    /// paresseuse de l'item, comme pour un paragraphe nu. Storage construit
    /// directement pour la même raison que ci-dessus.
    func test_listItemFollowedByTable_getsBlankLineToStayDistinct() {
        let storage = NSMutableAttributedString(string: "a\n")
        storage.addAttribute(.mdListInfo,
                             value: ListInfo(kind: .task, level: 0, index: nil, checked: false),
                             range: NSRange(location: 0, length: 2))
        let tableID = UUID()
        func cell(_ text: String, row: Int, column: Int) -> NSAttributedString {
            let info = TableCellInfo(tableID: tableID, row: row, column: column, columnCount: 2, alignment: nil)
            return NSAttributedString(string: text + "\n", attributes: [.mdTableCell: info])
        }
        storage.append(cell("A", row: 0, column: 0))
        storage.append(cell("B", row: 0, column: 1))
        storage.append(cell("1", row: 1, column: 0))
        storage.append(cell("2", row: 1, column: 1))

        let serialized = MarkdownSerializer.serialize(storage)
        XCTAssertEqual(serialized, "- [ ] a\n\n| A | B |\n| --- | --- |\n| 1 | 2 |",
                       "une ligne vide doit séparer l'item de liste du tableau qui le suit")

        // Le reparse doit reconnaître les 4 cellules du tableau — pas du
        // texte littéral absorbé dans l'item.
        var cellCount = 0
        let reparsed = MarkdownParser.parse(serialized)
        reparsed.enumerateAttribute(.mdTableCell, in: NSRange(location: 0, length: reparsed.length)) { value, _, _ in
            if value != nil { cellCount += 1 }
        }
        XCTAssertEqual(cellCount, 4, "les 4 cellules doivent être reconnues comme un vrai tableau au reparse")

        let secondPass = MarkdownSerializer.serialize(reparsed)
        XCTAssertEqual(secondPass, serialized, "Stable dès la première passe")
    }
}
