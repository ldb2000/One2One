# Lot 18 — Atelier : planche de séance (6b) et rapport d'atelier

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans`
> (exécution en session) ou `superpowers:subagent-driven-development`. Les étapes
> sont des cases à cocher (`- [ ]`).

**But :** donner à l'atelier son mode **Relire** — la sortie de séance : toutes
les planches, captures et pièces sur une page, dans l'ordre du temps, avec une
légende textuelle, un export en un dossier et un `Joindre au rapport` — puis
brancher la variable `{{planches}}` du rapport d'atelier.

**Architecture :** trois modules purs (`WorkshopTimelineModel`,
`BoardCaptionBuilder`, `WorkshopExport.exportAll`) que la vue
`WorkshopSessionSheetView` assemble. Aucune logique dans la vue, aucun WebKit
dans les tests, aucun appel réseau (l'IA est doublée par `AIClientProtocol`).
Deux colonnes à défaut sur `Board` (`includeInReport`, `caption`) : migration
légère, pas de version de schéma.

**Pile :** SwiftUI, SwiftData, Swift Testing, exécutable SwiftPM.

**Spec :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §7.3, §7.2,
§8, critère chantier 6 n° 5 ; plan directeur
`docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 lot 18, §4
(D6), §7, §8 ; capture qui fait foi
`docs/superpowers/specs/refonte-2026-09/ecrans/6b-atelier-planche-de-seance.png`.

## Contraintes globales

- Commentaires et libellés d'interface **en français**, symboles en anglais.
- Énums persistées en `…Raw: String` + wrapper calculé.
- Services : `enum` de fonctions pures, ou `class` `@MainActor` `.shared`.
- Colonnes SwiftData neuves **à valeur par défaut** : aucune version de schéma.
- `swift build` vert avant chaque commit, `swift test` complet vert avant la PR.
- **Aucune recette graphique, aucun lancement d'application, aucun appel réseau.**
- `.drawio` est **hors v1** (D6) : ne pas l'afficher, même en grisé.
- Fichiers interdits : `OneOnOne/**`, `Capture/**`, `Rail/**`, `Notes/**`,
  `Review/**`, `Resources/**`, `Project/**`, `Session/**`, `MeetingView.swift`,
  `MeetingTopChromeBar.swift`.
- Fichiers partagés : **une** ligne dans `WorkshopDock.swift`, **une** branche
  dans `MeetingSpaceView`/`MeetingSpaceRouting`, **un** cas dans
  `RecetteScreen.swift`, **deux** colonnes dans `Models/Board.swift`,
  propriétés de `WorkshopState` **en fin de type**.

---

## Structure des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `OneToOne/Services/Workshop/WorkshopTimelineModel.swift` | Modèle pur : fusion planches + captures + pièces, tri par `t`, libellés, compte « éléments produits », invite du vide. |
| `OneToOne/Services/Workshop/BoardCaptionBuilder.swift` | Légende d'une planche depuis les libellés d'objets — pure, puis raffinement IA facultatif. |
| `OneToOne/Services/Workshop/WorkshopExport+All.swift` | `Tout exporter` : un dossier, une image et une scène par planche, un `index.md`. |
| `OneToOne/Services/Workshop/WorkshopReportAttachment.swift` | `Joindre au rapport` : coche les planches et les captures, idempotent ; état « Joint ✓ ». |
| `OneToOne/Views/Meeting/Workshop/Session/WorkshopSessionSheetView.swift` | L'écran 6b : carte de 920 px, en-tête, frise chronologique, encart de clôture. |
| `OneToOne/Models/Board.swift` | +`includeInReport`, +`caption`. |
| `OneToOne/Services/Meeting/MeetingSpaceRouting.swift` | +`usesWorkshopReview(kind:mode:)`. |
| `OneToOne/Views/Meeting/Spaces/MeetingSpaceView.swift` | +1 branche vers 6b. |
| `OneToOne/Views/Meeting/Workshop/WorkshopDock.swift` | +1 ligne : la légende sous la vignette. |
| `OneToOne/Services/Debug/RecetteScreen.swift` | +`case atelierPlancheDeSeance = "6b"`. |
| `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot18.swift` | Semis 6b : manuscrit à deux lignes, texte extrait de la capture, légendes. |
| `Tests/WorkshopTimelineTests.swift` | Ordre du temps (critère n° 5), compte, invite, repli de `t`. |
| `Tests/BoardCaptionBuilderTests.swift` | Légende pure sur 3 scènes, repli si l'IA échoue, jamais d'exception. |
| `Tests/WorkshopExportAllTests.swift` | Dossier temporaire : n PNG + n JSON + `index.md`. |
| `Tests/WorkshopReportAttachmentTests.swift` | Coche tout, idempotent, état. |
| `Tests/WorkshopSeedLot18Tests.swift` | Semis idempotent, routage `6b`. |
| Après rebase : `Services/Report/**` | `{{planches}}` — additif seulement. |

---

## Tâche 1 — `WorkshopTimelineModel` : la frise, en pur

**Fichiers :** créer `OneToOne/Services/Workshop/WorkshopTimelineModel.swift`,
`Tests/WorkshopTimelineTests.swift`.

**Interfaces produites :**

