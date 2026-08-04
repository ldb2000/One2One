# Éditeur — Commandes de bloc par attributs

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le chemin d'édition de bloc destructeur par une couche opérant sur les attributs, et y brancher la barre d'outils — la fondation sans laquelle le menu `/` ne peut pas être écrit correctement.

**Architecture:** Un nouveau `MarkdownBlockCommands` mute `.mdBlockType` / `.mdListInfo` sur la plage de la ligne du `NSTextStorage`, puis restyle et notifie. `MarkdownToolbar` cesse d'appeler `toggleLinePrefix` (qui passe du texte d'affichage à une API attendant des marqueurs littéraux, et reparse tout).

**Tech Stack:** Swift 6, AppKit (`NSTextView`, `NSTextStorage`, TextKit 1), `swift-markdown` (Apple), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-03-editeur-slash-blocs-design.md`, section « Le menu `/` » telle que corrigée le 2026-08-04. Le panneau `/` lui-même fait l'objet du plan suivant.

---

## Pourquoi ce plan existe

La spec prévoyait que le menu `/` réutilise `MarkdownEditingCommands`, « les mêmes fonctions que la barre d'outils ». Une enquête a établi que ce chemin est destructeur.

`MarkdownEditingCommands.toggleLinePrefix` manipule des marqueurs littéraux (`## `, `- `). Ses deux seuls appelants (`EditableTextField.swift:384` et `:405`) lui passent `tv.string` — le texte **d'affichage**, qui n'en contient aucun, le storage ne portant que des attributs. Le résultat est ensuite reparsé intégralement par `apply(_:to:)` (`EditableTextField.swift:426-438`).

Mesures d'exécution :

| Action | Entrée markdown | Après clic | Verdict |
|---|---|---|---|
| bouton h2 | `Voici du **gras** et un [lien](https://ex.com)` | `## Voici du gras et un lien` | gras et lien détruits |
| bouton liste | `Avant ![alt](file:///tmp/a.png) après` | `- Avant ￼ après` | URL perdue, `U+FFFC` littéral, fichier orphelin |
| bouton h2 ×2 | `## Titre` | `## Titre` | jamais réversible |

Le deuxième cas est la corruption d'image que la branche a écartée dans `EditorTextView.paste` (commit `4e44738`), réintroduite par une autre porte. Le troisième s'explique par `exclusivePrefixes` : `"## "` n'existe jamais dans le texte d'affichage, donc `shouldRemove` (`MarkdownEditingCommands.swift:65`) est toujours `false` — les boutons titre et liste sont *add-only*.

Ce chemin est **vivant en production** : `DetailsViews.swift:1713` branche la barre sur les notes d'entretien, et `:1732` y monte l'éditeur du module.

Les boutons gras et italique, eux, ne perdent rien : ils passent par `toggleInlineAttribute` (`EditableTextField.swift:334-373`), qui mute les attributs. C'est le mécanisme à généraliser.

## File map

| Chemin | Responsabilité | Action |
|---|---|---|
| `OneToOne/Markdown/Core/MarkdownBlockCommands.swift` | muter `.mdBlockType`/`.mdListInfo` sur une ligne | créer |
| `Tests/MarkdownBlockCommandsTests.swift` | comportement des commandes | créer |
| `OneToOne/Views/EditableTextField.swift` | `MarkdownToolbar` | modifier |
| `OneToOne/Markdown/Core/MarkdownEditingCommands.swift` | ancienne API littérale | supprimer en fin de plan |
| `Tests/MarkdownEditingCommandsTests.swift` | tests de l'ancienne API | supprimer avec elle |

---

### Task 1 : figer le comportement destructeur actuel

Avant de changer quoi que ce soit, écrire les tests qui **documentent** ce que fait le code aujourd'hui. Ils échoueront à la tâche 3, et c'est le but : ils prouvent que le correctif change bien ce qu'on croit.

**Files:**
- Test: `Tests/MarkdownBlockCommandsTests.swift` (créer)

