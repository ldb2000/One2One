# Aération des blocs et aperçu figé du bloc mermaid ouvert — plan d'implémentation

> **Pour les agents :** SOUS-SKILL REQUISE — utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par tâche.
> Les étapes utilisent la syntaxe case à cocher (`- [ ]`).

**Spec** : [`docs/superpowers/specs/2026-08-08-aeration-blocs-mermaid-design.md`](../specs/2026-08-08-aeration-blocs-mermaid-design.md)

**But** : rendre lisible la frontière entre deux blocs voisins de l'éditeur Markdown,
et rattacher visuellement un source mermaid en édition au diagramme qu'il produit.

**Architecture** : deux changements indépendants qui se rejoignent à l'écran. (1) Un
écart vertical de 28 pt autour de tout bloc qui dessine un cadre, posé par
`StyleRenderer.applyBlockSpacing` via `paragraphSpacing` uniquement. (2) Une bande
d'aperçu **figée** insérée dans le cadre du bloc mermaid ouvert, entre l'en-tête et
le source, réservée par `paragraphSpacingBefore` — le même levier qui réserve déjà
l'en-tête — et peinte depuis l'attachment déjà posé, sans relancer aucun rendu.

**Pile technique** : Swift 6, AppKit, TextKit 1, SwiftPM. Tests XCTest
(`@testable import OneToOne`).

## Contraintes globales

- **Ne jamais relancer de rendu mermaid pendant l'édition.** La branche « bloc
  ouvert » de `StyleRenderer.applyMermaidAttachment` repose l'attachment existant
  tel quel ; c'est le correctif du 2026-08-08 contre la superposition carte/source.
  Aucune tâche de ce plan n'appelle `MermaidAttachmentFactory.attachment(for:isDark:onUpdate:)`.
- **Ne jamais poser `paragraphSpacingBefore` pour l'écart entre blocs.** TextKit
  additionne `paragraphSpacing` (bloc du dessus) et `paragraphSpacingBefore` (bloc du
  dessous) ; deux cartes voisines recevraient 56 pt. L'écart entre blocs passe
  exclusivement par `paragraphSpacing`.
- **Ne jamais gonfler `minimumLineHeight` sur la première ligne d'un bloc ouvert.**
  Cela produirait un curseur vertical surdimensionné (défaut déjà corrigé). La bande
  d'aperçu est réservée par `paragraphSpacingBefore`, comme l'en-tête.
- **Un seul calcul de géométrie partagé dessin/hit-test.** `previewHeight` a un point
  d'entrée unique ; le dessin du cadre, le dessin de l'en-tête et le hit-test du
  bouton « Terminé » l'appellent tous les trois. Deux valeurs divergentes mettraient
  « Terminé » hors de sa zone cliquable.
- **Attributs d'affichage uniquement.** Aucune tâche ne touche le parseur, le
  sérialiseur, le storage textuel ni la pile d'annulation.
- Commentaires et libellés en **français**, symboles et code en anglais.
- Commits conventionnels. Ne **jamais** ajouter `OneToOne/OneToOneApp.swift` à un
  commit de ce plan (hunk de migration à isoler, cf. `STATUS.md`).
- Vérification de référence du dépôt : `swift test --skip CalendarImportEventTests`.

## Structure des fichiers

| Fichier | Rôle | Tâche |
|---|---|---|
| `OneToOne/Markdown/Core/BlockGutterLayout.swift` | *Modifié* — constante `cardBlockSpacing` + prédicat pur `isCardBlock` | 1 |
| `OneToOne/Markdown/Core/StyleRenderer.swift` | *Modifié* — `applyBlockSpacing` (T1), `applyOpenMermaidGeometry` + son appelant (T3) | 1, 3 |
| `OneToOne/Markdown/Blocks/MermaidSourceLayout.swift` | *Modifié* — géométrie de la bande d'aperçu, décalage de `headerRect`/`frameRect`/`bodyRect`/`doneButtonRect` | 2 |
| `OneToOne/Markdown/Core/EditorTextView.swift` | *Modifié* — `mermaidDoneButtonRange` passe `previewHeight` | 4 |
| `OneToOne/Markdown/Core/MarkdownLayoutManager.swift` | *Modifié* — `drawMermaidHeader` (T4), `drawOpenMermaidBackgrounds` peint l'aperçu (T5) | 4, 5 |
| `Tests/BlockGutterLayoutTests.swift` | *Modifié* — `isCardBlock` | 1 |
| `Tests/StyleRendererBlockSpacingTests.swift` | **Créé** — les quatre voisinages | 1 |
| `Tests/MermaidSourceLayoutTests.swift` | *Modifié* — bande d'aperçu et décalages | 2 |
| `Tests/StyleRendererMermaidTests.swift` | *Modifié* — hauteur réservée en état ouvert | 3 |
| `Tests/EditorTextViewMermaidClickTests.swift` | *Modifié* — « Terminé » cliquable avec aperçu | 4 |
| `STATUS.md` | *Modifié* — état, limites connues, prochaine action | 6 |

Les tâches 2 → 5 sont séquentielles (chacune consomme la signature produite par la
précédente). La tâche 1 est indépendante et peut être menée en parallèle.

---

### Tâche 1 : écart vertical autour des blocs-cartes

**Fichiers :**
- Modifier : `OneToOne/Markdown/Core/BlockGutterLayout.swift:46` (après `blockSpacing`)
- Modifier : `OneToOne/Markdown/Core/StyleRenderer.swift:274-307` (`applyBlockSpacing`)
- Test : `Tests/BlockGutterLayoutTests.swift`
- Test : `Tests/StyleRendererBlockSpacingTests.swift` (créé)

**Interfaces :**
- Consomme : rien.
- Produit :
  - `BlockGutterLayout.cardBlockSpacing: CGFloat` (= 28)
  - `BlockGutterLayout.isCardBlock(in storage: NSTextStorage, at location: Int) -> Bool`

- [ ] **Étape 1 : écrire les tests en échec pour `isCardBlock`**

Ajouter dans `Tests/BlockGutterLayoutTests.swift`, après
`test_iconsFrame_keepsTheGutterOutsideTheBody` :

```swift
// MARK: - isCardBlock

/// Les blocs qui peignent un cadre reçoivent l'écart large ; le texte
/// courant garde `blockSpacing`. Le prédicat se lit au **début** du bloc :
/// `BlockRange.tableRange` et `BlockRange.attributedRunRange` démarrent
/// tous deux, par construction, sur un caractère qui porte l'attribut
/// (vérifié dans `BlockRange.swift`).
func test_isCardBlock_isTrueForATableAndACodeBlock() throws {
    let cases: [(markdown: String, needle: String)] = [
        ("```swift\nprint(1)\n```", "print(1)"),
        ("| a | b |\n|---|---|\n| 1 | 2 |", "a")
    ]
    for (markdown, needle) in cases {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        let location = (storage.string as NSString).range(of: needle).location
        XCTAssertNotEqual(location, NSNotFound, "prémisse : « \(needle) » présent dans le storage stylé")
        let block = BlockRange.of(in: storage, at: location).range
        XCTAssertTrue(
            BlockGutterLayout.isCardBlock(in: storage, at: block.location),
            "« \(markdown) » dessine un cadre"
        )
    }
}

/// Image et bloc mermaid : storages construits à la main plutôt que parsés.
/// Pour l'image, la position exacte du run `.mdImageURL` après stylage n'est
/// pas garantie d'être le début du bloc ; pour mermaid, passer par
/// `applyVisualStyle` déclencherait un vrai `WKWebView` en tâche de fond
/// (voir la doc de tête de `StyleRendererMermaidTests`). Les deux branches
/// du prédicat sont exercées directement.
func test_isCardBlock_isTrueForAnImageAndAMermaidBlock() {
    let imageStorage = NSTextStorage(attributedString: NSAttributedString(string: "X"))
    imageStorage.addAttribute(
        .mdImageURL,
        value: URL(string: "https://example.com/x.png")!,
        range: NSRange(location: 0, length: 1)
    )
    XCTAssertTrue(BlockGutterLayout.isCardBlock(in: imageStorage, at: 0))

    let mermaidStorage = NSTextStorage(attributedString: NSAttributedString(string: "X"))
    mermaidStorage.addAttribute(
        .mdMermaidAttachment,
        value: NSTextAttachment(),
        range: NSRange(location: 0, length: 1)
    )
    XCTAssertTrue(BlockGutterLayout.isCardBlock(in: mermaidStorage, at: 0))
}

/// Garde-fou : une position hors bornes ne doit jamais lire dans le storage.
func test_isCardBlock_outOfBounds_isFalse() {
    let storage = NSTextStorage(attributedString: MarkdownParser.parse("Texte"))
    XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: -1))
    XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: storage.length))
    XCTAssertFalse(BlockGutterLayout.isCardBlock(in: storage, at: storage.length + 50))
}

func test_isCardBlock_isFalseForOrdinaryText() throws {
    let cases = ["Un paragraphe", "# Un titre", "- un item"]
    for markdown in cases {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        let block = BlockRange.of(in: storage, at: 0).range
        XCTAssertFalse(
            BlockGutterLayout.isCardBlock(in: storage, at: block.location),
            "« \(markdown) » est du texte courant"
        )
    }
}

func test_cardBlockSpacing_isVisiblyLargerThanTextSpacing() {
    XCTAssertGreaterThan(BlockGutterLayout.cardBlockSpacing, BlockGutterLayout.blockSpacing)
}
```

