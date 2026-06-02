# Rapport de revue & nettoyage — 2026-06-02

Revue exhaustive des **170 fichiers Swift** (~40 000 lignes) : cartographie complète,
détection de code mort vérifiée, documentation, simplifications sûres. Ce rapport
récapitule ce qui a été appliqué, ce qui a été délibérément conservé, et la roadmap des
refactors plus profonds laissés de côté (par prudence).

**État de validation : `swift build` ✅ · `swift test` ✅ 69/69 (identique à la référence).**

Diff : 159 fichiers modifiés, +1802 / −662, 3 fichiers supprimés.

---

## 1. Code mort supprimé (13)

Chaque suppression a été **vérifiée par grep sur tout le dépôt** (y compris refs string,
AppIntents, sélecteurs) puis confirmée par compilation.

| Fichier | Élément retiré | Raison |
|---|---|---|
| `Markdown/Core/EditorRepresentable.swift` | `import Combine` | Aucune API Combine utilisée |
| `Services/Maintenance/AudioCompressionService.swift` | `export.audioMix = nil` | No-op (déjà nil par défaut) |
| `Services/ExternalServices.swift` | Bloc AppleScript commenté | Code mort commenté (URL scheme actif) |
| `Services/LinkedInPhotoSearch.swift` | champ `title` (DDGResponse.Item) | Champ JSON jamais lu |
| `Services/MenuBarController.swift` | propriété `urgentTaskForPopover` (+ assignation) | Écrite, jamais lue |
| `Services/ExportService.swift` | `exportMeetingOutlookEML(meeting:)` | 0 appelant (shim « rétro-compat » obsolète) |
| `Views/SettingsView.swift` | `@State oauthToken` | Jamais lue ni liée |
| `Views/Meeting/MeetingTopChromeBar.swift` | paramètre `hasWAV` (+ call site) | Doublon mort de `hasWav` |
| `Views/DetailsViews.swift` | `previewedProjectAttachment` + sa `.sheet` | Jamais mise à non-nil → sheet jamais affichée |
| `Views/MeetingView.swift` | `section(_:_:)`, `bulletRow(...)`, `seekToSegment(...)` | 3 helpers privés sans appelant |
| **`Views/MermaidView.swift`** | **fichier entier** | `MermaidView` jamais instancié nulle part |
| **`Services/MarkdownToHTML.swift`** | **fichier entier** | Supplanté par `MarkdownToHTMLRenderer`, 0 référence |
| **`Services/ProjectSummaryService.swift`** | **fichier entier** | Service jamais appelé |

> ⚠️ **`MermaidView`** : la fonctionnalité « diagrammes Mermaid » du README n'était plus
> branchée (aucune instanciation). Le code étant réellement mort, il a été retiré. Si tu
> veux réactiver Mermaid, le restaurer depuis l'historique git (`git show HEAD:OneToOne/Views/MermaidView.swift`).

---

## 2. Code conservé volontairement (16) — NE PAS supprimer

Candidats « sans référence en code » mais qui **doivent rester** :

- **Schéma SwiftData persisté** : `AppSettings.braveSearchKey` (déprécié mais maintenu pour
  éviter une migration), `Note.stableID`. Supprimer un champ `@Model` casserait la
  migration / corromprait les bases existantes.
- **Conformances de protocole** : `FlexKey.intValue` / `init(intValue:)` (témoins
  `CodingKey` requis même si inutilisés).