```swift
struct WorkshopTimelineItem: Identifiable, Equatable, Sendable {
    enum Nature: String, Sendable { case board, capture, attachment }
    var id: String
    var nature: Nature
    var t: Double
    var typeLabel: String    // « Croquis » | « Schéma » | « Manuscrit » | « Capture » | « Pièce »
    var title: String
    var trailing: String     // auteur | « texte extrait » | « stylet »
    var caption: String      // « », si aucune légende
    var previewPath: String  // relatif à la réunion (planche) ou absolu (capture, pièce)
    var boardMode: BoardMode?
    var footer: String { "\(typeLabel) — \(title)" }
}

enum WorkshopTimelineModel {
    static func rows(for meeting: Meeting) -> [WorkshopTimelineItem]
    static func producedCount(for meeting: Meeting) -> Int
    static func headerSummary(date: Date, durationSeconds: Int,
                              participantCount: Int, producedCount: Int) -> String
    static func attachmentT(pinnedAtT: Double?, importedAt: Date,
                            meetingDate: Date, durationSeconds: Int) -> Double
    static let emptyInvite: String
}
```

**Règles :**

- Planche : `t` = `Board.t`, `typeLabel` = `mode.label`, `title` = `title` ou
  `BoardOrdering.defaultTitle(forIndex:)`, `trailing` = `authorNames` ou `—`,
  `previewPath` = `thumbPath`, `caption` = `caption`.
- Capture (`meeting.attachments.flatMap(\.slides)`) : `t` = `capture.t ?? 0`,
  `typeLabel` = `« Capture »`, `title` = **tête** du texte extrait (première
  ligne, coupée au premier ` — `, 60 caractères max) ou `Capture mm:ss`,
  `trailing` = `« texte extrait »` si `ocrText` non vide sinon
  `« sans texte extrait »`, `caption` = `ocrText` complet.
- Pièce : seulement `scope == .meeting`, ni lien, ni lot `slides` (un conteneur
  n'est pas une pièce — même règle qu'au lot 17). `t` = `attachmentT(…)`,
  `typeLabel` = `« Pièce »`, `title` = `fileName`,
  `trailing` = `addedByName` ou `« déposé dans la séance »`.
- `attachmentT` : `pinnedAtT` fait loi ; sinon l'écart `importedAt - meetingDate`
  **borné** à `0…durationSeconds` (`durationSeconds <= 0` ⇒ `0`). Une pièce
  importée deux jours après la séance ne doit pas s'horodater à `2880:00`.
- Tri : `t` croissant, puis `nature` (planche, capture, pièce), puis `title` —
  deux éléments au même timecode gardent un ordre stable.