- [ ] **Étape 2 : lancer les tests, vérifier qu'ils échouent**

```bash
swift test --filter BlockGutterLayoutTests
```

Attendu : échec de compilation — `isCardBlock` et `cardBlockSpacing` n'existent pas.

- [ ] **Étape 3 : implémenter `cardBlockSpacing` et `isCardBlock`**

Dans `BlockGutterLayout.swift`, juste après `blockSpacing` (ligne 46) :

```swift
/// Écart vertical sous un bloc qui **dessine un cadre** (mermaid, tableau,
/// image, bloc de code) — nettement plus large que `blockSpacing`, qui reste
/// l'écart du texte courant. À 10 pt, deux cartes de plusieurs centaines de
/// points se touchaient presque : rien ne disait où finissait l'une et où
/// commençait l'autre (constat d'écran).
static let cardBlockSpacing: CGFloat = 28

/// `true` si le bloc qui commence à `location` peint un cadre. Fonction
/// pure, lue au **début** du bloc — c'est là que le parseur pose
/// `.mdBlockType` et que `StyleRenderer` pose `.mdMermaidAttachment`.
///
/// `.rawBlock` couvre les tableaux GFM et le HTML brut ; `.mdTableCell` les
/// rattrape quand la plage interrogée est celle d'une cellule.
static func isCardBlock(in storage: NSTextStorage, at location: Int) -> Bool {
    guard location >= 0, location < storage.length else { return false }
    if storage.attribute(.mdMermaidAttachment, at: location, effectiveRange: nil) != nil { return true }
    if storage.attribute(.mdTableCell, at: location, effectiveRange: nil) != nil { return true }
    if storage.attribute(.mdImageURL, at: location, effectiveRange: nil) != nil { return true }
    if let type = storage.attribute(.mdBlockType, at: location, effectiveRange: nil) as? BlockType {
        return type == .codeBlock || type == .rawBlock
    }
    return false
}
```

- [ ] **Étape 4 : lancer les tests, vérifier qu'ils passent**

```bash
swift test --filter BlockGutterLayoutTests
```

Attendu : 9 tests, 0 échec.

- [ ] **Étape 5 : écrire les tests en échec pour l'écart posé**

Créer `Tests/StyleRendererBlockSpacingTests.swift` :

```swift
import XCTest
import AppKit
@testable import OneToOne

/// `StyleRenderer.applyBlockSpacing` pose l'écart vertical sur le **dernier**
/// paragraphe de chaque bloc logique. L'écart large s'applique dès qu'un des
/// deux blocs du couple dessine un cadre — sans quoi une carte suivie d'un
/// paragraphe aurait 28 pt en dessous mais 10 pt au-dessus, une asymétrie
/// visible à l'écran.
///
/// Ces tests n'utilisent **que** des blocs de code non-mermaid comme cartes :
/// un bloc ```` ```mermaid ```` déclencherait un vrai `WKWebView` en tâche de
/// fond (voir la doc de tête de `StyleRendererMermaidTests`).
final class StyleRendererBlockSpacingTests: XCTestCase {

    /// Espacement posé sur le dernier paragraphe du bloc contenant `needle`.
    private func spacingAfterBlock(containing needle: String, in markdown: String) throws -> CGFloat {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        StyleRenderer.applyVisualStyle(to: storage)
        let ns = storage.string as NSString
        let location = ns.range(of: needle).location
        XCTAssertNotEqual(location, NSNotFound, "« \(needle) » introuvable dans le storage stylé")
        let block = BlockRange.of(in: storage, at: location).range
        let lastCharacter = max(block.location, NSMaxRange(block) - 1)
        let terminal = ns.lineRange(for: NSRange(location: lastCharacter, length: 0))
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: terminal.location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacing
    }

    func test_textFollowedByText_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }

    func test_textFollowedByACard_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Premier", in: "Premier\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByText_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "```swift\nprint(1)\n```\n\nSuite")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_cardFollowedByACard_getsTheWideSpacing() throws {
        let markdown = "```swift\nprint(1)\n```\n\n```swift\nprint(2)\n```"
        let spacing = try spacingAfterBlock(containing: "print(1)", in: markdown)
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    /// Dernier bloc du document : aucun bloc ne suit, seule la nature du bloc
    /// lui-même décide. Garde-fou contre une lecture hors bornes du « bloc
    /// suivant ».
    func test_lastCardOfTheDocument_getsTheWideSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "print(1)", in: "Intro\n\n```swift\nprint(1)\n```")
        XCTAssertEqual(spacing, BlockGutterLayout.cardBlockSpacing)
    }

    func test_lastTextBlockOfTheDocument_keepsTheNarrowSpacing() throws {
        let spacing = try spacingAfterBlock(containing: "Second", in: "Premier\n\nSecond")
        XCTAssertEqual(spacing, BlockGutterLayout.blockSpacing)
    }
}
```

- [ ] **Étape 6 : lancer les tests, vérifier lesquels échouent**

```bash
swift test --filter StyleRendererBlockSpacingTests
```

Attendu : les quatre tests « wide » échouent avec `10.0` au lieu de `28.0` ; les
deux tests « narrow » passent déjà.

- [ ] **Étape 7 : implémenter la sélection de l'écart**

Dans `StyleRenderer.swift`, remplacer le corps de la boucle `while` de
`applyBlockSpacing` (lignes 279-306) par :

```swift
        while location < renderEnd {
            let block = BlockRange.of(in: storage, at: location).range
            let physicalLine = text.lineRange(for: NSRange(location: location, length: 0))
            let blockAdvance = block.length > 0 ? NSMaxRange(block) : location
            let nextLocation = min(
                renderEnd,
                max(location + 1, max(blockAdvance + 1, NSMaxRange(physicalLine)))
            )

            if block.length > 0 {
                let lastCharacter = NSMaxRange(block) - 1
                let terminalParagraph = NSIntersectionRange(
                    text.lineRange(for: NSRange(location: lastCharacter, length: 0)),
                    block
                )
                if terminalParagraph.length > 0 {
                    // L'écart large dès qu'un des deux voisins dessine un
                    // cadre : une carte doit avoir la même respiration
                    // au-dessus qu'en dessous, et seul `paragraphSpacing` la
                    // porte — poser en plus `paragraphSpacingBefore` sur la
                    // carte suivante ferait 56 pt (TextKit additionne les
                    // deux).
                    let nextBlockStart = NSMaxRange(block) + 1
                    let touchesACard = BlockGutterLayout.isCardBlock(in: storage, at: block.location)
                        || BlockGutterLayout.isCardBlock(in: storage, at: nextBlockStart)
                    let spacing = touchesACard
                        ? BlockGutterLayout.cardBlockSpacing
                        : BlockGutterLayout.blockSpacing

                    let existing = storage.attribute(
                        .paragraphStyle,
                        at: terminalParagraph.location,
                        effectiveRange: nil
                    ) as? NSParagraphStyle
                    let style = (existing?.mutableCopy() as? NSMutableParagraphStyle)
                        ?? NSMutableParagraphStyle()
                    style.paragraphSpacing = max(style.paragraphSpacing, spacing)
                    storage.addAttribute(.paragraphStyle, value: style, range: terminalParagraph)
                }
            }

            location = nextLocation
        }
