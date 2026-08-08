# Prototype d'éditeur par blocs — plan d'implémentation

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour exécuter ce plan tâche par tâche. Les
> étapes utilisent la syntaxe case à cocher (`- [ ]`) pour le suivi.

**Spec** : [`docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`](../specs/2026-08-08-prototype-editeur-par-blocs-design.md)

**Objectif** : répondre par oui ou non à une seule question — une vue éditable
par bloc (`NSTextView` par bloc) tient-elle en AppKit — et livrer un ADR de
verdict appuyé sur des mesures réelles.

**Architecture** : paquet SwiftPM autonome et jetable, sans aucune dépendance.
Deux couches : `ProbeCore`, pur Foundation, qui porte le document, les
mutations, la répartition de sélection et l'historique — entièrement testé en
unitaire ; `block-editor-probe`, exécutable AppKit, qui empile un `NSTextView`
par bloc et n'y met **aucune** logique. L'autorité est entièrement dans le
coordinateur ; les vues reflètent.

**Pile technique** : Swift 5.9 (tools-version), macOS 15+, AppKit / TextKit 1,
XCTest. Zéro dépendance externe.

---

## Contraintes globales

- **Langue** : commentaires et libellés d'interface en **français**, symboles et
  code en anglais. Cette règle vaut pour chaque fichier créé par ce plan.
- **Commits conventionnels**, un par tâche, message en français.
- **Branche** : `feat/prototype-blocs-appkit`, créée depuis `53e6e32`. Aucun
  commit sur `master`.
- **⚠️ Le worktree contient un gros lot de changements éditeur non commités**
  (voir `git status`). Chaque commit de ce plan ne cite que des chemins
  explicites — `Prototypes/`, `docs/`. **Jamais `git add -A`, jamais
  `git add .`, jamais `git commit -a`.** Un seul écart mélange le chantier
  éditeur avec le prototype.
- **Rien du module `OneToOne/Markdown/` n'est touché, importé ni modifié.** Le
  `Package.swift` racine n'est pas modifié non plus.
- **Zéro dépendance** dans le paquet du prototype.
- **Hors périmètre, à ne jamais ajouter** : markdown, types de blocs, images,
  tableaux, mermaid, styles inline, commandes `/`, persistance, thème sombre,
  accessibilité.
- **Offsets** : tous les décalages de `ProbeCore` sont des décalages **UTF-16**,
  pour coïncider avec les `NSRange` d'AppKit. Le découpage de chaîne passe donc
  systématiquement par `NSString`, jamais par `String.Index`.
- **Limite de temps** : trois sessions de travail (fixée par la spec). Au-delà,
  on tranche avec ce qu'on a.

### Emplacement et commandes

Le prototype est un **paquet imbriqué autonome**. Toutes les commandes `swift`
de ce plan s'exécutent depuis `Prototypes/BlockEditorProbe/` :

```bash
cd Prototypes/BlockEditorProbe
swift test                    # ~secondes, aucune dépendance MLX
swift run block-editor-probe  # ouvre la fenêtre du prototype
```

Conséquence assumée : `swift test` à la racine du dépôt **ne voit pas** les
tests de la sonde. C'est voulu — la suite globale de la racine est déjà
instable (`STATUS.md`) et reconstruire MLX à chaque itération tuerait la
vitesse, qui est la raison d'être du prototype.

---

## Structure de fichiers

```text
Prototypes/BlockEditorProbe/
├── Package.swift                          paquet autonome, 0 dépendance
├── README.md                              but, commandes, date de péremption
├── Sources/
│   ├── ProbeCore/                         pur Foundation — testé en unitaire
│   │   ├── ProbeBlock.swift               le bloc et sa longueur UTF-16
│   │   ├── ProbeSelection.swift           ProbePosition + ProbeSelection
│   │   ├── ProbeDocument.swift            liste de blocs, replace, navigation
│   │   ├── ProbeEditing.swift             ⌫ ⌦ ⏎ frappe, au-dessus de replace
│   │   ├── SelectionDistribution.swift    sélection → plage par bloc
│   │   └── ProbeHistory.swift             undo/redo par instantanés
│   └── block-editor-probe/                AppKit — vérifié à la main
│       ├── main.swift                     point d'entrée, analyse des options
│       ├── ProbeAppDelegate.swift         fenêtre et menu
│       ├── BlockTextView.swift            un NSTextView par bloc
│       ├── BlockStackView.swift           pile à disposition manuelle
│       ├── SelectionCoordinator.swift     toute l'autorité
│       └── ScaleHarness.swift             200 blocs, trois mesures
└── Tests/
    └── ProbeCoreTests/
        ├── ProbeDocumentTests.swift
        ├── ProbeEditingTests.swift
        ├── SelectionDistributionTests.swift
        └── ProbeHistoryTests.swift

docs/adr/
├── 2026-08-08-reecriture-editeur-architecture-appflowy.md   tâche 1
└── 2026-08-08-verdict-prototype-blocs-appkit.md             tâche 13
```

### Pourquoi cette découpe

`ProbeCore` ne connaît ni AppKit ni vue : c'est ce qui rend les quatre
mécanismes vérifiables sans fenêtre. `SelectionCoordinator` est le seul objet
qui décide ; `BlockTextView` et `BlockStackView` n'ont pas d'état métier. C'est
l'inverse exact de l'éditeur actuel, où la vue porte la logique — et c'est
précisément l'hypothèse que le prototype teste.

`BlockStackView` fait sa disposition **à la main**, sans Auto Layout ni
`NSStackView`. Raison : à 200 blocs, on veut mesurer le coût des vues éditables
par bloc, pas celui du moteur de contraintes. Confondre les deux rendrait le
verdict inexploitable.

---

## Vue d'ensemble des tâches

| # | Tâche | Livrable | Vérification |
|---|---|---|---|
| 1 | ADR de licence et d'architecture | `docs/adr/…-appflowy.md` | relecture |
| 2 | Paquet + primitives | `ProbeBlock`, `ProbePosition`, `ProbeSelection` | `swift test` |
| 3 | `ProbeDocument.replace` | la mutation unique | `swift test` |
| 4 | Navigation et extraction | `position(after:)`, `text(in:)`, `setText` | `swift test` |
| 5 | `ProbeEditing` | ⌫ ⌦ ⏎ frappe | `swift test` |
| 6 | `SelectionDistribution` | sélection → plage par bloc | `swift test` |
| 7 | `ProbeHistory` | undo/redo au niveau conteneur | `swift test` |
| 8 | Fenêtre et pile de blocs | ça s'affiche, ça se tape | à l'écran |
| 9 | **Mécanisme 1** — sélection traversante | souris, ⇧flèches, ⌘A, surlignage | à l'écran |
| 10 | **Mécanisme 2** — édition destructive | ⌫ fusion, ⏎ scission, frappe multi-blocs | à l'écran |
| 11 | **Mécanisme 3** — copier-coller et undo | pasteboard + ⌘Z global | à l'écran |
| 12 | **Mécanisme 4** — tenue à l'échelle | trois mesures chiffrées | `--scale` |
| 13 | ADR de verdict | `docs/adr/…-verdict….md` + `STATUS.md` | relecture |

Les tâches 1 à 7 sont pures et se font en TDD strict. Les tâches 8 à 12
produisent du code de vue : elles se vérifient **à la main dans la fenêtre**,
comme la spec l'impose. Automatiser un glisser-souris AppKit coûterait plus
cher que le prototype entier.

---

## Task 1: ADR de licence et d'architecture

La décision est déjà prise par l'auteur du dépôt ; cette tâche la date et la
consigne, comme la spec l'exige (« ADR daté maintenant, fichier de licence
changé plus tard »).

**Files:**
- Create: `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md`

**Interfaces:**
- Consomme : rien.
- Produit : rien de code. La tâche 13 référencera cet ADR.

- [ ] **Step 1: Créer la branche**

```bash
git checkout -b feat/prototype-blocs-appkit
git status --short | head
```

Attendu : la branche est créée depuis `53e6e32` ; les changements éditeur non
commités sont toujours là et suivent la branche. C'est normal — ils ne seront
jamais ajoutés par ce plan.

- [ ] **Step 2: Écrire l'ADR**

Créer `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md` :

```markdown
# Réécrire l'éditeur en reprenant l'architecture d'appflowy-editor

**Statut** : validée
**Date** : 2026-08-08
**Auteur de la décision** : l'auteur du dépôt

## Contexte

Trois chantiers successifs ont porté sur le rendu des blocs mermaid dans
l'éditeur Markdown : superposition carte/source, géométrie du cadre, ancrage
sur le mauvais repère TextKit. Chaque correctif était juste, mesuré et relu ;
le résultat restait décevant.

Le point commun de ces trois défauts n'est pas une erreur de programmation.
C'est que **les blocs sont simulés à l'intérieur d'un seul `NSTextView`** :
espacements de paragraphe détournés pour réserver de la place, rect de fragment
confondu avec rect de texte, dessin qui déborde sur le bloc voisin, clips à
élargir à la main. Cette classe de bug n'existe que là.

## Décision

Réécrire l'éditeur en reprenant l'architecture d'
[appflowy-editor](https://github.com/AppFlowy-IO/appflowy-editor) : arbre de
nœuds, `Delta` pour le texte inline, transactions et undo explicites, registre
de constructeurs de vues, une vue par bloc.

**La licence AGPL-3.0 d'appflowy-editor est acceptée pour ce dépôt.**

Le fichier de licence du dépôt n'est **pas** modifié à ce stade : la bascule
devient effective au premier point qui contient réellement du code dérivé
(le modèle de document). Le prototype qui suit cette décision n'en contient
aucune ligne.

## Alternatives étudiées

1. **Continuer à corriger l'existant.** Rejetée : trois chantiers l'ont
   essayée, chacun corrigeant un symptôme réel de la même cause.
2. **Sortir seulement les blocs-cartes (mermaid, tableaux, images) du flux
   TextKit en `NSView` ancrées.** Non rejetée — c'est le **repli** si le
   prototype échoue. Supprime la classe de bug sans réécriture, mais laisse
   l'architecture inchangée.
3. **Passer à TextKit 2.** Rejetée : change le moteur de mise en page sans
   changer le fait que les blocs restent simulés dans une seule vue.
4. **Éditeur en WebView.** Rejetée : abandonne l'intégration macOS native
   (saisie, correcteur, services) pour un problème de mise en page.

## Conséquences

Positives :

- supprime à la racine la classe de bug des trois derniers chantiers ;
- les points 1 à 3 (modèle, transactions, undo) sont réellement transposables
  depuis appflowy-editor ;
- une vue par bloc rend la géométrie de chaque bloc indépendante.

Négatives :

- le dépôt bascule sous AGPL-3.0 dès le premier code dérivé ;
- coût réel : 12 365 lignes sur 45 fichiers, 41 fichiers de tests, six
  consommateurs hors module (`MeetingView`, `DetailsViews`, `PrepWindow`,
  `MarkdownNoteEditor`, `EditableTextField`, `CollaboratorMentionSource`) ;
- **le risque central est solitaire** : la sélection et la navigation du
  curseur à travers les blocs, gratuites en Flutter, sont à reconstruire
  entièrement en AppKit. Sur ce point précis, appflowy-editor n'a rien à nous
  apprendre et il n'existe aucun code à transposer.

## Décisions annulées

Cet ADR annule trois décisions structurantes de `STATUS.md` :

- n°1 « le Markdown reste la source de vérité ; aucun modèle de blocs
  persistant séparé n'est introduit » ;
- n°2 « TextKit 1 est conservé » ;
- n°4 « aucun code AppFlowy n'est repris ».

La décision n°3 (les couleurs libres ne sont pas sérialisées) et la n°5 (les
liens internes restent routés par une closure injectée) restent valides.

## Suite

Le premier sous-projet est un **prototype jetable** qui sonde le risque
central, spécifié dans
`docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`. Son
verdict fera l'objet d'un ADR distinct.
```

- [ ] **Step 3: Commit**

```bash
git add docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md
git commit -m "docs(adr): acte la réécriture de l'éditeur et la bascule AGPL-3.0"
```

---

## Task 2: Paquet du prototype et primitives

**Files:**
- Create: `Prototypes/BlockEditorProbe/Package.swift`
- Create: `Prototypes/BlockEditorProbe/README.md`
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeBlock.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeSelection.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/main.swift`
- Test: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeDocumentTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit :
  - `ProbeBlock(id: UUID = UUID(), text: String)`, `var length: Int` (UTF-16) ;
  - `ProbePosition(blockIndex: Int, offset: Int)`, `Comparable` ;
  - `ProbeSelection(anchor:head:)`, `ProbeSelection(caret:)`, `.isCollapsed`,
    `.start`, `.end`, `.spansBlocks`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeDocumentTests.swift` :

