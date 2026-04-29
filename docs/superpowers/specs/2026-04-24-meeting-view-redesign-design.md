# Refonte MeetingView — design éditorial

**Date** : 2026-04-24
**Auteur** : Laurent De Berti (brainstorm assisté)
**Scope** : refonte UI de `OneToOne/Views/MeetingView.swift` (1578 lignes) inspirée de maquettes éditoriales (fond crème, serif, chips avatars empilés, carte Actions).

## 1. Intention

Transformer `MeetingView` d'un layout dense macOS-natif vers un design éditorial plus aéré, tout en conservant **toute la logique métier** (enregistrement, transcription, génération rapport, capture d'écran, RAG, imports, exports).

**Décisions cadrantes prises au brainstorm** :
- **Fidélité** : inspiration forte des maquettes (structure + style crème/serif), mais contrôles SwiftUI natifs à l'intérieur (DatePicker, Menu, Picker).
- **Panneau Actions** : sidebar collapsible (ni carte flottante, ni sidebar fixe), état persistant par meeting.
- **Recorder** : top chrome minimal sur 1 ligne + barre contextuelle conditionnelle sous le header.
- **Détails réunion** : bloc repliable, persistance par meeting via `@SceneStorage`.
- **Onglets** : underline custom (pas segmented).
- **Capture preview** : dans la sidebar Actions (bas) + badge compteur "N slides" sur le bouton Capture du top chrome.

## 2. Squelette

```
MeetingView.body
├── MeetingTopChromeBar              (1 ligne, toujours visible)
├── MeetingContextualRecorderBar     (visible si rec || WAV || capturing || transcribing || OCR)
└── HSplitView
    ├── MainPanel
    │   ├── MeetingHeaderEditorial
    │   ├── MeetingDetailsBlock      (collapsible, SceneStorage)
    │   ├── MeetingTabsUnderline
    │   └── sectionContent           (Notes / Transcription / Rapport / Documents)
    └── MeetingActionsSidebar        (collapsible entre 44pt rail et 320–440pt)
        ├── ActionsList (task rows + formulaire sticky)
        └── CapturePreviewCard
```

Toolbar natif `ToolbarItemGroup(.primaryAction)` : conservé mais allégé — seul "Enregistrer" (save context) y reste. Exporter et autres actions migrent dans le menu `⋯` du top chrome.

## 3. Composants

### 3.1 MeetingTopChromeBar

Hauteur 44pt. Fond `MeetingTheme.canvasCream`. Séparateur bas 0.5pt `MeetingTheme.hairline`.

Contenu gauche→droite :

1. **Breadcrumb** : `One2One › [project.name | kind label] › [sub]`.
   - Si `meeting.project != nil` : `One2One › Projets › [project.name]`.
   - Sinon : `One2One › [kind.label]` (RÉUNION / 1:1 / TRAVAIL).
   - Segments cliquables → nav back via coordinateur existant (ou `NotificationCenter` si pas de coordinateur — à vérifier dans Sidebar.swift).
   - Troncature au milieu si dépassement.

2. **Spacer**.

3. **Recorder pill** (trois états exclusifs) :
   - *Idle, pas de WAV* : pill rouge `● Enregistrer`, prominent, action = `startRecording()`.
   - *Recording* : pill noire `#111`, monospace `● HH:MM:SS` + boutons intégrés ⏸ (pause/resume) ⏹ (stop → transcribe). VU meter non ici (dans la barre contextuelle).
   - *WAV présent, idle* : pill noire `▶ HH:MM:SS / HH:MM:SS` (temps joué / total). Clic → toggle play. Bouton voisin `⟲` (re-transcrire).

4. **Bouton Capture** :
   - Idle + aucune slide : bouton bordured `☐ Capture` → ouvre `ScreenCaptureConfigView` en popover (comportement actuel).
   - Capture active : pill teintée bleue `● N slides` → popover liste slides (identique `slidesPopover` actuel).
   - Idle + slides existantes : bouton bordured `☐ Capture` avec **badge rouge compteur** en superposition affichant `N`. Clic → popover liste slides.

5. **Bouton Rapport** :
   - Style prominent `MeetingTheme.accentOrange`.
   - Désactivé si `meeting.rawTranscript.isEmpty` OU `isGeneratingReport` OU `recorder.isRecording` OU `stt.isTranscribing`.
   - Spinner inline pendant génération.
   - Si rapport déjà présent : style ghost `Rapport ✓`, clic = régénérer (confirmation si on veut écraser).

