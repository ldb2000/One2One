# Sûreté des données — correctifs 1 à 3 de la revue de mai

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`.
> Les étapes utilisent la syntaxe case à cocher (`- [ ]`).

**Spec** : [`docs/superpowers/specs/2026-08-09-revue-code-data-safety-perf-design.md`](../specs/2026-08-09-revue-code-data-safety-perf-design.md)

**Objectif** : appliquer les trois correctifs de l'axe « sûreté des données ». Ce sont les
seuls des onze dont la conséquence est une corruption ou une désynchronisation
**silencieuse**.

**Architecture** : une fonction de déduplication d'identifiants, pure et testée sans
SwiftData, consommée par la réparation du store au démarrage ; un type d'erreur qui nomme
la désynchronisation audio/transcription ; un nettoyage de fichier temporaire sur le chemin
d'échec, sur le modèle de celui qui existe déjà dans `split`.

**Pile technique** : Swift 6.3, SwiftData, XCTest. Aucune dépendance nouvelle.

---

## Contraintes globales

- Commentaires et libellés d'interface en **français**, symboles et code en anglais.
- **Zéro dépendance nouvelle.**
- **Aucun changement de forme du schéma SwiftData.** On répare des données, on ne modifie
  ni un type de propriété ni la liste des modèles versionnés. Changer `chunkId` en
  `UUID?` serait une migration — hors périmètre, et c'est précisément ce que la
  déduplication permet d'éviter.
- ⚠️ **34 entrées non commitées d'un autre chantier** dans l'arbre (`OneToOne/Markdown/`,
  `Tests/`, `Package.swift`, `Info.plist`, `CLAUDE.md`, `Vendor/`…). Jamais `git add -A`,
  `git add .`, `git add -u`, `git commit -a`, `git stash`, `git checkout`, `git switch`,
  `git restore`, `git reset`, `git clean`. Ajout **nommément**, vérification par
  `git diff --cached --name-only`.
- Commits conventionnels, messages en français. Un commit par tâche.

### L'inventaire, déjà fait — ne pas le refaire, ne pas l'élargir

La spec demandait un inventaire des modèles exposés au piège de l'UUID non optionnel.
Il a été fait le 2026-08-09 et donne :

| Modèle | Motif | Verdict |
|---|---|---|
| `TranscriptChunk.chunkId` | `UUID` non optionnel, **sans** valeur par défaut | **exposé** — la migration doit inventer une valeur, donc identique partout |
| `SlideCapture.id` | `UUID` non optionnel **avec** `= UUID()` | **exposé** — toutes les lignes migrées partagent le même |
| 10 autres modèles (dont `Meeting`) | `stableID: UUID? = nil` + `ensuredStableID` | **déjà protégés**, ne rien y toucher |
| `TemplateSection.id` | `UUID = UUID()` | **faux positif** — c'est une `struct Codable`, pas un `@Model` ; elle échappe à la migration. **Ne pas la « corriger ».** |

`TranscriptChunk` et `SlideCapture` figurent tous deux dans le schéma versionné
(`SchemaVersions.swift`).

---

## Structure de fichiers

```text
OneToOne/Services/IdentifierRepair.swift          NOUVEAU : la dédup, pure (tâche 1)
OneToOne/OneToOneApp.swift                        y branche la réparation (tâche 1)
OneToOne/Services/TranscriptEditService.swift     erreur de désynchronisation (tâche 2)
OneToOne/Services/AudioFileEditor.swift           nettoyage du temporaire (tâche 3)