```swift
import XCTest
@testable import ProbeCore

/// Primitives du document : longueur UTF-16 d'un bloc et ordre des positions.
final class ProbePrimitivesTests: XCTestCase {

    /// La longueur d'un bloc est comptée en UTF-16, comme les `NSRange`
    /// d'AppKit — un « é » décomposé vaut 2, un emoji vaut 2.
    func test_blockLength_isCountedInUTF16() {
        XCTAssertEqual(ProbeBlock(text: "abc").length, 3)
        XCTAssertEqual(ProbeBlock(text: "cafe\u{0301}").length, 5)
        XCTAssertEqual(ProbeBlock(text: "👍").length, 2)
    }

    /// Les positions s'ordonnent par bloc d'abord, puis par décalage.
    func test_positions_areOrderedByBlockThenOffset() {
        let first = ProbePosition(blockIndex: 0, offset: 9)
        let second = ProbePosition(blockIndex: 1, offset: 0)
        XCTAssertLessThan(first, second)
        XCTAssertLessThan(ProbePosition(blockIndex: 1, offset: 0),
                          ProbePosition(blockIndex: 1, offset: 1))
    }

    /// `start` et `end` normalisent une sélection posée à l'envers.
    func test_selection_normalisesABackwardsDrag() {
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 2, offset: 1),
                                       head: ProbePosition(blockIndex: 0, offset: 4))
        XCTAssertEqual(selection.start, ProbePosition(blockIndex: 0, offset: 4))
        XCTAssertEqual(selection.end, ProbePosition(blockIndex: 2, offset: 1))
        XCTAssertFalse(selection.isCollapsed)
        XCTAssertTrue(selection.spansBlocks)
    }

    func test_caretSelection_isCollapsedAndStaysInOneBlock() {
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 3))
        XCTAssertTrue(caret.isCollapsed)
        XCTAssertFalse(caret.spansBlocks)
    }
}
```

- [ ] **Step 2: Créer le paquet et lancer le test pour le voir échouer**

Créer `Prototypes/BlockEditorProbe/Package.swift` :

```swift
// swift-tools-version: 5.9
import PackageDescription

// Prototype jetable — sonde du risque central de la réécriture de l'éditeur.
// Paquet autonome : aucune dépendance, aucun lien avec le paquet racine.
// Se supprime entièrement par `rm -rf Prototypes/`.
let package = Package(
    name: "BlockEditorProbe",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "block-editor-probe", targets: ["block-editor-probe"])
    ],
    targets: [
        .target(name: "ProbeCore"),
        .executableTarget(
            name: "block-editor-probe",
            dependencies: ["ProbeCore"]
        ),
        .testTarget(
            name: "ProbeCoreTests",
            dependencies: ["ProbeCore"]
        )
    ]
)
```

Créer `Prototypes/BlockEditorProbe/README.md` :

```markdown
# BlockEditorProbe — sonde jetable

Ce paquet **n'est pas du code de production**. Il répond par oui ou non à une
seule question : une vue éditable par bloc (`NSTextView` par bloc) tient-elle
en AppKit ?

- Spec : `docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`
- Plan : `docs/superpowers/plans/2026-08-08-prototype-editeur-par-blocs.md`
- Livrable réel : un ADR de verdict dans `docs/adr/`.

## Commandes

```bash
cd Prototypes/BlockEditorProbe
swift test                                  # ProbeCore, pur, quelques secondes
swift run block-editor-probe                # fenêtre interactive, 12 blocs
swift run block-editor-probe --blocks 40    # fenêtre interactive, 40 blocs
swift run block-editor-probe --scale        # 200 blocs, trois mesures, sortie texte
```

## Péremption

**Ce répertoire doit être supprimé une fois l'ADR de verdict écrit.** S'il est
encore là et que l'ADR existe, c'est un oubli.
```

Créer un point d'entrée minimal pour que la cible exécutable compile,
`Prototypes/BlockEditorProbe/Sources/block-editor-probe/main.swift` :

```swift
import Foundation

// Remplacé par le vrai point d'entrée AppKit à la tâche 8.
print("block-editor-probe — sonde non encore câblée")
```

Lancer :

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « cannot find 'ProbeBlock' in scope ».

- [ ] **Step 3: Écrire les primitives**

Créer `Sources/ProbeCore/ProbeBlock.swift` :

```swift
import Foundation

/// Un bloc de la sonde. Volontairement pauvre : pas de type, pas d'attributs,
/// pas de `Delta`. Le prototype ne prouve rien sur le modèle de document ; y
/// mettre un modèle riche masquerait le vrai sujet derrière du travail
/// confortable.
public struct ProbeBlock: Identifiable, Equatable {

    /// Identité stable : c'est elle qui permet à la pile de vues de réutiliser
    /// le `NSTextView` d'un bloc au lieu de le reconstruire à chaque frappe.
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// Longueur en unités UTF-16, l'unité des `NSRange` d'AppKit.
    public var length: Int { (text as NSString).length }
}
```

Créer `Sources/ProbeCore/ProbeSelection.swift` :

```swift
import Foundation

/// Un point du document : un bloc, et un décalage **UTF-16** dans son texte.
public struct ProbePosition: Equatable, Hashable, Comparable {

    public var blockIndex: Int
    public var offset: Int

    public init(blockIndex: Int, offset: Int) {
        self.blockIndex = blockIndex
        self.offset = offset
    }

    public static func < (lhs: ProbePosition, rhs: ProbePosition) -> Bool {
        (lhs.blockIndex, lhs.offset) < (rhs.blockIndex, rhs.offset)
    }
}

/// Une sélection orientée : l'ancre est posée au `mouseDown` et ne bouge plus,
/// la tête suit le glissement ou les flèches. L'orientation compte pour
/// l'extension au clavier ; `start`/`end` la normalisent pour les mutations.
public struct ProbeSelection: Equatable {

    public var anchor: ProbePosition
    public var head: ProbePosition

    public init(anchor: ProbePosition, head: ProbePosition) {
        self.anchor = anchor
        self.head = head
    }

    public init(caret: ProbePosition) {
        self.anchor = caret
        self.head = caret
    }

    public var isCollapsed: Bool { anchor == head }
    public var start: ProbePosition { Swift.min(anchor, head) }
    public var end: ProbePosition { Swift.max(anchor, head) }

    /// Vrai si la sélection déborde d'un bloc. C'est le seul cas où le
    /// coordinateur reprend la main sur `NSTextView`.
    public var spansBlocks: Bool { start.blockIndex != end.blockIndex }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 4 tests, 0 échec.

- [ ] **Step 5: Vérifier que le paquet racine est intact**

```bash
cd ../.. && git status --short Package.swift Package.resolved
```

Attendu : `Package.swift` et `Package.resolved` gardent exactement l'état
qu'ils avaient avant cette tâche (ils sont modifiés par le chantier éditeur en
cours, mais cette tâche ne doit rien y ajouter). Vérifier au besoin avec
`git diff Package.swift` que la sonde n'y apparaît pas.

- [ ] **Step 6: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): paquet autonome et primitives de position et sélection"
```

---

## Task 3: `ProbeDocument.replace` — la mutation unique

Le cœur du prototype. ⌫ en fusion, ⏎ en scission, la frappe sur une sélection
multi-blocs et le collage passent **tous** par cette seule fonction. Si elle
est juste, les quatre gestes destructifs le sont.

**Files:**
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeDocument.swift`
- Modify: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeDocumentTests.swift`

**Interfaces:**
- Consomme : `ProbeBlock`, `ProbePosition`, `ProbeSelection` (tâche 2).
- Produit :
  - `ProbeDocument(blocks: [ProbeBlock])`, `ProbeDocument(texts: [String])` ;
  - `var blocks: [ProbeBlock]` en lecture seule ;
  - `mutating func replace(_ selection: ProbeSelection, with text: String) -> ProbePosition`
    — retourne la position du curseur **après** le texte inséré.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `Tests/ProbeCoreTests/ProbeDocumentTests.swift` :

```swift
/// `replace` est l'unique mutation structurante du document. Tous les gestes
/// destructifs de la sonde s'y ramènent.
final class ProbeDocumentReplaceTests: XCTestCase {

    func test_replace_insideOneBlock_replacesTheRun() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 0),
                                       head: ProbePosition(blockIndex: 0, offset: 3))

        let caret = document.replace(selection, with: "Salut")

        XCTAssertEqual(document.blocks.map(\.text), ["Salutjour"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 5))
    }

    /// Cas de la fusion par ⌫ : la queue du bloc suivant se recolle à la tête
    /// du précédent, et les blocs intermédiaires disparaissent.
    func test_replace_acrossBlocks_mergesHeadAndTail() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 2),
                                       head: ProbePosition(blockIndex: 2, offset: 0))

        let caret = document.replace(selection, with: "")

        XCTAssertEqual(document.blocks.map(\.text), ["UnTrois"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 2))
    }

    /// Cas de la scission par ⏎.
    func test_replace_withNewline_splitsTheBlock() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let caret = document.replace(
            ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)),
            with: "\n")

        XCTAssertEqual(document.blocks.map(\.text), ["Bon", "jour"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 1, offset: 0))
    }

    /// Cas du collage multi-lignes sur une sélection multi-blocs.
    func test_replace_acrossBlocks_withMultilineText_producesOneBlockPerLine() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let caret = document.replace(selection, with: "a\nb\nc")

        XCTAssertEqual(document.blocks.map(\.text), ["Ua", "b", "cois"])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 2, offset: 1))
    }

    /// L'identité du premier bloc touché survit à la mutation : sans cela, la
    /// pile de vues détruirait et reconstruirait le `NSTextView` focalisé à
    /// chaque frappe, et le curseur sauterait.
    func test_replace_keepsTheIdentityOfTheFirstBlock() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let firstID = document.blocks[0].id
        let secondID = document.blocks[1].id

        document.replace(ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2)),
                         with: "x")

        XCTAssertEqual(document.blocks[0].id, firstID)
        XCTAssertEqual(document.blocks[1].id, secondID, "un bloc hors plage ne doit pas changer d'identité")
    }

    /// Invariant : le document n'est jamais vide. Tout effacer laisse un bloc
    /// vide, pas zéro bloc.
    func test_replace_neverEmptiesTheDocument() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let everything = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 0),
                                        head: ProbePosition(blockIndex: 1, offset: 4))

        let caret = document.replace(everything, with: "")

        XCTAssertEqual(document.blocks.map(\.text), [""])
        XCTAssertEqual(caret, ProbePosition(blockIndex: 0, offset: 0))
    }

    /// Les décalages sont en UTF-16 : couper entre les deux unités d'un « é »
    /// décomposé se fait à l'offset 3..5, pas 3..4.
    func test_replace_offsetsAreUTF16() {
        var document = ProbeDocument(texts: ["cafe\u{0301}"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 3),
                                       head: ProbePosition(blockIndex: 0, offset: 5))

        document.replace(selection, with: "é")

        XCTAssertEqual(document.blocks[0].text, "café")
    }

    /// Un document construit vide se normalise en un bloc vide.
    func test_emptyDocument_normalisesToOneEmptyBlock() {
        let document = ProbeDocument(blocks: [])
        XCTAssertEqual(document.blocks.map(\.text), [""])
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « cannot find 'ProbeDocument' in scope ».

- [ ] **Step 3: Écrire `ProbeDocument`**

Créer `Sources/ProbeCore/ProbeDocument.swift` :

```swift
import Foundation

/// Le document de la sonde : une **liste plate** de blocs. Pas d'arbre, pas de
/// types. Toutes les mutations structurantes passent par `replace`.
public struct ProbeDocument: Equatable {

    public private(set) var blocks: [ProbeBlock]

    /// Un document n'est jamais vide : il contient au minimum un bloc vide.
    public init(blocks: [ProbeBlock]) {
        self.blocks = blocks.isEmpty ? [ProbeBlock(text: "")] : blocks
    }

    public init(texts: [String]) {
        self.init(blocks: texts.map { ProbeBlock(text: $0) })
    }

    // MARK: - L'unique mutation structurante