- `headerSummary` : `« 4 sept. · 1 h 02 · 4 participants · 9 éléments produits »`
  (`1 participant`, `1 élément produit` au singulier ; durée `« 1 h 02 »`
  au-delà de l'heure, `« 47 min »` sinon).
- `emptyInvite` : `« Aucun élément produit dans cette séance. Les planches, les
  captures et les pièces de l'atelier apparaissent ici, dans l'ordre du temps. »`

- [ ] **Étape 1 : test qui échoue** — `Tests/WorkshopTimelineTests.swift`

```swift
import Testing
import Foundation
import SwiftData
@testable import OneToOne

@Suite("Atelier — frise de la planche de séance (6b)")
@MainActor
struct WorkshopTimelineTests {

    private func contexte() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        return ModelContext(conteneur)
    }

    /// Critère chantier 6 n° 5 : « le rapport d'atelier contient les planches
    /// dans l'ordre du temps ». La frise est ce même ordre.
    @Test("les trois sources sont fusionnées dans l'ordre du temps")
    func test_ordreDuTemps() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        reunion.meetingDurationSeconds = 3_720
        context.insert(reunion)

        for (index, couple) in [("Périmètre actuel", 495.0), ("Flux réseau", 1_180.0)].enumerated() {
            let planche = Board(index: index, title: couple.0, mode: .sketch,
                                t: couple.1, authorNames: "Yann")
            context.insert(planche)
            planche.meeting = reunion
        }

        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: reunion.date,
                                   imagePath: "/tmp/slides/c.png")
        capture.t = 1_270
        capture.ocrText = "partage de Cléva — schéma réseau partagé"
        context.insert(capture)
        capture.attachment = lot

        let lignes = WorkshopTimelineModel.rows(for: reunion)
        #expect(lignes.map(\.t) == [495, 1_180, 1_270])
        #expect(lignes[0].footer == "Croquis — Périmètre actuel")
        #expect(lignes[2].typeLabel == "Capture")
        #expect(lignes[2].title == "partage de Cléva")
        #expect(lignes[2].trailing == "texte extrait")
        #expect(WorkshopTimelineModel.producedCount(for: reunion) == 3)
    }

    @Test("un lot de captures n'est pas une pièce")
    func test_lotDeCapturesExclu() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier 2", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        #expect(WorkshopTimelineModel.rows(for: reunion).isEmpty)
    }

    @Test("une pièce non épinglée s'horodate dans la séance, jamais au-delà")
    func test_repliDuTimecode() {
        let debut = Date(timeIntervalSince1970: 1_788_523_200)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: 780, importedAt: debut,
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 780)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(600),
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 600)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(200_000),
                                                  meetingDate: debut,
                                                  durationSeconds: 3_720) == 3_720)
        #expect(WorkshopTimelineModel.attachmentT(pinnedAtT: nil,
                                                  importedAt: debut.addingTimeInterval(-50),
                                                  meetingDate: debut,
                                                  durationSeconds: 0) == 0)
    }

    @Test("l'en-tête énumère la séance, au singulier comme au pluriel")
    func test_enTete() {
        let date = Date(timeIntervalSince1970: 1_788_523_200)
        let resume = WorkshopTimelineModel.headerSummary(
            date: date, durationSeconds: 3_720, participantCount: 4, producedCount: 9)
        #expect(resume.contains("1 h 02"))
        #expect(resume.contains("4 participants"))
        #expect(resume.contains("9 éléments produits"))
        let seul = WorkshopTimelineModel.headerSummary(
            date: date, durationSeconds: 2_820, participantCount: 1, producedCount: 1)
        #expect(seul.contains("47 min"))
        #expect(seul.contains("1 participant"))
        #expect(seul.contains("1 élément produit"))
    }

    @Test("un atelier sans élément produit porte une invite, jamais une zone vide")
    func test_invite() throws {
        let context = try contexte()
        let reunion = Meeting(title: "Atelier vide", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        #expect(WorkshopTimelineModel.rows(for: reunion).isEmpty)
        #expect(!WorkshopTimelineModel.emptyInvite.isEmpty)
    }
}
```

- [ ] **Étape 2 : lancer, vérifier l'échec** — `swift test --filter WorkshopTimelineTests`,
      attendu : erreur de compilation « cannot find 'WorkshopTimelineModel' ».
- [ ] **Étape 3 : implémenter** le fichier `WorkshopTimelineModel.swift` selon
      les règles ci-dessus, entièrement pur (aucune lecture disque).
- [ ] **Étape 4 : `swift build`, puis `swift test --filter WorkshopTimelineTests`** — vert.
- [ ] **Étape 5 : commit** — `feat(atelier): frise chronologique de la planche de séance`.

---

## Tâche 2 — `BoardCaptionBuilder` : la légende, pure puis raffinée

**Fichiers :** créer `OneToOne/Services/Workshop/BoardCaptionBuilder.swift`,
`Tests/BoardCaptionBuilderTests.swift`. Modifier `OneToOne/Models/Board.swift`
(deux colonnes).

**Interfaces produites :**

```swift
enum BoardCaptionBuilder {
    struct Inventory: Equatable, Sendable {
        var boxes: Int, connectors: Int, notes: Int, strokes: Int, images: Int
        var questions: Int, risks: Int
        var labels: [String]
        var isEmpty: Bool
    }
    static func inventory(scene: String) -> Inventory
    static func caption(mode: BoardMode, scene: String) -> String
    static func buildPrompt(mode: BoardMode, pure: String, labels: [String]) -> String
    static func parse(_ raw: String) -> String?
    @MainActor static func refined(mode: BoardMode, scene: String,
                                   settings: AppSettings,
                                   client: AIClientProtocol = AIClient.live) async -> String
    static let timeout: TimeInterval  // 8
    static let maxLabels: Int         // 3
}
```

**Règles de la légende pure** (aucune IA, aucun réseau) :

- Inventaire depuis le JSON : `rectangle`/`ellipse`/`diamond` = boîtes ;
  `arrow`/`line` = liaisons ; `text` sans `containerId` = notes ; `freedraw` =
  tracés ; `image` = images ; `BoardAnnotation.list` = questions et risques.
  `isDeleted == true` est ignoré partout.
- Libellés : texte de boîte (porté par l'élément lié `containerId`) puis notes
  libres, sauts de ligne aplatis, doublons écartés, 40 caractères max chacun,
  `maxLabels` retenus.
- Forme : `"\(mode.label) — "` puis les segments séparés par `, ` :
  `« 5 boîtes (Runners GitLab, Nexus, GitLab auto-hébergé, …) »`,
  `« 3 liaisons »`, `« 2 notes »`, `« 3 tracés »`, `« 1 image »`,
  `« 1 question ouverte »`, `« 1 risque »`. Singuliers : `1 boîte`,
  `1 liaison`, `1 note`, `1 tracé`.
- Scène vide ou illisible : `« Croquis — planche vide »`. **Jamais** d'exception.
- `parse` tolère un bloc de code markdown autour du JSON (comme
  `ProjectCardSuggestions`), exige `{"caption":"…"}`, refuse une légende vide ou
  de plus de 240 caractères, et rend `nil` dans tous les autres cas.
- `refined` : sans `settings.modelName`, ou sur exception, ou sur timeout, ou sur
  réponse illisible → la légende **pure**. Ne lève jamais.

**Colonnes de `Board`** (à ajouter à la fin des propriétés, avant `init`) :

```swift
    /// La planche est-elle jointe au rapport ? C'est le bouton `Joindre au
    /// rapport` de l'encart de clôture de 6b (spec §7.3). Colonne neuve à
    /// valeur par défaut : migration légère, aucune version de schéma.
    var includeInReport: Bool = false

    /// Légende textuelle de la planche, produite par `BoardCaptionBuilder`
    /// depuis les libellés d'objets (spec §7.2). Persistée pour que le rapport
    /// et le dock la lisent sans relire la scène — et pour qu'un raffinement
    /// par l'assistant survive à la fermeture de l'écran.
    var caption: String = ""
```

- [ ] **Étape 1 : test qui échoue** — `Tests/BoardCaptionBuilderTests.swift`

```swift
import Testing
import Foundation
@testable import OneToOne

/// Client factice : aucun test de ce lot ne touche le réseau (programme §8).
private struct StubCaptionClient: AIClientProtocol {
    let response: String
    let throwError: Bool
    final class Journal: @unchecked Sendable { var appels = 0 }
    let journal = Journal()

    init(_ response: String, throwError: Bool = false) {
        self.response = response
        self.throwError = throwError
    }

    func send(prompt: String, settings: AppSettings) async throws -> String {
        journal.appels += 1
        if throwError { throw NSError(domain: "stub", code: -1) }
        return response
    }
}

@Suite("Atelier — légende d'une planche")
@MainActor
struct BoardCaptionBuilderTests {

    @Test("croquis : boîtes, liaisons, question et risque")
    func test_legendeCroquis() {
        let scene = RefonteDemoSeed.workshopAnnotatedTargetScene()
        let legende = BoardCaptionBuilder.caption(mode: .sketch, scene: scene)
        #expect(legende.hasPrefix("Croquis — "))
        #expect(legende.contains("6 boîtes"))
        #expect(legende.contains("Runners GitLab"))
        #expect(legende.contains("2 liaisons"))
        #expect(legende.contains("1 question ouverte"))
        #expect(legende.contains("1 risque"))
    }

    @Test("schéma : les connecteurs liés comptent comme des liaisons")
    func test_legendeSchema() {
        let legende = BoardCaptionBuilder.caption(mode: .diagram,
                                                  scene: RefonteDemoSeed.workshopDiagramScene())
        #expect(legende.hasPrefix("Schéma — "))
        #expect(legende.contains("3 boîtes"))
        #expect(legende.contains("2 liaisons"))
        #expect(!legende.contains("question"))
    }

    @Test("manuscrit : des tracés, pas des boîtes")
    func test_legendeManuscrit() {
        let legende = BoardCaptionBuilder.caption(mode: .ink,
                                                  scene: RefonteDemoSeed.workshopInkScene())
        #expect(legende.hasPrefix("Manuscrit — "))
        #expect(legende.contains("3 tracés"))
        #expect(!legende.contains("boîte"))
    }

    @Test("une scène vide ou illisible ne lève jamais")
    func test_sceneVide() {
        #expect(BoardCaptionBuilder.caption(mode: .sketch, scene: BoardScene.empty)
                == "Croquis — planche vide")
        #expect(BoardCaptionBuilder.caption(mode: .ink, scene: "{ pas du json")
                == "Manuscrit — planche vide")
        #expect(BoardCaptionBuilder.caption(mode: .diagram, scene: "")
                == "Schéma — planche vide")
    }

    @Test("l'assistant raffine la légende quand il répond du JSON strict")
    func test_raffinement() async {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        let client = StubCaptionClient("{\"caption\":\"Croquis du périmètre GitLab actuel : trois runners partagés et Jenkins en dette.\"}")
        let legende = await BoardCaptionBuilder.refined(
            mode: .sketch, scene: RefonteDemoSeed.workshopAnnotatedTargetScene(),
            settings: reglages, client: client)
        #expect(legende.contains("Jenkins en dette"))
        #expect(client.journal.appels == 1)
    }

    @Test("l'échec de l'assistant rend la légende pure, sans exception")
    func test_repliSurEchec() async {
        let reglages = AppSettings()
        reglages.modelName = "qwen3-8b"
        let enPanne = StubCaptionClient("", throwError: true)
        let repli = await BoardCaptionBuilder.refined(
            mode: .diagram, scene: RefonteDemoSeed.workshopDiagramScene(),
            settings: reglages, client: enPanne)
        #expect(repli == BoardCaptionBuilder.caption(mode: .diagram,
                                                     scene: RefonteDemoSeed.workshopDiagramScene()))

        let illisible = StubCaptionClient("désolé, je ne peux pas")
        let repli2 = await BoardCaptionBuilder.refined(
            mode: .diagram, scene: RefonteDemoSeed.workshopDiagramScene(),
            settings: reglages, client: illisible)
        #expect(repli2.hasPrefix("Schéma — "))
    }

    @Test("sans endpoint configuré, rien n'est demandé")
    func test_sansEndpoint() async {
        let reglages = AppSettings()
        reglages.modelName = ""
        let client = StubCaptionClient("{\"caption\":\"jamais lu\"}")
        let legende = await BoardCaptionBuilder.refined(
            mode: .ink, scene: RefonteDemoSeed.workshopInkScene(),
            settings: reglages, client: client)
        #expect(client.journal.appels == 0)
        #expect(legende.hasPrefix("Manuscrit — "))
    }

    @Test("les deux colonnes de Board ont un défaut")
    func test_colonnesParDefaut() {
        let planche = Board(index: 0, title: "P", mode: .sketch, t: 0)
        #expect(planche.includeInReport == false)
        #expect(planche.caption.isEmpty)
    }
}
```

- [ ] **Étape 2 : lancer, vérifier l'échec** — `swift test --filter BoardCaptionBuilderTests`.
- [ ] **Étape 3 : implémenter** `BoardCaptionBuilder.swift` + les deux colonnes de `Board`.
- [ ] **Étape 4 : `swift build`, `swift test --filter BoardCaptionBuilderTests`** — vert.
- [ ] **Étape 5 : commit** — `feat(atelier): légende de planche depuis les libellés d'objets`.