Tests/IdentifierRepairTests.swift                 NOUVEAU (tâche 1)
Tests/TranscriptEditServiceTests.swift            complété (tâche 2)
Tests/AudioFileEditorTests.swift                  complété (tâche 3)
```

`IdentifierRepair` vit dans `Services/` et **ne connaît pas SwiftData** : c'est ce qui la
rend testable sans conteneur.

---

## Vue d'ensemble

| # | Tâche | Vérification |
|---|---|---|
| 1 | Déduplication des identifiants + branchement au démarrage | `swift test` |
| 2 | Erreur nommant la désynchronisation audio/transcription | `swift test` |
| 3 | Nettoyage du fichier temporaire sur échec | `swift test` |

---

## Task 1 : déduplication des identifiants

**Files:**
- Create: `OneToOne/Services/IdentifierRepair.swift`
- Modify: `OneToOne/OneToOneApp.swift` (`repairStoreIfNeeded`)
- Test: `Tests/IdentifierRepairTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit :
  - `enum IdentifierRepair`
  - `static func IdentifierRepair.duplicates<Element>(in elements: [Element], identifier: (Element) -> UUID) -> [Element]`
    — rend les éléments **à réattribuer** : pour chaque groupe d'identifiants identiques,
    tous sauf le premier. L'ordre d'entrée est conservé.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/IdentifierRepairTests.swift` :

```swift
import XCTest
@testable import OneToOne

/// Déduplication d'identifiants UUID.
///
/// Le piège SwiftData : un `UUID` non optionnel sur un `@Model` reçoit sa valeur à la
/// **migration**, pas à l'insertion — toutes les lignes migrées partagent alors le même
/// identifiant. On répare les données plutôt que de changer le schéma.
final class IdentifierRepairTests: XCTestCase {

    /// Objet minimal, sans SwiftData : c'est ce qui rend la règle testable seule.
    private final class Row {
        var id: UUID
        let label: String
        init(id: UUID, label: String) { self.id = id; self.label = label }
    }

    private func rows(_ pairs: [(UUID, String)]) -> [Row] {
        pairs.map { Row(id: $0.0, label: $0.1) }
    }

    func test_aucunDoublon_neRendRien() {
        let elements = rows([(UUID(), "a"), (UUID(), "b"), (UUID(), "c")])
        XCTAssertTrue(IdentifierRepair.duplicates(in: elements, identifier: \.id).isEmpty)
    }

    /// Le premier de chaque groupe est conservé : on ne réattribue que les suivants.
    func test_unGroupeDeTrois_rendLesDeuxDerniers() {
        let partage = UUID()
        let elements = rows([(partage, "a"), (partage, "b"), (partage, "c")])

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(aReattribuer.map(\.label), ["b", "c"])
    }

    /// Le cas réel après migration : toutes les lignes portent le même identifiant.
    func test_toutesLesLignesIdentiques_neConserveQueLaPremiere() {
        let partage = UUID()
        let elements = rows((0..<50).map { (partage, "l\($0)") })

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(aReattribuer.count, 49)
        XCTAssertFalse(aReattribuer.contains { $0.label == "l0" })
    }

    func test_plusieursGroupes_sontTraitesIndependamment() {
        let x = UUID(), y = UUID()
        let elements = rows([(x, "x1"), (y, "y1"), (x, "x2"), (UUID(), "seul"), (y, "y2")])

        let aReattribuer = IdentifierRepair.duplicates(in: elements, identifier: \.id)

        XCTAssertEqual(Set(aReattribuer.map(\.label)), ["x2", "y2"])
    }

    /// L'ordre d'entrée décide qui est conservé : le résultat doit être déterministe,
    /// sinon deux démarrages successifs réattribueraient des lignes différentes.
    func test_leResultatEstDeterministe() {
        let partage = UUID()
        let elements = rows([(partage, "a"), (partage, "b"), (partage, "c")])

        let premier = IdentifierRepair.duplicates(in: elements, identifier: \.id).map(\.label)
        let second = IdentifierRepair.duplicates(in: elements, identifier: \.id).map(\.label)

        XCTAssertEqual(premier, second)
        XCTAssertEqual(premier, ["b", "c"])
    }

    /// L'UUID tout à zéro est la valeur qu'une migration invente pour un champ non
    /// optionnel sans défaut : il doit être traité comme n'importe quel doublon.
    func test_lUUIDToutAZero_estUnDoublonCommeUnAutre() {
        let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let elements = rows([(zero, "a"), (zero, "b")])

        XCTAssertEqual(IdentifierRepair.duplicates(in: elements, identifier: \.id).map(\.label), ["b"])
    }