6. **Menu `⋯`** — `Menu` SwiftUI avec icône ellipsis, contenu :
   - Exporter sous-menu (Markdown / PDF / Mail / EML / Apple Notes) — migration des items actuels du toolbar.
   - Prompt spécifique (toggle show/hide du TextEditor du bloc Détails).
   - Importer Calendrier → `showCalendarImporter = true`.
   - Divider.
   - Enregistrer maintenant (flashe `saveStatusMessage`).

Pas de bouton "date maintenant" : la date devient éditable via clic sur la meta du header (popover DatePicker).

### 3.2 MeetingContextualRecorderBar

Fond `MeetingTheme.surfaceCream`. Hauteur variable. Animation slide-down/up 150ms. Affichage = concaténation de segments conditionnels, séparés par `Divider()` vertical 24pt.

**Segment RECORDING** (si `recorder.isRecording`, à gauche) :
- VU meter horizontal 140×8 (vert/orange/rouge selon level).
- Métriques : `Qualité: haute` · `Niveau: -XXdB` monospace caption.

**Segment PLAYBACK** (si `meeting.wavFileURL` existe ET pas en rec ET user a engagé player, à gauche — mutuellement exclusif avec RECORDING) :
- Bouton ◀︎15 (`player.skip(by: -15)`).
- Bouton ⏯ (`togglePlay`).
- Bouton 15▶︎ (`player.skip(by: 15)`).
- Slider pleine largeur restante (`player.currentTime` in `0...max(player.duration, 0.1)`).
- Label `HH:MM / HH:MM` monospace.

Le pill du top chrome reflète `player.isPlaying` et `player.currentTime`. Clic pill = toggle. Slider uniquement ici.

**Segment CAPTURE** (si `captureService.isCapturing`, milieu) :
- Icône 📷 + texte `Capture : auto XXs · N slides`.
- Bouton 📸 snapshot (`captureService.snapshot()`).
- Bouton ⏹ arrêter (`await captureService.stop()`).

**Segment PROGRESS** (droite) :
- Si `stt.isTranscribing` : `⟳ STT…` (pas de % car actuellement pas exposé).
- Si `captureService.ocrProgress != nil` : `⟳ OCR X/Y`.
- Si `isImportingAttachment` : `⟳ Import…`.

**Ligne d'erreurs** (sous la barre) :
- Condition : `recorder.lastError || transcribeError || reportError || captureService.lastError || attachmentError || calendarImportError`.
- Style : caption rouge, background rouge 0.08, padding 4, bouton `×` dismiss qui nil-ise l'erreur correspondante.
- Multiples erreurs empilées verticalement.

### 3.3 MeetingHeaderEditorial

Padding horizontal 28pt. Padding vertical 20pt.

Contenu :

```
[P25_241] COPIL · PROJET                                  [← vide, le top chrome tient le reste]
Evolution Offre Poste de travail Virtuel Citrix — Restitution POC
23/04/2026 · 11:30   [JD][FN][MR][YP][JO]…+3   10 participants
```

- **Badge projet** : si `meeting.project != nil`, capsule fond `MeetingTheme.badgeBlack`, texte blanc, `caption2.bold`, padding (6,2), margin-right 10pt. Contenu = `project.code`.
- **Kind label** : `caption2.weight(.semibold)`, `tracking 1.4`, foreground `.secondary`.
  - `.project` → `COPIL · PROJET`.
  - `.oneToOne` → `1:1 · [collaborator.name.uppercased()]`.
  - `.work` → `RÉUNION DE TRAVAIL`.
  - `.global` → `RÉUNION`.
- **Titre** : `EditableTextField` (existant) avec `font: MeetingTheme.titleSerif`, placeholder `Titre de la réunion…`, multi-line auto-wrap.
- **Meta ligne** (HStack 14pt spacing) :
  - Date format `dd/MM/yyyy · HH:mm` monospace caption. Clic → popover `DatePicker([.date, .hourAndMinute])` labels hidden.
  - `MeetingAvatarStack(participants: meeting.participants, max: 8)` — voir 3.6.
  - `Text("N participants")` caption secondary. Clic = toggle `detailsExpanded` (cohérent avec chevron du bloc Détails).

### 3.4 MeetingDetailsBlock

`@SceneStorage("meeting.\(meeting.persistentModelID.id).detailsExpanded") var detailsExpanded: Bool`. Valeur initiale :
- `true` si `meeting.title.isEmpty || meeting.participants.isEmpty` (création récente, besoin de configurer).
- `false` sinon.

Bouton header full-width (tap target) :
```
▾ Détails de la réunion                                    [chevron animé]
```

Si expandé, DisclosureGroup animé (ou VStack manuel + `withAnimation`) :