---

## Tâche 3 — `Tout exporter` et `Joindre au rapport`

**Fichiers :** créer `OneToOne/Services/Workshop/WorkshopExport+All.swift`,
`OneToOne/Services/Workshop/WorkshopReportAttachment.swift`,
`Tests/WorkshopExportAllTests.swift`, `Tests/WorkshopReportAttachmentTests.swift`.

**Interfaces produites :**

```swift
extension WorkshopExport {
    struct BundleSummary: Equatable, Sendable {
        var imageCount: Int, sceneCount: Int, folder: URL, indexPath: URL
    }
    static func folderName(meetingTitle: String, date: Date) -> String
    static func indexMarkdown(meetingTitle: String, rows: [WorkshopTimelineItem],
                              imageNames: [String: String]) -> String
    @MainActor static func exportAll(meeting: Meeting, store: BoardStore,
                                     into parent: URL) throws -> BundleSummary
}

enum WorkshopReportAttachment {
    @MainActor static func attachAll(meeting: Meeting) -> Int
    @MainActor static func isFullyAttached(meeting: Meeting) -> Bool
    static let attachedLabel = "Joint au rapport ✓"
    static let attachLabel = "Joindre au rapport"
}
```

**Règles :**

- `exportAll` crée `parent/<folderName>/`, puis pour chaque planche triée
  (`BoardOrdering.sorted`) : `NN-<titre assaini>.png` (copie de `thumbPath`,
  omise si le fichier manque) et `NN-<titre assaini>.excalidraw.json` (copie de
  `scenePath`, à défaut `BoardScene.empty`), `NN` sur deux chiffres à partir de
  `01`. Puis `index.md`. `.drawio` : **absent** (D6).
