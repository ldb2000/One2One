# Lot 15 — Rapport : blocs optionnels, chaîne de citation, récaps

> **Pour les agents :** SOUS-COMPÉTENCE REQUISE — `superpowers:executing-plans` (exécution
> en session, points de contrôle par tâche). Les étapes sont des cases à cocher (`- [ ]`).

**Objectif :** donner aux gabarits de rapport cinq blocs optionnels (pièces épinglées,
captures jointes, planches, engagements, mises à jour de fiche projet acceptées), rendre
tout timecode du rapport cliquable dans l'app et inerte à l'export, et exécuter au moment
de l'envoi les trois cases du pied du tiroir Ressources.

**Architecture :** trois nouveaux fichiers purs dans `Services/Report/`
(`ReportOptionalBlocks`, `CitationLinker`, `ReportSendPreparation`) + un fichier de
variables (`Services/ReportVariables+Refonte.swift`). Les blocs ont **une** source de
sélection et deux rendus (markdown pour le prompt, HTML pour le rapport) : la variable
`{{…}}` alimente l'IA, le bloc HTML annexe est déterministe et ne dépend d'aucun modèle.
L'audience de confidentialité descend du `ReportTemplateKind` et traverse prompt, HTML,
export et récap par la seule `ConfidentialityFilter.isExportable`.

**Pile technique :** Swift 6, SwiftUI, SwiftData (migration légère, aucune version de
schéma), Swift Testing (`@Test`/`@Suite`) pour les tests neufs, XCTest pour les suites
existantes.