    func test_listeVide_neRendRien() {
        XCTAssertTrue(IdentifierRepair.duplicates(in: [Row](), identifier: \.id).isEmpty)
    }
}
```

- [ ] **Étape 2 : lancer le test pour le voir échouer**

Run : `swift test --filter IdentifierRepairTests`
Attendu : ÉCHEC de compilation — « cannot find 'IdentifierRepair' in scope ».

- [ ] **Étape 3 : écrire `IdentifierRepair`**

Créer `OneToOne/Services/IdentifierRepair.swift` :

```swift
import Foundation

/// Réparation d'identifiants dupliqués.
///
/// Un `UUID` non optionnel sur un `@Model` SwiftData reçoit sa valeur au moment de la
/// **migration**, pas à l'insertion : toutes les lignes déjà présentes en base se
/// retrouvent alors avec le même identifiant. On répare les données au démarrage plutôt
/// que de modifier le schéma, qui coûterait une migration de plus.
///
/// Cette fonction ne connaît pas SwiftData : c'est ce qui la rend vérifiable seule.
enum IdentifierRepair {

    /// Les éléments dont l'identifiant doit être réattribué.
    ///
    /// Pour chaque groupe d'identifiants identiques, le **premier rencontré** est
    /// conservé et les suivants sont rendus. L'ordre d'entrée est préservé, de sorte
    /// que deux exécutions sur la même liste réparent exactement les mêmes lignes.
    static func duplicates<Element>(in elements: [Element],
                                    identifier: (Element) -> UUID) -> [Element] {
        var vus = Set<UUID>()
        var aReattribuer: [Element] = []
        for element in elements {
            if vus.insert(identifier(element)).inserted == false {
                aReattribuer.append(element)
            }
        }
        return aReattribuer
    }
}
```

- [ ] **Étape 4 : lancer les tests pour les voir passer**

Run : `swift test --filter IdentifierRepairTests`
Attendu : 7 tests, 0 échec.

- [ ] **Étape 5 : brancher la réparation au démarrage**

Dans `OneToOne/OneToOneApp.swift`, à la suite de ce que `repairStoreIfNeeded()` fait déjà
pour les codes de projet, ajouter la réparation des deux modèles exposés — et **uniquement
ces deux** :

- `TranscriptChunk`, sur `chunkId` ;
- `SlideCapture`, sur `id`.

Pour chacun : récupérer toutes les instances, appeler
`IdentifierRepair.duplicates(in:identifier:)`, attribuer un `UUID()` neuf à chaque élément
rendu, puis sauvegarder **une seule fois** à la fin. Journaliser le nombre de
réattributions par modèle : c'est la seule trace qu'aura l'utilisateur qu'une réparation a
eu lieu.

Ne toucher à **aucun** autre modèle : les dix qui portent `stableID: UUID? = nil` ont déjà
leur propre mécanisme (`ensuredStableID`), et `TemplateSection` est une `struct`, pas un
`@Model`.

- [ ] **Étape 6 : construire et vérifier la non-régression**

Run : `swift build && swift test --skip CalendarImportEventTests`
Attendu : build réussi ; suite complète sans échec.

- [ ] **Étape 7 : commit**

```bash
git add OneToOne/Services/IdentifierRepair.swift Tests/IdentifierRepairTests.swift OneToOne/OneToOneApp.swift
git diff --cached --name-only
git commit -m "fix(données): déduplique les identifiants de TranscriptChunk et SlideCapture au démarrage"
```

---

## Task 2 : nommer la désynchronisation audio/transcription

**Files:**
- Modify: `OneToOne/Services/TranscriptEditService.swift`
- Test: `Tests/TranscriptEditServiceTests.swift`

**Interfaces:**
- Consomme : rien de la tâche 1.
- Produit : `enum TranscriptEditError: Error, LocalizedError`, cas
  `saveFailedAfterAudioCut(underlying: Error)`.

**Le défaut, tel qu'il se présente aujourd'hui.** `deleteSegment` coupe le fichier audio
**d'abord**, décale les segments, supprime le segment cible, puis `try context.save()`.
Son commentaire annonce « failure-safe : si throw, transcript intact » — vrai de la
première étape, **faux de la dernière** : si la sauvegarde échoue, l'audio est déjà coupé
sur disque de façon irréversible pendant que la transcription conserve le segment.
L'appelant reçoit une erreur SwiftData générique qui ne dit rien de cet état.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/TranscriptEditServiceTests.swift` :