    /// Remplace la plage couverte par `selection` par `text`, en scindant sur
    /// les sauts de ligne, et retourne la position du curseur après le texte
    /// inséré.
    ///
    /// Les quatre gestes destructifs de la sonde s'y ramènent :
    /// - frappe sur une sélection multi-blocs → `replace(selection, with: "a")` ;
    /// - ⏎ → `replace(caret, with: "\n")` ;
    /// - ⌫ en tête de bloc → `replace(fin du précédent … début du courant, with: "")` ;
    /// - collage → `replace(selection, with: pasteboard)`.
    ///
    /// L'identité du **premier** bloc touché est conservée : la pile de vues
    /// réutilise alors son `NSTextView` au lieu de le reconstruire.
    @discardableResult
    public mutating func replace(_ selection: ProbeSelection, with text: String) -> ProbePosition {
        let start = clamped(selection.start)
        let end = clamped(selection.end)

        let head = (blocks[start.blockIndex].text as NSString).substring(to: start.offset)
        let tail = (blocks[end.blockIndex].text as NSString).substring(from: end.offset)
        let pieces = text.components(separatedBy: "\n")
        let keptIdentity = blocks[start.blockIndex].id

        let replacement: [ProbeBlock]
        let caret: ProbePosition

        if pieces.count == 1 {
            replacement = [ProbeBlock(id: keptIdentity, text: head + pieces[0] + tail)]
            caret = ProbePosition(
                blockIndex: start.blockIndex,
                offset: (head as NSString).length + (pieces[0] as NSString).length)
        } else {
            var built = [ProbeBlock(id: keptIdentity, text: head + pieces[0])]
            for piece in pieces[1..<(pieces.count - 1)] {
                built.append(ProbeBlock(text: piece))
            }
            let last = pieces[pieces.count - 1]
            built.append(ProbeBlock(text: last + tail))
            replacement = built
            caret = ProbePosition(
                blockIndex: start.blockIndex + pieces.count - 1,
                offset: (last as NSString).length)
        }

        blocks.replaceSubrange(start.blockIndex...end.blockIndex, with: replacement)
        return caret
    }

    // MARK: - Bornes

    /// Ramène une position dans les bornes du document. Protège des positions
    /// périmées après une mutation venue de la vue.
    public func clamped(_ position: ProbePosition) -> ProbePosition {
        let index = Swift.min(Swift.max(position.blockIndex, 0), blocks.count - 1)
        let offset = Swift.min(Swift.max(position.offset, 0), blocks[index].length)
        return ProbePosition(blockIndex: index, offset: offset)
    }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 12 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): l'unique mutation structurante du document"
```

---

## Task 4: Navigation et extraction de texte

Ce que le coordinateur utilisera pour ⇧→, ⇧←, ⌘A, la copie, et pour écrire
dans le modèle ce que l'utilisateur a tapé nativement dans un `NSTextView`.

**Files:**
- Modify: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeDocument.swift`
- Modify: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeDocumentTests.swift`

**Interfaces:**
- Consomme : `ProbeDocument.replace` (tâche 3).
- Produit :
  - `var startPosition: ProbePosition`, `var endPosition: ProbePosition` ;
  - `var wholeDocument: ProbeSelection` ;
  - `func position(after: ProbePosition) -> ProbePosition` ;
  - `func position(before: ProbePosition) -> ProbePosition` ;
  - `func text(in: ProbeSelection) -> String` ;
  - `mutating func setText(_ text: String, at blockIndex: Int)`.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `Tests/ProbeCoreTests/ProbeDocumentTests.swift` :

```swift
/// Navigation d'une position à l'autre, extraction du texte sélectionné, et
/// écriture non structurante d'un bloc.
final class ProbeDocumentNavigationTests: XCTestCase {

    func test_positionAfter_stepsToTheNextBlockAtTheEndOfOne() {
        let document = ProbeDocument(texts: ["Un", "Deux"])
        let end = ProbePosition(blockIndex: 0, offset: 2)
        XCTAssertEqual(document.position(after: end), ProbePosition(blockIndex: 1, offset: 0))
    }

    func test_positionAfter_atTheEndOfTheDocument_staysPut() {
        let document = ProbeDocument(texts: ["Un", "Deux"])
        let end = ProbePosition(blockIndex: 1, offset: 4)
        XCTAssertEqual(document.position(after: end), end)
    }

    func test_positionBefore_stepsToTheEndOfThePreviousBlock() {
        let document = ProbeDocument(texts: ["Un", "Deux"])
        let start = ProbePosition(blockIndex: 1, offset: 0)
        XCTAssertEqual(document.position(before: start), ProbePosition(blockIndex: 0, offset: 2))
    }

    /// Un pas franchit une séquence composée entière, jamais une demi-paire
    /// de substituts : sans cela, ⇧→ couperait un emoji en deux.
    func test_positionSteps_crossWholeComposedSequences() {
        let document = ProbeDocument(texts: ["a👍b"])
        let afterA = ProbePosition(blockIndex: 0, offset: 1)
        XCTAssertEqual(document.position(after: afterA), ProbePosition(blockIndex: 0, offset: 3))
        XCTAssertEqual(document.position(before: ProbePosition(blockIndex: 0, offset: 3)), afterA)
    }

    func test_wholeDocument_coversEverything() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        XCTAssertEqual(document.wholeDocument.start, ProbePosition(blockIndex: 0, offset: 0))
        XCTAssertEqual(document.wholeDocument.end, ProbePosition(blockIndex: 2, offset: 5))
    }

    /// Le texte d'une sélection multi-blocs joint les blocs par un saut de
    /// ligne — c'est ce qui part au pasteboard.
    func test_textInSelection_joinsBlocksWithNewlines() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))
        XCTAssertEqual(document.text(in: selection), "n\nDeux\nTr")
    }

    func test_textInSelection_insideOneBlock_takesTheRun() {
        let document = ProbeDocument(texts: ["Bonjour"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 3),
                                       head: ProbePosition(blockIndex: 0, offset: 7))
        XCTAssertEqual(document.text(in: selection), "jour")
    }

    /// Aller-retour : copier une sélection puis la recoller à sa place rend le
    /// même texte. C'est l'invariant qui relie `text(in:)` à `replace`.
    func test_copyThenPasteInPlace_leavesTheTextUnchanged() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let before = document.blocks.map(\.text)
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let copied = document.text(in: selection)
        document.replace(selection, with: copied)

        XCTAssertEqual(document.blocks.map(\.text), before)
    }

    /// `setText` est la voie de la frappe native : elle change le texte d'un
    /// bloc sans toucher à la structure ni à l'identité, donc sans provoquer
    /// de reconstruction de vue.
    func test_setText_changesOneBlockWithoutTouchingIdentityOrStructure() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let identity = document.blocks[1].id

        document.setText("Deuxième", at: 1)

        XCTAssertEqual(document.blocks.map(\.text), ["Un", "Deuxième"])
        XCTAssertEqual(document.blocks[1].id, identity)
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « value of type 'ProbeDocument' has no member
'position' ».

- [ ] **Step 3: Écrire la navigation et l'extraction**

Ajouter à la fin de `Sources/ProbeCore/ProbeDocument.swift`, dans une extension :

```swift
// MARK: - Navigation et extraction

extension ProbeDocument {

    public var startPosition: ProbePosition {
        ProbePosition(blockIndex: 0, offset: 0)
    }

    public var endPosition: ProbePosition {
        ProbePosition(blockIndex: blocks.count - 1, offset: blocks[blocks.count - 1].length)
    }

    /// La sélection de ⌘A.
    public var wholeDocument: ProbeSelection {
        ProbeSelection(anchor: startPosition, head: endPosition)
    }

    /// Un pas vers l'avant. Franchit une séquence composée entière et passe au
    /// bloc suivant quand la fin du bloc courant est atteinte.
    public func position(after position: ProbePosition) -> ProbePosition {
        let here = clamped(position)
        let block = blocks[here.blockIndex]
        if here.offset < block.length {
            let composed = (block.text as NSString).rangeOfComposedCharacterSequence(at: here.offset)
            return ProbePosition(blockIndex: here.blockIndex, offset: NSMaxRange(composed))
        }
        guard here.blockIndex + 1 < blocks.count else { return here }
        return ProbePosition(blockIndex: here.blockIndex + 1, offset: 0)
    }

    /// Un pas vers l'arrière, symétrique de `position(after:)`.
    public func position(before position: ProbePosition) -> ProbePosition {
        let here = clamped(position)
        if here.offset > 0 {
            let composed = (blocks[here.blockIndex].text as NSString)
                .rangeOfComposedCharacterSequence(at: here.offset - 1)
            return ProbePosition(blockIndex: here.blockIndex, offset: composed.location)
        }
        guard here.blockIndex > 0 else { return here }
        let previous = here.blockIndex - 1
        return ProbePosition(blockIndex: previous, offset: blocks[previous].length)
    }

    /// Le texte couvert par une sélection, les blocs joints par `\n`. C'est ce
    /// qui part au pasteboard, et ce que `replace` sait relire.
    public func text(in selection: ProbeSelection) -> String {
        let start = clamped(selection.start)
        let end = clamped(selection.end)

        if start.blockIndex == end.blockIndex {
            let range = NSRange(location: start.offset, length: end.offset - start.offset)
            return (blocks[start.blockIndex].text as NSString).substring(with: range)
        }

        var parts = [(blocks[start.blockIndex].text as NSString).substring(from: start.offset)]
        for index in (start.blockIndex + 1)..<end.blockIndex {
            parts.append(blocks[index].text)
        }
        parts.append((blocks[end.blockIndex].text as NSString).substring(to: end.offset))
        return parts.joined(separator: "\n")
    }

    /// Écrit le texte d'un bloc sans toucher à la structure.
    ///
    /// C'est la voie de la **frappe native** : le `NSTextView` focalisé traite
    /// lui-même la saisie — accents, touches mortes, correcteur, services — et
    /// le coordinateur recopie ensuite le résultat ici. Aucune vue n'est
    /// reconstruite, l'identité du bloc ne bouge pas.
    public mutating func setText(_ text: String, at blockIndex: Int) {
        guard blocks.indices.contains(blockIndex) else { return }
        blocks[blockIndex].text = text
    }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 21 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): navigation entre blocs, extraction et écriture d'un bloc"
```

---

## Task 5: `ProbeEditing` — les gestes destructifs

**Files:**
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeEditing.swift`
- Test: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeEditingTests.swift`

**Interfaces:**
- Consomme : `ProbeDocument.replace`, `position(before:)`, `position(after:)`.
- Produit, toutes `@discardableResult` et retournant le curseur résultant :
  - `ProbeEditing.insertText(_ text: String, in: inout ProbeDocument, selection: ProbeSelection) -> ProbePosition` ;
  - `ProbeEditing.insertNewline(in: inout ProbeDocument, selection: ProbeSelection) -> ProbePosition` ;
  - `ProbeEditing.deleteBackward(in: inout ProbeDocument, selection: ProbeSelection) -> ProbePosition` ;
  - `ProbeEditing.deleteForward(in: inout ProbeDocument, selection: ProbeSelection) -> ProbePosition`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ProbeCoreTests/ProbeEditingTests.swift` :

```swift
import XCTest
@testable import ProbeCore

/// Les quatre gestes destructifs, tous ramenés à `ProbeDocument.replace`.
final class ProbeEditingTests: XCTestCase {

    // MARK: - ⌫