- `indexMarkdown` : titre de la réunion en `#`, puis une section par ligne de
  frise — `## mm:ss · Type — titre · trailing`, la légende en paragraphe, et
  `![titre](fichier.png)` pour une planche qui a une image. L'ordre est celui de
  `WorkshopTimelineModel.rows` : c'est le critère chantier 6 n° 5.
- `attachAll` coche `Board.includeInReport` sur **toutes** les planches et
  `SlideCapture.includeInReport` sur toutes les captures de la séance, et rend le
  nombre de lignes **changées** (0 au second appel : idempotent).
- Aucune de ces fonctions n'écrit en base : le point d'appel enregistre.

- [ ] **Étape 1 : tests qui échouent**

```swift
// Tests/WorkshopExportAllTests.swift
import Testing
import Foundation
import SwiftData
@testable import OneToOne

@Suite("Atelier — Tout exporter")
@MainActor
struct WorkshopExportAllTests {

    @Test("le dossier porte une image, une scène et un index par planche")
    func test_dossierComplet() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        let context = ModelContext(conteneur)
        let racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lot18-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        let magasin = BoardStore(recordingsRoot: racine)

        let reunion = Meeting(title: "Cible d'architecture GitLab",
                              date: Date(timeIntervalSince1970: 1_788_523_200))
        reunion.kind = .workshop
        context.insert(reunion)

        for (index, titre) in ["Périmètre actuel", "Flux réseau"].enumerated() {
            let planche = Board(index: index, title: titre, mode: .sketch,
                                t: Double(index) * 100, authorNames: "Yann")
            context.insert(planche)
            planche.meeting = reunion
            try magasin.save(scene: BoardScene.scene(boxes: [
                .init(x: 0, y: 0, width: 100, height: 40, text: titre)]),
                             board: planche, meetingStableID: reunion.ensuredStableID)
            try magasin.saveThumbnail(Data([0x89, 0x50, 0x4E, 0x47]),
                                      board: planche,
                                      meetingStableID: reunion.ensuredStableID)
            magasin.resetThumbnailClock()
        }

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(bilan.imageCount == 2)
        #expect(bilan.sceneCount == 2)

        let contenu = try FileManager.default.contentsOfDirectory(atPath: bilan.folder.path).sorted()
        #expect(contenu.contains("index.md"))
        #expect(contenu.contains { $0.hasSuffix(".png") })
        #expect(contenu.filter { $0.hasSuffix(".excalidraw.json") }.count == 2)
        let index = try String(contentsOf: bilan.indexPath, encoding: .utf8)
        #expect(index.contains("Périmètre actuel"))
        let posPerimetre = index.range(of: "Périmètre actuel")!.lowerBound
        let posFlux = index.range(of: "Flux réseau")!.lowerBound
        #expect(posPerimetre < posFlux)   // ordre du temps
        #expect(!index.contains("drawio"))
    }

    @Test("une planche sans vignette n'empêche pas l'export")
    func test_sansVignette() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        let context = ModelContext(conteneur)
        let racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lot18-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        let magasin = BoardStore(recordingsRoot: racine)
        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        let planche = Board(index: 0, title: "Sans vignette", mode: .ink, t: 0)
        context.insert(planche)
        planche.meeting = reunion

        let destination = racine.appendingPathComponent("sortie", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bilan = try WorkshopExport.exportAll(meeting: reunion, store: magasin,
                                                 into: destination)
        #expect(bilan.imageCount == 0)
        #expect(bilan.sceneCount == 1)
    }
}
```