- [ ] **Step 1 : écrire les tests de caractérisation**

```swift
import XCTest
import AppKit
@testable import OneToOne

/// Caractérise le comportement des commandes de bloc. Les trois premiers tests
/// documentent la perte d'information du chemin actuel — ils seront inversés
/// par la tâche 3, une fois `MarkdownBlockCommands` en place.
final class MarkdownBlockCommandsTests: XCTestCase {

    /// Applique l'ancien chemin : texte d'affichage → `toggleLinePrefix` →
    /// reparse global, tel que `MarkdownToolbar.apply(_:to:)` le fait.
    private func legacyApply(markdown: String, prefix: String) -> String {
        let storage = NSTextStorage(attributedString: MarkdownParser.parse(markdown))
        let result = MarkdownEditingCommands.toggleLinePrefix(
            in: storage.string,
            range: NSRange(location: 0, length: 0),
            prefix: prefix
        )
        return MarkdownSerializer.serialize(MarkdownParser.parse(result.text))
    }

    func test_legacyHeadingButton_destroysInlineFormatting() {
        let out = legacyApply(markdown: "Voici du **gras** et un [lien](https://ex.com)", prefix: "## ")
        XCTAssertEqual(out, "## Voici du gras et un lien",
                       "Comportement actuel : le gras et le lien sont perdus.")
    }

    func test_legacyListButton_destroysImageURL() {
        let out = legacyApply(markdown: "Avant ![alt](file:///tmp/a.png) après", prefix: "- ")
        XCTAssertFalse(out.contains("file:///tmp/a.png"),
                       "Comportement actuel : l'URL de l'image est perdue.")
    }

    func test_legacyHeadingButton_isNotReversible() {
        let once = legacyApply(markdown: "Titre", prefix: "## ")
        let twice = legacyApply(markdown: once, prefix: "## ")
        XCTAssertEqual(twice, once,
                       "Comportement actuel : réappliquer n'enlève pas le titre.")
    }
}
```

- [ ] **Step 2 : lancer et confirmer que ces tests passent**

```bash
swift test --filter MarkdownBlockCommandsTests
```

Attendu : SUCCÈS, 3 tests. Ils décrivent le code tel qu'il est.

Si l'un échoue, **arrête-toi et signale-le** : cela voudrait dire que le diagnostic de l'enquête est faux, et tout ce plan repose dessus.

- [ ] **Step 3 : committer**

```bash
git add Tests/MarkdownBlockCommandsTests.swift
git commit -m "test(markdown): caractérise la perte d'information des commandes de bloc"
```

---

### Task 2 : la couche par attributs

**Files:**
- Create: `OneToOne/Markdown/Core/MarkdownBlockCommands.swift`
- Test: `Tests/MarkdownBlockCommandsTests.swift`

- [ ] **Step 1 : écrire les tests du nouveau comportement**

Ajouter à `MarkdownBlockCommandsTests` :

```swift
    private func storage(_ markdown: String) -> NSTextStorage {
        NSTextStorage(attributedString: MarkdownParser.parse(markdown))
    }

    private func serialized(_ storage: NSTextStorage) -> String {
        MarkdownSerializer.serialize(storage)
    }

    func test_setBlockType_preservesInlineFormatting() {
        let s = storage("Voici du **gras** ici")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Voici du **gras** ici")
    }

    func test_setBlockType_preservesImageURL() {
        let s = storage("Avant ![alt](file:///tmp/a.png) après")
        MarkdownBlockCommands.setBlockType(.blockquote, in: s, at: 0)
        XCTAssertEqual(serialized(s), "> Avant ![alt](file:///tmp/a.png) après")
    }

    func test_setBlockType_toSameType_revertsToParagraph() {
        let s = storage("Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Titre", "Réappliquer le même type revient au paragraphe.")
    }

    func test_setBlockType_clearsListInfo() {
        let s = storage("- une puce")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## une puce", "Un titre n'est pas une liste.")
    }

    func test_setListKind_preservesInlineFormatting() {
        let s = storage("Texte **fort**")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Texte **fort**")
    }

    func test_setListKind_task_producesCheckbox() {
        let s = storage("À faire")
        MarkdownBlockCommands.setListKind(.task, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- [ ] À faire")
    }

    func test_setListKind_toSameKind_revertsToParagraph() {
        let s = storage("Texte")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Texte")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Texte")
    }

    func test_setListKind_clearsBlockType() {
        let s = storage("## Titre")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertEqual(serialized(s), "- Titre", "Une liste n'est pas un titre.")
    }

    func test_operatesOnlyOnCaretLine() {
        let s = storage("Première\nDeuxième")
        let secondLineStart = (s.string as NSString).range(of: "Deuxième").location
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: secondLineStart)
        XCTAssertEqual(serialized(s), "Première\n## Deuxième")
    }
```

