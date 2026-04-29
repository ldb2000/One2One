# Design — Import enrichi + Capture d'écran (slides)

**Date :** 2026-04-23
**App :** OneToOne (macOS Swift / SwiftPM / SwiftData / MLX / Ollama)
**Statut :** approuvé, à implémenter

## Contexte

OneToOne enregistre, transcrit et synthétise des réunions. Il gère déjà :

- `MeetingAttachment` avec extraction texte (PDF / PPTX / DOCX / XLSX) via `AIIngestionService.extractTextPublic`
- `TranscriptChunk` (RAG) avec embeddings Ollama `nomic-embed-text`
- `AIReportService` produisant résumé / points clés / décisions / actions / alertes (JSON)
- `ExportService.exportMeetingMarkdown / exportMeetingPDF / exportMeetingMail`
- `MeetingView` avec onglets Notes live / Transcription / Rapport / Documents

**Deux trous à combler :**

1. Le contenu des documents importés **n'est pas réellement injecté** dans le prompt du rapport ni dans le mail. Besoin : drag-and-drop + texte extrait utilisé pour le rapport et inclus dans le mail.
2. Aucune capture d'écran possible. Besoin : capturer des slides projetées (fenêtre ou rectangle précis, mode manuel ou détection de changement) pour les transcrire (OCR) et joindre au compte-rendu.

## Décisions produit (figées lors du brainstorming)

| # | Décision |
|---|---|
| 1 | Import : conserver le file picker existant et ajouter **drag-and-drop** sur l'onglet Documents |
| 2 | Approche d'injection au rapport : **RAG fin** (top-K chunks attachments) pour les gros docs, texte brut cap 8000 chars sinon |
| 3 | Source capture : **fenêtre applicative OU zone rectangulaire précise** (pas plein écran) |
| 4 | Mode capture : **manuel (snapshot)** OU **auto (détection changement de slide)** |
| 5 | Stockage slides : **hybride** — un seul `MeetingAttachment(kind: "slides")` qui agrège, mais fichiers PNG préservés individuellement via un modèle enfant `SlideCapture` |
| 6 | Mail : uniquement les **slides capturées** en pièces jointes (PDF/PPTX importés ne sont PAS ré-attachés) |
| 7 | Mail body : **HTML rendu** depuis le markdown interne (pas de markdown brut) |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  MeetingView — onglet "Documents"                           │
│  ├─ DropZone (drag & drop)                                  │
│  ├─ Bouton "Importer"                     ── fichier picker │
│  ├─ Bouton "Capturer écran" (nouveau)     ── popover setup  │
│  └─ Liste attachments (PDF / PPTX / slides agrégées)        │
└───────────┬─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│ PIPELINE IMPORT (existant + extensions)                     │
│                                                             │
│  URL(s) ──► MeetingAttachmentService.importDocument         │
│               ├─ extract text (AIIngestionService)          │
│               ├─ chunk + embed (déjà)                       │
│               └─ persist MeetingAttachment + TranscriptChunks│
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ PIPELINE CAPTURE (nouveau)                                  │
│                                                             │
│  ScreenCaptureService                                       │
│   ├─ sources : SCShareableContent (fenêtres) + rect libre   │
│   ├─ mode : manuel (snapshot) | auto (slide-change)         │
│   ├─ storage : recordings/<uuid>/slides/slide-NNN-HHMMSS.png│
│   ├─ OCR : Vision framework (async, batch)                  │
│   └─ agrégation : 1 MeetingAttachment(kind:"slides")        │
│                    + SlideCapture (nouveau modèle enfant)   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ REPORT + EXPORT (modifiés)                                  │
│                                                             │
│  AIReportService                                            │
│   └─ NEW : paramètre attachmentsContext injecté au prompt   │
│                                                             │
│  ExportService                                              │
│   ├─ markdown → HTML (via NSAttributedString markdown init) │
│   └─ mail : HTML body + PJ slides PNG uniquement            │
│         via AppleScript Mail.app (`html content`)           │
└─────────────────────────────────────────────────────────────┘
```

## 1. Import enrichi

### 1a. Drag-and-drop

`MeetingView.documentsView` reçoit un `.onDrop(of: [UTType.fileURL])` multi-fichiers. Extensions acceptées : `pdf, pptx, docx, xlsx, md, txt, png, jpg, jpeg, heic`. Les autres sont rejetées silencieusement via un banner d'erreur.

DropZone visuelle : bordure pointillée + icône `tray.and.arrow.down` quand `isTargeted`. Même chemin que le file picker : `MeetingAttachmentService.importDocument`.

### 1b. Attachments → Rapport IA

`AIReportService.generate` reçoit un nouveau paramètre `attachmentsContext: String`. Construit en amont dans `MeetingView.generateReport` via :

```swift
func fetchAttachmentsContext() async -> String {
    let meetingPID = meeting.persistentModelID
    let totalChars = meeting.attachments
        .map { $0.extractedText.count }
        .reduce(0, +)

    // Seuil : < 20_000 chars total → on injecte le texte brut cap par doc.
    // Au-delà → on bascule sur top-K chunks via RAGQuery scope attachment + meeting.
    if totalChars < 20_000 {
        return meeting.attachments
            .filter { !$0.extractedText.isEmpty }
            .map { "### \($0.fileName) (\($0.kind))\n\($0.extractedText.prefix(8000))" }
            .joined(separator: "\n\n")
    }

    let query = String(meeting.mergedTranscript.prefix(2000))
    let scope = RAGQuery.Scope(
        projectPID: nil,
        collaboratorPID: nil,
        meetingKind: nil,
        excludeMeetingPID: nil,
        sourceType: "attachment",
        meetingPID: meetingPID  // nouveau champ
    )
    let results = try? await RAGQuery.search(query: query, topK: 8, scope: scope, context: context)
    return (results ?? []).map { r in
        "### \(r.chunk.attachment?.fileName ?? "?") — extrait\n\(r.chunk.text)"
    }.joined(separator: "\n\n")
}
```

Le prompt aval ajoute une section :

```
Documents joints à cette réunion (prime sur la transcription pour les chiffres, dates, noms propres) :

