# Meeting menu commands (barre de menu macOS) — Design spec

**Date**: 2026-06-10
**Branch**: TBD (probable: `feat/meeting-menu-commands`)
**Author**: laurent.deberti
**Status**: Approved (design phase), awaiting implementation plan.

> ⚠️ À ne pas confondre avec `2026-05-14-menubar-quick-actions` qui concerne le
> `MenuBarController` (icône `NSStatusItem` dans la barre d'état système). Ici on
> parle de la **barre de menu de l'application** (menus `Fichier`, `Réunion`… en
> haut de l'écran) via l'API SwiftUI `Commands`.

## 1. Problème

L'écran réunion (`MeetingTopChromeBar`) concentre toutes les actions secondaires
dans un seul menu « ⋯ » devenu un fourre-tout : 11 actions hétéroclites à plat
(export Markdown/PDF/Mail/Outlook/Notes, prompt spécifique, import calendrier,
import WAV, édition audio, révéler le WAV, suppression). Aucun raccourci clavier,
suppression collée au reste. L'utilisateur le décrit comme « éparpillé ».

L'app n'a **aucun** `Commands` personnalisé : la barre de menu macOS ne contient
que les menus générés par défaut par SwiftUI.

## 2. Objectifs

- Déplacer les actions secondaires de la réunion vers la **barre de menu macOS**,
  avec des **raccourcis clavier**, dans des emplacements conventionnels.
- Garder un point d'entrée souris in-window (« ⋯ ») mais **allégé** et structuré
  en miroir des menus natifs.
- Une **source de vérité unique** pour ces actions, partagée entre le « ⋯ » et la
  barre de menu (pas de duplication des closures).
- Les commandes sont **grisées** quand aucune réunion n'a le focus, et item par
  item selon l'état (pas de rapport → export grisé, pas d'audio → édition grisée…).

### Non-objectifs

- Pas de refonte du cœur de la barre (enregistrement/lecture, Capture, sélecteur
  de template « Auto », bouton « Rapport ») : ces contrôles fréquents/stateful
  restent en place et inchangés visuellement.
- Pas de modification du `MenuBarController` (barre d'état système).
- Pas de nouveaux comportements métier : on réexpose les actions existantes.

## 3. Décisions validées

| Décision | Choix retenu |
|---|---|
| Organisation des menus | Export rangé sous **`Fichier`** (`.importExport`) ; tout le reste dans un **nouveau menu `Réunion`**. Pas de menu « Exporter » séparé. |
| Bouton « ⋯ » in-window | **Conservé**, allégé, en miroir des menus natifs. |
| Enregistrement/rapport dans le menu | **Oui**, ajoutés au menu `Réunion` avec raccourcis. |

## 4. Architecture

### 4.1 `MeetingMenuActions` — source de vérité partagée

Une **struct valeur** rassemblant, pour la réunion courante :

- les **closures d'action** déjà définies inline dans `MeetingView` (réutilisées
  telles quelles) : `startRecording`, `stopRecording`, `appendRecording`,
  `togglePause`, `togglePlay`, `retranscribe`, `generateReport`,
  `toggleCustomPrompt`, `importCalendar`, `importExistingWAV`, `revealWAV`,
  `editAudio`, `exportMarkdown`, `exportPDF`, `exportMail(_:)`,
  `exportOutlook(_:)`, `exportAppleNotes(_:)`, `deleteMeeting` ;
- les **drapeaux d'état** nécessaires à l'activation : `meetingTitle`,
  `isRecording`, `isPaused`, `isTranscribing`, `isGeneratingReport`, `hasWav`,
  `hasPlayableAudio`, `hasReport`, `hasTranscript`.

Méthode pure testable :

```swift
enum MeetingMenuItem { case startStopRecording, appendRecording, pause,
    generateReport, retranscribe, customPrompt, importCalendar, importWAV,
    editAudio, revealWAV, delete, exportMarkdown, exportPDF, exportMail,
    exportOutlook, exportNotes }

func isEnabled(_ item: MeetingMenuItem) -> Bool
```