```

`isCardBlock` borne elle-même `location` : `nextBlockStart` au-delà du storage
renvoie `false` sans lecture hors bornes.

- [ ] **Étape 8 : lancer les tests, vérifier qu'ils passent**

```bash
swift test --filter StyleRendererBlockSpacingTests --filter BlockGutterLayoutTests
```

Attendu : 15 tests, 0 échec.

- [ ] **Étape 9 : vérifier qu'aucune suite éditeur ne régresse**

```bash
swift test --filter StyleRendererTests --filter TableControlLayoutTests \
  --filter MarkdownTableRenderingTests --filter BlockRangeTests
```

Attendu : 0 échec.

- [ ] **Étape 10 : commit**

```bash
git add OneToOne/Markdown/Core/BlockGutterLayout.swift \
        OneToOne/Markdown/Core/StyleRenderer.swift \
        Tests/BlockGutterLayoutTests.swift \
        Tests/StyleRendererBlockSpacingTests.swift
git commit -m "feat(editor): écart vertical élargi autour des blocs qui dessinent un cadre"
```

---

### Tâche 2 : géométrie de la bande d'aperçu

**Fichiers :**
- Modifier : `OneToOne/Markdown/Blocks/MermaidSourceLayout.swift`
- Test : `Tests/MermaidSourceLayoutTests.swift`

**Interfaces :**
- Consomme : `MermaidBlockLayout.fittedSize(for:maxWidth:)`, `MermaidBlockLayout.columnWidth`.
- Produit :
  - `MermaidSourceLayout.previewMaximumHeight: CGFloat` (= 240)
  - `MermaidSourceLayout.previewVerticalPadding: CGFloat` (= 12)
  - `MermaidSourceLayout.previewImageSize(forAttachmentSize: NSSize?, containerWidth: CGFloat) -> NSSize`
  - `MermaidSourceLayout.previewHeight(forAttachmentSize: NSSize?, containerWidth: CGFloat) -> CGFloat`
  - `MermaidSourceLayout.previewHeight(in: NSTextStorage, blockRange: NSRange, containerWidth: CGFloat) -> CGFloat`
  - `MermaidSourceLayout.previewRect(above: NSRect, containerWidth: CGFloat, imageSize: NSSize?) -> NSRect`
  - Signatures **modifiées**, toutes avec un nouveau paramètre `previewHeight: CGFloat` sans valeur par défaut :
    `headerRect(above:containerWidth:previewHeight:)`,
    `doneButtonRect(above:containerWidth:previewHeight:)`,
    `frameRect(firstLineRect:lastLineRect:containerWidth:previewHeight:)`,
    `bodyRect(firstLineRect:lastLineRect:containerWidth:previewHeight:)`

> Pas de valeur par défaut à `previewHeight` : un appelant qui l'oublierait
> retomberait silencieusement sur 0 et dessinerait — ou hit-testerait — l'en-tête au
> mauvais endroit. On veut une erreur de compilation, pas une divergence muette.

- [ ] **Étape 1 : écrire les tests en échec**

Dans `Tests/MermaidSourceLayoutTests.swift`, remplacer les quatre tests existants qui
appellent `headerRect`/`doneButtonRect`/`frameRect` par leurs versions avec
`previewHeight: 0`, puis ajouter la section aperçu. Le fichier devient :

```swift
    // MARK: - doneButtonRect

    func test_doneButtonRect_isAlignedToTheRightEdgeOfTheContainer() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(
            rect.maxX, 400 - MermaidSourceLayout.doneButtonTrailingMargin,
            "collé au bord droit du conteneur, pas de la ligne"
        )
        XCTAssertEqual(rect.width, MermaidSourceLayout.doneButtonWidth)
        XCTAssertEqual(rect.height, MermaidSourceLayout.doneButtonHeight)
    }

    func test_doneButtonRect_sitsInTheHeaderStripAboveTheFirstLine() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertGreaterThanOrEqual(rect.minY, firstLine.minY - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
        XCTAssertLessThanOrEqual(rect.maxY, firstLine.minY - MermaidSourceLayout.bodyTopPadding)
    }

    // MARK: - headerRect

    func test_headerRect_spansTheFullContainerWidth() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let rect = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(rect.width, 400)
        XCTAssertEqual(rect.height, MermaidSourceLayout.headerHeight)
        XCTAssertEqual(rect.minY, firstLine.minY - MermaidSourceLayout.bodyTopPadding - MermaidSourceLayout.headerHeight)
    }

    func test_frameRect_wrapsHeaderCodeAndBottomPadding() {
        let firstLine = NSRect(x: 0, y: 100, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 140, width: 300, height: 20)

        let frame = MermaidSourceLayout.frameRect(
            firstLineRect: firstLine,
            lastLineRect: lastLine,
            containerWidth: 400,
            previewHeight: 0
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, lastLine.maxY + MermaidSourceLayout.bodyBottomPadding)
        XCTAssertEqual(frame.width, 400)
    }