```swift
/// L'erreur qui signale que l'audio a été modifié mais pas la transcription.
///
/// On ne peut pas provoquer un échec de `context.save()` de façon fiable en test ; ce
/// qui est vérifiable, et ce qui compte pour l'utilisateur, c'est que l'erreur **existe**,
/// qu'elle **transporte** la cause d'origine, et que son message **nomme** la
/// désynchronisation au lieu d'un échec générique.
final class TranscriptEditErrorTests: XCTestCase {

    private struct CauseFactice: Error, LocalizedError {
        var errorDescription: String? { "disque plein" }
    }

    func test_lErreurTransporteLaCauseDOrigine() {
        let erreur = TranscriptEditError.saveFailedAfterAudioCut(underlying: CauseFactice())
        guard case .saveFailedAfterAudioCut(let cause) = erreur else {
            return XCTFail("cas d'erreur inattendu")
        }
        XCTAssertEqual((cause as? LocalizedError)?.errorDescription, "disque plein")
    }

    /// Le message doit dire que l'audio a changé : c'est la seule information qui permet
    /// à l'utilisateur de comprendre que son enregistrement et son texte ne correspondent
    /// plus.
    func test_leMessageNommeLaDesynchronisation() {
        let message = TranscriptEditError
            .saveFailedAfterAudioCut(underlying: CauseFactice())
            .errorDescription ?? ""

        XCTAssertTrue(message.localizedCaseInsensitiveContains("audio"),
                      "le message doit mentionner l'audio : \(message)")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("transcription"),
                      "le message doit mentionner la transcription : \(message)")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("disque plein"),
                      "le message doit reprendre la cause d'origine : \(message)")
    }
}
```

- [ ] **Étape 2 : lancer le test pour le voir échouer**

Run : `swift test --filter TranscriptEditErrorTests`
Attendu : ÉCHEC de compilation — « cannot find 'TranscriptEditError' in scope ».

- [ ] **Étape 3 : écrire le type d'erreur et l'utiliser**

Dans `TranscriptEditService.swift`, déclarer :

```swift
/// Échecs propres à l'édition de transcription.
enum TranscriptEditError: Error, LocalizedError {

    /// La coupe audio a réussi, la sauvegarde qui suit a échoué.
    ///
    /// C'est l'état dangereux : le fichier audio est **déjà** modifié sur disque, la
    /// transcription non. Les deux ne correspondent plus, et seul un message explicite
    /// permet à l'utilisateur de le savoir.
    case saveFailedAfterAudioCut(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .saveFailedAfterAudioCut(let underlying):
            return """
            L'audio a été coupé mais la transcription n'a pas pu être enregistrée : \
            les deux ne correspondent plus. Cause : \
            \((underlying as? LocalizedError)?.errorDescription ?? String(describing: underlying))
            """
        }
    }
}
```

Puis, dans `deleteSegment`, entourer **la sauvegarde finale seulement** :

```swift
        do {
            try context.save()
        } catch {
            throw TranscriptEditError.saveFailedAfterAudioCut(underlying: error)
        }
```

Et **corriger le commentaire de l'étape 1**, qui promet aujourd'hui une garantie que la
fonction ne tient pas : il doit dire que seule la première étape est sans risque, et que
l'échec de la sauvegarde finale laisse l'audio et le texte désaccordés.

- [ ] **Étape 4 : lancer les tests**