(Les closures ne sont pas `Equatable` ; ce n'est pas requis pour un `FocusedValue`.)

### 4.2 Plomberie `FocusedValue`

```swift
struct MeetingMenuActionsKey: FocusedValueKey { typealias Value = MeetingMenuActions }
extension FocusedValues { var meetingMenu: MeetingMenuActions? { … } }
```

- `MeetingView` construit la struct dans son `body` (réutilise les closures
  existantes) et applique `.focusedValue(\.meetingMenu, actions)`.
- Comme `MeetingView` est le composant partagé par **les 4 points de
  présentation** (fenêtre dédiée `1to1-meeting` + navigations `DetailsViews`,
  `MeetingsListView`, `Sidebar`), poser le `focusedValue` sur `MeetingView`
  couvre tous les cas.
- **Point ouvert technique** : si `focusedValue` ne se propage pas de façon
  fiable depuis le détail de la fenêtre principale (selon l'état du first
  responder), basculer sur `focusedSceneValue`. À trancher en implémentation par
  vérification manuelle.

### 4.3 `MeetingCommands` — les menus natifs

Nouveau fichier `OneToOne/Views/Menus/MeetingCommands.swift` :

```swift
struct MeetingCommands: Commands {
    @FocusedValue(\.meetingMenu) private var menu
    var body: some Commands {
        CommandGroup(after: .importExport) { exportItems }   // → menu Fichier
        CommandMenu("Réunion") { meetingItems }               // → nouveau menu
    }
}
```

Chaque `Button` appelle la closure correspondante de `menu` et porte un
`.disabled(menu == nil || !menu!.isEnabled(.x))`. `menu == nil` ⇒ tout grisé.

Branché **une fois** dans `OneToOneApp` sur la `WindowGroup` principale :
`.commands { MeetingCommands() }` (les commandes sont globales à l'app ;
SwiftUI les fusionne quelle que soit la scène active).

### 4.4 Refactor de `MeetingTopChromeBar`

Aujourd'hui le composant reçoit **~20 closures** + drapeaux en paramètres d'init.
On remplace ce bloc par **un seul paramètre** `actions: MeetingMenuActions`
(les `ObservableObject` `recorder`/`stt`/`player`/`captureService`, qui pilotent
l'UI réactive de la pill et de la progression, **restent** des paramètres
séparés). Le `moreMenu` (« ⋯ ») lit `actions` → même source que les menus natifs.

> C'est le principal changement structurel. Il sert directement l'objectif
> (source unique) et simplifie un init devenu lourd. Aucun autre refactor.

## 5. Contenu du menu « Réunion »

```
Démarrer l'enregistrement            ⇧⌘R   ← libellé "Arrêter et transcrire" si isRecording
Reprendre l'enregistrement                 (activé si hasWav && !isRecording)
Mettre en pause / Reprendre                (activé si isRecording ; libellé selon isPaused)
─────────
Générer le rapport                    ⌘↩   (activé si hasTranscript && !busy)
Relancer la transcription            ⇧⌘T   (activé si hasWav && !isTranscribing)
Prompt spécifique…
─────────
Importer depuis le calendrier…
Importer un fichier WAV…
─────────
Éditer l'audio…                            (grisé si !hasPlayableAudio)
Révéler le WAV dans le Finder              (grisé si !hasPlayableAudio)
─────────
Supprimer la réunion…                 ⌘⌫   (role: .destructive)
```

`busy` = `isRecording || isTranscribing || isGeneratingReport`.

## 6. Menu « Fichier » → groupe Exporter

```
Copier le rapport en Markdown        ⇧⌘C
Exporter en PDF…                     ⇧⌘E
Envoyer via Apple Mail            ▸  Rapport seul · +slides (PDF) · +transcript · +tout
Envoyer via Microsoft Outlook     ▸  (idem)
Exporter vers Apple Notes         ▸  (idem)
```

Tous grisés tant que `!hasReport`. Les 4 variantes reprennent exactement les
`MeetingMailExportOptions` actuelles.

## 7. « ⋯ » in-window (allégé)

De 11 items à plat → ~5 entrées avec sous-menus, en miroir :

```
Exporter ▸ (Copier Markdown, Exporter PDF, Apple Mail▸, Outlook▸, Apple Notes▸)
─────────
Prompt spécifique
Importer ▸ (Calendrier, WAV existant)
Audio ▸ (Éditer l'audio…, Révéler le WAV)
─────────
Supprimer la réunion…              (role: .destructive)
```

## 8. Raccourcis — table & non-conflit

| Action | Raccourci | Note |
|---|---|---|
| Démarrer/Arrêter l'enregistrement | ⇧⌘R | « R » = Record ; évite ⌘R (parfois Reload) |
| Générer le rapport | ⌘↩ | « valider/lancer » naturel |
| Relancer la transcription | ⇧⌘T | |
| Copier en Markdown | ⇧⌘C | ⌘C reste « Copier » système |
| Exporter en PDF | ⇧⌘E | évite ⌘P (Imprimer) |
| Supprimer la réunion | ⌘⌫ | convention « supprimer » |

Imports, prompt, édition/révélation audio : **sans raccourci** (actions rares).
Tous les raccourcis sont **ajustables** — ce sont des propositions.

## 9. Tests & vérification

- **Test unitaire** (`Tests/MeetingMenuActionsTests.swift`) sur
  `isEnabled(_:)` : matrice d'états (pas de rapport → exports désactivés ;
  `!hasPlayableAudio` → édition/révélation désactivées ; `isRecording` →
  re-transcription désactivée ; etc.). C'est la seule logique proprement
  testable en unité.