    /// Le geste qui fait tout l'intérêt du prototype : ⌫ en tête de bloc
    /// fusionne avec le précédent, ce qu'aucun `NSTextView` ne sait faire seul.
    func test_deleteBackward_atTheHeadOfABlock_mergesWithThePrevious() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 0))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["UnDeux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    func test_deleteBackward_insideABlock_removesOneComposedSequence() {
        var document = ProbeDocument(texts: ["cafe\u{0301}"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 5))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["caf"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 3))
    }

    func test_deleteBackward_atTheVeryStart_doesNothing() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 0))

        let result = ProbeEditing.deleteBackward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["Un", "Deux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 0))
    }

    func test_deleteBackward_onAMultiBlockSelection_removesIt() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.deleteBackward(in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["Uois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 1))
    }

    // MARK: - ⌦

    func test_deleteForward_atTheEndOfABlock_pullsUpTheNext() {
        var document = ProbeDocument(texts: ["Un", "Deux"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2))

        let result = ProbeEditing.deleteForward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["UnDeux"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    func test_deleteForward_atTheVeryEnd_doesNothing() {
        var document = ProbeDocument(texts: ["Un"])
        let caret = ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 2))

        let result = ProbeEditing.deleteForward(in: &document, selection: caret)

        XCTAssertEqual(document.blocks.map(\.text), ["Un"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    // MARK: - ⏎

    func test_insertNewline_splitsTheBlockAtTheCaret() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let result = ProbeEditing.insertNewline(
            in: &document,
            selection: ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)))

        XCTAssertEqual(document.blocks.map(\.text), ["Bon", "jour"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 0))
    }

    func test_insertNewline_onAMultiBlockSelection_removesItThenSplits() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.insertNewline(in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["U", "ois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 0))
    }

    // MARK: - Frappe

    /// Frapper une lettre alors que trois blocs sont sélectionnés doit les
    /// réduire à un seul portant cette lettre au bon endroit.
    func test_insertText_onAMultiBlockSelection_collapsesItToOneBlock() {
        var document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 2, offset: 2))

        let result = ProbeEditing.insertText("X", in: &document, selection: selection)

        XCTAssertEqual(document.blocks.map(\.text), ["UXois"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 0, offset: 2))
    }

    /// Le collage passe par la même porte que la frappe.
    func test_insertText_withNewlines_pastesOneBlockPerLine() {
        var document = ProbeDocument(texts: ["Bonjour"])
        let result = ProbeEditing.insertText(
            "a\nb",
            in: &document,
            selection: ProbeSelection(caret: ProbePosition(blockIndex: 0, offset: 3)))

        XCTAssertEqual(document.blocks.map(\.text), ["Bona", "bjour"])
        XCTAssertEqual(result, ProbePosition(blockIndex: 1, offset: 1))
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « cannot find 'ProbeEditing' in scope ».

- [ ] **Step 3: Écrire `ProbeEditing`**

Créer `Sources/ProbeCore/ProbeEditing.swift` :

```swift
import Foundation

/// Les gestes destructifs de la sonde. Chacun se ramène à une seule
/// `ProbeDocument.replace` — c'est tout l'intérêt : un seul endroit peut se
/// tromper.
public enum ProbeEditing {

    /// Frappe et collage. Un `\n` dans `text` scinde ; plusieurs produisent
    /// un bloc par ligne.
    @discardableResult
    public static func insertText(_ text: String,
                                  in document: inout ProbeDocument,
                                  selection: ProbeSelection) -> ProbePosition {
        document.replace(selection, with: text)
    }

    /// ⏎ : scinde au curseur, après avoir supprimé la sélection s'il y en a une.
    @discardableResult
    public static func insertNewline(in document: inout ProbeDocument,
                                     selection: ProbeSelection) -> ProbePosition {
        document.replace(selection, with: "\n")
    }

    /// ⌫ : supprime la sélection, sinon une séquence composée, sinon fusionne
    /// avec le bloc précédent.
    @discardableResult
    public static func deleteBackward(in document: inout ProbeDocument,
                                      selection: ProbeSelection) -> ProbePosition {
        guard selection.isCollapsed else {
            return document.replace(selection, with: "")
        }
        let caret = document.clamped(selection.head)
        let previous = document.position(before: caret)
        guard previous != caret else { return caret }
        return document.replace(ProbeSelection(anchor: previous, head: caret), with: "")
    }

    /// ⌦ : symétrique de ⌫ — remonte le bloc suivant quand le curseur est en
    /// fin de bloc.
    @discardableResult
    public static func deleteForward(in document: inout ProbeDocument,
                                     selection: ProbeSelection) -> ProbePosition {
        guard selection.isCollapsed else {
            return document.replace(selection, with: "")
        }
        let caret = document.clamped(selection.head)
        let next = document.position(after: caret)
        guard next != caret else { return caret }
        return document.replace(ProbeSelection(anchor: caret, head: next), with: "")
    }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 31 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): ⌫ ⌦ ⏎ et frappe, tous ramenés à la mutation unique"
```

---

## Task 6: `SelectionDistribution` — la sélection vue bloc par bloc

**Files:**
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/SelectionDistribution.swift`
- Test: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/SelectionDistributionTests.swift`

**Interfaces:**
- Consomme : `ProbeDocument`, `ProbeSelection`.
- Produit : `SelectionDistribution.ranges(for: ProbeSelection, in: ProbeDocument) -> [Int: NSRange]`
  — pour chaque index de bloc touché, la plage à surligner. Une sélection
  réduite au curseur produit une entrée de longueur zéro.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ProbeCoreTests/SelectionDistributionTests.swift` :

```swift
import XCTest
@testable import ProbeCore

/// Répartition d'une sélection traversante : chaque bloc reçoit sa part —
/// partielle aux extrêmes, entière au milieu.
final class SelectionDistributionTests: XCTestCase {

    func test_ranges_insideOneBlock_giveThatBlockTheRun() {
        let document = ProbeDocument(texts: ["Bonjour", "Monde"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 2),
                                       head: ProbePosition(blockIndex: 0, offset: 5))

        let ranges = SelectionDistribution.ranges(for: selection, in: document)

        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0], NSRange(location: 2, length: 3))
    }

    func test_ranges_acrossBlocks_arePartialAtTheEndsAndWholeInBetween() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois", "Quatre"])
        let selection = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                       head: ProbePosition(blockIndex: 3, offset: 2))

        let ranges = SelectionDistribution.ranges(for: selection, in: document)

        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(ranges[0], NSRange(location: 1, length: 1), "queue du premier bloc")
        XCTAssertEqual(ranges[1], NSRange(location: 0, length: 4), "bloc intermédiaire entier")
        XCTAssertEqual(ranges[2], NSRange(location: 0, length: 5), "bloc intermédiaire entier")
        XCTAssertEqual(ranges[3], NSRange(location: 0, length: 2), "tête du dernier bloc")
    }

    /// Une sélection posée à l'envers donne exactement le même surlignage.
    func test_ranges_ignoreTheDirectionOfTheDrag() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let forward = ProbeSelection(anchor: ProbePosition(blockIndex: 0, offset: 1),
                                     head: ProbePosition(blockIndex: 2, offset: 2))
        let backward = ProbeSelection(anchor: ProbePosition(blockIndex: 2, offset: 2),
                                      head: ProbePosition(blockIndex: 0, offset: 1))

        XCTAssertEqual(SelectionDistribution.ranges(for: forward, in: document),
                       SelectionDistribution.ranges(for: backward, in: document))
    }

    /// Un curseur simple : une seule entrée, de longueur zéro, sur son bloc.
    func test_ranges_forACaret_giveOneEmptyRange() {
        let document = ProbeDocument(texts: ["Un", "Deux"])
        let ranges = SelectionDistribution.ranges(
            for: ProbeSelection(caret: ProbePosition(blockIndex: 1, offset: 3)),
            in: document)

        XCTAssertEqual(ranges, [1: NSRange(location: 3, length: 0)])
    }

    func test_ranges_forTheWholeDocument_coverEveryBlockEntirely() {
        let document = ProbeDocument(texts: ["Un", "Deux", "Trois"])
        let ranges = SelectionDistribution.ranges(for: document.wholeDocument, in: document)

        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 2))
        XCTAssertEqual(ranges[1], NSRange(location: 0, length: 4))
        XCTAssertEqual(ranges[2], NSRange(location: 0, length: 5))
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « cannot find 'SelectionDistribution' in scope ».

- [ ] **Step 3: Écrire la répartition**

Créer `Sources/ProbeCore/SelectionDistribution.swift` :

```swift
import Foundation

/// Traduit une sélection traversante en une plage par bloc, prête à être
/// posée sur les `NSTextView`.
///
/// C'est la moitié calculable du mécanisme n°1 de la sonde ; l'autre moitié —
/// le dessin du surlignage sur un bloc qui n'a pas le focus — se vérifie à
/// l'écran.
public enum SelectionDistribution {

    /// Pour chaque index de bloc touché, la plage à surligner. Les blocs
    /// intermédiaires reçoivent leur texte entier ; les extrêmes, leur part.
    public static func ranges(for selection: ProbeSelection,
                              in document: ProbeDocument) -> [Int: NSRange] {
        let start = document.clamped(selection.start)
        let end = document.clamped(selection.end)

        if start.blockIndex == end.blockIndex {
            return [start.blockIndex: NSRange(location: start.offset,
                                              length: end.offset - start.offset)]
        }

        var ranges: [Int: NSRange] = [:]
        ranges[start.blockIndex] = NSRange(
            location: start.offset,
            length: document.blocks[start.blockIndex].length - start.offset)
        for index in (start.blockIndex + 1)..<end.blockIndex {
            ranges[index] = NSRange(location: 0, length: document.blocks[index].length)
        }
        ranges[end.blockIndex] = NSRange(location: 0, length: end.offset)
        return ranges
    }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 36 tests, 0 échec.

- [ ] **Step 5: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): répartition d'une sélection traversante bloc par bloc"
```

---

## Task 7: `ProbeHistory` — undo au niveau du conteneur

Le piège annoncé par la spec : chaque `NSTextView` a son propre `UndoManager`,
donc ⌘Z annulerait bloc par bloc. La réponse est un historique **au-dessus**
des vues, par instantanés du document et de la sélection.

**Files:**
- Create: `Prototypes/BlockEditorProbe/Sources/ProbeCore/ProbeHistory.swift`
- Test: `Prototypes/BlockEditorProbe/Tests/ProbeCoreTests/ProbeHistoryTests.swift`

**Interfaces:**
- Consomme : `ProbeDocument`, `ProbeSelection`.
- Produit :
  - `ProbeSnapshot(document: ProbeDocument, selection: ProbeSelection)` ;
  - `ProbeHistory()`, `func record(_ snapshot: ProbeSnapshot)`,
    `func undo(current: ProbeSnapshot) -> ProbeSnapshot?`,
    `func redo(current: ProbeSnapshot) -> ProbeSnapshot?`,
    `var canUndo: Bool`, `var canRedo: Bool`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `Tests/ProbeCoreTests/ProbeHistoryTests.swift` :

```swift
import XCTest
@testable import ProbeCore

/// Undo unifié : l'historique vit au-dessus des vues et ignore complètement
/// les `UndoManager` des `NSTextView`, qui sont désactivés.
final class ProbeHistoryTests: XCTestCase {

    private func snapshot(_ texts: [String], caret: ProbePosition) -> ProbeSnapshot {
        ProbeSnapshot(document: ProbeDocument(texts: texts),
                      selection: ProbeSelection(caret: caret))
    }

    func test_undo_restoresTheDocumentAndTheSelection() {
        let history = ProbeHistory()
        let before = snapshot(["Un", "Deux"], caret: ProbePosition(blockIndex: 1, offset: 0))
        let after = snapshot(["UnDeux"], caret: ProbePosition(blockIndex: 0, offset: 2))

        history.record(before)
        let restored = history.undo(current: after)

        XCTAssertEqual(restored, before)
    }

    /// Le point du prototype : deux mutations qui ont touché **des blocs
    /// différents** s'annulent dans l'ordre inverse, globalement.
    func test_undo_walksBackAcrossBlocksInReverseOrder() {
        let history = ProbeHistory()
        let first = snapshot(["a", "b"], caret: ProbePosition(blockIndex: 0, offset: 1))
        let second = snapshot(["aX", "b"], caret: ProbePosition(blockIndex: 1, offset: 1))
        let third = snapshot(["aX", "bY"], caret: ProbePosition(blockIndex: 1, offset: 2))

        history.record(first)
        history.record(second)

        XCTAssertEqual(history.undo(current: third), second)
        XCTAssertEqual(history.undo(current: second), first)
        XCTAssertNil(history.undo(current: first), "pile épuisée")
    }

    func test_redo_replaysWhatUndoTookBack() {
        let history = ProbeHistory()
        let before = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))
        let after = snapshot(["UnX"], caret: ProbePosition(blockIndex: 0, offset: 3))

        history.record(before)
        _ = history.undo(current: after)

        XCTAssertEqual(history.redo(current: before), after)
    }

    /// Une nouvelle mutation après un undo jette la pile de rétablissement —
    /// comportement attendu de tout éditeur.
    func test_record_afterAnUndo_dropsTheRedoStack() {
        let history = ProbeHistory()
        let before = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))
        let after = snapshot(["UnX"], caret: ProbePosition(blockIndex: 0, offset: 3))

        history.record(before)
        _ = history.undo(current: after)
        XCTAssertTrue(history.canRedo)

        history.record(before)

        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.redo(current: before))
    }

    func test_anEmptyHistory_canNeitherUndoNorRedo() {
        let history = ProbeHistory()
        let now = snapshot(["Un"], caret: ProbePosition(blockIndex: 0, offset: 0))

        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.undo(current: now))
        XCTAssertNil(history.redo(current: now))
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : ÉCHEC de compilation — « cannot find 'ProbeHistory' in scope ».

- [ ] **Step 3: Écrire l'historique**

Créer `Sources/ProbeCore/ProbeHistory.swift` :

```swift
import Foundation

/// Un état complet de l'éditeur : le document et la sélection.
public struct ProbeSnapshot: Equatable {

    public var document: ProbeDocument
    public var selection: ProbeSelection

    public init(document: ProbeDocument, selection: ProbeSelection) {
        self.document = document
        self.selection = selection
    }
}