```swift
// Tests/WorkshopReportAttachmentTests.swift
import Testing
import Foundation
import SwiftData
@testable import OneToOne

@Suite("Atelier — Joindre au rapport")
@MainActor
struct WorkshopReportAttachmentTests {

    @Test("tout est coché, et le second appel ne change rien")
    func test_idempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        let context = ModelContext(conteneur)
        let reunion = Meeting(title: "Atelier", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)

        for index in 0..<3 {
            let planche = Board(index: index, title: "P\(index)", mode: .sketch, t: Double(index))
            context.insert(planche)
            planche.meeting = reunion
        }
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"),
                                    kind: AttachmentCopyPolicy.slidesKind)
        context.insert(lot)
        lot.meeting = reunion
        let capture = SlideCapture(index: 0, capturedAt: Date(), imagePath: "/tmp/c.png")
        context.insert(capture)
        capture.attachment = lot

        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion) == false)
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 4)
        #expect(reunion.boards.allSatisfy(\.includeInReport))
        #expect(capture.includeInReport)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion))
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 0)
    }

    @Test("un atelier sans rien à joindre n'est pas « joint »")
    func test_vide() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        let context = ModelContext(conteneur)
        let reunion = Meeting(title: "Vide", date: Date())
        reunion.kind = .workshop
        context.insert(reunion)
        #expect(WorkshopReportAttachment.isFullyAttached(meeting: reunion) == false)
        #expect(WorkshopReportAttachment.attachAll(meeting: reunion) == 0)
    }
}
```

- [ ] **Étape 2 : lancer, vérifier l'échec.**
- [ ] **Étape 3 : implémenter** les deux fichiers de service.
- [ ] **Étape 4 : `swift build`, `swift test --filter "WorkshopExportAll|WorkshopReportAttachment"`** — vert.
- [ ] **Étape 5 : commit** — `feat(atelier): tout exporter en un dossier et joindre au rapport`.

---

## Tâche 4 — L'écran 6b et son routage

**Fichiers :** créer
`OneToOne/Views/Meeting/Workshop/Session/WorkshopSessionSheetView.swift` ;
modifier `MeetingSpaceRouting.swift` (+1 fonction), `MeetingSpaceView.swift`
(+1 branche), `WorkshopDock.swift` (+1 ligne), `WorkshopState.swift`
(+propriétés en fin de type), `RecetteScreen.swift` (+1 cas). Test :
`Tests/WorkshopSeedLot18Tests.swift` (routage) — le semis vient en tâche 5.

**Routage :**

```swift
    /// Vrai quand le mode Relire du type Atelier doit monter la **planche de
    /// séance** (capture `6b-atelier-planche-de-seance.png`, lot 18) au lieu du
    /// poste de pilotage.
    static func usesWorkshopReview(kind: MeetingKind,
                                   mode: MeetingScreenModel.Mode) -> Bool {
        kind == .workshop && mode == .review
    }
```

Dans `MeetingSpaceView` : une propriété calculée jumelle de `estAtelierEnSeance`

```swift
    private var estAtelierEnRelecture: Bool {
        settings.workshopEnabled
            && MeetingSpaceRouting.usesWorkshopReview(kind: meeting.kind, mode: screen.mode)
    }
```

et **une** branche, posée **avant** `screen.mode == .review` :

```swift
        } else if estAtelierEnRelecture {
            WorkshopSessionSheetView(meeting: meeting, screen: screen)
        } else if screen.mode == .review {
```

**L'écran** (largeur max 920 px, carte centrée, `ScrollView` vertical) :

- En-tête sur fond `One2OneToken.workshopBg` : `Chip("ATELIER")` en
  `One2OneToken.workshop`, titre `plexSans(15, .semibold)`,
  `MonoMeta(headerSummary(…))`, et à droite le bouton `Tout exporter`
  (secondaire, `NSOpenPanel` de choix de dossier).
- Frise : `ForEach` sur `WorkshopTimelineModel.rows(for:)`. Chaque ligne =
  `TimecodeLabel`-like sur 40 px (`MonoMeta(MeetingPlayhead.mmss(t))` dans un
  `frame(width: 40, alignment: .leading)`) + une `RefonteCard(padding: 0)` :
  aperçu de 92 px de haut (`Image(nsImage:)` depuis `previewPath`, à défaut une
  pastille de mode sur `surfaceAlt`), filet, pied
  `Text(footer)` + `Spacer` + `MonoMeta(trailing)`, et la légende
  (`plexSans(11)`, `ink3`) sous le pied quand elle existe.
- Liste vide : `WorkshopTimelineModel.emptyInvite` dans une `RefonteCard`.
- Encart de clôture : `« Tout est stocké dans le fichier de la réunion — aucun
  service externe. Export PNG, SVG ou .excalidraw si besoin. »`, un bouton
  secondaire `Décrire les planches` (raffinement IA, désactivé sans endpoint) et
  le bouton primaire teal `Joindre au rapport`, qui devient
  `Joint au rapport ✓` (désactivé) une fois tout coché.
- `Décrire les planches` et l'affichage remplissent d'abord la légende **pure**
  manquante de chaque planche (`onAppear`, sans IA, sans réseau) : une planche a
  toujours une légende, même hors ligne.