{attachmentsContext}
```

### 1c. Attachments → Mail

`exportMeetingMarkdown` ajoute une section "Contenu des documents" qui inclut le texte extrait (limité 4000 chars par doc) avec le nom du fichier en `### ` heading. Sert à la fois pour l'export Markdown et pour le corps du mail après conversion HTML.

## 2. Capture d'écran

### 2a. Sélection de la source

Popover déclenché par un bouton "Capturer l'écran" dans la recorder bar de `MeetingView` :

```
┌──────────────────────────────────────┐
│  Capturer depuis…                    │
│  ○ Fenêtre                           │
│    [Dropdown: Keynote — Slide 1/42] │
│    [Rafraîchir]                      │
│  ○ Zone d'écran précise              │
│    [Définir la zone…]                │
│    Actuel : (120,80) 1280×720        │
│  ────────────────────────────────   │
│  Mode :                              │
│  ○ Manuel (bouton snapshot)          │
│  ○ Auto (détection slide change)     │
│      Intervalle : [2s]  Seuil : 15% │
│  [Commencer]                         │
└──────────────────────────────────────┘
```

**Fenêtre** : `SCShareableContent.current.windows` → filtre sur `windowLayer == 0` et `isOnScreen`. Dropdown affiche `"<AppName> — <Title>"`. Stocke `CGWindowID`.

**Zone rectangle** : clic "Définir la zone…" ouvre un overlay plein écran semi-transparent (NSWindow `.floating`, transparent, ignoreMouseEvents=false). Vue custom trace un rectangle via drag, escape annule, return/enter valide. Le `RectSelectorOverlay` retourne un `CGRect` en coordonnées écran + identifiant `CGDirectDisplayID`.

### 2b. Modes capture

**Manuel** : bouton "📸 Capturer" dans la recorder bar → un `ScreenCaptureService.snapshot()` → ajouté à la session.

**Auto slide-change** :
- Timer `interval` configurable 1 à 5 s (default 2 s)
- Chaque tick : capture frame via `SCStream` → `PerceptualHasher.hash(image) -> UInt64` (pHash 64 bits)
- Comparaison `hammingDistance(prev, current) ≥ threshold` (default 12 bits sur 64)
- Si changement significatif → conserver le frame + pousser en file OCR
- Tampon : dernière frame acceptée mémorisée pour la prochaine comparaison

### 2c. PerceptualHasher (pHash minimaliste)

Swift natif, pas de dépendance :
1. Downscale `CGImage` en 32×32 niveaux de gris
2. DCT 2D → garder le bloc 8×8 top-left
3. Calculer la médiane (hors composant DC)
4. Pour chaque pixel DCT : bit 1 si > médiane, 0 sinon → 64 bits

Distance de Hamming via `popcount(a ^ b)`.

### 2d. Stockage

Arborescence :
```
~/Library/Application Support/OneToOne/recordings/
└── <meeting-uuid>/
    └── slides/
        ├── slide-001-14h23m12s.png
        ├── slide-002-14h24m05s.png
        └── …
```

Un seul `MeetingAttachment(kind: "slides")` par session de capture. Si l'utilisateur relance une nouvelle session (Stop puis nouvelle capture) → nouvel attachment "slides-2", "slides-3"…

Nouveau modèle SwiftData :