Run : `swift test --filter TranscriptEditErrorTests --filter TranscriptEditServiceTests`
Attendu : les 2 nouveaux tests passent, les tests existants de `TranscriptEditService`
restent verts — le chemin nominal ne change pas.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Services/TranscriptEditService.swift Tests/TranscriptEditServiceTests.swift
git diff --cached --name-only
git commit -m "fix(transcription): nomme la désynchronisation audio/texte au lieu d'une erreur générique"
```

---

## Task 3 : nettoyer le fichier temporaire sur échec

**Files:**
- Modify: `OneToOne/Services/AudioFileEditor.swift` (`trim`, `cut`)
- Test: `Tests/AudioFileEditorTests.swift`

**Interfaces:**
- Consomme : rien.
- Produit : rien de réutilisable.

**Le défaut.** `trim` et `cut` suppriment le `.tmp.wav` **avant** d'écrire, jamais après un
échec. `split` a déjà un `do/catch` qui nettoie ses deux sorties : c'est le modèle à
reproduire, pas à inventer.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/AudioFileEditorTests.swift` un test par opération. Le moyen de provoquer
un échec d'écriture sans dépendre du système : **créer un répertoire à l'emplacement exact
du fichier temporaire**. `AVAudioFile(forWriting:)` échoue alors, et le nettoyage doit
supprimer l'obstacle.

```swift
    /// `trim` doit retirer son fichier temporaire même quand l'écriture échoue.
    ///
    /// L'échec est provoqué en plaçant un **répertoire** là où le temporaire doit être
    /// écrit : `AVAudioFile(forWriting:)` ne peut pas l'ouvrir.
    func test_trim_nettoieLeTemporaireQuandLEcritureEchoue() async throws {
        let source = try makeSampleWav(seconds: 3)
        defer { try? FileManager.default.removeItem(at: source) }

        let tmp = source.deletingLastPathComponent()
            .appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".tmp.wav")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        do {
            try await AudioFileEditor.trim(url: source, from: 0, to: 2)
            XCTFail("l'écriture aurait dû échouer")
        } catch {
            // attendu
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path),
                       "le temporaire doit avoir été nettoyé après l'échec")
        try? FileManager.default.removeItem(at: tmp)
    }
```

Écrire l'équivalent pour `cut`, avec le suffixe `.cut.tmp.wav`.

⚠️ **Le nom de la fabrique de fichier de test (`makeSampleWav` ci-dessus) est une
hypothèse.** Lis `Tests/AudioFileEditorTests.swift` et réutilise la fabrique qui s'y
trouve réellement, quel que soit son nom. Si aucune n'existe, écris-en une et dis-le dans
le rapport.

- [ ] **Étape 2 : lancer les tests pour les voir échouer**

Run : `swift test --filter AudioFileEditorTests`
Attendu : les deux nouveaux tests ÉCHOUENT — le temporaire survit.

- [ ] **Étape 3 : nettoyer sur le chemin d'échec**

Dans `trim` et dans `cut`, entourer le bloc `Task.detached` d'un `do/catch` qui supprime le
temporaire puis relance l'erreur — exactement la forme déjà présente dans `split` :

```swift
        do {
            try await Task.detached(priority: .userInitiated) {
                // … inchangé …
            }.value
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
```

Ne rien changer d'autre : ni l'ordre des opérations, ni le remplacement atomique qui suit.

- [ ] **Étape 4 : lancer les tests pour les voir passer**

Run : `swift test --filter AudioFileEditorTests`
Attendu : tous les tests passent, dont les 7 préexistants qui exercent le chemin nominal.

- [ ] **Étape 5 : commit**

```bash
git add OneToOne/Services/AudioFileEditor.swift Tests/AudioFileEditorTests.swift
git diff --cached --name-only
git commit -m "fix(audio): supprime le fichier temporaire quand l'écriture échoue"
```

---

## Vérification finale

```bash
swift build
swift test --skip CalendarImportEventTests
git diff --stat origin/master..HEAD
```

Attendu : build réussi ; suite complète **sans aucun échec** (elle est verte depuis
`51cbc20`, toute nouvelle erreur vient donc de ce chantier) ; le diff ne contient que les
quatre fichiers de code, les trois fichiers de tests et ce plan.

**Et le contrôle que les tests ne peuvent pas faire** : la réparation d'identifiants de la
tâche 1 ne s'exécute qu'au démarrage, sur une vraie base. Lancer l'application une fois et
vérifier dans les journaux qu'elle ne signale aucune réattribution — ou, si elle en
signale, que l'application reste utilisable et que les transcriptions s'affichent
normalement.