- [ ] **Step 2 : lancer et constater l'échec**

```bash
swift test --filter MarkdownBlockCommandsTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'MarkdownBlockCommands' in scope`.

- [ ] **Step 3 : écrire la couche**

Créer `OneToOne/Markdown/Core/MarkdownBlockCommands.swift` :

```swift
import AppKit

/// Change le type de bloc de la ligne portant le curseur, en mutant les
/// attributs du storage plutôt qu'en réécrivant du markdown littéral.
///
/// L'ancienne approche — insérer `## ` dans le texte puis tout reparser —
/// détruisait le gras, les liens et les images de la ligne : le storage ne
/// contient que du texte d'affichage, l'information de style vivant dans les
/// attributs, qu'un reparse du seul texte ne peut pas reconstituer.
enum MarkdownBlockCommands {

    /// Applique `type` à la ligne contenant `location`. Réappliquer le type
    /// déjà en place revient au paragraphe, ce qui rend le geste réversible.
    /// Le `.mdListInfo` éventuel est retiré : un titre n'est pas une liste.
    static func setBlockType(_ type: BlockType, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let current = storage.attribute(.mdBlockType, at: range.location, effectiveRange: nil) as? BlockType
        let hasList = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) != nil
        let target: BlockType = (current == type && !hasList) ? .paragraph : type

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: target, range: range)
        storage.removeAttribute(.mdListInfo, range: range)
        storage.endEditing()
    }

    /// Applique une liste de type `kind` à la ligne contenant `location`.
    /// Réappliquer le même type revient au paragraphe. Le `.mdBlockType` est
    /// ramené à `.paragraph` : une liste n'est pas un titre.
    static func setListKind(_ kind: ListInfo.Kind, in storage: NSTextStorage, at location: Int) {
        let range = lineRange(in: storage, at: location)
        guard range.length > 0 else { return }

        let current = storage.attribute(.mdListInfo, at: range.location, effectiveRange: nil) as? ListInfo

        storage.beginEditing()
        storage.addAttribute(.mdBlockType, value: BlockType.paragraph, range: range)
        if current?.kind == kind {
            storage.removeAttribute(.mdListInfo, range: range)
        } else {
            let info = ListInfo(kind: kind,
                                level: 0,
                                index: kind == .ordered ? 1 : nil,
                                checked: kind == .task ? false : nil)
            storage.addAttribute(.mdListInfo, value: info, range: range)
        }
        storage.endEditing()
    }

    /// Plage de la ligne contenant `location`, **saut de ligne final exclu** :
    /// l'inclure ferait porter l'attribut de bloc au séparateur, que le
    /// sérialiseur traite comme la frontière entre deux paragraphes.
    static func lineRange(in storage: NSTextStorage, at location: Int) -> NSRange {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let safe = min(max(0, location), ns.length)
        var range = ns.lineRange(for: NSRange(location: safe, length: 0))
        if range.length > 0, ns.character(at: range.location + range.length - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }
}
```

- [ ] **Step 4 : lancer les tests**

```bash
swift test --filter MarkdownBlockCommandsTests
```

Attendu : SUCCÈS pour les 9 nouveaux tests. Les 3 tests de caractérisation de la tâche 1 passent toujours — ils décrivent l'ancien chemin, encore en place.

- [ ] **Step 5 : vérification par mutation**

Neutralise tour à tour, note le test qui échoue ou « aucun », restaure :
- le `removeAttribute(.mdListInfo)` de `setBlockType`
- la remise à `.paragraph` du `.mdBlockType` dans `setListKind`
- la bascule vers `.paragraph` quand le type est déjà en place (les deux commandes)
- l'exclusion du `\n` final dans `lineRange`

Rapporte le tableau. Une case vide annoncée vaut mieux qu'une couverture inventée.

- [ ] **Step 6 : committer**

```bash
git add OneToOne/Markdown/Core/MarkdownBlockCommands.swift Tests/MarkdownBlockCommandsTests.swift
git commit -m "feat(markdown): commandes de bloc opérant sur les attributs"
```

---

### Task 3 : brancher la barre d'outils

**Files:**
- Modify: `OneToOne/Views/EditableTextField.swift`
- Test: `Tests/MarkdownBlockCommandsTests.swift`

- [ ] **Step 1 : inverser les tests de caractérisation**

Les trois tests de la tâche 1 décrivent un comportement qu'on supprime. Remplace-les par leur contraire, en gardant les mêmes entrées :

```swift
    func test_headingCommand_preservesInlineFormatting() {
        let s = storage("Voici du **gras** et un [lien](https://ex.com)")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "## Voici du **gras** et un [lien](https://ex.com)")
    }

    func test_listCommand_preservesImageURL() {
        let s = storage("Avant ![alt](file:///tmp/a.png) après")
        MarkdownBlockCommands.setListKind(.bullet, in: s, at: 0)
        XCTAssertTrue(serialized(s).contains("file:///tmp/a.png"))
    }

    func test_headingCommand_isReversible() {
        let s = storage("Titre")
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        MarkdownBlockCommands.setBlockType(.h2, in: s, at: 0)
        XCTAssertEqual(serialized(s), "Titre")
    }