```

Puis ajouter, avant la section « Constantes de contrat » :

```swift
    // MARK: - Bande d'aperçu figé (bloc ouvert)

    /// Sans image livrée par le rendu, pas de bande : le cadre garde
    /// exactement l'allure qu'il avait avant ce chantier (en-tête + source).
    func test_previewHeight_withoutAnImage_isZero() {
        XCTAssertEqual(MermaidSourceLayout.previewHeight(forAttachmentSize: nil, containerWidth: 400), 0)
        XCTAssertEqual(MermaidSourceLayout.previewHeight(forAttachmentSize: .zero, containerWidth: 400), 0)
    }

    /// Un diagramme plus haut que le plafond est réduit à `previewMaximumHeight` :
    /// sans ça, une carte de 450 pt repousserait le source hors de l'écran
    /// pendant qu'on le tape.
    func test_previewHeight_capsATallDiagram() {
        let height = MermaidSourceLayout.previewHeight(
            forAttachmentSize: NSSize(width: 300, height: 900), containerWidth: 400
        )
        XCTAssertEqual(height, MermaidSourceLayout.previewMaximumHeight + 2 * MermaidSourceLayout.previewVerticalPadding)
    }

    func test_previewHeight_keepsASmallDiagramAtItsRealHeight() {
        let height = MermaidSourceLayout.previewHeight(
            forAttachmentSize: NSSize(width: 300, height: 100), containerWidth: 400
        )
        XCTAssertEqual(height, 100 + 2 * MermaidSourceLayout.previewVerticalPadding)
    }

    /// L'image est réduite **deux fois** : d'abord à la largeur du conteneur,
    /// puis au plafond de hauteur. Sans la première réduction, la hauteur
    /// réservée serait celle de l'image native alors que le dessin, lui,
    /// tiendrait dans le conteneur — un vide sous l'aperçu.
    func test_previewImageSize_fitsTheContainerWidthBeforeCappingTheHeight() {
        let size = MermaidSourceLayout.previewImageSize(
            forAttachmentSize: NSSize(width: 800, height: 200), containerWidth: 400
        )
        XCTAssertEqual(size.width, 400, accuracy: 0.001)
        XCTAssertEqual(size.height, 100, accuracy: 0.001, "ratio conservé : 200 × (400/800)")
    }

    func test_previewImageSize_neverEnlargesASmallDiagram() {
        let size = MermaidSourceLayout.previewImageSize(
            forAttachmentSize: NSSize(width: 120, height: 80), containerWidth: 400
        )
        XCTAssertEqual(size, NSSize(width: 120, height: 80))
    }

    func test_previewRect_isHorizontallyCenteredUnderTheHeader() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let imageSize = NSSize(width: 200, height: 100)
        let previewHeight = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)

        let rect = MermaidSourceLayout.previewRect(above: firstLine, containerWidth: 400, imageSize: imageSize)
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: previewHeight)

        XCTAssertEqual(rect.midX, 200, accuracy: 0.001, "centré dans le conteneur")
        XCTAssertEqual(rect.minY, header.maxY + MermaidSourceLayout.previewVerticalPadding, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
    }

    func test_previewRect_withoutAnImage_isEmpty() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let rect = MermaidSourceLayout.previewRect(above: firstLine, containerWidth: 400, imageSize: nil)

        XCTAssertTrue(rect.isEmpty)
    }

    /// L'en-tête reste **en haut** du cadre : la bande d'aperçu s'insère
    /// entre lui et le source, elle ne le pousse pas dedans. C'est ce qui
    /// empêche l'en-tête de paraître coiffer la carte du bloc précédent.
    func test_headerAndDoneButton_shiftUpByTheWholePreviewBand() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let band: CGFloat = 160

        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)
        let flat = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: 0)
        XCTAssertEqual(header.minY, flat.minY - band, accuracy: 0.001)
        XCTAssertEqual(header.height, MermaidSourceLayout.headerHeight)

        let button = MermaidSourceLayout.doneButtonRect(above: firstLine, containerWidth: 400, previewHeight: band)
        XCTAssertGreaterThanOrEqual(button.minY, header.minY)
        XCTAssertLessThanOrEqual(button.maxY, header.maxY, "le bouton reste dans sa bande, jamais sur l'aperçu")
    }

    func test_frameRect_wrapsTheWholeBandIncludingThePreview() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 440, width: 300, height: 20)
        let band: CGFloat = 160

        let frame = MermaidSourceLayout.frameRect(
            firstLineRect: firstLine, lastLineRect: lastLine, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(frame.minY, header.minY)
        XCTAssertEqual(frame.maxY, lastLine.maxY + MermaidSourceLayout.bodyBottomPadding)
    }

    /// Le corps (fond du source + gouttière) commence **sous** la bande
    /// d'aperçu, jamais sous l'en-tête seul — sinon la gouttière de numéros
    /// de ligne serait peinte derrière le diagramme.
    func test_bodyRect_startsBelowThePreviewBand() {
        let firstLine = NSRect(x: 0, y: 400, width: 300, height: 20)
        let lastLine = NSRect(x: 0, y: 440, width: 300, height: 20)
        let band: CGFloat = 160

        let body = MermaidSourceLayout.bodyRect(
            firstLineRect: firstLine, lastLineRect: lastLine, containerWidth: 400, previewHeight: band
        )
        let header = MermaidSourceLayout.headerRect(above: firstLine, containerWidth: 400, previewHeight: band)

        XCTAssertEqual(body.minY, header.maxY + band, accuracy: 0.001)
    }
```

- [ ] **Étape 2 : lancer les tests, vérifier qu'ils échouent**

```bash
swift test --filter MermaidSourceLayoutTests
```

Attendu : échec de compilation — les nouvelles fonctions et le paramètre
`previewHeight` n'existent pas.

- [ ] **Étape 3 : implémenter la géométrie**

Dans `MermaidSourceLayout.swift`, ajouter après `headerHeight` (ligne 37) :

```swift
    /// Hauteur maximale de l'**image** dans la bande d'aperçu du bloc ouvert
    /// (hors `previewVerticalPadding`). Un diagramme plus haut est réduit à
    /// l'échelle : sans ce plafond, une carte de 450 pt repousserait le source
    /// sous la ligne de flottaison et on éditerait à l'aveugle.
    static let previewMaximumHeight: CGFloat = 240

    /// Marge au-dessus et en dessous de l'image d'aperçu, à l'intérieur de la
    /// bande.
    static let previewVerticalPadding: CGFloat = 12
```

Puis, avant `doneButtonRect`, la section aperçu :

```swift
    // MARK: - Bande d'aperçu figé

    /// Taille à laquelle dessiner l'aperçu d'un bloc **ouvert** : l'image de
    /// l'attachment réduite **deux fois**, ratio conservé à chaque étape —
    /// d'abord à `containerWidth` (comme le fait déjà le dessin du bloc
    /// fermé, voir `MarkdownLayoutManager.drawMermaidDiagram`), puis à
    /// `previewMaximumHeight` si elle dépasse encore. Jamais agrandie.
    /// `NSSize.zero` quand il n'y a pas encore d'image.
    static func previewImageSize(forAttachmentSize size: NSSize?, containerWidth: CGFloat) -> NSSize {
        guard let size, size.width > 0, size.height > 0, containerWidth > 0 else { return .zero }
        let widthFitted = MermaidBlockLayout.fittedSize(for: size, maxWidth: containerWidth)
        guard widthFitted.height > previewMaximumHeight else { return widthFitted }
        let scale = previewMaximumHeight / widthFitted.height
        return NSSize(width: widthFitted.width * scale, height: previewMaximumHeight)
    }

    /// Hauteur **totale** réservée à la bande d'aperçu, paddings compris —
    /// `0` quand l'attachment n'a pas encore d'image : le cadre garde alors
    /// son allure d'origine (en-tête directement au-dessus du source).
    ///
    /// `containerWidth` est un paramètre ici, pas seulement dans
    /// `previewRect` : sans lui, une image plus large que le conteneur serait
    /// réduite au dessin mais pas dans la hauteur réservée — un vide sous
    /// l'aperçu.
    static func previewHeight(forAttachmentSize size: NSSize?, containerWidth: CGFloat) -> CGFloat {
        let scaled = previewImageSize(forAttachmentSize: size, containerWidth: containerWidth)
        guard scaled.height > 0 else { return 0 }
        return scaled.height + previewVerticalPadding * 2
    }

    /// Point d'entrée **unique** de la hauteur d'aperçu depuis un bloc vivant :
    /// le dessin du cadre, le dessin de l'en-tête et le hit-test du bouton
    /// « Terminé » l'appellent tous les trois, et `StyleRenderer` réserve la
    /// même valeur. Deux calculs divergents mettraient « Terminé » hors de sa
    /// zone cliquable — même principe que `TableControlLayout.placementForCursor`.
    static func previewHeight(in storage: NSTextStorage, blockRange: NSRange, containerWidth: CGFloat) -> CGFloat {
        guard blockRange.location >= 0, blockRange.location < storage.length,
              let attachment = storage.attribute(
                .mdMermaidAttachment, at: blockRange.location, effectiveRange: nil
              ) as? NSTextAttachment
        else { return 0 }
        return previewHeight(forAttachmentSize: attachment.image?.size, containerWidth: containerWidth)
    }

    /// Rectangle où peindre l'image d'aperçu, en coordonnées **conteneur** —
    /// centré horizontalement, juste sous la bande d'en-tête. `NSRect.zero`
    /// quand il n'y a pas d'image : rien à peindre.
    static func previewRect(above firstLineRect: NSRect, containerWidth: CGFloat, imageSize: NSSize?) -> NSRect {
        let scaled = previewImageSize(forAttachmentSize: imageSize, containerWidth: containerWidth)
        guard scaled.height > 0 else { return .zero }
        let band = scaled.height + previewVerticalPadding * 2
        let header = headerRect(above: firstLineRect, containerWidth: containerWidth, previewHeight: band)
        return NSRect(
            x: (containerWidth - scaled.width) / 2,
            y: header.maxY + previewVerticalPadding,
            width: scaled.width,
            height: scaled.height
        )
    }