/// Historique **par instantanés**, au-dessus des vues.
///
/// Chaque `NSTextView` a son propre `UndoManager` ; laissés actifs, ils
/// annuleraient bloc par bloc, dans l'ordre où l'utilisateur a visité les
/// blocs plutôt que dans l'ordre des modifications. La sonde les désactive
/// tous (`allowsUndo = false`) et enregistre ici l'état **avant** chaque
/// mutation.
///
/// Volontairement sans fusion des frappes consécutives : un ⌘Z par caractère
/// suffit à prouver que l'undo est global. La fusion est un raffinement, pas
/// une question ouverte.
public final class ProbeHistory {

    private var undoStack: [ProbeSnapshot] = []
    private var redoStack: [ProbeSnapshot] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// À appeler avec l'état **avant** la mutation, juste avant de l'appliquer.
    public func record(_ snapshot: ProbeSnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    public func undo(current: ProbeSnapshot) -> ProbeSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public func redo(current: ProbeSnapshot) -> ProbeSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
```

- [ ] **Step 4: Lancer les tests pour les voir passer**

```bash
cd Prototypes/BlockEditorProbe && swift test
```

Attendu : 41 tests, 0 échec. `ProbeCore` est terminé — plus une seule ligne de
logique ne sera écrite dans la couche vue.

- [ ] **Step 5: Commit**

```bash
git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): historique par instantanés au-dessus des vues"
```

---

## Task 8: Fenêtre, pile de blocs, un `NSTextView` par bloc

Première tâche de vue. Objectif limité : la fenêtre s'ouvre, les blocs
s'affichent chacun dans son `NSTextView`, on peut cliquer dans l'un et taper —
**accents et touches mortes compris**, puisque la frappe simple reste native.
Aucune sélection traversante encore, aucun geste destructif.

**Files:**
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/BlockTextView.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/BlockStackView.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/SelectionCoordinator.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/ProbeAppDelegate.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/ProbeMenu.swift`
- Create: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/ScaleHarness.swift` (souche, complétée tâche 12)
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/main.swift`

**Interfaces:**
- Consomme : tout `ProbeCore`.
- Produit :
  - `BlockTextView(owner: SelectionCoordinator)`, `var blockIndex: Int`,
    `func measuredHeight(forWidth: CGFloat) -> CGFloat`,
    `var crossBlockSelection: NSRange?` ;
  - `BlockStackView(coordinator:)`, `func reload(document: ProbeDocument)`,
    `func view(at index: Int) -> BlockTextView?`,
    `func blockIndex(atContentPoint: NSPoint) -> Int?` ;
  - `SelectionCoordinator(document: ProbeDocument)`, `var document`,
    `var selection`, `func attach(stack: BlockStackView)` ;
  - `ProbeAppDelegate(mode: ProbeMode, blockCount: Int)`.

- [ ] **Step 1: Écrire `BlockTextView`**

Créer `Sources/block-editor-probe/BlockTextView.swift` :

```swift
import AppKit
import ProbeCore

/// Un bloc = un `NSTextView`.
///
/// Cette vue ne décide de rien : elle reflète ce que le coordinateur lui dit.
/// Elle garde en revanche la **saisie native** — accents, touches mortes,
/// correcteur, services macOS — qui est la raison d'être du choix
/// « un `NSTextView` par bloc » plutôt qu'un moteur de saisie maison.
final class BlockTextView: NSTextView {

    /// Index du bloc dans le document, réaffecté à chaque `reload`.
    var blockIndex: Int = 0

    /// Autorité unique. `unowned` volontaire : le coordinateur possède la pile
    /// qui possède ces vues.
    unowned let owner: SelectionCoordinator

    /// Part de la sélection traversante à peindre **quand ce bloc n'a pas le
    /// focus**. Nil pour le bloc focalisé, qui garde le surlignage natif.
    var crossBlockSelection: NSRange? {
        didSet {
            guard crossBlockSelection != oldValue else { return }
            needsDisplay = true
        }
    }

    init(owner: SelectionCoordinator) {
        self.owner = owner

        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: .greatestFiniteMagnitude))
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        // La largeur est pilotée à la main par `BlockStackView` : pas d'Auto
        // Layout, pour ne pas confondre le coût des vues avec celui du moteur
        // de contraintes lors de la mesure à 200 blocs.
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0

        super.init(frame: .zero, textContainer: container)

        isRichText = false
        isEditable = true
        isSelectable = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        drawsBackground = false
        textContainerInset = NSSize(width: 0, height: 3)
        font = NSFont.systemFont(ofSize: 14)
        // L'undo est unifié au niveau du conteneur : voir `ProbeHistory`.
        allowsUndo = false
        delegate = owner
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    // MARK: - Mesure

    /// Hauteur nécessaire pour afficher tout le texte à cette largeur.
    func measuredHeight(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let manager = layoutManager else { return 22 }
        let contentWidth = max(width - textContainerInset.width * 2, 1)
        if abs(container.size.width - contentWidth) > 0.5 {
            container.size = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height
        return max(ceil(used), 18) + textContainerInset.height * 2
    }

    // MARK: - Surlignage d'un bloc sans focus

    /// Peint la part de sélection traversante de ce bloc.
    ///
    /// `NSTextView` grise sa propre sélection dès qu'il perd le focus, or un
    /// seul bloc peut l'avoir. On peint donc le surlignage nous-mêmes pour les
    /// autres, à partir des rects du gestionnaire de disposition. Ce n'est
    /// **pas** réécrire le dessin du texte : on ne fait qu'ajouter un fond.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let range = crossBlockSelection, range.length > 0,
              let manager = layoutManager, let container = textContainer else { return }

        NSColor.selectedTextBackgroundColor.setFill()
        let origin = textContainerOrigin
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        manager.enumerateEnclosingRects(forGlyphRange: glyphs,
                                        withinSelectedGlyphRange: glyphs,
                                        in: container) { painted, _ in
            painted.offsetBy(dx: origin.x, dy: origin.y).fill()
        }
    }
}
```

- [ ] **Step 2: Écrire `BlockStackView`**

Créer `Sources/block-editor-probe/BlockStackView.swift` :

```swift
import AppKit
import ProbeCore

/// Empile un `BlockTextView` par bloc, à disposition **manuelle**.
///
/// Ni `NSStackView` ni Auto Layout : à 200 blocs on veut mesurer le coût des
/// vues éditables, pas celui du moteur de contraintes.
final class BlockStackView: NSView {

    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 24
    static let blockSpacing: CGFloat = 8

    private unowned let coordinator: SelectionCoordinator

    /// Vues dans l'ordre du document.
    private(set) var orderedViews: [BlockTextView] = []
    /// Réemploi par identité de bloc : un bloc qui survit à une mutation garde
    /// sa vue, donc son curseur et son état de saisie.
    private var viewsByIdentity: [UUID: BlockTextView] = [:]

    init(coordinator: SelectionCoordinator) {
        self.coordinator = coordinator
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("non utilisé") }

    override var isFlipped: Bool { true }

    // MARK: - Synchronisation avec le document

    /// Reconstruit la liste des vues à partir du document, en réutilisant
    /// celles dont le bloc a survécu.
    func reload(document: ProbeDocument) {
        var reused: [UUID: BlockTextView] = [:]
        var ordered: [BlockTextView] = []

        for (index, block) in document.blocks.enumerated() {
            let view = viewsByIdentity[block.id] ?? BlockTextView(owner: coordinator)
            view.blockIndex = index
            if view.string != block.text {
                view.string = block.text
            }
            if view.superview !== self {
                addSubview(view)
            }
            reused[block.id] = view
            ordered.append(view)
        }

        for (identity, view) in viewsByIdentity where reused[identity] == nil {
            view.removeFromSuperview()
        }

        viewsByIdentity = reused
        orderedViews = ordered
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func view(at index: Int) -> BlockTextView? {
        orderedViews.indices.contains(index) ? orderedViews[index] : nil
    }

    /// Bloc situé sous un point exprimé dans les coordonnées de cette vue.
    /// Au-dessus du premier bloc renvoie 0, en dessous du dernier renvoie le
    /// dernier : c'est ce qui rend un glissement au-delà des bords utilisable.
    func blockIndex(atContentPoint point: NSPoint) -> Int? {
        guard !orderedViews.isEmpty else { return nil }
        if point.y <= orderedViews[0].frame.minY { return 0 }
        for (index, view) in orderedViews.enumerated() where point.y <= view.frame.maxY {
            return index
        }
        return orderedViews.count - 1
    }

    // MARK: - Disposition

    override func layout() {
        super.layout()

        let contentWidth = max(bounds.width - Self.horizontalInset * 2, 40)
        var y = Self.verticalInset

        for view in orderedViews {
            let height = view.measuredHeight(forWidth: contentWidth)
            view.frame = NSRect(x: Self.horizontalInset, y: y, width: contentWidth, height: height)
            y += height + Self.blockSpacing
        }

        let neededHeight = y - Self.blockSpacing + Self.verticalInset
        if abs(frame.height - neededHeight) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: neededHeight))
        }
    }
}
```

- [ ] **Step 3: Écrire un `SelectionCoordinator` minimal**

Créer `Sources/block-editor-probe/SelectionCoordinator.swift`. À cette tâche il
ne fait que porter l'état et recopier la frappe native dans le modèle ; les
tâches 9 à 11 le complètent.

```swift
import AppKit
import ProbeCore

/// Toute l'autorité de la sonde.
///
/// Les `NSTextView` ne décident de rien : ils reflètent. C'est l'inverse exact
/// de l'éditeur actuel, où la vue porte la logique — et c'est l'hypothèse que
/// ce prototype teste.
@MainActor
final class SelectionCoordinator: NSObject, NSTextViewDelegate {

    private(set) var document: ProbeDocument
    private(set) var selection: ProbeSelection

    let history = ProbeHistory()
    private(set) weak var stack: BlockStackView?

    /// Vrai pendant que le coordinateur écrit dans les vues : empêche les
    /// rappels d'AppKit de réécrire l'état qu'on est en train de poser.
    private var isSynchronising = false

    init(document: ProbeDocument) {
        self.document = document
        self.selection = ProbeSelection(caret: document.startPosition)
        super.init()
    }

    func attach(stack: BlockStackView) {
        self.stack = stack
        stack.reload(document: document)
        synchroniseViews(focusing: true)
    }

    // MARK: - Application d'une mutation

    /// Applique une mutation structurante : enregistre l'état précédent,
    /// mute le document, reconstruit la pile, replace le curseur.
    func apply(_ mutation: (inout ProbeDocument) -> ProbePosition) {
        history.record(ProbeSnapshot(document: document, selection: selection))
        let caret = mutation(&document)
        selection = ProbeSelection(caret: document.clamped(caret))
        stack?.reload(document: document)
        synchroniseViews(focusing: true)
    }

    /// Pose une nouvelle sélection sans toucher au document.
    func setSelection(_ newSelection: ProbeSelection, focusing: Bool = true) {
        selection = ProbeSelection(anchor: document.clamped(newSelection.anchor),
                                   head: document.clamped(newSelection.head))
        synchroniseViews(focusing: focusing)
    }

    // MARK: - Reflet dans les vues

    /// Répartit la sélection sur les vues : surlignage natif pour le bloc
    /// focalisé, surlignage peint pour les autres.
    func synchroniseViews(focusing: Bool) {
        guard let stack else { return }
        isSynchronising = true
        defer { isSynchronising = false }

        let ranges = SelectionDistribution.ranges(for: selection, in: document)
        let focused = selection.head.blockIndex
        let focusedView = stack.view(at: focused)

        // Le premier répondant est repris **avant** de poser les plages :
        // `makeFirstResponder` fait reprendre à `NSTextView` sa propre
        // sélection et écraserait celle qu'on vient d'écrire.
        if focusing, let focusedView, focusedView.window?.firstResponder !== focusedView {
            focusedView.window?.makeFirstResponder(focusedView)
        }

        for (index, view) in stack.orderedViews.enumerated() {
            let range = ranges[index]
            if index == focused {
                view.crossBlockSelection = nil
                view.setSelectedRange(range ?? NSRange(location: selection.head.offset, length: 0))
            } else {
                view.crossBlockSelection = range
                // Sélection native vide : sinon `NSTextView` peindrait sa
                // propre bande grise d'inactivité sous le surlignage qu'on
                // peint nous-mêmes.
                view.setSelectedRange(NSRange(location: range?.location ?? 0, length: 0))
            }
        }

        if focusing, let focusedView {
            focusedView.scrollToVisible(focusedView.bounds)
        }
    }

    // MARK: - NSTextViewDelegate

    /// La frappe simple reste **native** : c'est ce qui donne gratuitement les
    /// accents, les touches mortes, le correcteur et les services. Le
    /// coordinateur recopie ensuite le résultat dans le modèle.
    func textDidChange(_ notification: Notification) {
        guard !isSynchronising,
              let view = notification.object as? BlockTextView else { return }
        document.setText(view.string, at: view.blockIndex)
        stack?.needsLayout = true
        stack?.layoutSubtreeIfNeeded()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSynchronising,
              let view = notification.object as? BlockTextView else { return }
        let range = view.selectedRange()
        selection = ProbeSelection(
            anchor: ProbePosition(blockIndex: view.blockIndex, offset: range.location),
            head: ProbePosition(blockIndex: view.blockIndex, offset: NSMaxRange(range)))
    }
}
```

- [ ] **Step 4: Écrire la fenêtre et le point d'entrée**

Créer `Sources/block-editor-probe/ProbeAppDelegate.swift` :

```swift
import AppKit
import ProbeCore

enum ProbeMode {
    case interactive
    case scale
}

/// Fenêtre de la sonde, construite programmatiquement — pas de bundle `.app`,
/// pas de nib.
@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {

    private let mode: ProbeMode
    private let blockCount: Int
    private var window: NSWindow?
    private var coordinator: SelectionCoordinator?

    init(mode: ProbeMode, blockCount: Int) {
        self.mode = mode
        self.blockCount = blockCount
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if mode == .scale {
            ScaleHarness.run(blockCount: blockCount)
            NSApp.terminate(nil)
            return
        }
        openWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func openWindow() {
        let coordinator = SelectionCoordinator(document: ProbeDocument(texts: SampleText.blocks(count: blockCount)))
        let stack = BlockStackView(coordinator: coordinator)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 620))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = stack
        stack.setFrameSize(NSSize(width: scroll.contentSize.width, height: 400))
        stack.autoresizingMask = [.width]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Sonde — éditeur par blocs (\(blockCount) blocs)"
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)

        coordinator.attach(stack: stack)

        self.window = window
        self.coordinator = coordinator
    }
}

/// Texte de remplissage. Volontairement en français, avec accents : le premier
/// « ê » mal saisi se verrait tout de suite.
enum SampleText {

    private static let lines = [
        "Le prototype ne prouve rien sur le modèle de document.",
        "Chaque bloc est une vue autonome — c'est tout ce qu'on teste ici.",
        "Un être humain doit pouvoir taper « forêt », « cœur », « à côté ».",
        "La sélection traversante est le vrai risque de la réécriture.",
        "L'undo doit être global, jamais bloc par bloc.",
        "Le collage multi-lignes crée un bloc par ligne."
    ]

    static func blocks(count: Int) -> [String] {
        (0..<max(count, 1)).map { index in
            "\(index + 1). \(lines[index % lines.count])"
        }
    }
}
```

Remplacer entièrement `Sources/block-editor-probe/main.swift` :

```swift
import AppKit

// Point d'entrée de la sonde. Exécutable SwiftPM nu : pas de bundle `.app`,
// donc `setActivationPolicy(.regular)` et `activate` sont indispensables pour
// obtenir une fenêtre au premier plan et le clavier.
let arguments = CommandLine.arguments

/// Valeur entière d'une option `--nom valeur`.
func intOption(_ name: String, default fallback: Int) -> Int {
    guard let position = arguments.firstIndex(of: name),
          arguments.indices.contains(position + 1),
          let value = Int(arguments[position + 1]) else { return fallback }
    return value
}

let mode: ProbeMode = arguments.contains("--scale") ? .scale : .interactive
let blockCount = intOption("--blocks", default: mode == .scale ? 200 : 12)

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = ProbeAppDelegate(mode: mode, blockCount: blockCount)
application.delegate = delegate
application.mainMenu = ProbeMenu.make()
application.activate(ignoringOtherApps: true)
application.run()
```

Créer `Sources/block-editor-probe/ProbeMenu.swift` :

```swift
import AppKit

/// Menu minimal. Il existe pour une seule raison : router ⌘Z, ⌘⇧Z, ⌘A, ⌘C et
/// ⌘V par la chaîne des répondants, comme une vraie application — c'est la
/// seule façon honnête de tester si l'undo peut être repris au niveau du
/// conteneur.
enum ProbeMenu {

    static func make() -> NSMenu {
        let root = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quitter la sonde",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        root.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Rétablir",
                                    action: Selector(("redo:")),
                                    keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner",
                         action: #selector(NSResponder.selectAll(_:)),
                         keyEquivalent: "a")
        editItem.submenu = editMenu
        root.addItem(editItem)

        return root
    }
}
```

Créer un `ScaleHarness` provisoire pour que le tout compile,
`Sources/block-editor-probe/ScaleHarness.swift` :

```swift
import AppKit

/// Complété à la tâche 12.
@MainActor
enum ScaleHarness {
    static func run(blockCount: Int) {
        print("harnais d'échelle non encore câblé (\(blockCount) blocs)")
    }
}
```

- [ ] **Step 5: Construire et vérifier à l'écran**

```bash
cd Prototypes/BlockEditorProbe && swift build && swift run block-editor-probe
```

À l'écran, cocher chaque point :

1. une fenêtre s'ouvre au premier plan, titrée « Sonde — éditeur par blocs
   (12 blocs) », douze paragraphes espacés visibles ;
2. cliquer dans un bloc : un curseur apparaît **dans ce bloc seulement** ;
3. taper du texte : il s'insère, et le bloc **grandit** quand la ligne passe à
   la ligne suivante — les blocs du dessous descendent ;
4. taper `option-e` puis `e` : un `é` apparaît, pas deux caractères. Taper
   `option-i` puis `e` : `ê`. **Si ce point échoue, l'approche perd son seul
   avantage sur un moteur de saisie maison — le noter tout de suite** ;
5. redimensionner la fenêtre : les blocs se reflowent à la nouvelle largeur ;
6. faire défiler : rien ne clignote, rien ne se superpose ;
7. ⌘Q ferme la sonde.

Noter par écrit tout écart — ces notes alimentent l'ADR de la tâche 13.

- [ ] **Step 6: Commit**

```bash
cd ../.. && git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): fenêtre, pile de blocs et saisie native par bloc"
```

---

## Task 9: Mécanisme 1 — sélection traversante

Le mécanisme qui décide. Trois entrées : le glissement souris, l'extension au
clavier, et ⌘A. Plus le surlignage des blocs qui n'ont pas le focus, déjà écrit
à la tâche 8 mais jamais exercé.

**Files:**
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/SelectionCoordinator.swift`
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/BlockTextView.swift`

**Interfaces:**
- Consomme : `SelectionDistribution.ranges`, `ProbeDocument.position(after:)`,
  `position(before:)`, `wholeDocument`.
- Produit :
  - `SelectionCoordinator.beginSelectionDrag(from:event:)` ;
  - `SelectionCoordinator.selectAllBlocks()` ;
  - `SelectionCoordinator.textView(_:doCommandBy:) -> Bool` (extension de sélection).

- [ ] **Step 1: Router le `mouseDown` vers le coordinateur**

Ajouter à `BlockTextView` :

```swift
    // MARK: - Souris

    /// Le clic ne pose pas la sélection lui-même : il la demande au
    /// coordinateur, qui seul sait ce qu'est une sélection traversante.
    override func mouseDown(with event: NSEvent) {
        owner.beginSelectionDrag(from: self, event: event)
    }

    /// Position du document sous un point exprimé dans les coordonnées de
    /// cette vue.
    func probeOffset(atViewPoint point: NSPoint) -> Int {
        characterIndexForInsertion(at: point)
    }
```

- [ ] **Step 2: Écrire le glissement et l'extension**

Ajouter à `SelectionCoordinator`, dans une section « Mécanisme 1 » :

```swift
    // MARK: - Mécanisme 1 : sélection traversante

    /// Pose l'ancre au clic, puis suit le glissement **au niveau du
    /// conteneur** : c'est le seul endroit qui voit tous les blocs à la fois.
    func beginSelectionDrag(from view: BlockTextView, event: NSEvent) {
        guard let stack, let window = view.window else { return }

        let anchor = position(ofWindowPoint: event.locationInWindow, in: stack)
        setSelection(ProbeSelection(caret: anchor))

        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp],
                           timeout: NSEvent.foreverDuration,
                           mode: .eventTracking) { tracked, stop in
            guard let tracked else {
                stop.pointee = true
                return
            }
            if tracked.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let head = self.position(ofWindowPoint: tracked.locationInWindow, in: stack)
            // `focusing: false` : reprendre le premier répondant à chaque
            // mouvement casserait le suivi du glissement.
            self.setSelection(ProbeSelection(anchor: self.selection.anchor, head: head),
                              focusing: false)
        }

        // Le focus n'est repris qu'au relâchement, sur le bloc de la tête.
        synchroniseViews(focusing: true)
    }

    /// Traduit un point de la fenêtre en position du document, en débordant
    /// proprement au-dessus du premier bloc et sous le dernier.
    private func position(ofWindowPoint point: NSPoint, in stack: BlockStackView) -> ProbePosition {
        let inStack = stack.convert(point, from: nil)
        guard let index = stack.blockIndex(atContentPoint: inStack),
              let view = stack.view(at: index) else {
            return document.clamped(selection.head)
        }
        let inView = view.convert(point, from: nil)
        let clampedPoint = NSPoint(x: inView.x,
                                   y: min(max(inView.y, 0), max(view.bounds.height - 1, 0)))
        return ProbePosition(blockIndex: index, offset: view.probeOffset(atViewPoint: clampedPoint))
    }

    /// ⌘A prend tout le document, pas seulement le bloc focalisé.
    func selectAllBlocks() {
        setSelection(document.wholeDocument)
    }
```

- [ ] **Step 3: Intercepter les commandes de sélection**

Ajouter à `SelectionCoordinator` la méthode de délégué qui capte les
sélecteurs standard d'AppKit. Passer par `doCommandBy` plutôt que par
`keyDown` fait arriver ici les **vraies** liaisons clavier de macOS, ⇧⌥→
comprise.

```swift
    // MARK: - Commandes clavier

    /// Ne reprend la main que lorsque `NSTextView` ne peut pas s'en sortir
    /// seul : au franchissement d'une frontière de bloc, ou dès que la
    /// sélection en déborde déjà.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let view = textView as? BlockTextView else { return false }

        switch selector {
        case #selector(NSResponder.selectAll(_:)):
            selectAllBlocks()
            return true

        case #selector(NSResponder.moveRightAndModifySelection(_:)),
             #selector(NSResponder.moveForwardAndModifySelection(_:)):
            return extendSelection(to: document.position(after: selection.head),
                                   whenNativeWouldSuffice: !selection.spansBlocks
                                       && selection.head.offset < document.blocks[selection.head.blockIndex].length)

        case #selector(NSResponder.moveLeftAndModifySelection(_:)),
             #selector(NSResponder.moveBackwardAndModifySelection(_:)):
            return extendSelection(to: document.position(before: selection.head),
                                   whenNativeWouldSuffice: !selection.spansBlocks
                                       && selection.head.offset > 0)

        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            guard selection.spansBlocks || view.isOnLastLine(offset: selection.head.offset) else { return false }
            let next = min(selection.head.blockIndex + 1, document.blocks.count - 1)
            setSelection(ProbeSelection(anchor: selection.anchor,
                                        head: ProbePosition(blockIndex: next, offset: 0)))
            return true

        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            guard selection.spansBlocks || view.isOnFirstLine(offset: selection.head.offset) else { return false }
            guard selection.head.blockIndex > 0 else { return false }
            let previous = selection.head.blockIndex - 1
            setSelection(ProbeSelection(
                anchor: selection.anchor,
                head: ProbePosition(blockIndex: previous, offset: document.blocks[previous].length)))
            return true

        default:
            return false
        }
    }

    /// Étend la sélection vers `head`. Rend la main à `NSTextView` quand le
    /// mouvement reste dans un bloc : c'est lui qui connaît le mieux ses
    /// propres lignes.
    private func extendSelection(to head: ProbePosition, whenNativeWouldSuffice native: Bool) -> Bool {
        guard !native else { return false }
        setSelection(ProbeSelection(anchor: selection.anchor, head: head))
        return true
    }
```

Ajouter à `BlockTextView` les deux prédicats de ligne :

```swift
    // MARK: - Lignes

    /// Vrai si le décalage tombe sur le dernier fragment de ligne du bloc.
    /// Sert à savoir quand ↓ doit franchir la frontière de bloc.
    func isOnLastLine(offset: Int) -> Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var lineRange = NSRange()
        let glyph = min(manager.glyphIndexForCharacter(at: offset), manager.numberOfGlyphs - 1)
        manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        return NSMaxRange(lineRange) >= manager.numberOfGlyphs
    }

    /// Symétrique : vrai sur le premier fragment de ligne du bloc.
    func isOnFirstLine(offset: Int) -> Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var lineRange = NSRange()
        let glyph = min(manager.glyphIndexForCharacter(at: offset), manager.numberOfGlyphs - 1)
        manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
        return lineRange.location == 0
    }
```

- [ ] **Step 4: Rediriger ⌘A depuis la vue**

`NSTextView` implémente `selectAll:` lui-même et gagnerait sur la chaîne des
répondants ; le déléguer explicitement. Ajouter à `BlockTextView` :

```swift
    override func selectAll(_ sender: Any?) {
        owner.selectAllBlocks()
    }
```

- [ ] **Step 5: Construire et vérifier à l'écran**

```bash
cd Prototypes/BlockEditorProbe && swift build && swift run block-editor-probe
```

À l'écran, cocher chaque point :

1. **glissement souris** : cliquer au milieu du bloc 2, glisser jusqu'au milieu
   du bloc 5. Le surlignage doit couvrir la queue du 2, les blocs 3 et 4
   **entiers**, et la tête du 5 ;
2. le surlignage des blocs 3, 4 et 5 doit avoir **la même couleur** que celui
   du bloc focalisé — pas de bande grise d'inactivité. **C'est le critère
   d'abandon n°1 : si ce point ne peut pas être obtenu, le verdict est
   négatif** ;
3. glisser vers le haut (du bloc 5 vers le bloc 2) : même surlignage ;
4. glisser au-delà du dernier bloc : la sélection s'arrête proprement à la fin
   du document, sans plantage ;
5. **clavier** : curseur en fin du bloc 2, presser ⇧→ plusieurs fois — la
   sélection doit franchir dans le bloc 3 ;
6. ⇧↓ depuis la dernière ligne d'un bloc doit passer au bloc suivant ;
7. ⇧← et ⇧↑ symétriquement ;
8. **⌘A** : tous les blocs surlignés entièrement, du premier au dernier ;
9. cliquer ailleurs : la sélection retombe à un simple curseur.

Noter tout écart, en particulier au point 2.

- [ ] **Step 6: Commit**

```bash
cd ../.. && git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): sélection traversante — souris, clavier et ⌘A"
```

---

## Task 10: Mécanisme 2 — édition destructive

**Files:**
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/SelectionCoordinator.swift`

**Interfaces:**
- Consomme : `ProbeEditing` (tâche 5), `SelectionCoordinator.apply` (tâche 8).
- Produit : le câblage de `insertNewline:`, `deleteBackward:`, `deleteForward:`
  et de `textView(_:shouldChangeTextIn:replacementString:)`.

- [ ] **Step 1: Câbler les trois gestes destructifs**

Compléter le `switch` de `textView(_:doCommandBy:)` — ajouter ces cas **avant**
le `default` :

```swift
        case #selector(NSResponder.insertNewline(_:)):
            apply { ProbeEditing.insertNewline(in: &$0, selection: self.selection) }
            return true