```

- [ ] **Step 2 : rediriger `prefixButton`**

Dans `MarkdownToolbar`, `prefixButton` (`EditableTextField.swift:384`) appelle `toggleLinePrefix` puis `apply(_:to:)`. Remplace ce chemin par un appel à `MarkdownBlockCommands` sur le storage de la vue, suivi de `StyleRenderer.applyVisualStyle(to:affectedRange:)` sur la plage de ligne, puis de `didChangeText()`.

Suis le motif de `toggleInlineAttribute` (`EditableTextField.swift:334-373`), qui fait déjà exactement cette séquence pour le gras et l'italique. **Lis-le avant d'écrire** : il gère aussi la restauration de la sélection, qu'il ne faut pas perdre.

Les boutons concernés sont h2, h3 et liste. Le mapping vers les commandes est direct.

- [ ] **Step 3 : laisser les boutons de tag tranquilles**

`tagButton` (`EditableTextField.swift:405`) insère `[ACTION] `, `[RISQUE] `… Ce sont de vrais préfixes de **texte**, pas des types de bloc — `toggleLinePrefix` y est adapté et le toggle fonctionne dans les deux sens.

Ne les touche pas. Note qu'ils sont persistés échappés (`\[ACTION\]`, via `MarkdownEscaping.escapeInline`) : défaut réel, mais antérieur et hors périmètre.

- [ ] **Step 4 : vérifier**

```bash
swift test --filter "MarkdownBlockCommands|Markdown|StyleRenderer"
swift test --skip CalendarImportEventTests
```

Attendu : aucune **nouvelle** régression. Deux échecs préexistants, confirmés sans lien, à ne pas traiter ni masquer : `MenuBarStatsTests.test_badge_twelve_compact` et `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`. Le crash `CalendarImportEventTests` est environnemental, d'où le `--skip`. `TranscriptEditServiceTests.test_delete_shiftsLaterSegmentsByRemovedDuration` s'est révélé flaky — si tu le vois, signale-le sans le traiter.

- [ ] **Step 5 : vérifier dans l'app**

```bash
Scripts/bump-and-build.sh dev
```

Ouvrir un entretien, écrire une ligne contenant du gras et un lien, cliquer le bouton Titre 2 : le gras et le lien doivent survivre. Recliquer : le titre doit disparaître.

Le script modifie `Info.plist` (bump de `CFBundleVersion`) — le reverter avant de committer.

- [ ] **Step 6 : committer**

```bash
git add OneToOne/Views/EditableTextField.swift Tests/MarkdownBlockCommandsTests.swift
git commit -m "fix(markdown): la barre d'outils ne détruit plus le style de la ligne