```swift
@Model final class SlideCapture {
    var index: Int
    var capturedAt: Date
    var imagePath: String
    var ocrText: String = ""
    var perceptualHash: String = ""
    var attachment: MeetingAttachment?

    init(index: Int, capturedAt: Date, imagePath: String) {
        self.index = index
        self.capturedAt = capturedAt
        self.imagePath = imagePath
    }
}
```

`MeetingAttachment` gagne une relation :

```swift
@Relationship(deleteRule: .cascade, inverse: \SlideCapture.attachment)
var slides: [SlideCapture] = []
```

`extractedText` de l'attachment = concaténation OCR des slides avec séparateurs :

```
--- Slide 1 [14:23:12] ---
Titre slide 1 …

--- Slide 2 [14:24:05] ---
Contenu slide 2 …
```

Le chunking + embeddings RAG (`TranscriptChunk`) s'opère sur ce texte agrégé comme pour les autres documents. Réutilise le pipeline existant sans modification.

### 2e. OCR

`OCRService` wrappe Vision framework :

```swift
enum OCRService {
    static func recognize(imageAt url: URL,
                          languages: [String] = ["fr-FR", "en-US"]) async throws -> String {
        let handler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
```

Queue OCR : `ScreenCaptureService` maintient un `Task` par slide capturée, append au `SlideCapture.ocrText` puis rebuild `attachment.extractedText` (opération légère, en mémoire).

Quand l'utilisateur arrête la capture, un Await sur toutes les tâches OCR en cours avec indicateur "OCR en cours… N/M" avant de rendre l'attachment disponible au rapport.

### 2f. UI pendant capture

Dans la recorder bar, quand la capture est active, ajouter un élément :

```
📸 23 slides · [≡ liste]   ⏹ Arrêter capture
```

Click sur "23 slides" → popover list : vignette miniature + timestamp + bouton "Supprimer". Supprimer une slide retire aussi le fichier PNG et son `SlideCapture`.

### 2g. Permissions

Info.plist :

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>OneToOne capture les slides projetées pendant vos réunions pour les retranscrire et les joindre au compte-rendu.</string>
<key>NSAppleEventsUsageDescription</key>
<string>OneToOne pilote Mail.app pour envoyer le compte-rendu en HTML avec pièces jointes.</string>
```

Premier lancement de capture → popup système Screen Recording. Si refusé, `lastError` dans `ScreenCaptureService` et bouton "Ouvrir Réglages" dans le popover de config.

## 3. Mail HTML + pièces jointes slides

### 3a. Markdown → HTML

Nouveau fichier `MarkdownToHTML.swift`. Utilise `AttributedString(markdown:options:)` (macOS 12+) + conversion NSAttributedString → HTML :

```swift
enum MarkdownToHTML {
    static func render(_ markdown: String) -> String {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full
        )
        let attr = (try? AttributedString(markdown: markdown, options: opts))
            ?? AttributedString(markdown)
        let ns = NSAttributedString(attr)
        guard let data = try? ns.data(
            from: NSRange(location: 0, length: ns.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ), let body = String(data: data, encoding: .utf8) else {
            return "<html><body><pre>\(markdown)</pre></body></html>"
        }
        return body
    }
}
```

NSAttributedString → HTML produit un document HTML complet avec styles inline. Mail.app le rend proprement. Si rendu trop lourd plus tard, on pourra substituer par un renderer custom (regex sur `# /### / - / **bold**`) pour produire un HTML plus compact.

### 3b. `ExportService.exportMeetingMail` réécrit

```swift
func exportMeetingMail(meeting: Meeting) {
    let markdown = exportMeetingMarkdown(meeting: meeting)
    let html = MarkdownToHTML.render(markdown)
    let subject = "Compte-rendu : \(meeting.title.isEmpty ? "Réunion" : meeting.title) — \(meeting.date.formatted(date: .abbreviated, time: .omitted))"

    // PJ : uniquement les slides capturées.
    var attachmentURLs: [URL] = []
    for att in meeting.attachments where att.kind == "slides" {
        for slide in att.slides.sorted(by: { $0.index < $1.index }) {
            let url = URL(fileURLWithPath: slide.imagePath)
            if FileManager.default.fileExists(atPath: url.path) {
                attachmentURLs.append(url)
            }
        }
    }

    composeMailViaAppleScript(subject: subject, htmlBody: html, attachmentURLs: attachmentURLs)
}
```

### 3c. `composeMailViaAppleScript`

```applescript
tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"…", visible:true}
    tell newMsg
        set html content to "<html>…</html>"
        repeat with p in {"<path1>", "<path2>"}
            make new attachment with properties {file name:POSIX file p}
        end repeat
    end tell
    activate
end tell
```