        case #selector(NSResponder.deleteBackward(_:)):
            // `NSTextView` sait très bien effacer à l'intérieur d'un bloc, et
            // le faire nativement préserve la composition en cours (touches
            // mortes). On ne reprend la main qu'en tête de bloc, ou dès que la
            // sélection déborde.
            guard selection.spansBlocks || (selection.isCollapsed && selection.head.offset == 0) else {
                return false
            }
            apply { ProbeEditing.deleteBackward(in: &$0, selection: self.selection) }
            return true

        case #selector(NSResponder.deleteForward(_:)):
            let atBlockEnd = selection.isCollapsed
                && selection.head.offset == document.blocks[selection.head.blockIndex].length
            guard selection.spansBlocks || atBlockEnd else { return false }
            apply { ProbeEditing.deleteForward(in: &$0, selection: self.selection) }
            return true
```

- [ ] **Step 2: Intercepter la frappe sur une sélection multi-blocs**

Ajouter à `SelectionCoordinator` :

```swift
    // MARK: - Mécanisme 2 : édition destructive

    /// Arbitre entre la voie native et la voie du modèle.
    ///
    /// Voie native (retour `true`) : la sélection tient dans un bloc. Le
    /// `NSTextView` fait son travail — accents, touches mortes, correcteur —
    /// et `textDidChange` recopiera le résultat dans le modèle.
    ///
    /// Voie du modèle (retour `false`) : la sélection déborde du bloc. Aucun
    /// `NSTextView` ne peut l'honorer ; le coordinateur applique la mutation
    /// et reconstruit.
    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedRange: NSRange,
                  replacementString: String?) -> Bool {
        guard selection.spansBlocks else {
            // Voie native, mais l'historique doit quand même voir l'état
            // d'avant : l'undo est unifié au niveau du conteneur.
            history.record(ProbeSnapshot(document: document, selection: selection))
            return true
        }
        let inserted = replacementString ?? ""
        apply { ProbeEditing.insertText(inserted, in: &$0, selection: self.selection) }
        return false
    }