```

Enfin, remplacer les quatre fonctions de géométrie existantes (lignes 79-115) par :

```swift
    /// Rectangle du bouton « Terminé », en coordonnées **conteneur** (mêmes
    /// conventions que `TableControlLayout.Placement` : sans le décalage
    /// `origin`/`textContainerInset` qu'ajoute chaque appelant) — dans la
    /// bande d'en-tête, aligné à droite. `previewHeight` : voir
    /// `headerRect(above:containerWidth:previewHeight:)`.
    static func doneButtonRect(above firstLineRect: NSRect, containerWidth: CGFloat, previewHeight: CGFloat) -> NSRect {
        let header = headerRect(above: firstLineRect, containerWidth: containerWidth, previewHeight: previewHeight)
        let y = header.minY + (headerHeight - doneButtonHeight) / 2
        let x = containerWidth - doneButtonWidth - doneButtonTrailingMargin
        return NSRect(x: x, y: y, width: doneButtonWidth, height: doneButtonHeight)
    }

    /// Rectangle de la bande d'en-tête (fond/label « mermaid »), sur toute la
    /// largeur du conteneur. Elle reste **en haut** du cadre : la bande
    /// d'aperçu (`previewHeight`, 0 s'il n'y en a pas) s'insère entre elle et
    /// la première ligne de source, et l'en-tête remonte d'autant. C'est ce
    /// qui l'empêche de paraître coiffer la carte du bloc précédent.
    ///
    /// L'espace total ainsi occupé au-dessus de `firstLineRect` est exactement
    /// le `paragraphSpacingBefore` que pose
    /// `StyleRenderer.applyOpenMermaidGeometry` : `headerHeight +
    /// previewHeight + bodyTopPadding`.
    static func headerRect(above firstLineRect: NSRect, containerWidth: CGFloat, previewHeight: CGFloat) -> NSRect {
        NSRect(
            x: 0,
            y: firstLineRect.minY - bodyTopPadding - previewHeight - headerHeight,
            width: containerWidth,
            height: headerHeight
        )
    }

    static func frameRect(
        firstLineRect: NSRect, lastLineRect: NSRect, containerWidth: CGFloat, previewHeight: CGFloat
    ) -> NSRect {
        let header = headerRect(above: firstLineRect, containerWidth: containerWidth, previewHeight: previewHeight)
        return NSRect(
            x: 0,
            y: header.minY,
            width: containerWidth,
            height: max(0, lastLineRect.maxY + bodyBottomPadding - header.minY)
        )
    }

    /// Zone du **source** (fond + gouttière de numéros de ligne) : elle
    /// commence sous la bande d'aperçu, jamais sous l'en-tête seul — sinon la
    /// gouttière serait peinte derrière le diagramme.
    static func bodyRect(
        firstLineRect: NSRect, lastLineRect: NSRect, containerWidth: CGFloat, previewHeight: CGFloat
    ) -> NSRect {
        let header = headerRect(above: firstLineRect, containerWidth: containerWidth, previewHeight: previewHeight)
        let top = header.maxY + previewHeight
        return NSRect(
            x: 0,
            y: top,
            width: containerWidth,
            height: max(0, lastLineRect.maxY + bodyBottomPadding - top)
        )
    }
```

- [ ] **Étape 4 : corriger les appelants pour que le module compile**

Trois appelants ne compilent plus. Les mettre à jour **mécaniquement** avec
`previewHeight: 0` — la vraie valeur arrive en tâches 4 et 5 :

- `OneToOne/Markdown/Core/EditorTextView.swift:1414` :
  `MermaidSourceLayout.doneButtonRect(above: firstLineRect, containerWidth: container.size.width, previewHeight: 0)`
- `OneToOne/Markdown/Core/MarkdownLayoutManager.swift:310-323` : ajouter
  `previewHeight: 0` aux appels `frameRect`, `headerRect`, `bodyRect`.
- `OneToOne/Markdown/Core/MarkdownLayoutManager.swift:550,561` : ajouter
  `previewHeight: 0` aux appels `headerRect` et `doneButtonRect`.
- `Tests/EditorTextViewMermaidClickTests.swift:360` : ajouter `previewHeight: 0`.

- [ ] **Étape 5 : lancer les tests, vérifier qu'ils passent**

```bash
swift test --filter MermaidSourceLayoutTests
```

Attendu : 18 tests, 0 échec.

- [ ] **Étape 6 : vérifier que rien n'a bougé à l'écran**

```bash
swift build && swift test --filter Mermaid
```

Attendu : 0 échec. Avec `previewHeight: 0` partout, le comportement est
strictement celui d'avant la tâche — c'est le but de cette étape intermédiaire.

- [ ] **Étape 7 : commit**

```bash
git add OneToOne/Markdown/Blocks/MermaidSourceLayout.swift \
        OneToOne/Markdown/Core/EditorTextView.swift \
        OneToOne/Markdown/Core/MarkdownLayoutManager.swift \
        Tests/MermaidSourceLayoutTests.swift \
        Tests/EditorTextViewMermaidClickTests.swift