- Ligne TYPE / PROJET :
  - `TYPE` label caption2 bold tracking 1.2 + `Picker(MeetingKind)` style `.menu`.
  - Si `kind == .project` : `PROJET` label + `Picker(Project?)` style `.menu`, sinon ligne masquée.
- Section PARTICIPANTS :
  - Label `PARTICIPANTS` caption2 bold tracking 1.2.
  - Si `meeting.calendarEventTitle != ""` : ligne caption secondary `calendar` + titre calendrier (info passive existante).
  - `FlowLayout(spacing: 8)` de chips :
    - Chaque participant → `Menu { status items + retirer }` label = HStack(spacing: 6) { AvatarMini(collaborator, 18pt) + Text(name) + icône status si `.absent` }. Background `participantChipColor(for:)`. Radius 12. Padding (10, 5).
    - Bouton final `+ Ajouter` style dashed border (1pt dashed secondary), padding identique, action = `Menu` avec `availableCollaborators`.
- Section COLLABORATEURS (si `!availableCollaborators.isEmpty`) :
  - Label `COLLABORATEURS` caption2 bold tracking 1.2.
  - FlowLayout(8) de chips fond `collaboratorChipColor`, radius 12. Clic = `addParticipant(c)`. Inclut un chip dashed `+ Nouveau Collaborateur` (créé ailleurs via AllCollaboratorsView — juste ouvrir la vue via closure ou TODO : laisser bouton ad-hoc à sa place).
- Champ AD-HOC :
  - `TextField("Ad-hoc : nom…")` + bouton `+` bordured. Existant conservé.
- Prompt spécifique (si `showCustomPrompt == true`) :
  - TextEditor 70pt (existant).

### 3.5 MeetingTabsUnderline

Composant dédié. État lié à `activeSection: MeetingSection` (enum existant).

```swift
HStack(spacing: 28) {
    ForEach(MeetingSection.allCases) { section in
        tab(section)
    }
}
.overlay(alignment: .bottom) { Divider() }
```

Chaque tab :
- `body` : Text(label) + éventuel badge (`(N)` pour Documents si attachments, `✓` pour Rapport si summary, ` ●` pour Notes live si notes.count > 0 non inscrit dans transcript — optionnel).
- Actif : `.body.weight(.semibold)`, `.primary`, underline 2pt `MeetingTheme.accentOrange` animé via `@Namespace` + `matchedGeometryEffect(id: "underline", in: ns)`.
- Inactif : `.body`, `.secondary`, pas d'underline.
- Animation : `withAnimation(.easeInOut(duration: 0.2))` au changement.
- Hauteur : 40pt.

### 3.6 MeetingAvatarStack

Composant réutilisable.

```swift
struct MeetingAvatarStack: View {
    let participants: [Collaborator]
    let max: Int = 8
    let settings: AppSettings
    
    var body: some View {
        HStack(spacing: -8) {  // overlap
            ForEach(participants.prefix(max)) { p in
                AvatarCircle(collaborator: p, size: 26, settings: settings)
                    .overlay(Circle().stroke(MeetingTheme.canvasCream, lineWidth: 1.5))
            }
            if participants.count > max {
                Circle().fill(Color.secondary.opacity(0.2))
                    .frame(width: 26, height: 26)
                    .overlay(Text("+\(participants.count - max)").font(.caption2.bold()))
            }
        }
    }
}
```

`AvatarCircle` : cercle taille `size`, fond `participantChipColor` (depuis settings), texte = initiales 2 lettres blanc `caption2.bold`. Utilise même color mapping que chips actuels (couleurs configurées dans AppSettings).

### 3.7 MeetingActionsSidebar

Deux états pilotés par `@SceneStorage("meeting.\(id).actionsCollapsed") var actionsCollapsed: Bool` (default false).

**EXPANDED** (width min 320, max 440) — structure VStack :

1. Header :
   ```
   ACTIONS [n]                                    [sidebar.right toggle]
   ```
   - Label caption2 bold tracking 1.2 secondary.
   - Compteur `n` = `meeting.tasks.filter { !$0.isCompleted }.count`, badge rond rouge si > 0.
   - Bouton collapse = `Image(systemName: "sidebar.right")`, bordered.