**`WorkshopState`** — en fin de type, deux propriétés et une méthode :

```swift
    /// Une opération longue de l'écran 6b est en cours (export du dossier,
    /// description des planches par l'assistant).
    var isBusy = false

    /// Remplit la légende **pure** des planches qui n'en ont pas, puis
    /// enregistre. Sans IA et sans réseau : une planche doit porter sa légende
    /// même hors ligne (spec §8, « local d'abord »).
    @discardableResult
    func fillMissingCaptions(meeting: Meeting, context: ModelContext) -> Int { … }

    /// `Décrire les planches` : raffine la légende de chaque planche par
    /// l'assistant, en repliant sur la légende pure à chaque échec.
    func describeBoards(meeting: Meeting, settings: AppSettings,
                        context: ModelContext,
                        client: AIClientProtocol = AIClient.live) async { … }
```

**`WorkshopDock`** — une ligne, sous `Text(sousTitre(planche))` :

```swift
                    if !planche.caption.isEmpty {
                        Text(planche.caption).font(.plexSans(10.5))
                            .foregroundStyle(One2OneToken.ink3).lineLimit(1)
                    }
```

**`RecetteScreen`** — un cas, plus les deux `switch` :

```swift
    /// `6b-atelier-planche-de-seance.png` — le même atelier en mode Relire.
    case atelierPlancheDeSeance = "6b"
```
`cible` → `.atelier` ; `mode` → `.review`.

- [ ] **Étape 1 : test qui échoue** — dans `Tests/WorkshopSeedLot18Tests.swift` :

```swift
    @Test("le code 6b ouvre l'atelier en mode Relire")
    func test_recette6b() {
        let ecran = RecetteScreen.from(environment: "6b")
        #expect(ecran == .atelierPlancheDeSeance)
        #expect(ecran?.cible == .atelier)
        #expect(ecran?.mode == .review)
    }

    @Test("le mode Relire de l'atelier remplace le poste de pilotage")
    func test_routage() {
        #expect(MeetingSpaceRouting.usesWorkshopReview(kind: .workshop, mode: .review))
        #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: .workshop, mode: .live))
        #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: .project, mode: .review))
        #expect(!MeetingSpaceRouting.usesWorkshopReview(kind: .oneToOne, mode: .review))
    }
```

- [ ] **Étape 2 : lancer, vérifier l'échec.**
- [ ] **Étape 3 : implémenter** la vue, le routage, le cas de recette, la ligne
      du dock, les propriétés de `WorkshopState`.
- [ ] **Étape 4 : `swift build`, `swift test --filter WorkshopSeedLot18Tests`** — vert.
- [ ] **Étape 5 : commit** — `feat(atelier): écran 6b — planche de séance, exports et rapport`.

---

## Tâche 5 — Jeu de démonstration `6b`