Les boutons titre et liste passaient le texte d'affichage à une API attendant
des marqueurs littéraux, puis reparsaient le tout — ce qui effaçait gras,
liens et images de la ligne, et rendait les boutons irréversibles."
```

---

### Task 4 : retirer l'ancienne API

**Files:**
- Delete: `OneToOne/Markdown/Core/MarkdownEditingCommands.swift`
- Delete: `Tests/MarkdownEditingCommandsTests.swift`
- Modify: `OneToOne/Views/EditableTextField.swift`

- [ ] **Step 1 : vérifier ce qui reste**

```bash
grep -rn "MarkdownEditingCommands\|toggleLinePrefix\|wrapSelection" OneToOne Tests --include="*.swift"
```

Attendu après la tâche 3 : `toggleLinePrefix` n'est plus appelé que par `tagButton`. `wrapSelection` n'a **aucun** appelant en production (vérifié par l'enquête : seuls les tests l'utilisent).

- [ ] **Step 2 : décider en fonction de ce que tu trouves**

Si `tagButton` est le seul appelant restant, ne supprime pas le fichier entier : réduis `MarkdownEditingCommands` à `toggleLinePrefix` et ses fonctions privées, supprime `wrapSelection` et ses tests, et documente en tête du fichier que cette API n'est plus utilisée que pour les préfixes de **texte** (les tags), jamais pour les types de bloc.

Si tu trouves d'autres appelants que l'enquête n'avait pas vus, **arrête-toi et signale-le**.

- [ ] **Step 3 : vérifier et committer**

```bash
swift test --skip CalendarImportEventTests
```

```bash
git commit -m "chore(markdown): réduit MarkdownEditingCommands aux préfixes de texte"
```

---

## Ce que ce plan ne couvre pas

- **Le panneau `/` lui-même** — plan suivant, qui s'appuiera sur `MarkdownBlockCommands`.
- **La fusion des paragraphes** : `parse("Avant\n\nAprès")` → affichage → `serialize` → reparse donne `"Avant Après"`, un seul paragraphe. Vérifié. Chaque frappe fusionne donc silencieusement les paragraphes de la note persistée. Défaut antérieur à ce chantier, sérieux, à traiter dans son propre plan — et **avant** que le menu `/` n'insère des blocs sur de nouvelles lignes.
- **Puces et cases à cocher non dessinées** : `StyleRenderer` traduit `.mdListInfo` en simple indentation. Une entrée « Case à cocher » au menu produirait un item invisible. À traiter avant d'exposer cette entrée.
- **`EditorTextView.mouseDown` (bascule des cases)** : compare les 6 premiers caractères à `"- [ ] "` dans un storage qui contient `"tâche"` — ne peut jamais se déclencher sur une vraie liste. Code mort à réécrire sur `.mdListInfo` en même temps que le dessin des puces.
- **Propagation du type de bloc au Retour** : `"## Titre"` + ⏎ + `"corps"` donne `"## Titre\n## corps"`. Souhaitable pour une liste, pas pour un titre. À traiter avec le menu `/`.
- **Tableaux GFM et blocs HTML effacés par le parser**, titres markdown perdus, `invalidate()` sans appelant en production, `TranscriptEditServiceTests` flaky.