git commit -m "feat(markdown): géométrie de la bande d'aperçu du bloc mermaid ouvert"
```

---

### Tâche 3 : réserver la bande dans la géométrie ouverte

**Fichiers :**
- Modifier : `OneToOne/Markdown/Core/StyleRenderer.swift:334-382` (`applyMermaidAttachment`)
- Modifier : `OneToOne/Markdown/Core/StyleRenderer.swift:469-503` (`applyOpenMermaidGeometry`)
- Test : `Tests/StyleRendererMermaidTests.swift`

**Interfaces :**
- Consomme : `MermaidSourceLayout.previewHeight(forAttachmentSize:containerWidth:)` (tâche 2).
- Produit : `applyOpenMermaidGeometry(to:range:attachmentImageSize:containerWidth:)` — privée,
  aucune tâche ultérieure ne l'appelle.

- [ ] **Étape 1 : écrire les tests en échec**

Ajouter à la fin de `Tests/StyleRendererMermaidTests.swift`, avant l'accolade
fermante :

```swift
    // MARK: - Bande d'aperçu réservée (bloc ouvert)

    /// Storage d'un bloc mermaid **ouvert** (curseur dedans) portant déjà un
    /// attachment dont l'image fait `imageSize` — construit sans passer par
    /// `applyVisualStyle`, qui déclencherait un vrai `WKWebView` (voir la doc
    /// de tête de cette suite).
    private func makeOpenMermaidStorage(imageSize: NSSize?) throws -> (NSTextStorage, NSRange) {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse("```mermaid\ngraph TD\nA-->B\n```"))
        let ns = storage.string as NSString
        let start = ns.range(of: "graph TD").location
        let end = NSMaxRange(ns.range(of: "A-->B"))
        let range = NSRange(location: start, length: end - start)

        let attachment = NSTextAttachment()
        if let imageSize {
            let image = NSImage(size: imageSize)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: imageSize).fill()
            image.unlockFocus()
            attachment.image = image
        }
        storage.addAttribute(.mdMermaidAttachment, value: attachment, range: range)
        return (storage, range)
    }

    /// Hauteur réservée au-dessus de la première ligne d'un bloc ouvert.
    private func paragraphSpacingBefore(in storage: NSTextStorage, at location: Int) throws -> CGFloat {
        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        )
        return style.paragraphSpacingBefore
    }

    /// Avec une image livrée, l'espace réservé au-dessus du source couvre
    /// l'en-tête **et** la bande d'aperçu : c'est là que
    /// `MarkdownLayoutManager` peint le diagramme figé.
    func test_openMermaidBlock_withAnImage_reservesTheHeaderAndThePreviewBand() throws {
        let imageSize = NSSize(width: 300, height: 150)
        let (storage, range) = try makeOpenMermaidStorage(imageSize: imageSize)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: imageSize, containerWidth: 400
        )

        let band = MermaidSourceLayout.previewHeight(forAttachmentSize: imageSize, containerWidth: 400)
        XCTAssertGreaterThan(band, 0, "prémisse : une image de 300×150 produit une bande")
        XCTAssertEqual(
            try paragraphSpacingBefore(in: storage, at: range.location),
            MermaidSourceLayout.headerHeight + band + MermaidSourceLayout.bodyTopPadding,
            accuracy: 0.001
        )
    }

    /// Sans image (bloc jamais rendu), la réservation reste exactement celle
    /// d'avant ce chantier — le cadre garde son allure d'origine.
    func test_openMermaidBlock_withoutAnImage_reservesOnlyTheHeader() throws {
        let (storage, range) = try makeOpenMermaidStorage(imageSize: nil)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: nil, containerWidth: 400
        )

        XCTAssertEqual(
            try paragraphSpacingBefore(in: storage, at: range.location),
            MermaidSourceLayout.headerHeight + MermaidSourceLayout.bodyTopPadding,
            accuracy: 0.001
        )
    }

    /// La première ligne d'un bloc ouvert garde une hauteur de ligne de code
    /// normale : la bande est réservée par l'espacement de paragraphe, jamais
    /// en gonflant `minimumLineHeight` — ce qui produirait un curseur vertical
    /// surdimensionné (défaut déjà corrigé, à ne pas réintroduire).
    func test_openMermaidBlock_neverInflatesTheFirstLineHeight() throws {
        let imageSize = NSSize(width: 300, height: 900)
        let (storage, range) = try makeOpenMermaidStorage(imageSize: imageSize)
        StyleRenderer.applyOpenMermaidGeometryForTesting(
            to: storage, range: range, attachmentImageSize: imageSize, containerWidth: 400
        )

        let style = try XCTUnwrap(
            storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertEqual(style.minimumLineHeight, MermaidSourceLayout.sourceLineHeight)
    }
```

- [ ] **Étape 2 : lancer les tests, vérifier qu'ils échouent**

```bash
swift test --filter StyleRendererMermaidTests
```

Attendu : échec de compilation — `applyOpenMermaidGeometryForTesting` n'existe pas.

- [ ] **Étape 3 : implémenter la réservation**

Dans `StyleRenderer.swift`, changer la signature d'`applyOpenMermaidGeometry`
(ligne 469) et le calcul de `paragraphSpacingBefore` (lignes 480-481) :

```swift
    private static func applyOpenMermaidGeometry(
        to storage: NSTextStorage, range: NSRange,
        attachmentImageSize: NSSize?, containerWidth: CGFloat
    ) {
```

```swift
        firstLineStyle.paragraphSpacingBefore = MermaidSourceLayout.headerHeight
            + MermaidSourceLayout.previewHeight(
                forAttachmentSize: attachmentImageSize, containerWidth: containerWidth
              )
            + MermaidSourceLayout.bodyTopPadding
```

Compléter la doc de la fonction (ligne 465-468) par :

```swift
    /// La première ligne reçoit `paragraphSpacingBefore` : l'espace où
    /// `MarkdownLayoutManager` peint l'étiquette `mermaid`, le bouton
    /// « Terminé » **et** la bande d'aperçu figé (l'image déjà posée sur
    /// l'attachment, jamais un rendu relancé — voir `applyMermaidAttachment`).
    /// Toujours l'espacement de paragraphe, jamais `minimumLineHeight` :
    /// gonfler la hauteur de la première ligne produirait un curseur vertical
    /// surdimensionné.
```

Ajouter juste après la fonction, le point d'entrée de test — même patron que
`refreshClosedMermaidGeometry`, `internal` pour être exercée sans vue vivante :

```swift
    /// Point d'entrée `internal` sur `applyOpenMermaidGeometry`, pour les
    /// tests : exercer la géométrie ouverte sans passer par
    /// `applyVisualStyle`, qui déclencherait un vrai `WKWebView` en tâche de
    /// fond (voir la doc de tête de `StyleRendererMermaidTests`). Même patron
    /// que `refreshClosedMermaidGeometry`/`EditorTextView.mermaidDoneButtonRange`.
    static func applyOpenMermaidGeometryForTesting(
        to storage: NSTextStorage, range: NSRange,
        attachmentImageSize: NSSize?, containerWidth: CGFloat
    ) {
        applyOpenMermaidGeometry(
            to: storage, range: range,
            attachmentImageSize: attachmentImageSize, containerWidth: containerWidth
        )
    }
```

Enfin, dans la branche « bloc ouvert » d'`applyMermaidAttachment`, remplacer
l'appel de la ligne 371 par :

```swift
            // Largeur de la colonne réellement affichée : la bande d'aperçu
            // est réduite pour y tenir, et la hauteur réservée ici doit être
            // calculée sur la **même** largeur que le dessin, sinon un vide
            // subsiste sous l'aperçu. Repli sur `columnWidth` quand aucune vue
            // n'est attachée (cas des tests).
            let containerWidth = MainActor.assumeIsolated {
                storage.layoutManagers.first?.firstTextView?.textContainer?.size.width
            } ?? 0
            applyOpenMermaidGeometry(
                to: storage, range: range,
                attachmentImageSize: attachment.image?.size,
                containerWidth: containerWidth > 0 ? containerWidth : MermaidBlockLayout.columnWidth
            )
```

- [ ] **Étape 4 : lancer les tests, vérifier qu'ils passent**

```bash
swift test --filter StyleRendererMermaidTests
```

Attendu : 20 tests, 0 échec.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Markdown/Core/StyleRenderer.swift Tests/StyleRendererMermaidTests.swift
git commit -m "feat(markdown): réserve la bande d'aperçu au-dessus du source mermaid ouvert"
```

---

### Tâche 4 : le bouton « Terminé » suit le décalage

**Fichiers :**
- Modifier : `OneToOne/Markdown/Core/EditorTextView.swift:1404-1422` (`mermaidDoneButtonRange`)
- Modifier : `OneToOne/Markdown/Core/MarkdownLayoutManager.swift:373-403` (`drawMermaidDiagrams`)
- Modifier : `OneToOne/Markdown/Core/MarkdownLayoutManager.swift:533-580` (`drawMermaidHeader`)
- Test : `Tests/EditorTextViewMermaidClickTests.swift`

**Interfaces :**
- Consomme : `MermaidSourceLayout.previewHeight(in:blockRange:containerWidth:)` (tâche 2).
- Produit : `MarkdownLayoutManager.drawMermaidHeader(above:origin:containerWidth:previewHeight:)` — privée.

> C'est la tâche la plus risquée du plan : si le hit-test et le dessin ne
> calculent pas la **même** hauteur de bande, « Terminé » devient incliquable et
> le bloc ne peut plus se refermer autrement qu'en cliquant ailleurs.

- [ ] **Étape 1 : écrire le test en échec**

Dans `Tests/EditorTextViewMermaidClickTests.swift`, mettre à jour l'assistant
`pointInDoneButton` (ligne 355-365) pour qu'il lise la vraie hauteur de bande :

```swift
    private func pointInDoneButton(forBlockRange blockRange: NSRange, in editor: EditorTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(editor.layoutManager)
        let container = try XCTUnwrap(editor.textContainer)
        let storage = try XCTUnwrap(editor.textStorage)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let previewHeight = MermaidSourceLayout.previewHeight(
            in: storage, blockRange: blockRange, containerWidth: container.size.width
        )
        let buttonRect = MermaidSourceLayout.doneButtonRect(
            above: firstLineRect, containerWidth: container.size.width, previewHeight: previewHeight
        )
        return NSPoint(
            x: buttonRect.midX + editor.textContainerInset.width,
            y: buttonRect.midY + editor.textContainerInset.height
        )
    }
```

Puis ajouter, après `test_doneButtonRange_onAClosedBlock_returnsNil` :

```swift
    /// Avec une bande d'aperçu, le bouton « Terminé » remonte de toute sa
    /// hauteur. Le hit-test doit suivre — sinon le seul geste qui referme un
    /// bloc devient incliquable.
    func test_doneButtonRange_withAPreviewBand_followsTheShiftedHeader() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")
        let storage = try XCTUnwrap(editor.textStorage)
        let container = try XCTUnwrap(editor.textContainer)

        let imageSize = NSSize(width: 300, height: 150)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        let attachment = try XCTUnwrap(
            storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment
        )
        attachment.image = image

        let band = MermaidSourceLayout.previewHeight(
            in: storage, blockRange: blockRange, containerWidth: container.size.width
        )
        XCTAssertGreaterThan(band, 0, "prémisse : l'attachment porte maintenant une image")

        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))
        let point = try pointInDoneButton(forBlockRange: blockRange, in: editor)
        XCTAssertEqual(editor.mermaidDoneButtonRange(at: point), blockRange)
    }

    /// Contrôle négatif : l'ancienne position du bouton (celle d'un cadre
    /// sans aperçu) ne doit plus rien toucher. Sans ce test, un hit-test resté
    /// à `previewHeight: 0` passerait inaperçu — les deux rectangles se
    /// chevauchent tant que la bande est plus courte que le bouton.
    func test_doneButtonRange_withAPreviewBand_ignoresTheOldButtonPosition() throws {
        let (editor, blockRange) = try makeWiredEditorWithMermaidBlock(prefix: "intro\n\n")
        let storage = try XCTUnwrap(editor.textStorage)
        let container = try XCTUnwrap(editor.textContainer)
        let layoutManager = try XCTUnwrap(editor.layoutManager)

        let imageSize = NSSize(width: 300, height: 150)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()
        let attachment = try XCTUnwrap(
            storage.attribute(.mdMermaidAttachment, at: blockRange.location, effectiveRange: nil) as? NSTextAttachment
        )
        attachment.image = image

        editor.setSelectedRange(NSRange(location: blockRange.location, length: 0))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let staleRect = MermaidSourceLayout.doneButtonRect(
            above: firstLineRect, containerWidth: container.size.width, previewHeight: 0
        )
        let stalePoint = NSPoint(
            x: staleRect.midX + editor.textContainerInset.width,
            y: staleRect.midY + editor.textContainerInset.height
        )

        XCTAssertNil(editor.mermaidDoneButtonRange(at: stalePoint))
    }
```

- [ ] **Étape 2 : lancer les tests, vérifier qu'ils échouent**

```bash
swift test --filter EditorTextViewMermaidClickTests
```

Attendu : `test_doneButtonRange_withAPreviewBand_followsTheShiftedHeader` échoue
(`nil` au lieu de la plage) — le hit-test est encore figé à `previewHeight: 0`.

- [ ] **Étape 3 : brancher le hit-test sur la vraie hauteur**

Dans `EditorTextView.swift`, remplacer les lignes 1412-1414 par :

```swift
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: blockRange.location)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        // Même calcul que le dessin (`MarkdownLayoutManager.drawMermaidHeader`) :
        // la bande d'aperçu remonte l'en-tête, donc le bouton. Deux valeurs
        // divergentes rendraient « Terminé » incliquable.
        let previewHeight = MermaidSourceLayout.previewHeight(
            in: storage, blockRange: blockRange, containerWidth: container.size.width
        )
        let buttonRect = MermaidSourceLayout.doneButtonRect(
            above: firstLineRect, containerWidth: container.size.width, previewHeight: previewHeight
        )
```

- [ ] **Étape 4 : brancher le dessin de l'en-tête sur la même valeur**

Dans `MarkdownLayoutManager.swift`, `drawMermaidDiagrams`, remplacer les lignes
394-396 par :

```swift
                if charRange.location == blockRange.location {
                    let previewHeight = MermaidSourceLayout.previewHeight(
                        in: storage, blockRange: blockRange, containerWidth: container.size.width
                    )
                    self.drawMermaidHeader(
                        above: lineRect, origin: origin,
                        containerWidth: container.size.width, previewHeight: previewHeight
                    )
                }
```

Puis changer la signature de `drawMermaidHeader` (ligne 533) et ses deux appels
internes à la géométrie (lignes 550 et 561) :

```swift
    private func drawMermaidHeader(
        above lineFragmentRect: NSRect, origin: NSPoint,
        containerWidth: CGFloat, previewHeight: CGFloat
    ) {
```

```swift
        let headerRect = MermaidSourceLayout.headerRect(
            above: lineFragmentRect, containerWidth: containerWidth, previewHeight: previewHeight
        )
```

```swift
        let buttonRect = MermaidSourceLayout.doneButtonRect(
            above: lineFragmentRect, containerWidth: containerWidth, previewHeight: previewHeight
        )
            .offsetBy(dx: origin.x, dy: origin.y)
```

- [ ] **Étape 5 : lancer les tests, vérifier qu'ils passent**

```bash
swift test --filter EditorTextViewMermaidClickTests
```

Attendu : 13 tests, 0 échec.

- [ ] **Étape 6 : commit**

```bash
git add OneToOne/Markdown/Core/EditorTextView.swift \
        OneToOne/Markdown/Core/MarkdownLayoutManager.swift \
        Tests/EditorTextViewMermaidClickTests.swift
git commit -m "fix(markdown): le hit-test « Terminé » suit la bande d'aperçu"
```

---

### Tâche 5 : peindre l'aperçu figé

**Fichiers :**
- Modifier : `OneToOne/Markdown/Core/MarkdownLayoutManager.swift:288-349` (`drawOpenMermaidBackgrounds`)

**Interfaces :**
- Consomme : `MermaidSourceLayout.previewHeight(in:blockRange:containerWidth:)`,
  `MermaidSourceLayout.previewRect(above:containerWidth:imageSize:)` (tâche 2) ;
  la hauteur réservée par `applyOpenMermaidGeometry` (tâche 3) ;
  `drawMermaidHeader` déjà décalé (tâche 4).
- Produit : rien — c'est la feuille du chantier.

> Le dessin ne se teste pas unitairement. Cette tâche se valide au build, aux
> suites existantes (non-régression) et à l'écran.

- [ ] **Étape 1 : peindre la bande**

Dans `drawOpenMermaidBackgrounds`, remplacer le corps du `enumerateAttribute`
(lignes 298-348) par :

```swift
        storage.enumerateAttribute(.mdMermaidAttachment, in: visibleCharacters) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let blockRange = MermaidBlockLayout.blockRange(in: storage, at: range.location),
                  MermaidBlockLayout.selectionTouches(selectedLocation, blockRange: blockRange),
                  drawnStarts.insert(blockRange.location).inserted
            else { return }

            let containerWidth = container.size.width
            let firstGlyph = self.glyphIndexForCharacter(at: blockRange.location)
            let lastCharacter = max(blockRange.location, NSMaxRange(blockRange) - 1)
            let lastGlyph = self.glyphIndexForCharacter(at: lastCharacter)
            let firstLine = self.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let lastLine = self.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)

            // Même calcul que le hit-test de « Terminé » et que la hauteur
            // réservée par `StyleRenderer.applyOpenMermaidGeometry`.
            let previewHeight = MermaidSourceLayout.previewHeight(
                in: storage, blockRange: blockRange, containerWidth: containerWidth
            )

            let frame = MermaidSourceLayout.frameRect(
                firstLineRect: firstLine, lastLineRect: lastLine,
                containerWidth: containerWidth, previewHeight: previewHeight
            ).offsetBy(dx: origin.x, dy: origin.y)
            let header = MermaidSourceLayout.headerRect(
                above: firstLine, containerWidth: containerWidth, previewHeight: previewHeight
            ).offsetBy(dx: origin.x, dy: origin.y)
            let body = MermaidSourceLayout.bodyRect(
                firstLineRect: firstLine, lastLineRect: lastLine,
                containerWidth: containerWidth, previewHeight: previewHeight
            ).offsetBy(dx: origin.x, dy: origin.y)

            // `drawBackground(forGlyphRange:at:)` peut fournir un clip limité
            // aux lignes en cours : le cadre et l'aperçu vivent au-dessus de
            // la première ligne du bloc, donc **hors** de ce clip. Sans cet
            // élargissement, la bande d'aperçu du bloc ouvert disparaît
            // derrière le cadre du bloc précédent — exactement le défaut déjà
            // rencontré avec l'en-tête (voir `drawMermaidHeader`).
            NSGraphicsContext.current?.saveGraphicsState()
            defer { NSGraphicsContext.current?.restoreGraphicsState() }
            let clipHeight = self.firstTextView?.bounds.height ?? frame.height
            NSBezierPath(
                rect: NSRect(x: origin.x, y: 0, width: containerWidth, height: clipHeight)
            ).addClip()

            let card = NSBezierPath(
                roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                xRadius: MermaidSourceLayout.cornerRadius,
                yRadius: MermaidSourceLayout.cornerRadius
            )
            MermaidSourceLayout.frameBackgroundColor.setFill()
            card.fill()

            NSGraphicsContext.current?.saveGraphicsState()
            card.addClip()
            MermaidSourceLayout.headerBackgroundColor.setFill()
            header.fill()
            MermaidSourceLayout.gutterBackgroundColor.setFill()
            NSRect(x: body.minX, y: body.minY, width: MermaidSourceLayout.gutterWidth, height: body.height).fill()

            // Aperçu **figé** : l'image déjà portée par l'attachment, jamais
            // un rendu relancé (voir `StyleRenderer.applyMermaidAttachment`,
            // branche « bloc ouvert »). Elle date de la dernière fermeture du
            // bloc ; « Terminé » la rafraîchit.
            if previewHeight > 0, let image = attachment.image {
                let preview = MermaidSourceLayout.previewRect(
                    above: firstLine, containerWidth: containerWidth, imageSize: image.size
                ).offsetBy(dx: origin.x, dy: origin.y)
                if !preview.isEmpty {
                    image.draw(in: preview)
                }
            }
            NSGraphicsContext.current?.restoreGraphicsState()

            MermaidSourceLayout.dividerColor.setFill()
            NSRect(x: header.minX, y: header.maxY - 1, width: header.width, height: 1).fill()
            if previewHeight > 0 {
                // Filet entre l'aperçu et le source : c'est lui qui fait lire
                // les deux comme un seul bloc en deux moitiés, pas comme deux
                // cadres empilés.
                NSRect(x: body.minX, y: body.minY, width: body.width, height: 1).fill()
            }
            NSRect(x: body.minX + MermaidSourceLayout.gutterWidth, y: body.minY, width: 1, height: body.height).fill()

            MermaidSourceLayout.borderColor.setStroke()
            card.lineWidth = MermaidSourceLayout.borderWidth
            card.stroke()
        }
```

- [ ] **Étape 2 : compiler**

```bash
swift build
```

Attendu : build réussi.

- [ ] **Étape 3 : vérifier la non-régression des suites éditeur**

```bash
swift test --filter Mermaid --filter BlockGutterLayoutTests \
  --filter StyleRendererBlockSpacingTests --filter SlashControllerTests \
  --filter StyleRendererTests --filter TableControlLayoutTests \
  --filter EditorTextView --filter EditorRepresentable
```

Attendu : 0 échec.

- [ ] **Étape 4 : commit**

```bash
git add OneToOne/Markdown/Core/MarkdownLayoutManager.swift
git commit -m "feat(markdown): peint l'aperçu figé dans le cadre du bloc mermaid ouvert"
```

---

### Tâche 6 : vérification complète et `STATUS.md`

**Fichiers :**
- Modifier : `STATUS.md`

**Interfaces :**
- Consomme : tout ce qui précède.
- Produit : rien.

- [ ] **Étape 1 : vérification de référence du dépôt**

```bash
swift test --skip CalendarImportEventTests
```

Attendu : les échecs **préexistants** listés dans `STATUS.md` uniquement
(`MenuBarStatsTests.test_badge_twelve_compact`, dépendant de l'heure). Tout autre
échec est une régression de ce chantier : la corriger avant de continuer.

- [ ] **Étape 2 : construire et lancer l'app de développement**

```bash
Scripts/bump-and-build.sh dev
```

- [ ] **Étape 3 : vérifier à l'écran**

Dans une note, saisir un document contenant, dans cet ordre : un paragraphe, un
bloc mermaid valide, un second bloc mermaid valide, un tableau. Attendre que les
deux diagrammes se rendent, puis cliquer dans le source du **second** bloc.

Contrôler :

1. les deux cartes rendues et le tableau sont nettement séparés (28 pt) ; deux
   paragraphes de texte restent serrés ;
2. le bloc ouvert affiche, **dans son propre cadre** : en-tête `mermaid` +
   « Terminé » en haut, puis son diagramme, puis un filet, puis le source
   numéroté ;
3. l'en-tête ne touche plus le cadre du bloc précédent ;
4. frapper plusieurs caractères dans le source : l'aperçu **ne bouge pas** et
   aucune carte ne se superpose au source ;
5. cliquer « Terminé » : le bloc se referme et le diagramme se met à jour ;
6. répéter avec un bloc mermaid placé en **tout début** de document (risque 2 de
   la spec : `paragraphSpacingBefore` sur le premier paragraphe du conteneur) ;
7. répéter avec un source volontairement invalide (`flowchart TD` puis `((((`) :
   le cadre d'erreur doit s'afficher dans la bande d'aperçu ;
8. redimensionner la fenêtre pendant qu'un bloc est ouvert et noter le
   comportement (voir limite connue ci-dessous).

- [ ] **Étape 4 : consigner l'état dans `STATUS.md`**

Dans la section « Diagrammes Mermaid », ajouter à la liste des défauts corrigés :

```markdown
- le bloc mermaid **ouvert** affiche son propre diagramme dans son cadre, au-dessus
  du source (bande plafonnée à 240 pt, `MermaidSourceLayout.previewMaximumHeight`) :
  l'image est celle de la dernière fermeture, **jamais** un rendu relancé à la
  frappe — le correctif de superposition du 2026-08-08 reste intact. L'en-tête
  passe en haut du cadre et cesse de paraître coiffer la carte du bloc précédent ;
```

Dans la section « Manipulation des blocs », remplacer la ligne sur l'espacement de
10 pt par :

```markdown
- espacement vertical de 10 pt à la fin de chaque bloc logique, porté à 28 pt
  (`BlockGutterLayout.cardBlockSpacing`) dès qu'un des deux blocs voisins dessine
  un cadre — mermaid, tableau, image, bloc de code. Seul `paragraphSpacing` le
  porte : y ajouter `paragraphSpacingBefore` doublerait l'écart, TextKit
  additionnant les deux.
```

Dans « Défauts connus hors chantier », ajouter :

```markdown
- la poignée de gouttière d'un bloc mermaid **ouvert** s'aligne sur la première
  ligne de source, donc à côté du source et non en haut du cadre : elle se cale
  sur les rects de ligne, et la bande en-tête/aperçu vit dans l'espacement de
  paragraphe, hors ligne ;
- la hauteur réservée à la bande d'aperçu est calculée avec la largeur de colonne
  connue **au moment du stylage** : redimensionner la fenêtre pendant qu'un bloc
  est ouvert peut laisser un léger vide (ou un léger recouvrement) sous l'aperçu
  jusqu'au prochain restylage du bloc.
```

Mettre à jour la date de dernière mise à jour et la « Prochaine action ».

- [ ] **Étape 5 : commit**

```bash
git add STATUS.md
git commit -m "docs(status): aération des blocs-cartes et aperçu figé du bloc mermaid ouvert"
```

---

## Auto-revue

**Couverture de la spec** — chaque section de la spec a sa tâche :

| Section de la spec | Tâche |
|---|---|
| Conception §1, respiration entre blocs | 1 |
| Conception §2, géométrie de la bande | 2 |
| Conception §2, raccord 1 (`paragraphSpacingBefore`) | 3 |
| Conception §2, raccord 2 (décalage `headerRect`/`frameRect`/`bodyRect`) | 2 + 5 |
| Conception §2, raccord 3 (dessin de l'aperçu) | 5 |
| Conception §3, point de correction unique | 2 (`previewHeight(in:blockRange:containerWidth:)`) + 4 |
| Tests `MermaidSourceLayoutTests` | 2 |
| Tests `StyleRendererMermaidTests` | 3 |
| Tests `BlockGutterLayoutTests` | 1 |
| Tests `StyleRendererBlockSpacingTests` | 1 |
| Vérification à l'écran | 6 |
| Risque 1 (clip de la passe fond) | 5, étape 1 |
| Risque 2 (bloc en début de document) | 6, étape 3, point 6 |
| Risque 3 (poignée de gouttière) | 6, étape 4 (`STATUS.md`) |

**Écart assumé par rapport à la spec** : la spec ne mentionnait pas le décalage
possible entre la largeur de colonne lue au stylage et celle lue au dessin après un
redimensionnement de fenêtre. Le plan l'ajoute comme limite connue (tâche 6, étape
4) plutôt que d'élargir le périmètre — même nature d'écart mineur que celui déjà
documenté pour le bloc fermé dans `MermaidBlockLayout.fittedSize`.