```

- [ ] **Step 3: Construire et vérifier à l'écran**

```bash
cd Prototypes/BlockEditorProbe && swift build && swift run block-editor-probe
```

À l'écran, cocher chaque point :

1. **⌫ en tête de bloc** : placer le curseur tout au début du bloc 3, presser
   ⌫. Les blocs 2 et 3 fusionnent en un seul, et le curseur se retrouve à la
   jonction — pas au début, pas à la fin ;
2. **⌫ à l'intérieur** : effacer une lettre au milieu d'un bloc n'affecte que
   ce bloc ;
3. effacer un `é` composé par touche morte doit l'effacer **entièrement**, pas
   à moitié ;
4. **⏎ au milieu** : placer le curseur au milieu du bloc 4, presser ⏎. Deux
   blocs distincts apparaissent, le curseur est au début du second ;
5. **⏎ en fin de bloc** : crée un bloc vide en dessous, curseur dedans ;
6. **frappe sur sélection multi-blocs** : sélectionner du bloc 2 au bloc 5 par
   glissement, taper `X`. Il ne doit rester **qu'un** bloc, portant la tête du
   2, un `X`, et la queue du 5 ;
7. **⌫ sur sélection multi-blocs** : même sélection, presser ⌫ — même
   résultat sans le `X` ;
8. **⌦ en fin de bloc** : remonte le bloc suivant ;
9. après chaque geste, le curseur est visible et la frappe suivante s'insère au
   bon endroit ;
10. tout effacer (⌘A puis ⌫) laisse **un** bloc vide éditable, pas une fenêtre
    vide inerte.

- [ ] **Step 4: Commit**

```bash
cd ../.. && git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): édition destructive — fusion, scission et frappe multi-blocs"
```

---

## Task 11: Mécanisme 3 — copier-coller et undo au niveau du conteneur

**Files:**
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/SelectionCoordinator.swift`
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/BlockTextView.swift`

**Interfaces:**
- Consomme : `ProbeDocument.text(in:)`, `ProbeEditing.insertText`, `ProbeHistory`.
- Produit :
  - `SelectionCoordinator.copySelection()`, `cutSelection()`, `pasteFromPasteboard()` ;
  - `SelectionCoordinator.undoLastEdit()`, `redoLastEdit()` ;
  - les redirections `copy:`, `cut:`, `paste:`, `undo:`, `redo:` sur `BlockTextView`.

- [ ] **Step 1: Écrire le pasteboard et l'undo dans le coordinateur**

Ajouter à `SelectionCoordinator` :

```swift
    // MARK: - Mécanisme 3 : pasteboard et undo

    /// Sérialise la sélection multi-blocs : un bloc par ligne. Le collage
    /// relit exactement ce format, ce que `ProbeDocument.replace` sait faire.
    func copySelection() {
        guard !selection.isCollapsed else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.text(in: selection), forType: .string)
    }

    func cutSelection() {
        guard !selection.isCollapsed else { return }
        copySelection()
        apply { ProbeEditing.insertText("", in: &$0, selection: self.selection) }
    }

    func pasteFromPasteboard() {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        apply { ProbeEditing.insertText(pasted, in: &$0, selection: self.selection) }
    }

    /// ⌘Z global.
    ///
    /// Les `UndoManager` des `NSTextView` sont désactivés (`allowsUndo =
    /// false`) : sans cela, ⌘Z annulerait bloc par bloc, dans l'ordre où
    /// l'utilisateur a visité les blocs et non dans celui des modifications.
    /// C'est ce point qui décide si l'undo explicite d'AppFlowy est
    /// transposable.
    func undoLastEdit() {
        let current = ProbeSnapshot(document: document, selection: selection)
        guard let previous = history.undo(current: current) else { return }
        restore(previous)
    }

    func redoLastEdit() {
        let current = ProbeSnapshot(document: document, selection: selection)
        guard let next = history.redo(current: current) else { return }
        restore(next)
    }

    private func restore(_ snapshot: ProbeSnapshot) {
        document = snapshot.document
        selection = snapshot.selection
        stack?.reload(document: document)
        synchroniseViews(focusing: true)
    }
```

- [ ] **Step 2: Rediriger les actions depuis la vue focalisée**

`NSTextView` implémente `copy:`, `cut:` et `paste:` et, premier répondant, il
les capterait avant le coordinateur. Ajouter à `BlockTextView` :

```swift
    // MARK: - Actions déléguées au coordinateur

    override func copy(_ sender: Any?) {
        owner.copySelection()
    }

    override func cut(_ sender: Any?) {
        owner.cutSelection()
    }

    override func paste(_ sender: Any?) {
        owner.pasteFromPasteboard()
    }

    /// `undo:` et `redo:` n'existent pas sur `NSResponder` : les déclarer ici
    /// met le premier répondant sur leur chemin, avant tout `UndoManager`
    /// que la fenêtre pourrait fournir.
    @objc func undo(_ sender: Any?) {
        owner.undoLastEdit()
    }

    @objc func redo(_ sender: Any?) {
        owner.redoLastEdit()
    }
```

- [ ] **Step 3: Construire et vérifier à l'écran**

```bash
cd Prototypes/BlockEditorProbe && swift build && swift run block-editor-probe
```

À l'écran, cocher chaque point :

1. **copie multi-blocs** : sélectionner du bloc 2 au bloc 5, ⌘C, puis coller
   dans TextEdit — le texte doit arriver sur quatre lignes, tronqué aux bons
   endroits ;
2. **collage multi-lignes** : copier trois lignes depuis TextEdit, placer le
   curseur au milieu d'un bloc, ⌘V — trois blocs doivent apparaître, le
   premier recollé à la tête et le dernier à la queue ;
3. **couper** : ⌘X sur une sélection multi-blocs supprime et met au
   pasteboard ;
4. **undo global** : taper dans le bloc 2, puis dans le bloc 6, puis dans le
   bloc 4. Presser ⌘Z trois fois. Les modifications doivent se défaire **dans
   l'ordre inverse de leur exécution** — 4, puis 6, puis 2. **C'est le
   critère d'abandon n°2 : si ⌘Z défait bloc par bloc selon le focus, le
   verdict est négatif** ;
5. **undo d'un geste structurant** : fusionner deux blocs par ⌫, ⌘Z — les deux
   blocs reviennent, curseur à sa place d'avant ;
6. **undo d'un collage** : ⌘V puis ⌘Z rend le document d'avant en un seul coup ;
7. **rétablir** : ⌘⇧Z rejoue ce que ⌘Z a défait ;
8. taper après un ⌘Z : la pile de rétablissement est vidée, ⌘⇧Z ne fait rien ;
9. **accent par touche morte puis ⌘Z** : composer un `ê` (`option-i` puis `e`),
   presser ⌘Z. Compter combien de ⌘Z il faut pour le défaire — chaque étape de
   composition traverse `shouldChangeTextIn` et laisse donc son propre
   instantané. Ce n'est pas un défaut de l'approche, mais l'observation doit
   figurer dans l'ADR : elle dit ce que coûtera la fusion des frappes au point 2
   de la réécriture ;
10. vérifier qu'aucun ⌘Z n'annule « bloc par bloc » — un seul historique.

- [ ] **Step 4: Commit**

```bash
cd ../.. && git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): copier-coller multi-blocs et undo unifié au conteneur"
```

---

## Task 12: Mécanisme 4 — tenue à l'échelle

Trois mesures, chiffrées, reproductibles. Elles vont telles quelles dans l'ADR.

**Files:**
- Modify: `Prototypes/BlockEditorProbe/Sources/block-editor-probe/ScaleHarness.swift`

**Interfaces:**
- Consomme : `SelectionCoordinator`, `BlockStackView`, `SampleText`.
- Produit : `ScaleHarness.run(blockCount: Int)` — imprime un tableau et rend la
  main.

- [ ] **Step 1: Écrire le harnais**

Remplacer entièrement `Sources/block-editor-probe/ScaleHarness.swift` :

```swift
import AppKit
import ProbeCore