La propriété `html content` est disponible dans Mail 16+ (macOS 14+). Déclenche le rendu HTML côté Mail.app. Réutilise la permission Automation déjà demandée pour `MailService`.

Fallback si `html content` échoue : définir `content` avec le markdown brut + ajouter un avertissement dans le log.

## 4. Schéma données

### 4a. Nouveau modèle `SlideCapture`

Dans `OneToOne/Models/MeetingModels.swift` — voir section 2d.

### 4b. `MeetingAttachment`

Ajout de la relation `slides`. Inchangé pour les autres types.

### 4c. `SchemaV1.models`

Ajouter `SlideCapture.self` à la liste. Lightweight migration auto : nouveau modèle et nouvelle relation optionnelle.

### 4d. `RAGQuery.Scope`

Ajout de champs :

```swift
struct Scope {
    var projectPID: PersistentIdentifier? = nil
    var collaboratorPID: PersistentIdentifier? = nil
    var meetingKind: MeetingKind? = nil
    var excludeMeetingPID: PersistentIdentifier? = nil

    // Nouveaux :
    var sourceType: String? = nil      // "meeting" | "attachment" | "mail" | nil (tous)
    var meetingPID: PersistentIdentifier? = nil  // restreint à une réunion précise
}
```

Le `filtered(context:scope:)` ajoute les deux filtres correspondants.

## 5. Nouveaux fichiers

| Fichier | Rôle |
|---|---|
| `OneToOne/Services/ScreenCaptureService.swift` | SCStream + modes + orchestration OCR |
| `OneToOne/Services/OCRService.swift` | Vision framework wrapper |
| `OneToOne/Services/PerceptualHasher.swift` | pHash pour slide-change |
| `OneToOne/Services/MarkdownToHTML.swift` | Rendu MD → HTML |
| `OneToOne/Views/ScreenCaptureConfigView.swift` | Popover sélection source + mode |
| `OneToOne/Views/RectSelectorOverlay.swift` | NSWindow fullscreen transparent pour drag-rect |

## 6. Fichiers modifiés

| Fichier | Changement |
|---|---|
| `OneToOne/Views/MeetingView.swift` | DropZone + bouton capture + état capture |
| `OneToOne/Services/AIReportService.swift` | Param `attachmentsContext`, bloc prompt |
| `OneToOne/Services/ExportService.swift` | `exportMeetingMail` réécrite (HTML + AppleScript) + `exportMeetingMarkdown` section Contenu des documents |
| `OneToOne/Services/RAGService.swift` | Scope `sourceType`, `meetingPID` |
| `OneToOne/Models/MeetingModels.swift` | `SlideCapture` + relation |
| `OneToOne/Models/SchemaVersions.swift` | `SchemaV1.models` += `SlideCapture.self` |
| `Info.plist` | 2 permissions |

## 7. Ordre d'implémentation

1. **Import enrichi** (drag-drop + report attachmentsContext + section mail) — ~2 h
2. **ScreenCaptureService + RectSelectorOverlay + popover config** — ~3 h
3. **PerceptualHasher + mode auto** — ~1 h
4. **OCR + SlideCapture + agrégation** — ~2 h
5. **Mail HTML + AppleScript PJ slides** — ~1.5 h
6. **Tests live + polish états vides/erreurs** — ~1.5 h

Total estimé : ~11 h d'implémentation.

## 8. Contraintes et risques

| Risque | Mitigation |
|---|---|
| Permissions Screen Recording refusées | UI guide vers Réglages + message clair |
| OCR lent sur batch de 50 slides | Queue async, progress indicator, ne bloque pas le Stop recording |
| Boucle de capture bouffe CPU | Interval minimum 1 s, comparaison pHash est O(64 bits XOR) |
| `html content` AppleScript échoue sur Mail ancien | Fallback plain-text + log avertissement |
| Migration SwiftData pour nouveau modèle | Le filet de sécurité `backup-before-wipe` est déjà en place |
| pHash insensible à animations subtiles | Paramètre seuil ajustable, par défaut conservateur (12 / 64) |

## 9. Critères d'acceptation

- Drag-drop de 3 PDF sur l'onglet Documents → 3 attachments importés, chunks indexés, visible dans la liste
- Génération de rapport sur une réunion avec 2 docs attachés → prompt LLM contient bien les extraits (vérifiable via log)
- Capture manuelle d'une fenêtre Keynote → 1 slide dans l'attachment, OCR rempli, vignette cliquable
- Capture auto 10 min avec 8 changements de slide → 8 `SlideCapture` en base, PNG fichiers présents, OCR rempli
- Export mail → Mail.app s'ouvre avec corps HTML rendu (pas de ``#`` visibles) et les PNG slides en PJ
- Aucune PJ si la réunion n'a pas de slides capturées
- Migration SwiftData d'un store V1 existant sans perte