**Fichiers :** créer `OneToOne/Services/Debug/Seed/RefonteDemoSeed+Lot18.swift`
(extension : **aucun autre fichier de semis n'est modifié**) ; compléter
`Tests/WorkshopSeedLot18Tests.swift`.

**Contenu :**

```swift
extension RefonteDemoSeed {
    /// Les deux lignes manuscrites de la capture 6b.
    static let workshopInkLines = ["3 runners → autoscale ?", "+ VPN April à vérifier"]
    /// Le texte extrait de la capture Teams de 21:10.
    static let workshopCaptureOCR = "partage de Cléva — schéma réseau partagé"
    /// `Notes de Patrice` : les trois tracés du lot 17 **plus** les deux lignes
    /// lisibles de la capture, pour que la légende dise quelque chose.
    static func workshopInkSceneWithLines() -> String
    /// L'écran 6b complet : `seedWorkshopComplete`, puis les deux lignes du
    /// manuscrit, le texte extrait de la capture, l'épinglage de la pièce et
    /// les légendes pures de chaque planche. Idempotent.
    @discardableResult
    static func seedWorkshopSession(in context: ModelContext,
                                    store: BoardStore? = nil,
                                    root: URL? = nil) -> Meeting
}
```

- La pièce `Archi_cible_Cléva.pdf` reçoit `pinnedAtT = 300` (05:00) : sans
  timecode, elle se serait horodatée sur son heure d'import, qui n'a rien à voir
  avec la séance.
- Chaque planche reçoit `caption = BoardCaptionBuilder.caption(mode:scene:)` —
  pure, donc reproductible et hors ligne.
- Le point d'appel de recette (`MeetingCommands`, **une** ligne) appelle
  `seedWorkshopSession`. Si le fichier est hors périmètre à ce moment-là, le
  laisser sur `seedWorkshopComplete` et le documenter.

- [ ] **Étape 1 : test qui échoue** — compléter la suite :

```swift
    @Test("le semis 6b est idempotent et porte les éléments de la capture")
    func test_semis() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let conteneur = try ModelContainer(for: Schema(SchemaVersions.currentModels),
                                           configurations: config)
        let context = ModelContext(conteneur)
        let racine = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lot18-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        let magasin = BoardStore(recordingsRoot: racine)

        let reunion = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        let deuxieme = RefonteDemoSeed.seedWorkshopSession(in: context, store: magasin, root: racine)
        #expect(reunion.ensuredStableID == deuxieme.ensuredStableID)
        #expect(reunion.boards.count == 4)

        let manuscrit = reunion.boards.first { $0.mode == .ink }
        let scene = magasin.loadScene(board: manuscrit!, meetingStableID: reunion.ensuredStableID) ?? ""
        for ligne in RefonteDemoSeed.workshopInkLines { #expect(scene.contains(ligne)) }
        #expect(manuscrit!.caption.hasPrefix("Manuscrit — "))

        let capture = reunion.attachments.flatMap(\.slides).first
        #expect(capture?.ocrText == RefonteDemoSeed.workshopCaptureOCR)

        let lignes = WorkshopTimelineModel.rows(for: reunion)
        #expect(lignes.count == 6)                     // 4 planches + 1 capture + 1 pièce
        #expect(lignes.map(\.t) == lignes.map(\.t).sorted())
        #expect(lignes.allSatisfy { !$0.footer.isEmpty })
    }
```

- [ ] **Étape 2 : lancer, vérifier l'échec.**
- [ ] **Étape 3 : implémenter** le semis.
- [ ] **Étape 4 : `swift build`, `swift test --filter WorkshopSeedLot18Tests`** — vert.
- [ ] **Étape 5 : commit** — `feat(atelier): jeu de démonstration de l'écran 6b`.

---

## Tâche 6 — Rebase et câblage de `{{planches}}` (dépend du lot 15)

Le lot 15 (variable `{{planches}}`, `ReportOptionalBlocks`,
`RefonteReportVariables`, template `d9_workshop`) **n'est pas** dans la base au
démarrage : une passe d'intégration empile `#33 → 8 → 13 → 15 → 17 → recette` et
force-poussera `feat/refonte-lot-17-atelier-modes`.

- [ ] **Étape 1 :** `git fetch origin` et comparer
      `git rev-parse origin/feat/refonte-lot-17-atelier-modes` à `.lot18-base-sha`.
- [ ] **Étape 2 :** si les SHA diffèrent :
      `git rebase --onto origin/feat/refonte-lot-17-atelier-modes $(cat .lot18-base-sha)`,
      résoudre (`STATUS.md` en union, ma section en tête).
- [ ] **Étape 3 :** brancher `{{planches}}` — **additif**, sans réécrire le bloc
      du lot 15 : chaque planche cochée rend, dans l'ordre de
      `WorkshopTimelineModel.rows`, `mm:ss · Type — titre · auteur`, puis sa
      légende, puis son image en annexe. `ExportService` joint les PNG des
      planches cochées comme il joint déjà ceux des captures.
- [ ] **Étape 4 :** test — le rendu de `{{planches}}` sur la réunion semée est
      dans l'ordre du temps et cite la légende (critère chantier 6 n° 5).
- [ ] **Étape 5 :** `swift build`, `swift test`, commit
      `feat(rapport): alimenter {{planches}} depuis la frise de l'atelier`.
- [ ] **Repli :** si l'intégration n'est pas finie après les tâches 1 à 5,
      sonder toutes les 5 minutes, **45 minutes au plus**, puis livrer sans le
      câblage, documenté dans `STATUS.md` et dans le corps de la PR.

---

## Tâche 7 — Clôture

- [ ] `STATUS.md` : ma section **en tête**, datée `2026-09-08`, avec l'état, les
      écarts assumés et la prochaine action.
- [ ] `swift build` puis `swift test` **complet** — vert. L'unique échec toléré
      est `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject`
      (préexistant, horaire, 0 h–2 h) : mentionner l'heure de lancement.
- [ ] `git push -u origin feat/refonte-lot-18-planche-de-seance`.
- [ ] `gh pr create --base feat/refonte-lot-17-atelier-modes --title
      "feat(refonte): lot 18 — atelier : planche de séance et rapport"` — corps :
      critères couverts, résultat de `swift test`, ordre de fusion,
      `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] **Ne pas fusionner.**

---

## Revue du plan

**Couverture de la spec.** §7.3 liste chronologique → tâches 1 et 4 ; §7.3
encart de clôture et exports → tâches 3 et 4 ; §7.2 « l'assistant peut décrire
les planches » → tâche 2 (pur) + `Décrire les planches` (tâche 4) + ligne du
dock (tâche 4) ; §8 rapport → tâche 6 ; critère chantier 6 n° 5 → tests des
tâches 1, 3 et 6 ; D6 (`.drawio` hors v1) → assertion `!index.contains("drawio")`
et libellé de l'encart sans `.drawio`.

**Écarts assumés, à documenter dans `STATUS.md` :**

1. **`Décrire les planches`** est un bouton secondaire de l'encart de clôture,
   absent de la capture 6b : sans lui, le raffinement IA de la spec §7.2 serait
   du code mort, et le placer sur `Joindre au rapport` ferait partir une requête
   réseau depuis une action que la spec veut locale.
2. **`9 éléments produits`** de la capture n'est pas atteignable avec le jeu de
   démonstration (4 planches + 1 capture + 1 pièce = **6**). Le compte est
   calculé honnêtement plutôt que codé en dur.
3. **Vignettes de planches absentes du semis** : le semis n'écrit pas de PNG de
   planche (il faudrait dessiner), les cartes montrent donc la pastille de mode.
   Sans recette graphique dans ce lot, c'est sans conséquence.