2. List des tasks (ScrollView + LazyVStack — pas List native pour contrôler l'apparence) :
   - `onDelete` remplacé par menu `⋯` contextuel.
   - Drag-and-drop pour réordonner : `.draggable` + `.dropDestination`. Ordre persisté via nouveau champ `Meeting.tasks` (SwiftData gère l'ordre insertion mais pas un index explicite — **à vérifier** si besoin d'ajouter `ActionTask.sortIndex: Int`).
   - Card task :
     ```
     ○ Titre éditable…                                      [⋯]
       AvatarMini · Non assigné|Nom · 30/04/2026
     ```
     - Background `textBackgroundColor.opacity(0.55)` (conservé).
     - Radius 12.
     - Padding (14, 12).
     - Checkbox + EditableTextField (conservés).
     - Méta ligne 2 : AvatarMini 18pt + nom ou "Non assigné" (foreground secondary si nil) + `·` + date format `dd/MM/yyyy` ou "Pas d'échéance".
     - Menu `⋯` (hover) : Réassigner (picker collab), Échéance (DatePicker popover), Supprimer, Convertir en alerte projet (si `meeting.project != nil`).

3. Formulaire sticky bas :
   - `EditableTextField` placeholder "Nouvelle action…".
   - Row optionnel (apparaît au focus ou toujours visible au choix — **décider au fil du dev** — default : toujours visible mais compact) : Picker(Collaborator?) + Toggle Échéance + DatePicker si toggle on.
   - Bouton `+` rond rouge (MeetingTheme.accentOrange) ou bouton large "Ajouter l'action".

4. Divider.

5. CapturePreviewCard :
   - Label `CAPTURE` caption2 bold tracking.
   - Carte 16:9 full-width sidebar, radius 12 :
     - Si `currentSlides.last` existe : Image + overlay gradient + `Slide N · HH:mm`. Clic = popover slides.
     - Sinon : placeholder icône `camera.viewfinder` + "Aucune capture". Clic = ouvre `ScreenCaptureConfigView` si capture pas active.

**COLLAPSED** (width 44pt, rail vertical) :

VStack(spacing: 12) padding(vertical: 14) :
- Bouton `sidebar.left` (expand).
- Si `n > 0` : badge circle rouge avec `n`, tooltip hover = 3 premières tasks ouvertes (titre tronqué 40 chars).
- Icône `checkmark.circle` caption secondary (indicateur "il y a des tasks").
- Spacer.
- Si `currentSlides.count > 0` : icône `camera.viewfinder` + badge mini `N`, clic = expand + scroll vers capture.

Background `MeetingTheme.surfaceCream`. Séparateur gauche 0.5pt `hairline`.

**Animation** : transition largeur via `.frame(width:)` + `withAnimation(.easeInOut(duration: 0.2))`.

**Raccourci clavier** : `⌘⌥.` (à confirmer qu'il n'est pas pris par existant — sinon `⌘⇧A`).

## 4. Thème & tokens

Fichier `OneToOne/Views/Meeting/MeetingTheme.swift` :

```swift
import SwiftUI

enum MeetingTheme {
    static let canvasCream   = Color(nsColor: NSColor(srgbRed: 0.976, green: 0.960, blue: 0.929, alpha: 1))
    static let surfaceCream  = Color(nsColor: NSColor(srgbRed: 0.988, green: 0.980, blue: 0.957, alpha: 1))
    static let accentOrange  = Color(nsColor: NSColor(srgbRed: 0.776, green: 0.400, blue: 0.400, alpha: 1))
    static let hairline      = Color.secondary.opacity(0.18)
    static let badgeBlack    = Color(nsColor: NSColor(white: 0.10, alpha: 1))
    static let softShadow    = Color.black.opacity(0.06)

    static let titleSerif    = Font.system(size: 34, weight: .semibold, design: .serif)
    static let bodySerif     = Font.system(.body, design: .serif)
    static let sectionLabel  = Font.caption2.weight(.bold)
    static let meta          = Font.caption.monospacedDigit()
}
```

Dark mode : toutes les couleurs définies via `NSColor` → passer en dynamic via `NSColor(name: nil) { appearance in ... }` si on veut supporter dark. **Décision** : en phase 1, rester light only pour la MeetingView (cohérent avec l'esprit "papier"). À reprocher plus tard.

## 5. Découpage fichiers

Nouveau dossier `OneToOne/Views/Meeting/`.

| Fichier | Rôle |
|---|---|
| `MeetingView.swift` (existant, rétréci ~350 lignes) | Racine : state, services, HSplitView, actions métier (startRecording, generateReport, importCalendarEvent, applyReport, fetchHistoricalContext, fetchAttachmentsContext, saveContext) |
| `MeetingTheme.swift` | Tokens couleurs / polices |
| `MeetingTopChromeBar.swift` | Composant section 3.1 |
| `MeetingContextualRecorderBar.swift` | Composant section 3.2 |
| `MeetingHeaderEditorial.swift` | Composant section 3.3 |
| `MeetingDetailsBlock.swift` | Composant section 3.4 + FlowLayout si utilisé seulement ici (sinon reste au global) |
| `MeetingTabsUnderline.swift` | Composant section 3.5 |
| `MeetingAvatarStack.swift` | Section 3.6 + AvatarCircle + AvatarMini |
| `MeetingActionsSidebar.swift` | Composant section 3.7 (ActionsList + TaskRow + CapturePreviewCard + ActionsRail pour collapsed) |

**Communication inter-composants** : les sous-vues reçoivent `@Bindable var meeting`, les services via `@ObservedObject`, et des closures pour les actions (startRecording, generateReport, etc.) pour garder la logique asynchrone dans MeetingView.

`FlowLayout` (Layout existant) reste dans MeetingView.swift ou migre dans un fichier `Layouts/FlowLayout.swift` dédié (plus propre). **Décision** : le migrer.

## 6. Migration (ordre de travail)

Pas de flag, pas de toggle. Refonte in-place en étapes testables :

1. `MeetingTheme.swift` + `MeetingAvatarStack.swift` + `Layouts/FlowLayout.swift` (extraction).
2. `MeetingHeaderEditorial.swift` — brancher dans `MeetingView.mainPanel`, supprimer l'ancien `header`.
3. `MeetingDetailsBlock.swift` — brancher, supprimer `participantsSection` et les lignes TYPE/PROJET du header actuel.
4. `MeetingTabsUnderline.swift` — remplacer `sectionPicker`.
5. `MeetingTopChromeBar.swift` — insérer en haut du body, retirer les boutons correspondants du toolbar natif et du `recorderBar`.
6. `MeetingContextualRecorderBar.swift` — remplacer `recorderBar`.
7. `MeetingActionsSidebar.swift` — remplacer `actionsPanel`, implémenter collapsible avec SceneStorage.
8. Nettoyage final : suppression du code mort dans MeetingView (expected reduction : ~1200 lignes retirées, ~350 restantes).
9. Build + test manuel complet :
   - Créer une nouvelle réunion.
   - Enregistrer 30s audio → vérifier transcription → générer rapport.
   - Démarrer une capture d'écran, prendre 2 snapshots.
   - Ajouter participants, collaborateurs, ad-hoc.
   - Importer un fichier calendrier si possible.
   - Ajouter 3 tasks, cocher une, réordonner.
   - Collapse/expand sidebar.
   - Collapse/expand détails.
   - Export Markdown + PDF.

## 7. Risques & décisions à trancher en implémentation

- **HSplitView + rail 44pt** : `HSplitView` peut imposer un min-width. Fallback : `HStack` avec largeur animée manuelle. Décision au premier build.
- **Ordre des tasks** : drag-and-drop nécessite un champ `sortIndex` sur `ActionTask` OU s'appuyer sur l'ordre d'insertion SwiftData. Décision : ajouter `sortIndex: Int = 0` et `@Query(sort: \.sortIndex)` (migration légère du modèle — acceptable, sinon fallback sans reorder).
- **Navigation breadcrumb** : dépend de Sidebar.swift et du routing actuel. Vérifier comment naviguer "back to project" — sinon rendre les segments non-cliquables au début.
- **Dark mode** : désactivé phase 1. Les tokens sont light-only. Ajouter dark plus tard.
- **matchedGeometryEffect** : namespace local à `MeetingTabsUnderline`.
- **SceneStorage clé** : `"meeting.\(persistentModelID.storeIdentifier).\(persistentModelID.entityName).collapsed"` — persistentModelID stringifiable ? Vérifier. Fallback : `meeting.id` si un UUID stable existe.
- **Toolbar natif** : garder uniquement "Enregistrer maintenant" OU supprimer totalement et tout migrer dans le menu `⋯`. Décision : suppression totale, tout dans menu ⋯.

## 8. Hors-scope

- Pas de refonte de `transcriptView`, `reportView`, `documentsView` dans leur contenu (seulement padding + typographie serif pour le body).
- Pas de changement des modèles SwiftData (sauf `ActionTask.sortIndex` optionnel).
- Pas de changement des services AI, RAG, export, import calendrier.
- Pas de changement de la sidebar projet, chatbot, settings.
- Pas de dark mode en phase 1.
- Pas de nouveaux raccourcis clavier au-delà de l'expand sidebar.

## 9. Définition de terminé

- Le nouveau `MeetingView` s'affiche sans régression visuelle sur les features existantes.
- Tous les flux testés au §6 étape 9 passent.
- `MeetingView.swift` < 400 lignes.
- Aucun littéral de couleur hors `MeetingTheme`.
- Build compile sans warning nouveau.
- Pas de logs print erronés ajoutés (les existants `[MeetingView]` conservés).