/// Mesure la tenue à l'échelle : montage initial, fluidité au défilement,
/// latence de frappe. Les trois chiffres partent tels quels dans l'ADR de
/// verdict — c'est leur seule raison d'être.
@MainActor
enum ScaleHarness {

    static func run(blockCount: Int) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 620))
        scroll.hasVerticalScroller = true
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)

        let coordinator = SelectionCoordinator(
            document: ProbeDocument(texts: SampleText.blocks(count: blockCount)))
        let stack = BlockStackView(coordinator: coordinator)
        stack.setFrameSize(NSSize(width: scroll.contentSize.width, height: 400))
        scroll.documentView = stack

        let mount = measureMount(coordinator: coordinator, stack: stack, scroll: scroll)
        let scrolling = measureScrolling(scroll: scroll, stack: stack)
        let typing = measureTyping(coordinator: coordinator, stack: stack, blockCount: blockCount)

        report(blockCount: blockCount, mount: mount, scrolling: scrolling, typing: typing)
        window.orderOut(nil)
    }

    // MARK: - Les trois mesures

    /// Montage initial : de la pose du document à la première disposition
    /// complète, affichage compris.
    private static func measureMount(coordinator: SelectionCoordinator,
                                     stack: BlockStackView,
                                     scroll: NSScrollView) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        coordinator.attach(stack: stack)
        stack.layoutSubtreeIfNeeded()
        scroll.displayIfNeeded()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    /// Défilement : quarante pas du haut vers le bas, chacun forcé à
    /// s'afficher. On rapporte le pire pas, celui qui se verrait à l'œil.
    private static func measureScrolling(scroll: NSScrollView, stack: BlockStackView) -> [Double] {
        let steps = 40
        let travel = max(stack.frame.height - scroll.contentSize.height, 1)
        var samples: [Double] = []

        for step in 0...steps {
            let y = travel * CGFloat(step) / CGFloat(steps)
            let start = CFAbsoluteTimeGetCurrent()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            scroll.displayIfNeeded()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        return samples
    }

    /// Latence de frappe : deux cents caractères insérés par le vrai chemin,
    /// dans un bloc au milieu du document, disposition et affichage compris.
    private static func measureTyping(coordinator: SelectionCoordinator,
                                      stack: BlockStackView,
                                      blockCount: Int) -> [Double] {
        let target = blockCount / 2
        guard let view = stack.view(at: target) else { return [] }
        view.window?.makeFirstResponder(view)
        coordinator.setSelection(ProbeSelection(
            caret: ProbePosition(blockIndex: target, offset: coordinator.document.blocks[target].length)))

        var samples: [Double] = []
        for index in 0..<200 {
            let start = CFAbsoluteTimeGetCurrent()
            view.insertText("x", replacementRange: view.selectedRange())
            stack.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if index % 40 == 39 {
                // Une frappe sur cinq déclenche un retour à la ligne : c'est
                // le cas coûteux, on veut qu'il soit dans l'échantillon.
                stack.needsLayout = true
            }
        }
        return samples
    }

    // MARK: - Rapport

    private static func report(blockCount: Int,
                               mount: Double,
                               scrolling: [Double],
                               typing: [Double]) {
        print("")
        print("Tenue à l'échelle — \(blockCount) blocs, \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("---------------------------------------------------------------")
        print(String(format: "Montage initial            %8.1f ms", mount))
        print(String(format: "Défilement, pas médian     %8.2f ms", percentile(scrolling, 0.50)))
        print(String(format: "Défilement, pire pas       %8.2f ms", scrolling.max() ?? 0))
        print(String(format: "Frappe, médiane            %8.2f ms", percentile(typing, 0.50)))
        print(String(format: "Frappe, 95e centile        %8.2f ms", percentile(typing, 0.95)))
        print(String(format: "Frappe, pire cas           %8.2f ms", typing.max() ?? 0))
        print("---------------------------------------------------------------")
        print("Repère : un pas de défilement au-delà de 16,7 ms saute une image.")
        print("Repère : une frappe au-delà de 16,7 ms se sent au doigt.")
        print("")
    }

    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[index]
    }
}
```

- [ ] **Step 2: Lancer la mesure et relever les chiffres**

```bash
cd Prototypes/BlockEditorProbe && swift build -c release
swift run -c release block-editor-probe --scale
```

Copier le tableau imprimé — **il ira tel quel dans l'ADR**. Lancer aussi une
comparaison à 50 blocs pour savoir si le coût est linéaire ou s'effondre :

```bash
swift run -c release block-editor-probe --scale --blocks 50
swift run -c release block-editor-probe --scale --blocks 400
```

- [ ] **Step 3: Vérifier l'usage réel à 200 blocs**

```bash
swift run -c release block-editor-probe --blocks 200
```

À l'écran, cocher chaque point :

1. la fenêtre s'ouvre en un temps acceptable — noter l'impression subjective à
   côté du chiffre de montage ;
2. faire défiler de haut en bas à la molette : noter tout à-coup ;
3. taper dans un bloc du milieu : la frappe suit-elle le doigt ?
4. ⌘A sur 200 blocs : le surlignage complet apparaît-il sans gel ?
5. glisser une sélection du premier au dernier bloc en défilant : le suivi
   tient-il ?

**Si le montage ou la frappe s'effondrent**, le prototype doit dire si le
recyclage sauverait l'approche — vraies vues éditables pour le visible et le
bloc focalisé, texte simplement dessiné pour le reste. Ne pas l'implémenter :
noter, dans l'ADR, si la sélection traversante telle qu'elle est écrite ici
survivrait au recyclage. Le critère d'abandon n°3 est « 200 blocs imposent le
recyclage **et** le recyclage casse la sélection » — les deux, pas l'un.

- [ ] **Step 4: Commit**

```bash
cd ../.. && git add Prototypes/BlockEditorProbe
git commit -m "feat(sonde): harnais de mesure — montage, défilement, latence de frappe"
```

---

## Task 13: ADR de verdict et mise à jour de `STATUS.md`

Le livrable réel de tout ce plan. Le code peut être supprimé après.

**Files:**
- Create: `docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md`
- Modify: `STATUS.md`

**Interfaces:**
- Consomme : les notes prises aux tâches 8 à 12, et les chiffres de la tâche 12.
- Produit : le verdict qui décide de la suite (points 1 à 3, ou repli).

- [ ] **Step 1: Écrire l'ADR de verdict**

Créer `docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md` en suivant ce
canevas. **Les chiffres doivent être ceux réellement relevés, et les pièges
ceux réellement rencontrés — pas ceux anticipés par la spec.** Un ADR qui
recopie les pièges attendus sans les avoir vus ne vaut rien.

```markdown
# Verdict — une vue éditable par bloc tient-elle en AppKit ?

**Statut** : validée
**Date** : <date du jour>
**Prototype** : `Prototypes/BlockEditorProbe/` (jetable)
**Spec** : `docs/superpowers/specs/2026-08-08-prototype-editeur-par-blocs-design.md`
**Décision d'origine** : `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md`

## Verdict

<« Tient » ou « Ne tient pas », en une phrase, sans nuance.>

## Les quatre critères

| Critère | Résultat | Ce qui a été observé |
|---|---|---|
| 1. Sélection traversante | <tient / ne tient pas> | <observation> |
| 2. Édition destructive | <tient / ne tient pas> | <observation> |
| 3. Copier-coller et undo | <tient / ne tient pas> | <observation> |
| 4. Tenue à l'échelle | <tient / ne tient pas> | <observation> |

## Les trois mesures

<Coller ici la sortie brute de `block-editor-probe --scale`, à 50, 200 et 400
blocs. Ne pas résumer : les chiffres bruts sont la valeur de cet ADR.>

Lecture : <ce que ces chiffres impliquent — coût linéaire ou non, seuil où
le recyclage devient nécessaire.>

## Pièges réellement rencontrés

<Un paragraphe par piège **effectivement** rencontré, avec ce qui a marché.
Les pièges anticipés par la spec qui ne se sont pas matérialisés doivent être
signalés comme tels — c'est une information.>

### Pièges anticipés qui ne se sont pas produits

<Liste. Si le surlignage inactif ou l'`UndoManager` par vue n'ont pas posé
problème, le dire.>

### Pièges non anticipés

<Liste. Ce sont les plus précieux : ce sont eux qui manqueront aux estimations
des points 1 à 8.>

## Critère d'abandon

Fixé avant de commencer, dans la spec :

1. le surlignage d'une sélection traversante ne peut pas être rendu
   correctement sans réécrire le dessin du texte — <vérifié / non vérifié> ;
2. l'undo ne peut pas être unifié au niveau du conteneur — <vérifié / non vérifié> ;
3. 200 blocs imposent le recyclage **et** le recyclage casse la sélection —
   <vérifié / non vérifié>.

## Ce que cela implique pour les points 1 à 8

<Pour chacun des huit points de la réécriture, ce que le prototype a appris.
Notamment : le point 5 est-il plus cher ou moins cher que craint ? Le modèle
plat a-t-il masqué un problème que l'arbre de nœuds fera revenir ?>

## Suite décidée

<« On enchaîne sur les points 1 à 3 » ou « repli sur la sortie des blocs
mermaid, tableaux et images du flux TextKit en vraies `NSView` ancrées ».>

## Sort du prototype

Le code de `Prototypes/BlockEditorProbe/` n'a plus de raison d'être une fois
cet ADR écrit. <Supprimé dans le commit X / conservé jusqu'à Y parce que Z.>
```

- [ ] **Step 2: Mettre `STATUS.md` à jour**

Ajouter en tête de `STATUS.md`, juste sous « Synthèse », une section qui dit
trois choses et rien de plus :

```markdown
## Réécriture de l'éditeur — décision et verdict

L'éditeur est réécrit en reprenant l'architecture d'appflowy-editor
(ADR `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md`,
AGPL-3.0 acceptée). Cet ADR **annule les décisions structurantes n°1, n°2 et
n°4** listées en bas de ce fichier.

Le premier sous-projet, un prototype jetable sondant le risque central
(sélection traversante entre `NSTextView`), a rendu son verdict :
`docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md` — <verdict en trois mots>.

Le chantier `feat/editeur-slash-blocs` décrit ci-dessous reste **en l'état** :
il n'est ni fusionné ni abandonné, et sa vérification à l'écran reste due.
```

Ajouter également, à la liste « Décisions structurantes » en fin de fichier,
la mention de l'annulation sur les décisions 1, 2 et 4 — sans effacer leur
texte, pour que l'historique reste lisible :

```markdown
1. ~~Le Markdown reste la source de vérité…~~ **Annulée** le 2026-08-08 par
   `docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md`.
2. ~~TextKit 1 est conservé…~~ **Annulée** le 2026-08-08 par le même ADR.
4. ~~Aucun code AppFlowy n'est repris…~~ **Annulée** le 2026-08-08 par le même ADR.
```

Mettre à jour la ligne « Dernière mise à jour » en tête de fichier, et la
« Prochaine action » finale pour qu'elle pointe la suite décidée par l'ADR de
verdict.

- [ ] **Step 3: Vérifier que rien n'a fui hors du périmètre**

```bash
git diff --stat master...HEAD
```

Attendu : uniquement `Prototypes/BlockEditorProbe/**`, `docs/adr/**`,
`docs/superpowers/**` et `STATUS.md`. **Aucun fichier de
`OneToOne/`, aucun `Package.swift` racine, aucun `Tests/` racine.** Si un autre
fichier apparaît, il vient du chantier éditeur non commité : le retirer de la
branche avant de proposer la PR.

- [ ] **Step 4: Commit**

```bash
git add docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md STATUS.md
git commit -m "docs(adr): verdict du prototype d'éditeur par blocs"
```

---

## Vérification finale avant PR

```bash
cd Prototypes/BlockEditorProbe && swift test && swift build -c release
cd ../.. && swift build
git diff --stat master...HEAD
```

Attendu :

- 41 tests `ProbeCore`, 0 échec ;
- build release du prototype réussi ;
- **`swift build` racine réussi** — preuve que le paquet imbriqué n'a rien
  cassé du paquet principal ;
- le diff de branche ne contient que les chemins listés à la tâche 13, étape 3.

La suite racine `swift test --skip CalendarImportEventTests` n'est **pas**
requise ici : cette branche ne touche aucune ligne de `OneToOne/` ni de
`Tests/`. Si elle est lancée quand même, les deux échecs préexistants
documentés dans `STATUS.md` (`MenuBarStatsTests.test_badge_twelve_compact`
dépendant de l'heure, et l'instabilité de l'exécution globale) sont étrangers à
ce plan.