- **DTO de backup/restore** : `ProjectDTO.comment2`, `SettingsDTO.managerReportPrompt`
  (sérialisation JSON — retirer casserait la lecture d'anciens backups).
- **Alias de compat documentés** : `SpeakerMatcher.autoThreshold` / `suggestThreshold`.
- **Garde-fous / API système** : `OneToOneApp.didRunDataRepair`, `@unknown default`
  (AudioRecorderService), `CalendarAgendaService.changeObserver` (cleanup d'observer),
  `@Query` (CalendarEventImportSheet) — mécanisme réactif SwiftUI.
- **Exhaustivité d'enum** : cases `FilterStatus.all` / `DueDateFilter.any` (ActionsListView).
- **Templates intégrés** : `BuiltInTemplates.d1…d10` (référencés via `all`).

## 3. Faux positifs écartés (≈14)

Candidats marqués « morts » par l'analyse automatique mais **rejetés après vérification
manuelle** (auto-contradictoires, refactors déguisés, ou réellement utilisés) :

- `EditableTextField` → `MarkdownEditorRegistry` : **utilisé par la toolbar** (même fichier).
- `EditableTextField` → `textViewID` : paramètre d'API conservé pour rétro-compat.
- `AIReportService` → `revise()` / `extractJSONBlock` : la boucle critique-révision est une
  feature réelle (partenaire `critique()`, `ReportRevision` créés dans `MeetingView`).
- `MailBrowserView` 518-520 : **non** redondant (fixe aussi `selectedAttachmentIDs`).
- `ManagerCRGenerator.Wrapper`, `MeetingHighlightableTextView.line` : utilisés (refactor, pas mort).
- `AllCollaboratorsView.statCell` (utilisé 5×), param `coordinator` (signature protocole), etc.

## 4. À revoir manuellement (4 incertains)

- `MeetingModels.AdhocAttendee` — Codable/Hashable sans usage direct évident (vérifier le
  décodage `adhocAttendeesJSON`).
- `JobQueueSidebar.showsHeader` — paramètre à défaut, usage interne uniquement.
- `RectSelectorOverlay` — `DragGesture().onEnded { _ in }` vide (probablement requis pour activer le geste).

---

## 5. Documentation ajoutée

- **642 doc-comments `///`** ajoutés (français, style du dépôt) sur types, services, vues et
  méthodes clés non documentés.
- **`docs/architecture.md`** — document d'architecture complet (sous-systèmes, modèle de
  données, pipeline STT/diarisation, services IA, flux, intégrations, diagrammes Mermaid).

## 6. Simplifications appliquées (42, iso-comportement)

Uniquement des changements **mécaniquement sûrs**, vérifiés par build + tests :

- **Cache de `DateFormatter`/`RelativeDateTimeFormatter`** recréés à chaque appel → `static let`
  (≈16 occurrences : DetailsViews, WeekStripView, SearchPopover, ReportTemplating, MailService,
  AIIngestionService, ManagerActionReviewSheet, MeetingHeaderEditorial, ActionsPanel…).
- **Extraction de helpers dupliqués** : `QuickLaunchRouter` (`saveContext`, `launchWith`),
  `TranscriptionService.deleteExistingSegments`, `OCRService.perform`, `MailBrowserView.fetchMailBody`,
  `MeetingView.fieldText`, `ChatbotView` guard partagé, `JobQueueSidebar`.
- **`Sidebar`** : `batchUpdate` générique par `ReferenceWritableKeyPath` (fusionne 3 setters) ;
  dédup de `riskColor` (2 définitions → 1).
- Suppression d'alias/no-ops redondants, constantes nommées pour magic numbers, `@Bindable` direct.

## 7. Roadmap — refactors différés (371, par prudence)

Non appliqués car **non garantis iso-comportement** ou structurels (jugement requis). À traiter
manuellement, par ordre de valeur :

1. **Découper les objets « dieu »** (cf. `architecture.md` §13) :
   - `MeetingView` (~2300 l.), `DetailsViews` (~2670 l.), `Sidebar` (~1890 l.),
     `SettingsView` (~1200 l.) → fichiers/sous-vues par responsabilité.
   - Modèle `Meeting` (50+ propriétés), `Project` (40+).
2. **Factoriser les helpers JSON `@Model`** (encode/decode des champs JSON-backed) — risqué car
   touche la sérialisation ; à faire avec tests dédiés.
3. **Centraliser** : palette navy/cream dupliquée (`ReportThemeCSS` vs `ReportHTMLBuilder`),
   extension `Array`/subscript « safe » répétée dans plusieurs services.
4. **Extractions structurelles** signalées (parsers Markdown, `AIIngestionService`,
   `MeetingDetailsBlock.resyncFromCalendar`…) — bénéfice réel mais refonte de flux.
5. **Robustesse / i18n** : remplacer les `try?`/early-return silencieux par du logging ;
   externaliser les chaînes FR (pas de `Localizable.strings`).

---

*Méthode : cartographie (36 lots) → vérification adversariale du code mort (30 lots, grep
repo-wide) → application (39 lots) → build + tests. Toute suppression validée par compilation ;
toute simplification validée par les 69 tests.*