**Spécification :** `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §8 (transverse),
§4.1 (pied « À L'ENVOI DU RAPPORT »), §4.2, §5.3, §3.3, §6.2, §7.3, critères chantier 3 n° 3
et chantier 6 n° 5. Plan directeur : `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md` §5 « Lot 15 ».

## Contraintes globales

- Branche `feat/refonte-lot-15-rapport`, base `origin/feat/refonte-lot-7-captures`
  (SHA dans `.lot15-base-sha`). **2 509 tests** sur la base (1 041 XCTest + 1 468 Swift Testing).
- Commentaires et libellés d'interface en **français**, symboles en anglais.
- Énums persistées en `…Raw: String` + wrapper calculé.
- **Au plus une** colonne JSON à défaut sur `Meeting` (`acceptedProjectUpdatesJSON`).
  Aucune nouvelle version de schéma.
- Fichiers réservés : `Services/Report/**`, `Services/ReportTemplating.swift`,
  `Services/ReportVariables+Refonte.swift`, `Services/BuiltInTemplates.swift`,
  `Services/ExportService.swift`, `Services/AIReportService.swift` (assemblage seulement),
  `Views/Settings/ReportTemplateEditorView.swift`, `Views/Meeting/Spaces/MeetingReportSpace.swift`,
  `Services/QuickLaunchURLHandler.swift`, `Models/ReportTemplate.swift`, tests.
  Interdits : `Views/Meeting/OneOnOne/**`, `Services/OneOnOne/**`, `Views/Capture/**`,
  `Services/Capture/**`, `Workshop/**`, `Rail/**`, `Notes/**`, `Review/**`, `Resources/**`,
  `Session/**`, `MeetingView.swift` ; `MeetingTopChromeBar.swift` seulement pour la liste
  `compatibleTemplates` ; `Project/**` seulement par l'extension `ProjectCardSuggestions+Log.swift`
  (plus le câblage minimal de la feuille, documenté comme écart).
- `swift build` avant chaque commit, `swift test` complet vert avant la PR.
- **Aucune recette graphique, aucun lancement d'application, aucun appel réseau.**
- Commits conventionnels, `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

## Structure des fichiers

| Fichier | Responsabilité |
| --- | --- |
| `Models/ReportTemplate.swift` (modifié) | cas `escalade` de `ReportTemplateKind` + `audience` par catégorie |
| `Services/Report/ReportOptionalBlocks.swift` (créé) | sélection + ordre + libellés des 5 blocs, rendus markdown **et** HTML |
| `Services/Report/CitationLinker.swift` (créé) | URL `onetoone://` et post-traitement des `<code>mm:ss</code>` des blocs de l'app |
| `Services/Report/ReportSendPreparation.swift` (créé) | annexes, destinataires, versement projet — **au moment de l'envoi** |
| `Services/ReportVariables+Refonte.swift` (créé) | les 5 variables `{{…}}` du lot 15, branchées dans `TemplateVariableResolver` |
| `Services/ReportTemplating.swift` (modifié) | `audience` en paramètre de `resolve`, délégation au fichier ci-dessus |
| `Services/AIReportService.swift` (modifié) | audience du gabarit, injection des blocs optionnels absents du corps |
| `Services/Report/ReportHTMLBuilder.swift` (modifié) | annexes HTML des 5 blocs, citations, audience du gabarit |
| `Services/BuiltInTemplates.swift` (modifié) | `revisions: [String: Int]`, révisions d1/d2/d3/d4/d5/d9, nouveau `d11_escalade` |
| `Services/ExportService.swift` (modifié) | appelle `ReportSendPreparation` dans `composeMeetingMail` |
| `Services/QuickLaunchURLHandler.swift` (modifié) | décode `onetoone://meeting/<uuid>?t=…&note=…` |
| `Services/Project/ProjectCardSuggestions+Log.swift` (créé) | trace des mises à jour de fiche acceptées, sur `Meeting` |
| `Models/OtherModels.swift` (modifié) | `acceptedProjectUpdatesJSON` (une colonne) |
| `Views/Settings/ReportTemplateEditorView.swift` (modifié) | palette de variables complétée |
| `Views/Meeting/Spaces/MeetingReportSpace.swift` (modifié) | invite quand un bloc optionnel est vide |
| `Views/Meeting/MeetingReportPreview.swift` (modifié) | délégué de navigation pour les liens `onetoone://` |
| `Views/Meeting/MeetingTopChromeBar.swift` (modifié, 3 lignes) | Escalade prioritaire pour `.oneToOne`/`.manager` |
| `Tests/ReportOptionalBlocksTests.swift` (créé) | les 5 blocs, critères chantier 3 n° 3 et chantier 6 n° 5 |
| `Tests/CitationLinkerTests.swift` (créé) | liens internes, texte à l'export, faux positifs |
| `Tests/ReportAudienceTests.swift` (créé) | table `ReportTemplateKind` → `Audience`, bout en bout par gabarit |
| `Tests/ReportSendPreparationTests.swift` (créé) | annexes, destinataires, versement projet |
| `Tests/BuiltInTemplatesTests.swift` (modifié) | révisions versionnées, édition utilisateur préservée |

---

### Tâche 1 : `ReportTemplateKind.escalade` et l'audience par gabarit

**Fichiers :**
- Modifier : `OneToOne/Models/ReportTemplate.swift`
- Test : `Tests/ReportAudienceTests.swift` (créé)

**Interfaces :**
- Produit : `ReportTemplateKind.escalade` ; `ReportTemplateKind.audience: Audience` ;
  `ReportAudience.forTemplate(_ template: ReportTemplate?, meeting: Meeting) -> Audience`.

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/ReportAudienceTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Audience du rapport — une par catégorie de gabarit")
struct ReportAudienceTests {

    @Test("La table catégorie → audience est exhaustive et sans surprise")
    func tableExhaustive() {
        let attendu: [ReportTemplateKind: Audience] = [
            .general: .projectTeam,
            .oneToOne: .collaborator,
            .manager: .manager,
            .copil: .projectTeam,
            .cosui: .projectTeam,
            .codir: .projectTeam,
            .preparation: .projectTeam,
            .restitution: .projectTeam,
            .workshop: .projectTeam,
            .metier: .projectTeam,
            .initiative: .projectTeam,
            .custom: .projectTeam,
            .escalade: .hr
        ]
        // Toute catégorie ajoutée sans décision d'audience fait tomber ce test.
        #expect(Set(attendu.keys) == Set(ReportTemplateKind.allCases))
        for (kind, audience) in attendu {
            #expect(kind.audience == audience, "\(kind.rawValue)")
        }
    }

    @Test("Sans gabarit, l'audience retombe sur le type de réunion")
    @MainActor
    func sansGabarit() throws {
        let reunion = Meeting(title: "1:1", date: Date())
        reunion.kind = .oneToOne
        #expect(ReportAudience.forTemplate(nil, meeting: reunion) == .collaborator)
        reunion.kind = .workshop
        #expect(ReportAudience.forTemplate(nil, meeting: reunion) == .projectTeam)
    }

    @Test("Le gabarit d'escalade parle aux RH, même sur un 1:1")
    @MainActor
    func gabaritEscalade() throws {
        let reunion = Meeting(title: "1:1", date: Date())
        reunion.kind = .oneToOne
        let gabarit = ReportTemplate(name: "Escalade", kind: .escalade)
        #expect(ReportAudience.forTemplate(gabarit, meeting: reunion) == .hr)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportAudienceTests` → échec de compilation
(« type 'ReportTemplateKind' has no member 'escalade' »).

- [ ] **Étape 3 : implémenter**

Dans `Models/ReportTemplate.swift`, ajouter `case escalade` à l'énum (après `workshop`),
son `label` (`"Escalade"`), son `sfSymbol` (`"exclamationmark.shield"`), puis :

```swift
extension ReportTemplateKind {

    /// À qui le rapport de cette catégorie s'adresse (spec §8 : « filtre de
    /// confidentialité unique »). L'audience n'est pas la règle de sortie —
    /// celle-là vit dans `ConfidentialityFilter.isExportable` — c'est son
    /// paramètre, et le gabarit choisi est ce qui la détermine : générer un
    /// rapport « Escalade » depuis un 1:1 doit emporter les lignes escaladées
    /// et laisser celles qui n'étaient que partagées.
    ///
    /// Table exhaustive et sans `default` : une catégorie ajoutée doit obliger
    /// à trancher, jamais retomber sur l'audience la plus large.
    var audience: Audience {
        switch self {
        case .oneToOne: return .collaborator
        case .manager:  return .manager
        case .escalade: return .hr
        case .general, .copil, .cosui, .codir, .preparation,
             .restitution, .workshop, .metier, .initiative, .custom:
            return .projectTeam
        }
    }
}

/// L'audience effective d'une génération de rapport : celle du gabarit choisi,
/// ou celle du type de réunion quand aucun gabarit ne l'est.
enum ReportAudience {
    static func forTemplate(_ template: ReportTemplate?, meeting: Meeting) -> Audience {
        template?.kind.audience ?? ConfidentialityFilter.audience(for: meeting.kind)
    }
}
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportAudienceTests` → 3 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Models/ReportTemplate.swift Tests/ReportAudienceTests.swift
git commit -m "feat(rapport): catégorie Escalade et audience par gabarit"
```

---

### Tâche 2 : l'audience du gabarit traverse prompt et HTML

**Fichiers :**
- Modifier : `OneToOne/Services/AIReportService.swift` (`assembleTemplatePrompt` seulement)
- Modifier : `OneToOne/Services/Report/ReportHTMLBuilder.swift` (`build`, `renderNotesBlock`)
- Test : `Tests/ReportAudienceTests.swift`

**Interfaces :**
- Consomme : `ReportAudience.forTemplate(_:meeting:)` (tâche 1).
- Produit : `ReportHTMLBuilder.build(meeting:template:includeTranscript:managerName:managerRole:mode:)`
  inchangé en signature ; l'audience est dérivée du `template` reçu.

- [ ] **Étape 1 : écrire le test rouge**

Ajouter à `Tests/ReportAudienceTests.swift` :

```swift
    /// Test rouge **avant** câblage : aujourd'hui le HTML et le prompt
    /// dérivent l'audience du `MeetingKind`, donc une note `escalated` d'un
    /// 1:1 est écartée même sous le gabarit Escalade — c'est ce que ce test
    /// refuse.
    @Test("Une ligne escaladée sort dans l'export Escalade et nulle part ailleurs")
    @MainActor
    func ligneEscaladeeSeulementEnEscalade() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: cfg)
        let ctx = ModelContext(container)

        let personne = Collaborator(name: "Marine LEROY")
        ctx.insert(personne)
        let reunion = Meeting(title: "1:1 Marine", date: Date())
        reunion.kind = .oneToOne
        reunion.participants = [personne]
        reunion.summary = "## Sujets\n\nLa séance a porté sur la charge."
        ctx.insert(reunion)

        let privee = MeetingNote(t: 60, text: "DOUTE PERSONNEL", visibility: .private)
        privee.meeting = reunion
        let escaladee = MeetingNote(t: 120, text: "SIGNAL RH", visibility: .escalated)
        escaladee.meeting = reunion
        let partagee = MeetingNote(t: 180, text: "POINT PARTAGE", visibility: .shared)
        partagee.meeting = reunion
        ctx.insert(privee); ctx.insert(escaladee); ctx.insert(partagee)
        try ctx.save()

        let collab = ReportTemplate(name: "1:1 Collaborateur", kind: .oneToOne)
        let escalade = ReportTemplate(name: "Escalade", kind: .escalade)
        ctx.insert(collab); ctx.insert(escalade)
        try ctx.save()

        let htmlCollab = ReportHTMLBuilder.build(meeting: reunion, template: collab,
                                                 includeTranscript: false)
        #expect(!htmlCollab.contains("DOUTE PERSONNEL"))
        #expect(!htmlCollab.contains("SIGNAL RH"))
        #expect(htmlCollab.contains("POINT PARTAGE"))

        let htmlEscalade = ReportHTMLBuilder.build(meeting: reunion, template: escalade,
                                                   includeTranscript: false)
        #expect(!htmlEscalade.contains("DOUTE PERSONNEL"))
        #expect(htmlEscalade.contains("SIGNAL RH"))
        #expect(!htmlEscalade.contains("POINT PARTAGE"))

        let promptCollab = AIReportService.assembleTemplatePrompt(meeting: reunion, in: ctx,
                                                                  template: collab)
        #expect(!promptCollab.contains("DOUTE PERSONNEL"))
        #expect(!promptCollab.contains("SIGNAL RH"))
        let promptEscalade = AIReportService.assembleTemplatePrompt(meeting: reunion, in: ctx,
                                                                    template: escalade)
        #expect(!promptEscalade.contains("DOUTE PERSONNEL"))
        #expect(promptEscalade.contains("SIGNAL RH"))
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportAudienceTests` → `ligneEscaladeeSeulementEnEscalade` échoue :
le HTML Escalade ne contient pas `SIGNAL RH` (audience `.collaborator` déduite du type).

- [ ] **Étape 3 : implémenter**

Dans `ReportHTMLBuilder.build`, remplacer l'appel `renderNotesBlock(meeting: meeting)` par
`renderNotesBlock(meeting: meeting, audience: audience)` où
`let audience = ReportAudience.forTemplate(template, meeting: meeting)` est calculé en tête,
et dans `renderNotesBlock` remplacer
`let audience = ConfidentialityFilter.audience(for: meeting.kind)` par le paramètre.

Dans `AIReportService.assembleTemplatePrompt`, remplacer
`audience: ConfidentialityFilter.audience(for: meeting.kind)` par
`audience: ReportAudience.forTemplate(template, meeting: meeting)`.

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportAudienceTests` puis `swift test --filter ReportHTMLBuilderTests`
et `--filter ConfidentialityFilterTests` → verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/AIReportService.swift OneToOne/Services/Report/ReportHTMLBuilder.swift Tests/ReportAudienceTests.swift
git commit -m "feat(rapport): l'audience de confidentialité descend du gabarit"
```

---

### Tâche 3 : bloc « pièces épinglées » (critère chantier 3 n° 3)

**Fichiers :**
- Créer : `OneToOne/Services/Report/ReportOptionalBlocks.swift`
- Test : `Tests/ReportOptionalBlocksTests.swift` (créé)

**Interfaces :**
- Produit :
  ```swift
  enum ReportOptionalBlocks {
      struct PinnedPiece: Equatable { var t: Double; var name: String; var page: Int?; var stableID: UUID? }
      static func pinnedPieces(of meeting: Meeting) -> [PinnedPiece]
      static func pinnedMarkdown(_ pieces: [PinnedPiece]) -> String
      static func pinnedHTML(_ pieces: [PinnedPiece]) -> String
      static let pinnedTitle = "Pièces épinglées"
      static let pinnedEmptyInvite = "Aucune pièce épinglée — épinglez depuis Ressources."
  }
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/ReportOptionalBlocksTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("Blocs optionnels du rapport")
@MainActor
struct ReportOptionalBlocksTests {

    private func contexte() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: cfg))
    }

    private func piece(_ nom: String, t: Double?, in reunion: Meeting,
                       _ ctx: ModelContext) -> MeetingAttachment {
        let p = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/\(nom)"))
        p.pinnedAtT = t
        p.meeting = reunion
        ctx.insert(p)
        return p
    }

    @Test("Les pièces épinglées sortent triées par timecode, les autres pas du tout")
    func pieceEpingleeTrieeParTimecode() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        _ = piece("Annexe_technique.pdf", t: 728, in: reunion, ctx)
        _ = piece("Chiffrage_Marine_v3.xlsx", t: 252, in: reunion, ctx)
        _ = piece("Brouillon.txt", t: nil, in: reunion, ctx)
        try ctx.save()

        let pieces = ReportOptionalBlocks.pinnedPieces(of: reunion)
        #expect(pieces.map(\.name) == ["Chiffrage_Marine_v3.xlsx", "Annexe_technique.pdf"])
        #expect(pieces.map(\.t) == [252, 728])
    }

    /// Critère d'acceptation n° 3 du chantier 3 : « une pièce épinglée est
    /// citée automatiquement dans le rapport » — avec son timecode.
    @Test("Le markdown cite la pièce avec son timecode et sa page")
    func markdownCiteTimecodeEtPage() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let p = piece("Chiffrage_Marine_v3.xlsx", t: 252, in: reunion, ctx)
        // La page vit dans la puce `◫ … · p.n` écrite par le lot 6 dans la
        // note qui cite la pièce : c'est là qu'on va la relire.
        let note = MeetingNote(t: 252, text: "Le chiffrage annonce 21 000 € ◫ Chiffrage_Marine_v3 · p.2")
        note.meeting = reunion
        note.sourceRef = SourceRef(kind: .capture, stableID: p.ensuredStableID, t: 252)
        ctx.insert(note)
        try ctx.save()

        let md = ReportOptionalBlocks.pinnedMarkdown(ReportOptionalBlocks.pinnedPieces(of: reunion))
        #expect(md.contains("04:12"))
        #expect(md.contains("Chiffrage_Marine_v3.xlsx"))
        #expect(md.contains("p.2"))
    }

    @Test("Un bloc vide ne rend rien du tout")
    func blocVideRendVide() throws {
        #expect(ReportOptionalBlocks.pinnedMarkdown([]).isEmpty)
        #expect(ReportOptionalBlocks.pinnedHTML([]).isEmpty)
    }

    @Test("Le HTML porte le timecode en <code> pour que la citation le trouve")
    func htmlPorteLeTimecodeEnCode() {
        let html = ReportOptionalBlocks.pinnedHTML([
            .init(t: 252, name: "Chiffrage_Marine_v3.xlsx", page: 2, stableID: nil)
        ])
        #expect(html.contains("<code>04:12</code>"))
        #expect(html.contains("Pièces épinglées"))
        #expect(html.contains("p.2"))
    }
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« cannot find 'ReportOptionalBlocks' in scope »).

- [ ] **Étape 3 : implémenter**

Créer `OneToOne/Services/Report/ReportOptionalBlocks.swift`. Les collecteurs sont
`@MainActor` (ils lisent des `@Model`), les rendus sont purs et prennent les structures.
`pageDeLaPuce` relit la page dans la puce du lot 6 via une expression régulière
` · p.(\d+)` sur les notes dont le `sourceRef` désigne la pièce.

```swift
import Foundation
import SwiftData

/// Les cinq blocs optionnels des gabarits de rapport (spec §8 : « les templates
/// existants restent ; ils gagnent des blocs optionnels — pièces épinglées,
/// captures jointes, planches d'atelier, engagements réciproques (1:1), mises à
/// jour de fiche projet acceptées »).
///
/// **Une** sélection, **deux** rendus. La variable `{{…}}` injecte du markdown
/// dans le prompt pour que le modèle sache citer ; le bloc HTML est une annexe
/// déterministe du rapport, écrite sans lui. Un seul rendu n'aurait pas suffi :
/// un rapport dont les pièces ne figurent que si le modèle a bien voulu les
/// reprendre ne satisfait pas le critère n° 3 du chantier 3.
@MainActor
enum ReportOptionalBlocks {

    // MARK: - Pièces épinglées

    struct PinnedPiece: Equatable {
        var t: Double
        var name: String
        /// Page citée, quand la puce du lot 6 en mentionne une.
        var page: Int?
        var stableID: UUID?
    }

    static let pinnedTitle = "Pièces épinglées"
    static let pinnedEmptyInvite = "Aucune pièce épinglée — épinglez depuis Ressources."

    /// Les pièces `pinnedAtT != nil`, dans l'ordre du temps.
    /// `Meeting.pinnedAttachments` (lot 6) est la source de l'ordre : la
    /// dupliquer ici aurait fait deux tris à tenir en phase.
    static func pinnedPieces(of meeting: Meeting) -> [PinnedPiece] {
        meeting.pinnedAttachments.map { piece in
            PinnedPiece(t: piece.pinnedAtT ?? 0,
                        name: piece.fileName,
                        page: citedPage(of: piece, in: meeting),
                        stableID: piece.stableID)
        }
    }

    private static let pageMotif = try! NSRegularExpression(pattern: #"·\s*p\.(\d+)"#)

    /// La page citée dans la puce `◫ <nom> · p.n` que le lot 6 écrit dans la
    /// note. Elle n'est pas persistée sur la pièce — la relire dans la note
    /// évite une colonne de plus pour une information qui n'existe que parce
    /// qu'on a cité la pièce à cet endroit.
    private static func citedPage(of piece: MeetingAttachment, in meeting: Meeting) -> Int? {
        guard let cible = piece.stableID else { return nil }
        let notes = meeting.timedNotes
            .filter { $0.sourceRef?.stableID == cible }
            .sorted { $0.t < $1.t }
        for note in notes {
            let ns = note.text as NSString
            guard let m = pageMotif.firstMatch(in: note.text,
                                               range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges == 2,
                  let page = Int(ns.substring(with: m.range(at: 1))), page > 0
            else { continue }
            return page
        }
        return nil
    }

    /// `- 04:12 · Chiffrage_Marine_v3.xlsx · p.2`
    nonisolated static func pinnedMarkdown(_ pieces: [PinnedPiece]) -> String {
        guard !pieces.isEmpty else { return "" }
        return pieces.map { piece in
            var ligne = "- \(MeetingPlayhead.mmss(piece.t)) · \(piece.name)"
            if let page = piece.page { ligne += " · p.\(page)" }
            return ligne
        }.joined(separator: "\n")
    }

    nonisolated static func pinnedHTML(_ pieces: [PinnedPiece]) -> String {
        guard !pieces.isEmpty else { return "" }
        var html = "<h2>\(pinnedTitle)</h2>\n<ul>\n"
        for piece in pieces {
            var ligne = "<li><code>\(MeetingPlayhead.mmss(piece.t))</code> \(escape(piece.name))"
            if let page = piece.page { ligne += " · p.\(page)" }
            html += ligne + "</li>\n"
        }
        html += "</ul>\n"
        return html
    }

    // MARK: - Échappement

    nonisolated static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` → 4 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportOptionalBlocks.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "feat(rapport): bloc des pièces épinglées avec timecode et page"
```

---

### Tâche 4 : bloc « captures jointes »

**Fichiers :**
- Modifier : `OneToOne/Services/Report/ReportOptionalBlocks.swift`
- Test : `Tests/ReportOptionalBlocksTests.swift`

**Interfaces :**
- Produit :
  ```swift
  struct CaptureEntry: Equatable { var t: Double?; var index: Int; var firstOCRLine: String; var imagePath: String }
  static func captures(of meeting: Meeting) -> [CaptureEntry]
  nonisolated static func capturesMarkdown(_ entries: [CaptureEntry]) -> String
  nonisolated static func capturesHTML(_ entries: [CaptureEntry], embedImages: Bool) -> String
  static let capturesTitle = "Captures jointes"
  static let capturesEmptyInvite = "Aucune capture jointe — cochez « Joindre au rapport » dans la bande de captures."
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportOptionalBlocksTests.swift` :

```swift
    @Test("Seules les captures cochées « Joindre au rapport » entrent dans le bloc")
    func capturesSeulementCochees() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        let lot = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/slides"), kind: "slides")
        lot.meeting = reunion
        ctx.insert(lot)

        let cochee = SlideCapture(index: 1, capturedAt: Date(), imagePath: "/tmp/c1.png")
        cochee.t = 305
        cochee.includeInReport = true
        cochee.ocrText = "Architecture cible\nDeux zones réseau"
        cochee.attachment = lot
        let ignoree = SlideCapture(index: 2, capturedAt: Date(), imagePath: "/tmp/c2.png")
        ignoree.t = 400
        ignoree.includeInReport = false
        ignoree.attachment = lot
        ctx.insert(cochee); ctx.insert(ignoree)
        try ctx.save()

        let entrees = ReportOptionalBlocks.captures(of: reunion)
        #expect(entrees.count == 1)
        #expect(entrees[0].firstOCRLine == "Architecture cible")

        let md = ReportOptionalBlocks.capturesMarkdown(entrees)
        #expect(md.contains("05:05"))
        #expect(md.contains("Architecture cible"))
        #expect(!md.contains("Deux zones réseau"))
    }

    @Test("Une capture hors enregistrement n'invente pas de timecode")
    func captureSansTimecode() {
        let md = ReportOptionalBlocks.capturesMarkdown([
            .init(t: nil, index: 3, firstOCRLine: "Sans horloge", imagePath: "/tmp/c3.png")
        ])
        #expect(!md.contains("00:00"))
        #expect(md.contains("Capture 3"))
        #expect(md.contains("Sans horloge"))
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« type 'ReportOptionalBlocks' has no member 'captures' »).

- [ ] **Étape 3 : implémenter**

Ajouter dans `ReportOptionalBlocks.swift` :

```swift
    // MARK: - Captures jointes

    struct CaptureEntry: Equatable {
        /// `nil` pour une capture prise hors enregistrement : la spec du lot 7
        /// interdit de lui coller `00:00`, qui désignerait un instant où rien
        /// ne s'est passé.
        var t: Double?
        var index: Int
        var firstOCRLine: String
        var imagePath: String
    }

    static let capturesTitle = "Captures jointes"
    static let capturesEmptyInvite =
        "Aucune capture jointe — cochez « Joindre au rapport » dans la bande de captures."

    /// Les captures cochées `includeInReport`, dans l'ordre du temps puis de
    /// l'index (une capture sans `t` passe après celles qui en ont un).
    static func captures(of meeting: Meeting) -> [CaptureEntry] {
        meeting.attachments
            .flatMap(\.slides)
            .filter(\.includeInReport)
            .sorted { ($0.t ?? .greatestFiniteMagnitude, $0.index)
                    < ($1.t ?? .greatestFiniteMagnitude, $1.index) }
            .map { capture in
                CaptureEntry(t: capture.t,
                             index: capture.index,
                             firstOCRLine: firstLine(capture.ocrText),
                             imagePath: capture.imagePath)
            }
    }

    nonisolated static func capturesMarkdown(_ entries: [CaptureEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            var ligne = "- \(entry.t.map(MeetingPlayhead.mmss) ?? "Capture \(entry.index)")"
            if entry.t != nil { ligne += " · Capture \(entry.index)" }
            if !entry.firstOCRLine.isEmpty { ligne += " · \(entry.firstOCRLine)" }
            return ligne
        }.joined(separator: "\n")
    }

    /// `embedImages` : l'image en annexe, en `data:` URI. Le rendu d'aperçu la
    /// veut ; le prompt et l'export mail Outlook non — un base64 de plusieurs
    /// centaines de kilooctets dans un corps de mail ne passe aucun filtre.
    nonisolated static func capturesHTML(_ entries: [CaptureEntry],
                                          embedImages: Bool) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(capturesTitle)</h2>\n<ul>\n"
        for entry in entries {
            var ligne = "<li>"
            if let t = entry.t { ligne += "<code>\(MeetingPlayhead.mmss(t))</code> " }
            ligne += "Capture \(entry.index)"
            if !entry.firstOCRLine.isEmpty { ligne += " · \(escape(entry.firstOCRLine))" }
            ligne += "</li>\n"
            html += ligne
        }
        html += "</ul>\n"
        if embedImages {
            for entry in entries {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: entry.imagePath))
                else { continue }
                html += "<div><img src=\"data:image/png;base64,\(data.base64EncodedString())\""
                     + " style=\"max-width:100%;border-radius:6px;\" /></div>\n"
            }
        }
        return html
    }

    nonisolated static func firstLine(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` → 6 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportOptionalBlocks.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "feat(rapport): bloc des captures cochées avec OCR en tête"
```

---

### Tâche 5 : bloc « planches » (critère chantier 6 n° 5)

**Fichiers :**
- Modifier : `OneToOne/Services/Report/ReportOptionalBlocks.swift`
- Test : `Tests/ReportOptionalBlocksTests.swift`

**Interfaces :**
- Produit :
  ```swift
  struct BoardEntry: Equatable { var t: Double; var title: String; var mode: String; var authors: String; var thumbPath: String }
  static func boards(of meeting: Meeting) -> [BoardEntry]
  nonisolated static func boardsMarkdown(_ entries: [BoardEntry]) -> String
  nonisolated static func boardsHTML(_ entries: [BoardEntry]) -> String
  static let boardsTitle = "Planches"
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportOptionalBlocksTests.swift` :

```swift
    /// Critère d'acceptation n° 5 du chantier 6 : « le rapport d'atelier
    /// contient les planches dans l'ordre du temps ». Trois planches insérées
    /// à contretemps : l'ordre de la relation SwiftData ne garantit rien.
    @Test("Les trois planches sortent dans l'ordre du temps, pas de l'insertion")
    func planchesDansLOrdreDuTemps() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        for (index, (titre, t, mode)) in [
            ("Zones réseau", 900.0, BoardMode.diagram),
            ("Premier jet", 120.0, BoardMode.sketch),
            ("Notes manuscrites", 450.0, BoardMode.ink)
        ].enumerated() {
            let planche = Board(index: index, title: titre, mode: mode, t: t,
                                authorNames: "Laurent DEBERTI")
            planche.meeting = reunion
            ctx.insert(planche)
        }
        try ctx.save()

        let entrees = ReportOptionalBlocks.boards(of: reunion)
        #expect(entrees.map(\.title) == ["Premier jet", "Notes manuscrites", "Zones réseau"])
        #expect(entrees.map(\.t) == [120, 450, 900])

        let md = ReportOptionalBlocks.boardsMarkdown(entrees)
        let positions = ["Premier jet", "Notes manuscrites", "Zones réseau"]
            .compactMap { md.range(of: $0)?.lowerBound }
        #expect(positions.count == 3)
        #expect(positions == positions.sorted())
        #expect(md.contains("02:00"))
        #expect(md.contains("Croquis"))
        #expect(md.contains("Laurent DEBERTI"))
    }

    @Test("Sans planche, la variable existe et rend vide")
    func planchesVides() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Atelier", date: Date())
        ctx.insert(reunion)
        try ctx.save()
        #expect(ReportOptionalBlocks.boards(of: reunion).isEmpty)
        #expect(ReportOptionalBlocks.boardsMarkdown([]).isEmpty)
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« has no member 'boards' »).

- [ ] **Étape 3 : implémenter**

```swift
    // MARK: - Planches

    struct BoardEntry: Equatable {
        var t: Double
        var title: String
        var mode: String
        var authors: String
        var thumbPath: String
    }

    static let boardsTitle = "Planches"
    static let boardsEmptyInvite = "Aucune planche — le type Atelier en produit."

    /// Les planches de la séance **dans l'ordre du temps** (critère n° 5 du
    /// chantier 6). L'ordre de `Meeting.boards` n'est pas garanti par
    /// SwiftData, et `index` est un rang d'affichage que le réordonnancement
    /// du dock (lot 16) peut faire diverger de la chronologie.
    ///
    /// La légende textuelle générée par l'assistant est au lot 18 : ici le
    /// bloc rend ce que la base sait déjà — titre, mode, auteur, vignette.
    static func boards(of meeting: Meeting) -> [BoardEntry] {
        meeting.boards
            .sorted { ($0.t, $0.index) < ($1.t, $1.index) }
            .map { planche in
                BoardEntry(t: planche.t,
                           title: planche.title,
                           mode: planche.mode.label,
                           authors: planche.authorNames,
                           thumbPath: planche.thumbPath)
            }
    }

    nonisolated static func boardsMarkdown(_ entries: [BoardEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            let titre = entry.title.isEmpty ? "Planche sans titre" : entry.title
            var ligne = "- \(MeetingPlayhead.mmss(entry.t)) · \(titre) · \(entry.mode)"
            if !entry.authors.isEmpty { ligne += " · \(entry.authors)" }
            return ligne
        }.joined(separator: "\n")
    }

    nonisolated static func boardsHTML(_ entries: [BoardEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(boardsTitle)</h2>\n<ul>\n"
        for entry in entries {
            let titre = entry.title.isEmpty ? "Planche sans titre" : entry.title
            var ligne = "<li><code>\(MeetingPlayhead.mmss(entry.t))</code> "
                + "\(escape(titre)) · \(escape(entry.mode))"
            if !entry.authors.isEmpty { ligne += " · \(escape(entry.authors))" }
            ligne += "</li>\n"
            html += ligne
        }
        html += "</ul>\n"
        return html
    }
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` → 8 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportOptionalBlocks.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "feat(rapport): bloc des planches dans l'ordre du temps"
```

---

### Tâche 6 : bloc « engagements » (1:1, filtré par audience)

**Fichiers :**
- Modifier : `OneToOne/Services/Report/ReportOptionalBlocks.swift`
- Test : `Tests/ReportOptionalBlocksTests.swift`

**Interfaces :**
- Produit :
  ```swift
  struct CommitmentEntry: Equatable {
      var sideTitle: String; var text: String; var dueAt: Date?
      var state: CommitmentState; var deferrals: Int
  }
  static func commitments(of meeting: Meeting, in context: ModelContext, audience: Audience) -> [CommitmentEntry]
  nonisolated static func commitmentsMarkdown(_ entries: [CommitmentEntry]) -> String
  nonisolated static func commitmentsHTML(_ entries: [CommitmentEntry]) -> String
  static let commitmentsTitle = "Engagements"
  static let commitmentsPrivacyNotice = "Les notes privées ne sont jamais incluses."
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportOptionalBlocksTests.swift` :

```swift
    @Test("Les engagements sortent par côté, l'engagement privé jamais")
    func engagementsParCoteSansPrive() throws {
        let ctx = try contexte()
        let personne = Collaborator(name: "Marine LEROY")
        ctx.insert(personne)
        let fil = OneOnOneThread(collaborator: personne, myRole: .manager)
        ctx.insert(fil)
        let reunion = Meeting(title: "1:1 Marine", date: Date())
        reunion.kind = .oneToOne
        reunion.participants = [personne]
        ctx.insert(reunion)

        let mien = Commitment(text: "Ouvrir le poste", ownerSide: .manager, visibility: .shared)
        let sien = Commitment(text: "Livrer la maquette", ownerSide: .collaborator,
                              state: .kept, visibility: .shared)
        let manque = Commitment(text: "Relire l'ADR", ownerSide: .collaborator,
                                state: .missed, visibility: .shared)
        let secret = Commitment(text: "SUJET SENSIBLE", ownerSide: .manager, visibility: .private)
        for e in [mien, sien, manque, secret] {
            e.thread = fil
            e.promisedInMeeting = reunion
            ctx.insert(e)
        }
        try ctx.save()

        let entrees = ReportOptionalBlocks.commitments(of: reunion, in: ctx,
                                                        audience: .collaborator)
        #expect(entrees.count == 3)
        #expect(!entrees.contains { $0.text == "SUJET SENSIBLE" })
        #expect(entrees.filter { $0.sideTitle == "Moi" }.count == 1)
        #expect(entrees.filter { $0.sideTitle == "Marine" }.count == 2)

        let md = ReportOptionalBlocks.commitmentsMarkdown(entrees)
        #expect(md.contains("### Moi"))
        #expect(md.contains("### Marine"))
        #expect(md.contains("[x] Livrer la maquette"))
        #expect(md.contains("manqué"))
        #expect(!md.contains("SUJET SENSIBLE"))
    }

    @Test("Hors 1:1, le bloc des engagements est vide")
    func engagementsHors1a1() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "COPIL", date: Date())
        reunion.kind = .project
        ctx.insert(reunion)
        try ctx.save()
        #expect(ReportOptionalBlocks.commitments(of: reunion, in: ctx,
                                                  audience: .projectTeam).isEmpty)
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« has no member 'commitments' »).

- [ ] **Étape 3 : implémenter**

```swift
    // MARK: - Engagements réciproques (1:1)

    struct CommitmentEntry: Equatable {
        /// `Moi` ou le prénom de la personne du fil — les deux groupes de la
        /// colonne de droite de la capture 2a.
        var sideTitle: String
        var text: String
        var dueAt: Date?
        var state: CommitmentState
        var deferrals: Int
    }

    static let commitmentsTitle = "Engagements"
    static let commitmentsEmptyInvite = "Aucun engagement pris dans cette séance."
    /// Reprise du pied `CLÔTURER` de la capture 2a, à mettre dans le gabarit.
    static let commitmentsPrivacyNotice = "Les notes privées ne sont jamais incluses."

    /// Les engagements **pris dans cette séance**, par côté, filtrés par
    /// `ConfidentialityFilter` (spec §8 : la règle n'est jamais réécrite).
    ///
    /// Lecture seule du fil : `OneOnOneThreadStore.existingThread` et non
    /// `thread(for:in:)`, qui en crée un — générer un rapport ne doit rien
    /// écrire en base.
    static func commitments(of meeting: Meeting,
                            in context: ModelContext,
                            audience: Audience) -> [CommitmentEntry] {
        guard let role = OneOnOneThreadStore.role(for: meeting.kind),
              let personne = meeting.participants.first,
              let fil = OneOnOneThreadStore.existingThread(for: personne, role: role,
                                                            in: context)
        else { return [] }
        let cible = meeting.persistentModelID
        var entrees: [CommitmentEntry] = []
        for cote in [OneOnOneSide.manager, .collaborator] {
            let titre = OneOnOneRecapBuilder.sideTitle(cote, in: fil)
            let engagements = fil.commitments
                .filter { $0.ownerSide == cote }
                .filter { $0.promisedInMeeting?.persistentModelID == cible }
                .filter { ConfidentialityFilter.isExportable($0, for: audience) }
                .sorted { ($0.dueAt ?? .distantFuture, $0.text)
                        < ($1.dueAt ?? .distantFuture, $1.text) }
            entrees += engagements.map {
                CommitmentEntry(sideTitle: titre, text: $0.text, dueAt: $0.dueAt,
                                state: $0.state, deferrals: $0.deferralCount)
            }
        }
        return entrees
    }

    nonisolated static func commitmentsMarkdown(_ entries: [CommitmentEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var out: [String] = []
        for titre in orderedSideTitles(entries) {
            out.append("### \(titre)")
            for entry in entries where entry.sideTitle == titre {
                out.append("- \(commitmentLine(entry))")
            }
        }
        return out.joined(separator: "\n")
    }

    nonisolated static func commitmentsHTML(_ entries: [CommitmentEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var html = "<h2>\(commitmentsTitle)</h2>\n"
        for titre in orderedSideTitles(entries) {
            html += "<h3>\(escape(titre))</h3>\n<ul>\n"
            for entry in entries where entry.sideTitle == titre {
                html += "<li>\(escape(commitmentLine(entry)))</li>\n"
            }
            html += "</ul>\n"
        }
        return html
    }

    /// Les titres de côté dans l'ordre de première apparition : `commitments`
    /// les produit déjà manager puis collaborateur, et un tri alphabétique
    /// inverserait ce que la capture montre.
    private nonisolated static func orderedSideTitles(_ entries: [CommitmentEntry]) -> [String] {
        var vus: Set<String> = []
        return entries.compactMap { vus.insert($0.sideTitle).inserted ? $0.sideTitle : nil }
    }

    private nonisolated static func commitmentLine(_ entry: CommitmentEntry) -> String {
        var ligne = "[\(entry.state == .kept ? "x" : " ")] \(entry.text)"
        if let due = entry.dueAt { ligne += " — \(OneOnOneDateFormat.dayMonth(due))" }
        if entry.deferrals > 0 { ligne += " (\(entry.deferrals)× reporté)" }
        if entry.state == .missed { ligne += " — manqué" }
        return ligne
    }
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` → 10 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportOptionalBlocks.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "feat(rapport): bloc des engagements réciproques filtré par audience"
```

---

### Tâche 7 : trace des mises à jour de fiche projet acceptées

**Fichiers :**
- Modifier : `OneToOne/Models/OtherModels.swift` (une colonne)
- Créer : `OneToOne/Services/Project/ProjectCardSuggestions+Log.swift`
- Modifier : `OneToOne/Views/Project/ProjectCardSuggestionsSheet.swift` (une propriété, une ligne)
- Modifier : `OneToOne/Views/Project/ProjectCardPanel.swift` (un argument)
- Modifier : `OneToOne/Services/Report/ReportOptionalBlocks.swift`
- Test : `Tests/ReportOptionalBlocksTests.swift`

**Interfaces :**
- Consomme : `ProjectCardUpdate` (lot 9), `ProjectCardSuggestions.accept(_:in:)`.
- Produit :
  ```swift
  struct AcceptedProjectUpdate: Codable, Equatable, Sendable {
      var field: String; var label: String; var from: String; var to: String; var evidence: String
  }
  extension Meeting { var acceptedProjectUpdates: [AcceptedProjectUpdate] { get set } }
  extension ProjectCardSuggestions {
      @MainActor static func recordAcceptance(_ update: ProjectCardUpdate, in meeting: Meeting?)
  }
  // dans ReportOptionalBlocks
  static func cardUpdates(of meeting: Meeting) -> [AcceptedProjectUpdate]
  nonisolated static func cardUpdatesMarkdown(_ updates: [AcceptedProjectUpdate]) -> String
  nonisolated static func cardUpdatesHTML(_ updates: [AcceptedProjectUpdate]) -> String
  static let cardUpdatesTitle = "Mises à jour de la fiche projet"
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportOptionalBlocksTests.swift` :

```swift
    @Test("Seules les mises à jour acceptées sont tracées et rendues")
    func majFicheProjetAcceptees() throws {
        let ctx = try contexte()
        let projet = Project(code: "P25_110", name: "Marine", domain: "Assurance",
                             phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue Marine", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        try ctx.save()

        #expect(reunion.acceptedProjectUpdates.isEmpty)

        var brouillon = ProjectCardDraft(from: projet)
        let acceptee = ProjectCardUpdate(field: .status, label: "Statut du projet",
                                         current: "Vert", proposed: "Jaune",
                                         evidence: "12:08 le chiffrage dérape")
        #expect(ProjectCardSuggestions.accept(acceptee, in: &brouillon))
        ProjectCardSuggestions.recordAcceptance(acceptee, in: reunion)

        let ignoree = ProjectCardUpdate(field: .budgetSpent, label: "Budget consommé",
                                        current: "0", proposed: "21000",
                                        evidence: "12:10")
        // Non acceptée : rien n'est tracé.

        #expect(reunion.acceptedProjectUpdates.count == 1)
        let md = ReportOptionalBlocks.cardUpdatesMarkdown(
            ReportOptionalBlocks.cardUpdates(of: reunion))
        #expect(md.contains("Statut du projet"))
        #expect(md.contains("Vert"))
        #expect(md.contains("Jaune"))
        #expect(!md.contains(ignoree.displayLabel))
    }

    @Test("Tracer deux fois la même ligne n'écrit qu'une entrée")
    func majFicheProjetIdempotente() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        try ctx.save()
        let maj = ProjectCardUpdate(field: .risk, label: "Risque",
                                    current: "—", proposed: "Dérive de charge",
                                    evidence: "08:00")
        ProjectCardSuggestions.recordAcceptance(maj, in: reunion)
        ProjectCardSuggestions.recordAcceptance(maj, in: reunion)
        #expect(reunion.acceptedProjectUpdates.count == 1)
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« value of type 'Meeting' has no member 'acceptedProjectUpdates' »).

- [ ] **Étape 3 : implémenter**

Dans `Models/OtherModels.swift`, à côté de `reportAttachmentOptionsJSON` :

```swift
    /// Les mises à jour de fiche projet **acceptées** pendant la séance
    /// (spec §8, dernier tiret). JSON et non une table : c'est une trace
    /// d'audit attachée à la séance, jamais requêtée seule, et le lot 9
    /// n'en persiste aucune — accepter mute un `ProjectCardDraft`. Vide =
    /// aucune acceptation. Façade typée `acceptedProjectUpdates`, dans
    /// `Services/Project/ProjectCardSuggestions+Log.swift`.
    var acceptedProjectUpdatesJSON: String = ""
```

Créer `OneToOne/Services/Project/ProjectCardSuggestions+Log.swift` :

```swift
import Foundation

/// Une mise à jour de fiche projet **acceptée** en séance : ce que
/// `{{fiche_projet.maj}}` rend dans le rapport.
///
/// Le lot 9 ne persiste rien de l'acceptation — `ProjectCardSuggestions.accept`
/// mute un `ProjectCardDraft`, et le brouillon ne dit pas d'où vient une
/// valeur. Sans cette trace, le rapport devrait deviner ce que l'utilisateur a
/// validé, ce que le critère n° 4 du chantier 3 interdit précisément.
struct AcceptedProjectUpdate: Codable, Equatable, Sendable {
    var field: String
    var label: String
    var from: String
    var to: String
    var evidence: String

    /// Identité de la ligne, celle de `ProjectCardUpdate.id` : accepter deux
    /// fois la même proposition ne doit pas la tracer deux fois.
    var id: String { "\(field)|\(label)" }
}

extension Meeting {

    /// Façade typée de `acceptedProjectUpdatesJSON`. Même patron que
    /// `reportAttachmentOptions` : la vue lit et écrit une valeur, la colonne
    /// reste une chaîne. Un JSON illisible se relit en tableau vide — une
    /// exception ici empêcherait d'ouvrir l'espace Rapport.
    var acceptedProjectUpdates: [AcceptedProjectUpdate] {
        get {
            guard !acceptedProjectUpdatesJSON.isEmpty,
                  let data = acceptedProjectUpdatesJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([AcceptedProjectUpdate].self, from: data)
            else { return [] }
            return items
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                acceptedProjectUpdatesJSON = "[]"
                return
            }
            acceptedProjectUpdatesJSON = json
        }
    }
}

extension ProjectCardSuggestions {

    /// Trace une acceptation sur la séance. Idempotent sur `ProjectCardUpdate.id`.
    /// `meeting == nil` (la feuille ouverte depuis la fiche projet, hors
    /// séance) ne trace rien : il n'y a alors pas de rapport à alimenter.
    @MainActor
    static func recordAcceptance(_ update: ProjectCardUpdate, in meeting: Meeting?) {
        guard let meeting else { return }
        let entree = AcceptedProjectUpdate(field: update.field.rawValue,
                                           label: update.displayLabel,
                                           from: update.current,
                                           to: update.proposed,
                                           evidence: update.evidence)
        var toutes = meeting.acceptedProjectUpdates
        guard !toutes.contains(where: { $0.id == entree.id }) else { return }
        toutes.append(entree)
        meeting.acceptedProjectUpdates = toutes
        try? meeting.modelContext?.save()
    }
}
```

Dans `ReportOptionalBlocks.swift` :

```swift
    // MARK: - Mises à jour de fiche projet acceptées

    static let cardUpdatesTitle = "Mises à jour de la fiche projet"
    static let cardUpdatesEmptyInvite =
        "Aucune mise à jour acceptée — l'assistant propose, vous validez."

    static func cardUpdates(of meeting: Meeting) -> [AcceptedProjectUpdate] {
        meeting.acceptedProjectUpdates
    }

    nonisolated static func cardUpdatesMarkdown(_ updates: [AcceptedProjectUpdate]) -> String {
        guard !updates.isEmpty else { return "" }
        return updates.map { maj in
            let avant = maj.from.trimmingCharacters(in: .whitespaces)
            let depuis = avant.isEmpty ? "—" : avant
            return "- \(maj.label) : \(depuis) → \(maj.to)"
        }.joined(separator: "\n")
    }

    nonisolated static func cardUpdatesHTML(_ updates: [AcceptedProjectUpdate]) -> String {
        guard !updates.isEmpty else { return "" }
        var html = "<h2>\(cardUpdatesTitle)</h2>\n<ul>\n"
        for maj in updates {
            let avant = maj.from.trimmingCharacters(in: .whitespaces)
            let depuis = avant.isEmpty ? "—" : avant
            html += "<li>\(escape(maj.label)) : \(escape(depuis)) → \(escape(maj.to))</li>\n"
        }
        html += "</ul>\n"
        return html
    }
```

Câblage minimal dans `Views/Project/ProjectCardSuggestionsSheet.swift` : ajouter
`var meeting: Meeting? = nil` près de `let updates`, et dans `accept(_:)`, après
`handled.insert(proposition.id)`, la ligne
`ProjectCardSuggestions.recordAcceptance(proposition, in: meeting)`.
Dans `Views/Project/ProjectCardPanel.swift:157`, passer `meeting: meeting` si le panneau
en dispose ; sinon laisser le défaut `nil` et le consigner dans `STATUS.md`.

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` puis `--filter ProjectCard` → verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Models/OtherModels.swift OneToOne/Services/Project/ProjectCardSuggestions+Log.swift OneToOne/Views/Project/ProjectCardSuggestionsSheet.swift OneToOne/Views/Project/ProjectCardPanel.swift OneToOne/Services/Report/ReportOptionalBlocks.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "feat(rapport): tracer les mises à jour de fiche projet acceptées"
```

---

### Tâche 8 : les cinq variables `{{…}}` et la palette de l'éditeur

**Fichiers :**
- Créer : `OneToOne/Services/ReportVariables+Refonte.swift`
- Modifier : `OneToOne/Services/ReportTemplating.swift`
- Modifier : `OneToOne/Services/AIReportService.swift`
- Modifier : `OneToOne/Views/Settings/ReportTemplateEditorView.swift`
- Test : `Tests/TemplateVariableResolverTests.swift`

**Interfaces :**
- Consomme : tous les blocs de `ReportOptionalBlocks`, `ReportAudience.forTemplate`.
- Produit : `TemplateVariableResolver.resolve(prompt:for:in:audience:now:)` (nouveau
  paramètre `audience` avec défaut) ; `RefonteReportVariables.names: [String]` pour la palette.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/TemplateVariableResolverTests.swift` :

```swift
    func test_lot15_variablesResolvent_lesBlocsOptionnels() throws {
        let m = Meeting(title: "Revue", date: Date())
        context.insert(m)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = m
        context.insert(piece)
        let planche = Board(index: 0, title: "Zones", mode: .diagram, t: 120)
        planche.meeting = m
        context.insert(planche)
        try context.save()

        let resolved = TemplateVariableResolver.resolve(
            prompt: "P:{{pieces_epinglees}} C:{{captures_jointes}} B:{{planches}} "
                  + "E:{{engagements}} F:{{fiche_projet.maj}}",
            for: m, in: context
        )
        XCTAssertTrue(resolved.contains("04:12"))
        XCTAssertTrue(resolved.contains("Chiffrage.xlsx"))
        XCTAssertTrue(resolved.contains("02:00"))
        XCTAssertTrue(resolved.contains("Zones"))
        // Les variables inconnues restent littérales ; celles du lot 15 ne
        // doivent plus l'être, même quand elles rendent vide.
        XCTAssertFalse(resolved.contains("{{captures_jointes}}"))
        XCTAssertFalse(resolved.contains("{{engagements}}"))
        XCTAssertFalse(resolved.contains("{{fiche_projet.maj}}"))
    }

    func test_lot15_piecesEpinglees_respecteLaCaseDuTiroir() throws {
        let m = Meeting(title: "Revue", date: Date())
        var options = m.reportAttachmentOptions
        options.attachPinned = false
        m.reportAttachmentOptions = options
        context.insert(m)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = m
        context.insert(piece)
        try context.save()

        let resolved = TemplateVariableResolver.resolve(
            prompt: "P:{{pieces_epinglees}}", for: m, in: context
        )
        XCTAssertEqual(resolved, "P:")
    }

    func test_lot15_paletteExposeLesCinqVariables() {
        for nom in ["pieces_epinglees", "captures_jointes", "planches",
                    "engagements", "fiche_projet.maj"] {
            XCTAssertTrue(RefonteReportVariables.names.contains(nom), nom)
        }
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter TemplateVariableResolverTests` → échec de compilation
(« cannot find 'RefonteReportVariables' in scope ») ; les variables restent littérales.

- [ ] **Étape 3 : implémenter**

Créer `OneToOne/Services/ReportVariables+Refonte.swift` :

```swift
import Foundation
import SwiftData

/// Les cinq variables de gabarit du lot 15 (plan §5, spec §8). Séparées de
/// `TemplateVariableResolver` parce qu'elles ont une dépendance que les autres
/// n'ont pas : l'**audience**, qui décide de ce que le bloc des engagements
/// laisse sortir.
///
/// La case du pied du tiroir Ressources (`AttachmentReportOptions.attachPinned`)
/// et la case `Joindre au rapport` d'une capture pilotent l'inclusion : une
/// variable qui rendrait tout ce que la base contient, quelles que soient les
/// cases, ferait mentir le pied du tiroir.
enum RefonteReportVariables {

    /// Les noms exposés dans la palette de l'éditeur de gabarits.
    static let names: [String] = [
        "pieces_epinglees",
        "captures_jointes",
        "planches",
        "engagements",
        "fiche_projet.maj"
    ]

    /// Résout une des cinq variables. `nil` pour tout autre nom, ce qui laisse
    /// `TemplateVariableResolver` conclure « variable inconnue » et garder le
    /// placeholder littéral.
    @MainActor
    static func resolve(name: String,
                        meeting: Meeting,
                        context: ModelContext,
                        audience: Audience) -> String? {
        switch name {
        case "pieces_epinglees":
            guard meeting.reportAttachmentOptions.attachPinned else { return "" }
            return ReportOptionalBlocks.pinnedMarkdown(
                ReportOptionalBlocks.pinnedPieces(of: meeting))
        case "captures_jointes":
            return ReportOptionalBlocks.capturesMarkdown(
                ReportOptionalBlocks.captures(of: meeting))
        case "planches":
            return ReportOptionalBlocks.boardsMarkdown(
                ReportOptionalBlocks.boards(of: meeting))
        case "engagements":
            let entrees = ReportOptionalBlocks.commitments(of: meeting, in: context,
                                                            audience: audience)
            return ReportOptionalBlocks.commitmentsMarkdown(entrees)
        case "fiche_projet.maj":
            return ReportOptionalBlocks.cardUpdatesMarkdown(
                ReportOptionalBlocks.cardUpdates(of: meeting))
        default:
            return nil
        }
    }
}
```

Dans `ReportTemplating.swift` : ajouter le paramètre `audience: Audience? = nil` à
`resolve(prompt:for:in:now:)`, le propager à `resolveOne`, et dans `resolveOne`
remplacer `default: return nil` par :

```swift
        default:
            return RefonteReportVariables.resolve(
                name: name, meeting: meeting, context: context,
                audience: audience ?? ConfidentialityFilter.audience(for: meeting.kind))
```

Dans `AIReportService.assembleTemplatePrompt`, passer l'audience du gabarit :
`TemplateVariableResolver.resolve(prompt: body, for: meeting, in: context, audience: audience)`
(`audience` déjà calculée à la tâche 2), et **après** le bloc des notes, appender les blocs
optionnels que le corps du gabarit ne contient pas — même patron que les autres fallbacks :

```swift
        // Blocs optionnels du lot 15 absents du corps du gabarit : appendés en
        // queue plutôt que perdus. Un gabarit d'avant le lot 15 doit voir les
        // pièces épinglées de sa séance sans être réédité.
        for (nom, titre) in [("pieces_epinglees", "Pièces épinglées de la séance"),
                             ("captures_jointes", "Captures jointes au rapport"),
                             ("planches", "Planches de la séance"),
                             ("engagements", "Engagements pris dans cette séance"),
                             ("fiche_projet.maj", "Mises à jour de fiche projet acceptées")]
        where !body.contains("{{\(nom)}}") {
            let bloc = RefonteReportVariables.resolve(name: nom, meeting: meeting,
                                                      context: context, audience: audience) ?? ""
            if !bloc.isEmpty { historyAppendix += "\n\n\(titre) :\n\(bloc)\n" }
        }
```

Dans `ReportTemplateEditorView.variablesPalette`, ajouter le groupe :

```swift
            ("Blocs de séance", RefonteReportVariables.names),
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter TemplateVariableResolverTests` puis
`--filter ReportTemplatingCollabNotesTests` et `--filter HistoryContextBuilderTests` → verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/ReportVariables+Refonte.swift OneToOne/Services/ReportTemplating.swift OneToOne/Services/AIReportService.swift OneToOne/Views/Settings/ReportTemplateEditorView.swift Tests/TemplateVariableResolverTests.swift
git commit -m "feat(rapport): cinq variables de blocs optionnels et palette"
```

---

### Tâche 9 : gabarits intégrés — révisions versionnées et `d11_escalade`

**Fichiers :**
- Modifier : `OneToOne/Services/BuiltInTemplates.swift`
- Modifier : `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` (`compatibleTemplates`)
- Test : `Tests/BuiltInTemplatesTests.swift`

**Interfaces :**
- Produit : `BuiltInTemplates.revisions: [String: Int]` ; `BuiltInTemplates.d11_escalade` ;
  `BuiltInTemplates.revisionKey(for name: String) -> String`.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/BuiltInTemplatesTests.swift` :

```swift
    func test_lot15_escaladeEstSemee() throws {
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        let all = try context.fetch(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }))
        let escalade = all.first { $0.name == BuiltInTemplates.d11_escalade.name }
        XCTAssertNotNil(escalade)
        XCTAssertEqual(escalade?.kind, .escalade)
        XCTAssertEqual(escalade?.kind.audience, .hr)
    }

    func test_lot15_revisionsCouvrentLesSeedsRevises() {
        for nom in [BuiltInTemplates.d1_global.name,
                    BuiltInTemplates.d2_oneToOne.name,
                    BuiltInTemplates.d3_manager.name,
                    BuiltInTemplates.d4_copil.name,
                    BuiltInTemplates.d5_cosui.name,
                    BuiltInTemplates.d9_workshop.name] {
            XCTAssertNotNil(BuiltInTemplates.revisions[nom], nom)
        }
        // Toute clé de révision doit désigner un seed livré.
        for nom in BuiltInTemplates.revisions.keys {
            XCTAssertNotNil(BuiltInTemplates.dict[nom], nom)
        }
    }

    func test_lot15_revisionAppliqueeUneSeuleFois_etPreserveLEdition() throws {
        // Première pose : le seed frais.
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()

        let nom = BuiltInTemplates.d9_workshop.name
        let clef = BuiltInTemplates.revisionKey(for: nom)
        // Rejouer la révision : on remet le marqueur à zéro.
        UserDefaults.standard.removeObject(forKey: clef)

        let avant = try context.fetch(FetchDescriptor<ReportTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true })).first { $0.name == nom }
        XCTAssertNotNil(avant)
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        XCTAssertTrue(avant?.promptBody.contains("{{planches}}") == true)

        // L'utilisateur édite ; une seconde passe ne doit pas écraser.
        avant?.promptBody = "MON PROMPT À MOI"
        try context.save()
        BuiltInTemplates.seedIfNeeded(in: context)
        try context.save()
        XCTAssertEqual(avant?.promptBody, "MON PROMPT À MOI")
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter BuiltInTemplatesTests` → échec de compilation
(« has no member 'd11_escalade' »).

- [ ] **Étape 3 : implémenter**

1. Ajouter `d11_escalade` à `all` (après `d10_archTeam`) :

```swift
    // MARK: - D11 Escalade (décision D9)

    /// L'unique sortie qui emporte les lignes `escalated` — et **seulement**
    /// elles plus les privées de personne. Préambule sobre : un export vers les
    /// RH n'est pas un compte-rendu, c'est un dossier.
    static let d11_escalade = Seed(
        name: "Escalade",
        kind: .escalade,
        preamble: """
        Tu rédiges une note d'escalade destinée aux ressources humaines et au
        N+1. Ton neutre, factuel, sans interprétation psychologique.

        Règles strictes :
        - N'INVENTE RIEN. Chaque fait doit venir des lignes fournies.
        - Ne qualifie pas les personnes : décris des faits, des dates, des
          engagements tenus ou manqués.
        - N'inclus aucun ressenti, aucun cran de moral, aucune appréciation de
          motivation : ces éléments ne sont pas escaladés.
        - Si une section n'a aucune matière, omets-la.
        """,
        sections: [
            .init(title: "Objet", hint: "Une phrase : ce qui est porté à connaissance et pourquoi."),
            .init(title: "Faits", hint: "Chronologie datée des faits escaladés, un par puce."),
            .init(title: "Engagements", hint: "Engagements pris de part et d'autre, tenus ou manqués, avec leurs dates."),
            .init(title: "Demande", hint: "Ce qui est attendu du destinataire. Vide si rien n'est demandé.")
        ],
        historyMode: .lastN,
        historyN: 3,
        historyK: 0,
        promptBody: """
        Note d'escalade · {{date}}
        Personne concernée : {{collab.name}} ({{collab.role}})

        Engagements du fil :
        {{engagements}}

        Historique des entretiens :
        {{historique_n}}

        {{custom_prompt}}

        Notes retenues pour l'escalade :
        {{notes}}
        """
    )
```

2. Généraliser le mécanisme de révision :

```swift
    /// Révision de chaque seed livré. Bumper la valeur pousse le seed **une
    /// fois** dans les lignes existantes, sans écraser une édition utilisateur.
    ///
    /// Généralise le marqueur `d2OneToOneRevision` du 2026-05-23 : trois lots
    /// ont révisé des gabarits depuis, chacun avec sa clé, et une quatrième
    /// aurait fait quatre blocs `if` presque identiques.
    static let revisions: [String: Int] = [
        d1_global.name: 1,
        d2_oneToOne.name: 4,
        d3_manager.name: 1,
        d4_copil.name: 1,
        d5_cosui.name: 1,
        d9_workshop.name: 1
    ]

    /// La clé `UserDefaults` du marqueur de révision d'un seed. Le nom du seed
    /// et non un identifiant : c'est déjà la clé de recherche de `seedIfNeeded`.
    static func revisionKey(for name: String) -> String {
        "BuiltInTemplates.revision.\(name)"
    }

    /// Vrai quand la ligne diverge du seed **sans** qu'une révision l'explique :
    /// l'utilisateur l'a éditée, et la règle historique est de ne jamais
    /// l'écraser.
    private static func isUserEdited(_ row: ReportTemplate, seed: Seed) -> Bool {
        row.promptBody != seed.promptBody
            && UserDefaults.standard.integer(forKey: revisionKey(for: seed.name))
                >= (revisions[seed.name] ?? 0)
    }
```

Puis remplacer le bloc `d2Key`/`d2Target` par la boucle :

```swift
        // Révisions versionnées. Une ligne est mise à jour **une fois** par
        // révision ; passé ce point, une édition utilisateur reste intacte.
        for seed in all {
            guard let cible = revisions[seed.name] else { continue }
            let clef = revisionKey(for: seed.name)
            guard UserDefaults.standard.integer(forKey: clef) < cible else { continue }
            if let row = existingBuiltIns.first(where: { $0.name == seed.name }) {
                row.preamble = seed.preamble
                row.promptBody = seed.promptBody
                row.sections = seed.sections
                row.historyMode = seed.historyMode
                row.historyN = seed.historyN
                row.updatedAt = Date()
            }
            UserDefaults.standard.set(cible, forKey: clef)
        }
```

Retirer `isUserEdited` s'il n'est pas nécessaire (la règle « une fois par révision » suffit :
c'est celle que le test `test_seedIfNeeded_doesNotOverwriteEditedBuiltIn` garde déjà).

3. Réviser les seeds :
- `d2_oneToOne` : ajouter au `promptBody`, avant la transcription,
  `Engagements du fil :\n{{engagements}}\n` ; ajouter au `preamble` la ligne
  `- Les notes privées ne sont JAMAIS incluses : elles ne t'ont pas été transmises.`
- `d3_manager` : ajouter `Ce qu'il m'a promis :\n{{engagements}}\n`. `Ce que j'ai livré`
  n'a pas de `DeliveredItemsBuilder` sur cette base — ne pas inventer de variable, le
  consigner dans `STATUS.md`.
- `d9_workshop` : ajouter `Planches de la séance :\n{{planches}}\n` et
  `Captures jointes :\n{{captures_jointes}}\n`.
- `d1_global`, `d4_copil`, `d5_cosui` : ajouter
  `Pièces épinglées :\n{{pieces_epinglees}}\n`, `Captures jointes :\n{{captures_jointes}}\n`
  et `Mises à jour de fiche projet acceptées :\n{{fiche_projet.maj}}\n`.

4. Dans `MeetingTopChromeBar.compatibleTemplates`, faire d'Escalade un second choix
prioritaire pour les deux types de tête-à-tête :

```swift
        let preferred = mapping[meeting.kind] ?? .general
        // Escalade est proposé juste après le gabarit du type, sur les deux
        // types de tête-à-tête seulement (D9) : c'est là qu'une ligne
        // escaladée peut exister.
        let secondaire: ReportTemplateKind? =
            (meeting.kind == .oneToOne || meeting.kind == .manager) ? .escalade : nil
        return allTemplates
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                func rang(_ t: ReportTemplate) -> Int {
                    if t.kind == preferred { return 0 }
                    if let secondaire, t.kind == secondaire { return 1 }
                    return 2
                }
                let li = rang(lhs), ri = rang(rhs)
                if li != ri { return li < ri }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter BuiltInTemplatesTests` → verts (dont les trois existants).

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/BuiltInTemplates.swift OneToOne/Views/Meeting/MeetingTopChromeBar.swift Tests/BuiltInTemplatesTests.swift
git commit -m "feat(rapport): révisions versionnées des gabarits et gabarit Escalade"
```

---

### Tâche 10 : `CitationLinker`

**Fichiers :**
- Créer : `OneToOne/Services/Report/CitationLinker.swift`
- Test : `Tests/CitationLinkerTests.swift` (créé)

**Interfaces :**
- Produit :
  ```swift
  enum CitationLinker {
      enum Mode { case internalLinks(meetingStableID: UUID); case plainText }
      static func url(meetingStableID: UUID, t: Double, noteStableID: UUID? = nil) -> String
      static func link(_ html: String, mode: Mode) -> String
      static func seconds(fromTimecode s: String) -> Double?
  }
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/CitationLinkerTests.swift` :

```swift
import Testing
import Foundation
@testable import OneToOne

@Suite("Chaîne de citation — timecodes cliquables")
struct CitationLinkerTests {

    private let reunion = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000001")!

    @Test("L'URL porte la réunion, les secondes et la note quand il y en a une")
    func urlComplete() {
        #expect(CitationLinker.url(meetingStableID: reunion, t: 252)
                == "onetoone://meeting/\(reunion.uuidString)?t=252")
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000002")!
        #expect(CitationLinker.url(meetingStableID: reunion, t: 252, noteStableID: note)
                == "onetoone://meeting/\(reunion.uuidString)?t=252&note=\(note.uuidString)")
    }

    @Test("Un timecode se relit en secondes, mm:ss comme h:mm:ss")
    func lectureDesTimecodes() {
        #expect(CitationLinker.seconds(fromTimecode: "04:12") == 252)
        #expect(CitationLinker.seconds(fromTimecode: "1:02:33") == 3753)
        #expect(CitationLinker.seconds(fromTimecode: "pas un timecode") == nil)
    }

    @Test("En interne, chaque <code>mm:ss</code> devient un lien avec sa flèche")
    func lienInterne() {
        let html = "<li><code>04:12</code> Chiffrage_Marine_v3.xlsx</li>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie.contains("<a class=\"tc\" href=\"onetoone://meeting/\(reunion.uuidString)?t=252\">"))
        #expect(sortie.contains("04:12 ↗"))
        #expect(!sortie.contains("<code>04:12</code>"))
    }

    @Test("Une note nommée par data-note voyage dans l'URL")
    func lienVersUneNote() {
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000003")!
        let html = "<li><code data-note=\"\(note.uuidString)\">02:00</code> Point</li>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie.contains("?t=120&note=\(note.uuidString)"))
    }

    /// « Les schémas privés n'ont pas de sens hors machine » : à l'export, le
    /// timecode reste du texte.
    @Test("À l'export externe, le timecode reste du texte")
    func exportSansLien() {
        let html = "<li><code>04:12</code> Chiffrage_Marine_v3.xlsx</li>"
        let sortie = CitationLinker.link(html, mode: .plainText)
        #expect(!sortie.contains("onetoone://"))
        #expect(!sortie.contains("<a "))
        #expect(sortie.contains("04:12"))
    }

    @Test("Un horaire dans une phrase libre n'est pas transformé en lien")
    func aucunFauxPositif() {
        let html = "<p>Le point est reporté à 14:30, après la démo de 9:05.</p>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie == html)
    }

    @Test("Un code qui n'est pas un timecode reste un code")
    func codeNonTimecode() {
        let html = "<p><code>P25_110</code> et <code>12:345</code></p>"
        let sortie = CitationLinker.link(html, mode: .internalLinks(meetingStableID: reunion))
        #expect(sortie == html)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter CitationLinkerTests` → échec de compilation
(« cannot find 'CitationLinker' in scope »).

- [ ] **Étape 3 : implémenter**

```swift
import Foundation

/// La chaîne de citation, côté rendu (spec §8 : « le rapport rend ces
/// références cliquables »).
///
/// **Post-traitement pur, appliqué aux seuls fragments que l'app écrit
/// elle-même** — les blocs de notes, de pièces, de captures, de planches, le
/// plan d'actions. Jamais au corps markdown du modèle : « le point est reporté
/// à 14:30 » est un horaire, pas une position dans l'enregistrement, et le
/// transformer en lien mènerait la tête de lecture à la 870ᵉ seconde d'une
/// séance qui n'en compte peut-être pas tant.
///
/// La reconnaissance porte donc sur le balisage de l'app (`<code>mm:ss</code>`)
/// et non sur le texte nu : c'est ce qui rend le motif sûr sans dépendre de
/// l'endroit où on l'applique.
enum CitationLinker {

    enum Mode {
        /// Aperçu dans l'app : liens `onetoone://` cliquables.
        case internalLinks(meetingStableID: UUID)
        /// PDF, mail, Apple Notes : le timecode reste du texte.
        case plainText
    }

    /// `onetoone://meeting/<uuid>?t=252[&note=<uuid>]`
    static func url(meetingStableID: UUID, t: Double, noteStableID: UUID? = nil) -> String {
        var out = "onetoone://meeting/\(meetingStableID.uuidString)?t=\(Int(t.rounded()))"
        if let noteStableID { out += "&note=\(noteStableID.uuidString)" }
        return out
    }

    /// `04:12` → 252 ; `1:02:33` → 3753 ; autre chose → `nil`.
    static func seconds(fromTimecode s: String) -> Double? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0
        for (index, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0 else { return nil }
            // Minutes et secondes s'écrivent sur deux chiffres et restent
            // sous 60 ; seule la tête (heures ou minutes) peut être libre.
            if index > 0, part.count != 2 || value >= 60 { return nil }
            total = total * 60 + value
        }
        return Double(total)
    }

    private static let motif: NSRegularExpression = {
        // <code> éventuellement porteur de data-note, puis mm:ss ou h:mm:ss,
        // puis </code> et une flèche déjà posée à ignorer.
        try! NSRegularExpression(
            pattern: #"<code(?:\s+data-note="([0-9A-Fa-f-]{36})")?>(\d{1,2}(?::\d{2}){1,2})</code>(\s*↗)?"#)
    }()

    /// Rend cliquables les timecodes du fragment. `plainText` remet le
    /// timecode nu : un `<code>` de plus dans un corps de mail n'apporte rien,
    /// et un `onetoone://` y serait un lien mort.
    static func link(_ html: String, mode: Mode) -> String {
        let ns = html as NSString
        let matches = motif.matches(in: html,
                                    range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }
        var out = html
        for match in matches.reversed() {
            let timecode = (out as NSString).substring(with: match.range(at: 2))
            guard let t = seconds(fromTimecode: timecode) else { continue }
            let remplacement: String
            switch mode {
            case .plainText:
                remplacement = timecode
            case .internalLinks(let meetingStableID):
                var note: UUID? = nil
                if match.range(at: 1).location != NSNotFound {
                    note = UUID(uuidString: (out as NSString).substring(with: match.range(at: 1)))
                }
                let href = url(meetingStableID: meetingStableID, t: t, noteStableID: note)
                remplacement = "<a class=\"tc\" href=\"\(href)\">\(timecode) ↗</a>"
            }
            out = (out as NSString).replacingCharacters(in: match.range, with: remplacement)
        }
        return out
    }
}
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter CitationLinkerTests` → 7 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/CitationLinker.swift Tests/CitationLinkerTests.swift
git commit -m "feat(rapport): CitationLinker — timecodes cliquables, texte à l'export"
```

---

### Tâche 11 : annexes et citations dans `ReportHTMLBuilder`

**Fichiers :**
- Modifier : `OneToOne/Services/Report/ReportHTMLBuilder.swift`
- Modifier : `OneToOne/Services/Report/ReportThemeCSS.swift` (classe `.tc`)
- Test : `Tests/ReportHTMLBuilderTests.swift`

**Interfaces :**
- Consomme : `ReportOptionalBlocks.*HTML`, `CitationLinker.link(_:mode:)`,
  `ReportAudience.forTemplate`.
- Produit : `ReportHTMLBuilder.build` inchangé en signature, HTML enrichi des annexes.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportHTMLBuilderTests.swift` :

```swift
    /// Critère d'acceptation n° 3 du chantier 3, moitié rapport : la pièce
    /// épinglée est citée avec son timecode, sans aucune intervention du modèle.
    @MainActor
    func test_lot15_pieceEpingleeCiteeAvecSonTimecode() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue Marine", date: Date())
        meeting.summary = "## Contexte\n\nLa séance a passé le chiffrage en revue."
        ctx.insert(meeting)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage_Marine_v3.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = meeting
        ctx.insert(piece)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertTrue(html.contains("Pièces épinglées"))
        XCTAssertTrue(html.contains("Chiffrage_Marine_v3.xlsx"))
        XCTAssertTrue(html.contains("04:12"))
        XCTAssertTrue(html.contains("onetoone://meeting/\(meeting.ensuredStableID.uuidString)?t=252"))
    }

    @MainActor
    func test_lot15_exportOutlookGardeLeTimecodeEnTexte() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Contenu."
        ctx.insert(meeting)
        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Annexe.pdf"))
        piece.pinnedAtT = 252
        piece.meeting = meeting
        ctx.insert(piece)
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false, mode: .outlook)
        XCTAssertFalse(html.contains("onetoone://"))
        XCTAssertTrue(html.contains("04:12"))
    }

    @MainActor
    func test_lot15_horaireDansLeCorpsResteDuTexte() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Revue", date: Date())
        meeting.summary = "Le point est reporté à 14:30, après la démo."
        ctx.insert(meeting)
        try ctx.save()
        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        XCTAssertTrue(html.contains("14:30"))
        XCTAssertFalse(html.contains("onetoone://"))
    }

    @MainActor
    func test_lot15_planchesDansLOrdreDuTemps() throws {
        let ctx = try makeContext()
        let meeting = Meeting(title: "Atelier", date: Date())
        meeting.summary = "Contenu."
        ctx.insert(meeting)
        for (index, (titre, t)) in [("Troisième", 900.0), ("Première", 120.0),
                                    ("Deuxième", 450.0)].enumerated() {
            let planche = Board(index: index, title: titre, mode: .sketch, t: t)
            planche.meeting = meeting
            ctx.insert(planche)
        }
        try ctx.save()

        let html = ReportHTMLBuilder.build(meeting: meeting, template: nil,
                                           includeTranscript: false)
        let positions = ["Première", "Deuxième", "Troisième"]
            .compactMap { html.range(of: $0)?.lowerBound }
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(positions, positions.sorted())
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportHTMLBuilderTests` → les quatre tests du lot 15 échouent
(« Pièces épinglées » absent, aucun `onetoone://`).

- [ ] **Étape 3 : implémenter**

Dans `ReportHTMLBuilder.build`, après `assembled += notesHTML` :

```swift
        // Annexes du lot 15 : déterministes, écrites sans le modèle. Les cases
        // du pied du tiroir (spec §4.1) et `Joindre au rapport` (spec §5.3)
        // décident de ce qui entre ; l'ordre suit celui de la spec §8.
        let options = meeting.reportAttachmentOptions
        if options.attachPinned {
            assembled += ReportOptionalBlocks.pinnedHTML(
                ReportOptionalBlocks.pinnedPieces(of: meeting))
        }
        assembled += ReportOptionalBlocks.capturesHTML(
            ReportOptionalBlocks.captures(of: meeting), embedImages: mode == .preview)
        assembled += ReportOptionalBlocks.boardsHTML(
            ReportOptionalBlocks.boards(of: meeting))
        if let context = meeting.modelContext {
            assembled += ReportOptionalBlocks.commitmentsHTML(
                ReportOptionalBlocks.commitments(of: meeting, in: context, audience: audience))
        }
        assembled += ReportOptionalBlocks.cardUpdatesHTML(
            ReportOptionalBlocks.cardUpdates(of: meeting))
```

`renderNotesBlock` émet déjà ses timecodes en `<code>` ; y ajouter `data-note` :
`"<li><code data-note=\"\(note.ensuredStableID.uuidString)\">…"`.
Dans `renderActionsBlock`, préfixer la cellule d'action d'un `<code>` quand
`t.sourceRef?.t` existe : `"<code>\(MeetingPlayhead.mmss(refT))</code> "`.

Les blocs de l'app passent ensuite par le linker, **avant** l'injection dans le corps :
introduire en tête de `build`

```swift
        let citation: CitationLinker.Mode = mode == .preview
            ? .internalLinks(meetingStableID: meeting.ensuredStableID)
            : .plainText
```

et faire passer par `CitationLinker.link(_:mode: citation)` chacun des retours de
`renderNotesBlock`, `renderActionsBlock` et des cinq `…HTML` de `ReportOptionalBlocks`
(un petit `func cite(_ s: String) -> String` local évite la répétition).
`bodyHTML` n'y passe **pas**.

Dans `ReportThemeCSS.css`, ajouter :

```css
    a.tc {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11px;
      color: #1b4dad;
      text-decoration: none;
      border-bottom: 1px dotted rgba(27,77,173,.4);
    }
```

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportHTMLBuilderTests` puis `--filter ReportAudienceTests` → verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportHTMLBuilder.swift OneToOne/Services/Report/ReportThemeCSS.swift Tests/ReportHTMLBuilderTests.swift
git commit -m "feat(rapport): annexes des blocs optionnels et citations cliquables"
```

---

### Tâche 12 : ouverture d'une réunion au timecode (`onetoone://`)

**Fichiers :**
- Modifier : `OneToOne/Services/QuickLaunchURLHandler.swift`
- Modifier : `OneToOne/Views/Meeting/MeetingReportPreview.swift`
- Test : `Tests/CitationLinkerTests.swift`

**Interfaces :**
- Consomme : `CitationLinker.url`, `QuickLaunchRouter.openMeeting(_:)`.
- Produit :
  ```swift
  extension QuickLaunchURLHandler {
      struct MeetingCitation: Equatable { var meetingStableID: UUID; var t: Double?; var noteStableID: UUID? }
      static func parseCitation(_ url: URL) -> MeetingCitation?
      @MainActor static func handle(url: URL, router: QuickLaunchRouter, context: ModelContext, playhead: MeetingPlayhead?) -> Bool
  }
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/CitationLinkerTests.swift` :

```swift
@Suite("Ouverture d'une citation")
struct CitationURLHandlingTests {

    private let reunion = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000001")!

    @Test("L'URL produite par le linker se relit sans perte")
    func allerRetour() {
        let note = UUID(uuidString: "5C3E0A1E-0000-4000-8000-000000000002")!
        let brute = CitationLinker.url(meetingStableID: reunion, t: 252, noteStableID: note)
        let citation = QuickLaunchURLHandler.parseCitation(URL(string: brute)!)
        #expect(citation?.meetingStableID == reunion)
        #expect(citation?.t == 252)
        #expect(citation?.noteStableID == note)
    }

    @Test("Sans t, la citation ouvre la réunion sans déplacer la tête de lecture")
    func sansTimecode() {
        let citation = QuickLaunchURLHandler.parseCitation(
            URL(string: "onetoone://meeting/\(reunion.uuidString)")!)
        #expect(citation?.meetingStableID == reunion)
        #expect(citation?.t == nil)
    }

    @Test("Un schéma étranger ou un UUID cassé ne mène nulle part")
    func urlRefusees() {
        #expect(QuickLaunchURLHandler.parseCitation(URL(string: "https://exemple.fr/x")!) == nil)
        #expect(QuickLaunchURLHandler.parseCitation(URL(string: "onetoone://meeting/pas-un-uuid")!) == nil)
        #expect(QuickLaunchURLHandler.parseCitation(URL(string: "onetoone://collaborator/\(UUID().uuidString)")!) == nil)
    }

    @Test("La tête de lecture se déplace au timecode de la citation")
    @MainActor
    func seekAuTimecode() {
        let playhead = MeetingPlayhead(meetingStableID: reunion)
        playhead.duration = 600
        playhead.seek(to: 252)
        #expect(playhead.t == 252)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter CitationURLHandlingTests` → échec de compilation
(« has no member 'parseCitation' »).

- [ ] **Étape 3 : implémenter**

Dans `QuickLaunchURLHandler.swift`, ajouter :

```swift
extension QuickLaunchURLHandler {

    /// Une citation décodée depuis `onetoone://meeting/<uuid>?t=252&note=<uuid>`.
    /// Le schéma est privé : il ne vaut que sur cette machine, et c'est
    /// pourquoi l'export externe garde le timecode en texte (spec §8).
    struct MeetingCitation: Equatable {
        var meetingStableID: UUID
        var t: Double?
        var noteStableID: UUID?
    }

    /// Décode l'URL. `nil` pour tout ce qui n'est pas une citation de réunion :
    /// un autre schéma, un autre hôte, un UUID mal formé. Fonction pure.
    static func parseCitation(_ url: URL) -> MeetingCitation? {
        guard url.scheme == "onetoone", url.host == "meeting" else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        guard let premier = segments.first, let id = UUID(uuidString: premier) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let t = items.first { $0.name == "t" }?.value.flatMap(Double.init)
        let note = items.first { $0.name == "note" }?.value.flatMap(UUID.init(uuidString:))
        return MeetingCitation(meetingStableID: id, t: t, noteStableID: note)
    }

    /// Ouvre la réunion citée et, si un `t` est donné, déplace la tête de
    /// lecture. Rend `false` quand l'URL n'est pas une citation ou que la
    /// réunion n'existe pas — l'appelant laisse alors macOS traiter l'URL.
    @MainActor
    @discardableResult
    static func handle(url: URL,
                       router: QuickLaunchRouter,
                       context: ModelContext,
                       playhead: MeetingPlayhead? = nil) -> Bool {
        guard let citation = parseCitation(url) else { return false }
        let cible = citation.meetingStableID
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.stableID == cible })
        guard let meeting = try? context.fetch(descriptor).first else {
            print("[QuickLaunchURLHandler] no Meeting for citation \(cible)")
            return false
        }
        router.openMeeting(meeting)
        if let t = citation.t, let playhead, playhead.meetingStableID == cible {
            playhead.seek(to: t)
        }
        return true
    }
}
```

Dans `MeetingReportPreview.swift`, ajouter un délégué de navigation qui intercepte
`onetoone://` et appelle une closure `onCitation: (URL) -> Void` (défaut `{ _ in }`),
en laissant tout autre schéma s'ouvrir dans le navigateur :

```swift
    /// Appelée quand le lecteur clique un timecode `onetoone://`. Défaut vide :
    /// l'aperçu reste utilisable là où aucune tête de lecture n'est branchée.
    var onCitation: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onCitation: onCitation) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onCitation: (URL) -> Void
        init(onCitation: @escaping (URL) -> Void) { self.onCitation = onCitation }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            if url.scheme == "onetoone" {
                onCitation(url)
                decisionHandler(.cancel)
                return
            }
            // Un lien externe cliqué dans un rapport s'ouvre dans le
            // navigateur, pas dans l'aperçu : la WKWebView n'a ni barre
            // d'adresse ni bouton retour.
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
```

et brancher `webView.navigationDelegate = context.coordinator` dans `makeNSView`
(plus `context.coordinator.onCitation = onCitation` dans `updateNSView`).

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter CitationURLHandlingTests` → 4 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/QuickLaunchURLHandler.swift OneToOne/Views/Meeting/MeetingReportPreview.swift Tests/CitationLinkerTests.swift
git commit -m "feat(rapport): ouvrir une réunion au timecode depuis une citation"
```

---

### Tâche 13 : l'envoi — annexes, destinataires, versement projet

**Fichiers :**
- Créer : `OneToOne/Services/Report/ReportSendPreparation.swift`
- Modifier : `OneToOne/Services/ExportService.swift`
- Test : `Tests/ReportSendPreparationTests.swift` (créé)

**Interfaces :**
- Consomme : `AttachmentReportOptions`, `AttachmentImporter.copyIntoAppSupport(source:bucket:base:)`,
  `ReportOptionalBlocks.captures(of:)`.
- Produit :
  ```swift
  struct ReportSendPlan: Equatable { var attachmentPaths: [String]; var recipients: [String]; var projectCopies: [URL] }
  @MainActor enum ReportSendPreparation {
      static func recipients(for meeting: Meeting, options: AttachmentReportOptions) -> [String]
      static func annexPaths(for meeting: Meeting, options: AttachmentReportOptions) -> [String]
      @discardableResult static func pushToProject(_ meeting: Meeting, options: AttachmentReportOptions, base: URL) -> [URL]
      @discardableResult static func prepare(_ meeting: Meeting, base: URL) -> ReportSendPlan
  }
  ```

- [ ] **Étape 1 : écrire le test qui échoue**

`Tests/ReportSendPreparationTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import OneToOne

@Suite("À l'envoi du rapport — les trois cases du pied du tiroir")
@MainActor
struct ReportSendPreparationTests {

    private func contexte() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let cfg = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: cfg))
    }

    private func dossierTemporaire() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "lot15-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fichier(_ nom: String, dans dossier: URL) throws -> URL {
        let url = dossier.appending(path: nom)
        try Data("contenu".utf8).write(to: url)
        return url
    }

    @Test("Les pièces épinglées partent en annexe, et seulement si la case est cochée")
    func annexesPiecesEpinglees() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        let source = try fichier("Chiffrage.xlsx", dans: racine)

        let reunion = Meeting(title: "Revue", date: Date())
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        var options = AttachmentReportOptions.defaults
        #expect(ReportSendPreparation.annexPaths(for: reunion, options: options)
                == [source.path])
        options.attachPinned = false
        #expect(ReportSendPreparation.annexPaths(for: reunion, options: options).isEmpty)
    }

    @Test("Les destinataires sont les participants présents, quand la case est cochée")
    func destinatairesPresents() throws {
        let ctx = try contexte()
        let presente = Collaborator(name: "Marine LEROY")
        presente.email = "marine.leroy@exemple.fr"
        let absente = Collaborator(name: "Zied B")
        absente.email = "zied.b@exemple.fr"
        let sansMail = Collaborator(name: "Sans Mail")
        ctx.insert(presente); ctx.insert(absente); ctx.insert(sansMail)

        let reunion = Meeting(title: "Revue", date: Date())
        reunion.participants = [presente, absente, sansMail]
        ctx.insert(reunion)
        try ctx.save()
        reunion.setParticipantStatus(.absent, for: absente)

        var options = AttachmentReportOptions.defaults
        #expect(ReportSendPreparation.recipients(for: reunion, options: options)
                == ["marine.leroy@exemple.fr"])
        options.grantAccessToParticipants = false
        #expect(ReportSendPreparation.recipients(for: reunion, options: options).isEmpty)
    }

    @Test("Le versement copie dans les documents du projet et laisse l'original intact")
    func versementProjet() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        let source = try fichier("Chiffrage.xlsx", dans: racine)

        let projet = Project(code: "P25_110", name: "Marine", domain: "Assurance",
                             phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        var options = AttachmentReportOptions.defaults
        options.pushToProject = true
        let copies = ReportSendPreparation.pushToProject(reunion, options: options,
                                                          base: racine)
        #expect(copies.count == 1)
        #expect(FileManager.default.fileExists(atPath: copies[0].path))
        // « Copie, jamais référence » : l'original ne bouge pas.
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(copies[0].path.contains("projects/P25_110"))
        #expect(projet.attachments.contains { $0.fileName == "Chiffrage.xlsx" })

        // Idempotent : verser deux fois ne crée pas deux `ProjectAttachment`.
        _ = ReportSendPreparation.pushToProject(reunion, options: options, base: racine)
        #expect(projet.attachments.filter { $0.fileName == "Chiffrage.xlsx" }.count == 1)

        try? FileManager.default.removeItem(at: racine)
    }

    @Test("Case décochée, rien n'est versé")
    func versementDecoche() throws {
        let ctx = try contexte()
        let racine = try dossierTemporaire()
        let source = try fichier("Chiffrage.xlsx", dans: racine)
        let projet = Project(code: "P25_110", name: "Marine", domain: "A", phase: "Build")
        ctx.insert(projet)
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.project = projet
        ctx.insert(reunion)
        let piece = MeetingAttachment(url: source)
        piece.pinnedAtT = 1
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()

        #expect(ReportSendPreparation.pushToProject(reunion,
                                                     options: .defaults,
                                                     base: racine).isEmpty)
        #expect(projet.attachments.isEmpty)
        try? FileManager.default.removeItem(at: racine)
    }
}
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportSendPreparationTests` → échec de compilation
(« cannot find 'ReportSendPreparation' in scope »).

- [ ] **Étape 3 : implémenter**

Créer `OneToOne/Services/Report/ReportSendPreparation.swift` :

```swift
import Foundation
import os
import PDFKit
import AppKit

private let sendLog = Logger(subsystem: "com.onetoone.app", category: "report-send")

/// Ce que les trois cases du pied `À L'ENVOI DU RAPPORT` font — **au moment de
/// l'envoi**, jamais à la génération (spec §4.1).
///
/// La distinction n'est pas cosmétique : générer un rapport est un geste qu'on
/// répète, souvent plusieurs fois de suite pour ajuster un gabarit. Verser des
/// pièces dans les documents du projet à chaque essai remplirait la fiche de
/// doublons ; ajouter des destinataires à chaque essai n'aurait aucun sens.
struct ReportSendPlan: Equatable {
    var attachmentPaths: [String]
    var recipients: [String]
    var projectCopies: [URL]
}

@MainActor
enum ReportSendPreparation {

    // MARK: - Annexes

    /// Les fichiers joints au rapport : les pièces épinglées si la case l'est,
    /// et un PDF des captures cochées `Joindre au rapport`.
    static func annexPaths(for meeting: Meeting,
                           options: AttachmentReportOptions) -> [String] {
        var chemins: [String] = []
        if options.attachPinned {
            chemins += meeting.pinnedAttachments
                .map(\.filePath)
                .filter { FileManager.default.fileExists(atPath: $0) }
        }
        if let pdf = capturesPDF(for: meeting) { chemins.append(pdf.path) }
        return chemins
    }

    /// Un PDF d'une page par capture cochée, dans l'ordre du bloc de rapport.
    /// Réutilise le chemin slides→PDF d'`ExportService`, restreint aux captures
    /// que l'utilisateur a cochées : joindre les autres irait contre la case.
    static func capturesPDF(for meeting: Meeting) -> URL? {
        let entrees = ReportOptionalBlocks.captures(of: meeting)
        guard !entrees.isEmpty else { return nil }
        let doc = PDFDocument()
        var page = 0
        for entree in entrees {
            guard FileManager.default.fileExists(atPath: entree.imagePath),
                  let image = NSImage(contentsOfFile: entree.imagePath),
                  let p = PDFPage(image: image) else { continue }
            doc.insert(p, at: page)
            page += 1
        }
        guard page > 0 else { return nil }
        let nom = (meeting.title.isEmpty ? "reunion" : meeting.title)
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nom)-captures-\(UUID().uuidString.prefix(6)).pdf")
        return doc.write(to: url) ? url : nil
    }

    // MARK: - Destinataires

    /// « Donner l'accès aux participants » = les adresses des participants
    /// **présents**. Case décochée, la liste est vide : l'utilisateur adresse
    /// le message lui-même, ce qui est exactement ce que décocher veut dire.
    static func recipients(for meeting: Meeting,
                           options: AttachmentReportOptions) -> [String] {
        guard options.grantAccessToParticipants else { return [] }
        return meeting.participants
            .filter { meeting.participantStatus(for: $0) == .present }
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isLikelyEmail)
            .reduce(into: [String]()) { acc, mail in
                if !acc.contains(where: { $0.lowercased() == mail.lowercased() }) {
                    acc.append(mail)
                }
            }
    }

    private static func isLikelyEmail(_ s: String) -> Bool {
        guard !s.isEmpty, let at = s.firstIndex(of: "@") else { return false }
        return s[at...].firstIndex(of: ".") != nil && s.firstIndex(of: " ") == nil
    }

    // MARK: - Versement dans les documents du projet

    /// Copie les pièces épinglées dans `Bucket.project(code:)` et crée les
    /// `ProjectAttachment` correspondants. C'est l'exécution effective de la
    /// troisième case du lot 6, qui n'était jusqu'ici que persistée.
    ///
    /// Idempotent par nom de fichier : verser deux fois la même pièce ne crée
    /// qu'une entrée dans la fiche.
    @discardableResult
    static func pushToProject(_ meeting: Meeting,
                              options: AttachmentReportOptions,
                              base: URL = AttachmentImporter.baseDirectory()) -> [URL] {
        guard options.pushToProject, let projet = meeting.project else { return [] }
        var copies: [URL] = []
        for piece in meeting.pinnedAttachments {
            guard FileManager.default.fileExists(atPath: piece.filePath) else { continue }
            guard !projet.attachments.contains(where: { $0.fileName == piece.fileName })
            else { continue }
            do {
                let copie = try AttachmentImporter.copyIntoAppSupport(
                    source: URL(fileURLWithPath: piece.filePath),
                    bucket: .project(code: projet.code),
                    base: base)
                let versee = ProjectAttachment(url: copie,
                                               category: "Réunion",
                                               comment: "Versé depuis « \(meeting.title) »")
                // Le nom d'affichage est celui de la pièce, sans l'horodatage
                // que la copie ajoute : la fiche projet montre un document, pas
                // un nom de fichier technique.
                versee.fileName = piece.fileName
                versee.project = projet
                meeting.modelContext?.insert(versee)
                copies.append(copie)
            } catch {
                sendLog.error("versement projet impossible : \(String(describing: error), privacy: .public)")
            }
        }
        if !copies.isEmpty { try? meeting.modelContext?.save() }
        return copies
    }

    // MARK: - Tout, dans l'ordre

    /// Les trois cases, appliquées d'un coup au moment de l'envoi.
    @discardableResult
    static func prepare(_ meeting: Meeting,
                        base: URL = AttachmentImporter.baseDirectory()) -> ReportSendPlan {
        let options = meeting.reportAttachmentOptions
        return ReportSendPlan(attachmentPaths: annexPaths(for: meeting, options: options),
                              recipients: recipients(for: meeting, options: options),
                              projectCopies: pushToProject(meeting, options: options, base: base))
    }
}
```

Dans `ExportService.composeMeetingMail`, remplacer le calcul local des destinataires et des
pièces jointes par `let plan = ReportSendPreparation.prepare(meeting)` puis
`attachmentPaths += plan.attachmentPaths` et `let recipients = plan.recipients`, en gardant
le PDF des slides sous `options.contains(.includeSlidesPDF)` (comportement existant).

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportSendPreparationTests` → 4 tests verts.

- [ ] **Étape 5 : commiter**

```bash
swift build
git add OneToOne/Services/Report/ReportSendPreparation.swift OneToOne/Services/ExportService.swift Tests/ReportSendPreparationTests.swift
git commit -m "feat(rapport): exécuter les trois cases du pied à l'envoi"
```

---

### Tâche 14 : invites de l'espace Rapport, `STATUS.md`, PR

**Fichiers :**
- Modifier : `OneToOne/Views/Meeting/Spaces/MeetingReportSpace.swift`
- Modifier : `STATUS.md`
- Test : `Tests/ReportOptionalBlocksTests.swift`

**Interfaces :**
- Consomme : les `…EmptyInvite` de `ReportOptionalBlocks`.
- Produit : `MeetingReportSpace.invitesBlocsVides(for:) -> [String]` (statique, pure côté
  chaînes) pour être testable sans monter la vue.

- [ ] **Étape 1 : écrire le test qui échoue**

Ajouter à `Tests/ReportOptionalBlocksTests.swift` :

```swift
    @Test("Un bloc vide devient une invite, pas une section vide")
    func invitesPlutotQueSectionsVides() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        reunion.summary = "Contenu."
        ctx.insert(reunion)
        try ctx.save()

        let invites = MeetingReportSpaceInvites.forMeeting(reunion)
        #expect(invites.contains(ReportOptionalBlocks.pinnedEmptyInvite))
        #expect(invites.contains(ReportOptionalBlocks.capturesEmptyInvite))

        let piece = MeetingAttachment(url: URL(fileURLWithPath: "/tmp/Chiffrage.xlsx"))
        piece.pinnedAtT = 252
        piece.meeting = reunion
        ctx.insert(piece)
        try ctx.save()
        #expect(!MeetingReportSpaceInvites.forMeeting(reunion)
            .contains(ReportOptionalBlocks.pinnedEmptyInvite))
    }

    @Test("Case décochée, on n'invite pas à épingler")
    func pasDInviteQuandLaCaseEstDecochee() throws {
        let ctx = try contexte()
        let reunion = Meeting(title: "Revue", date: Date())
        var options = reunion.reportAttachmentOptions
        options.attachPinned = false
        reunion.reportAttachmentOptions = options
        ctx.insert(reunion)
        try ctx.save()
        #expect(!MeetingReportSpaceInvites.forMeeting(reunion)
            .contains(ReportOptionalBlocks.pinnedEmptyInvite))
    }
```

- [ ] **Étape 2 : vérifier l'échec**

`swift test --filter ReportOptionalBlocksTests` → échec de compilation
(« cannot find 'MeetingReportSpaceInvites' in scope »).

- [ ] **Étape 3 : implémenter**

Dans `MeetingReportSpace.swift`, ajouter au-dessus de la vue :

```swift
/// Les invites des blocs optionnels vides. Séparées de la vue pour être
/// vérifiables sans monter SwiftUI, et parce que la règle est du métier :
/// « afficher une invite plutôt qu'une section vide » (plan §5, lot 15 n° 6).
///
/// Une case décochée n'invite à rien : l'utilisateur a déjà répondu.
@MainActor
enum MeetingReportSpaceInvites {

    static func forMeeting(_ meeting: Meeting) -> [String] {
        var invites: [String] = []
        let options = meeting.reportAttachmentOptions
        if options.attachPinned, ReportOptionalBlocks.pinnedPieces(of: meeting).isEmpty {
            invites.append(ReportOptionalBlocks.pinnedEmptyInvite)
        }
        if ReportOptionalBlocks.captures(of: meeting).isEmpty {
            invites.append(ReportOptionalBlocks.capturesEmptyInvite)
        }
        return invites
    }
}
```

et, dans `body`, sous `toolbar` et le filet, une ligne d'invites quand elles existent :

```swift
                let invites = MeetingReportSpaceInvites.forMeeting(meeting)
                if !invites.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(invites, id: \.self) { invite in
                            Text(invite)
                                .font(.plexSans(11.5))
                                .foregroundStyle(One2OneToken.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
```

Le libellé `Rapport ✓ (m:ss)` de `MeetingTopChromeBar` n'est pas touché.

- [ ] **Étape 4 : vérifier le succès**

`swift test --filter ReportOptionalBlocksTests` → verts, puis **`swift test` complet**.

- [ ] **Étape 5 : `STATUS.md`, rebase, PR**

Ajouter la section du lot 15 **en tête** de `STATUS.md` (date `2026-09-08`) : ce qui est en
place, écarts (`Ce que j'ai livré` sans `DeliveredItemsBuilder`, légende de planche au lot 18,
câblage de la feuille du lot 9), fichiers partagés touchés, prochaine action.

Puis :

```bash
git add STATUS.md OneToOne/Views/Meeting/Spaces/MeetingReportSpace.swift Tests/ReportOptionalBlocksTests.swift
git commit -m "docs(status): consigner le lot 15 — rapport, blocs optionnels et citations"
git fetch origin
gh pr view 33 --json baseRefName --jq .baseRefName
# vaut feat/refonte-lot-11-1to1-manager-seance → l'intégration est finie :
#   git rebase --onto origin/feat/refonte-lot-12-1to1-manager-prepa $(cat .lot15-base-sha)
#   swift test   # complet, vert
#   gh pr create --base feat/refonte-lot-12-1to1-manager-prepa …
# sinon : gh pr create --base feat/refonte-lot-7-captures … (noter qu'un rebase suivra)
```

---

## Auto-revue

**Couverture de la spec.** §8 chaîne de citation → tâches 10-12 ; §8 filtre unique →
tâches 1-2, 6 ; §8 blocs optionnels → tâches 3-8 ; §4.1 pied à l'envoi → tâche 13 ;
§4.2 pièces citées → tâches 3, 11 ; §5.3 `Joindre au rapport` → tâches 4, 13 ;
§3.3 engagements et « les notes privées ne sont jamais incluses » → tâches 6, 9 ;
§6.2 côté collaborateur → tâche 9 (`d3_manager`) ; §7.3 planches → tâches 5, 11 ;
critère chantier 3 n° 3 → tâches 3, 11 ; critère chantier 6 n° 5 → tâches 5, 11 ;
D9 template Escalade → tâches 1, 9. **Écart assumé** : `Ce que j'ai livré` de §6.2
n'a pas de `DeliveredItemsBuilder` sur cette base — aucune variable inventée, écart
consigné dans `STATUS.md`. **Reporté au lot 18** : la légende textuelle des planches.

**Marqueurs.** Aucun « TBD », aucun « gérer les cas limites » : chaque étape porte son
code et sa commande.

**Cohérence des types.** `Audience`, `Visibility`, `CommitmentState`, `BoardMode`,
`SourceRef`, `AttachmentReportOptions` sont existants et utilisés avec leurs noms réels.
`ReportOptionalBlocks` expose cinq collecteurs `…(of:)` et dix rendus `…Markdown`/`…HTML`,
tous nommés à l'identique dans les tâches 3 à 8, 11 et 14. `CitationLinker.Mode` est le
même dans les tâches 10, 11 et 12.