- **Vérification manuelle** via `Scripts/bump-and-build.sh dev` :
  1. menus `Réunion`/`Fichier→Exporter` présents quand une réunion est au focus ;
  2. **tout grisé** quand on est sur le Dashboard (aucune réunion focus) ;
  3. items grisés cohérents avec l'état (sans rapport, sans audio) ;
  4. raccourcis fonctionnels ; 5. actions identiques à l'ancien « ⋯ » ;
  6. « ⋯ » allégé OK en souris.

## 10. Fichiers touchés

| Fichier | Changement |
|---|---|
| `OneToOne/Views/Menus/MeetingMenuActions.swift` | **Nouveau** — struct + `isEnabled` + `FocusedValueKey`/`FocusedValues`. |
| `OneToOne/Views/Menus/MeetingCommands.swift` | **Nouveau** — `Commands` (menu `Réunion` + groupe Exporter). |
| `OneToOne/OneToOneApp.swift` | `.commands { MeetingCommands() }` sur la `WindowGroup` principale. |
| `OneToOne/Views/MeetingView.swift` | Construit `MeetingMenuActions` ; `.focusedValue` ; passe la struct au chrome bar. |
| `OneToOne/Views/Meeting/MeetingTopChromeBar.swift` | Init simplifié (`actions:`) ; `moreMenu` allégé en sous-menus. |
| `Tests/MeetingMenuActionsTests.swift` | **Nouveau** — tests d'activation. |

## 11. Risques / points ouverts

1. **Propagation `focusedValue`** depuis la fenêtre principale (cf. §4.2) →
   fallback `focusedSceneValue`. Vérif manuelle requise.
2. **Localisation des menus système** : `Fichier` s'affiche selon la langue du
   Mac ; `Réunion` est fourni en dur en français. Cohérent pour un usage FR.
3. **Item « Démarrer/Arrêter » à libellé dynamique** : rendu conditionnel selon
   `isRecording` ; vérifier la mise à jour live (dépend de la réévaluation du
   `focusedValue` quand `MeetingView` se redessine).
