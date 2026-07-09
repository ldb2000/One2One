# Redesign écran Réunion — Dashboard « Vue d'ensemble » — Design

**Date** : 2026-07-09
**Statut** : validé (brainstorming), en attente de plan d'implémentation

## Objectif

Transformer l'écran de réunion pour correspondre aux maquettes fournies : un onglet
**« Vue d'ensemble »** en dashboard de cartes pleine largeur (Présence, Transcription live,
Actions, Capture, Projets affectés), une modale **« Gérer les participants »**, et un statut de
présence enrichi (« En attente »). Le chrome et le thème existants (crème/rouge-brique) sont
conservés et seulement retouchés.

Principe directeur : **réutiliser au maximum l'existant** (thème `MeetingTheme`, logique
participants, système de panneaux configurables `PanelLayoutEntry`) plutôt que reconstruire.

## Contexte (état actuel vérifié)

- **Thème** : `MeetingTheme` (`Views/Meeting/MeetingTheme.swift`) est déjà crème/beige
  (`canvasCream`, `surfaceCream`) + accent rouge-brique (`accentOrange`). **Aucun restyle** de
  palette nécessaire.
- **Onglets** : `enum MeetingView.MeetingSection` (`Views/MeetingView.swift:148-156`) =
  `preparation` / `liveNotes` / `liveTranscript` (« Direct ») / `transcript` / `report` /
  `documents`. Rendus par `sectionContent` (`:513-530`). Barre `MeetingTabsUnderline`.
- **Layout** : `body` = chrome + tabs + `HStack { mainPanel (minWidth 520) ; sidebar droite }`
  (`Views/MeetingView.swift:236-269`). Sidebar = `ConfigurableRightSidebar` (360px) sauf
  `.manager` → `ManagerAgendaSidebar` (380px). `HStack` (pas `HSplitView`) pour contourner un
  crash AppKit.
- **Participants** : modèle `Meeting` (`Models/MeetingModels.swift`) avec `participantStatuses`,
  `participantStatus(for:)`, `setParticipantStatus(_:for:)`, `clearParticipantStatus(for:)`
  (`:183-223`). Statut `MeetingAttendanceStatus` (`:45-64`) : **2 cas seulement**
  `.participant` / `.absent`. Logique UI dans `MeetingView` : `availableCollaborators` (`:1051`),
  `addParticipant` (`:1058`), `removeParticipant` (`:1064`), `removeAllParticipants` (`:1075`),
  `setParticipantStatus`/`participantStatus` (`:1102`), `addAdhocParticipant` (`:1112`).
  `resyncFromCalendar()` dans `MeetingDetailsBlock` (`:376-423`). Ad-hoc = `Collaborator.isAdhoc`
  (`Models/OtherModels.swift:47`).
- **Panneaux configurables** : `PanelLayoutEntry` (`Views/Meeting/Sidebar/PanelLayoutEntry.swift`,
  `{id, visible}`, persistance JSON `AppSettings.rightSidebarLayoutJSON`, migration auto des
  nouveaux cas, testé). `RightSidebarPanelID` (`.actions`/`.projects`/`.capture`).
  `ConfigurableRightSidebar` fournit déjà **drag-réordonner + show/hide + menu engrenage +
  reset**. Cartes de contenu isolées et réutilisables : `ActionsPanel`, `ProjectsPanel`,
  `CapturePanel`.
- **Avatars** : `MeetingAvatarStack` (photo/initiales, badge « +N »).
- **Transcription live** : `LiveTranscriptionService.shared` (`@Published liveTranscript`,
  `isLive`, `statusMessage`), affiché par `LiveTranscriptPanel` dans l'onglet « Direct ».

## Décisions produit (arbitrées)

| Sujet | Décision |
|---|---|
| Dashboard vs sidebar | **Remplacer** la sidebar permanente par un onglet « Vue d'ensemble » (grille pleine largeur). |
| Statuts de présence | **3 statuts** : présent / refusé / en attente. « Invité »/« Collaborateur » = libellé dérivé de `isAdhoc`. |
| Personnalisation grille | **Gabarit responsive fixe** + réordonner/masquer (réutilise `PanelLayoutEntry`). Pas de drag&resize libre. |
| Carte Transcription | Aperçu live ; l'icône agrandir ↗ ouvre l'onglet « Direct ». Onglets Direct/Transcription inchangés. |
| Cas `.manager` | L'agenda manager devient une **carte** du dashboard, visible seulement si `.manager`. |
| « Personnaliser » | **Conservé** (bascule mode édition : poignées + menu panneaux). |
| Livraison | **Une seule spec/plan** couvrant les 5 volets. |

## Architecture

### Composant 1 — Statut de présence « En attente »

`MeetingAttendanceStatus` (`Models/MeetingModels.swift`) : ajouter le cas `.pending`.
Rester sur la convention SwiftData (stockage en raw `String`) → **migration légère sans risque** :
les valeurs existantes (`participant`/`absent`) restent valides ; aucune donnée `pending`
préexistante. Renommage sémantique recommandé pour coller à la maquette :
`.present` / `.refused` / `.pending` (avec compatibilité de décodage des anciens raw
`participant`/`absent` → `present`/`refused`).

Mapping import calendrier (`CalendarMeetingImportService.swift:78`) : `declined` → `.refused`,
`tentative`/`needsAction` → `.pending`, `accepted`/autres → `.present`.

Libellé dérivé (pas un statut) : `Collaborator.isAdhoc == false && !dansAnnuaire` → « Invité » ;
sinon « Collaborateur ». Règle exacte précisée au plan.

**Testable (pur)** : mapping statut de participation calendrier → 3 statuts.

### Composant 2 — Onglet « Vue d'ensemble » et suppression de la sidebar fixe

- `MeetingSection` : ajouter `.overview = "Vue d'ensemble"` en **premier** cas ; défaut
  `activeSection = .overview`.
- `body` : le `HStack { mainPanel ; sidebar }` devient `mainPanel` pleine largeur. La sidebar
  droite permanente (`ConfigurableRightSidebar`) n'est plus montée ; `ManagerAgendaSidebar` non
  plus (son contenu devient une carte, cf. composant 3).
- `sectionContent` : `case .overview: OverviewDashboard(...)`. Les autres onglets inchangés,
  désormais pleine largeur.

### Composant 3 — Grille de cartes `OverviewDashboard`

- Réutilise le système de panneaux : renommer `RightSidebarPanelID` → `MeetingPanelID`, ajouter
  `.presence` et `.transcription` (+ `.managerAgenda` conditionnel `.manager`). `PanelLayoutEntry`
  et sa migration absorbent les nouveaux cas.
- **Gabarit responsive fixe** : rangée « héro » 2 colonnes (gauche ~1fr = Présence,
  droite ~1.6fr = Transcription) puis rangée(s) utilitaire(s) 3 colonnes (Actions, Capture,
  Projets), qui se replient responsivement sous une largeur seuil. L'ordre des cartes visibles
  (issu de `PanelLayoutEntry`) alimente les slots dans l'ordre : slot héro-gauche, slot héro-droite,
  puis flux 3-par-rangée. Réordonner via drag met à jour l'ordre ; show/hide via le menu
  « Personnaliser ».
- **Mode « Personnaliser »** : un état `isEditingLayout` affiche les poignées ⠿ sur les cartes et
  le menu de visibilité (repris de `ConfigurableRightSidebar` : toggles + « Réinitialiser »).
- **`DashboardCard`** : conteneur commun (fond `surfaceCream`, coins arrondis, ombre douce,
  en-tête = poignée + icône + titre + actions d'en-tête + compteur/badge optionnel). Chaque carte
  de contenu s'y insère.
- Contenu des cartes : `ActionsPanel`, `ProjectsPanel`, `CapturePanel` **réutilisés tels quels** ;
  `PresenceCard` et `TranscriptionCard` nouveaux (composants 4 et 6) ; agenda manager = contenu de
  `ManagerAgendaSidebar` ré-emballé en carte (carte `.managerAgenda`, visible si `.manager`).

**Testable (pur)** : sérialisation `PanelLayoutEntry` avec `MeetingPanelID` étendu (round-trip,
migration des nouveaux cas).

### Composant 4 — Carte « Présence » (`PresenceCard`)

- Donut de présence : `% = présents / total` (arc vert = présents, arc rouge = refusés, reste
  neutre = en attente). Grand pourcentage centré + libellé « de présence ».
- Compteurs : « X présents » (point vert), « Y ont refusé » (point rouge), « Z en attente »
  (point orange) — la ligne en attente masquée si Z = 0.
- Pile d'avatars (`MeetingAvatarStack`) + badge « +N ».
- Bouton **« Gérer les participants »** → ouvre `ManageParticipantsSheet`.
- Compteur total (ex. « 42 ») dans le coin de l'en-tête de carte.

**Testable (pur)** : calcul des compteurs et du pourcentage à partir des statuts.

### Composant 5 — Modale « Gérer les participants » (`ManageParticipantsSheet`)

Sheet SwiftUI réutilisant la logique existante (passée en closures depuis `MeetingView`, comme
le fait déjà `MeetingDetailsBlock`) : `addParticipant`, `removeParticipant`,
`setParticipantStatus`, `participantStatus`, `addAdhocParticipant`, `removeAllParticipants`,
`resyncFromCalendar`, `availableCollaborators`.

- En-tête : titre « Gérer les participants » + sous-titre (titre réunion · date) + bouton fermer.
- Barre de recherche (participant ou collaborateur) + bouton **Resync**.
- Chips de filtre : **Tous N / Présents N / Ont refusé N / En attente N** (compteurs live) +
  à droite « Collaborateurs N » (taille de l'annuaire).
- Liste des participants (filtrée par recherche + chip) : avatar, nom, sous-libellé
  « Invité »/« Collaborateur », menu de statut (Présent / A refusé / En attente), bouton retirer ✕.
  La recherche portant sur l'annuaire propose d'ajouter des collaborateurs non-participants.
- Pied : champ « Ajouter un participant ad-hoc (nom)… » + bouton **Ajouter** ; à gauche
  « Tout retirer » (rouge) ; à droite **Annuler** / **Terminé**.

### Composant 6 — Carte « Transcription » (`TranscriptionCard`)

Aperçu live via `LiveTranscriptionService.shared` : segments récents (ou dernier segment) avec
libellé locuteur si dispo, indicateur « En direct · MM:SS » quand `isLive`, ligne d'état
« En écoute… » + compteur de segments. Contrôles d'en-tête : toggle **Speakers** (affiche/masque
les libellés locuteurs), bouton **Détecter** (déclenche la détection de locuteurs — réutilise le
mécanisme existant), icône **agrandir ↗** → `activeSection = .liveTranscript` (onglet Direct).

### Composant 7 — Chrome (polish léger)

Réutilise `MeetingTheme` et les composants existants (`MeetingTopChromeBar`,
`MeetingContextualRecorderBar`). Retouches ciblées :
- Badge de type de réunion (ex. « Globale ») près du titre, dérivé de `MeetingKind.label` + icône.
- Rangée d'onglets (`MeetingTabsUnderline`) : date à droite + affordance **« Personnaliser »**
  (visible sur l'onglet Vue d'ensemble) qui bascule `isEditingLayout`.
- Aucune refonte des boutons existants (Capture / Auto / Rapport / ⋯).

## Découpage fichiers

**Modifiés :**
- `Models/MeetingModels.swift` — `MeetingAttendanceStatus` 3 cas + compat décodage.
- `Services/CalendarMeetingImportService.swift` — mapping vers 3 statuts.
- `Views/MeetingView.swift` — onglet `.overview`, suppression sidebar fixe, ouverture de la modale.
- `Views/Meeting/MeetingTabsUnderline.swift` — date + « Personnaliser ».
- `Views/Meeting/Sidebar/RightSidebarPanelID.swift` — renommage `MeetingPanelID` + `.presence`/
  `.transcription`/`.managerAgenda`.

**Nouveaux :**
- `Views/Meeting/Dashboard/OverviewDashboard.swift` — grille + mode édition.
- `Views/Meeting/Dashboard/DashboardCard.swift` — conteneur de carte commun.
- `Views/Meeting/Dashboard/PresenceCard.swift`
- `Views/Meeting/Dashboard/TranscriptionCard.swift`
- `Views/Meeting/ManageParticipantsSheet.swift`
- Tests : `Tests/AttendanceStatusMappingTests.swift`, `Tests/PresenceStatsTests.swift`,
  extension de `Tests/PanelLayoutEntryTests.swift` pour les nouveaux cas.

## Hors périmètre (YAGNI)

- Grille libre drag & resize (spans configurables).
- 4ᵉ statut « invité » distinct.
- Refonte des boutons du chrome / nouvelle palette.
- Toute nouvelle logique participants (réutilisation stricte de l'existant).

## Stratégie de test

- **Purs (unitaires)** :
  - Mapping statut calendrier → `.present`/`.refused`/`.pending`.
  - Décodage compat des anciens raw `participant`/`absent`.
  - Calcul présence : compteurs (présents/refusés/en attente), total, pourcentage (arrondi,
    total = 0 → 0 %).
  - `PanelLayoutEntry` round-trip + migration avec `MeetingPanelID` étendu.
- **Vérification manuelle (app packagée, `Scripts/bump-and-build.sh dev`)** :
  - Onglet « Vue d'ensemble » : grille fidèle, cartes présentes selon `kind`.
  - « Personnaliser » : réordonner (drag), masquer/afficher, réinitialiser, persistance.
  - Carte Présence : donut/compteurs cohérents ; bouton ouvre la modale.
  - Modale : recherche, filtres, changement de statut, ajout ad-hoc, resync, tout retirer, Terminé.
  - Carte Transcription : aperçu live, toggle Speakers, Détecter, agrandir → onglet Direct.
  - Cas `.manager` : carte agenda manager présente ; autres kinds : absente.
  - Régression : les onglets existants s'affichent pleine largeur sans sidebar, sans perte de
    fonctionnalité.

## Risques

- **Migration statut** : bien gérer le décodage des anciens raw pour ne pas perdre les statuts
  existants (compat `participant`→`present`, `absent`→`refused`).
- **Perte de la sidebar permanente** : des actions accessibles en permanence via la sidebar
  (Actions, Capture) ne le sont plus que dans l'onglet Vue d'ensemble → vérifier qu'aucun flux
  critique n'en dépend hors de cet onglet.
- **Cas `.manager`** : l'agenda manager (génération CR, filtres catégories) doit rester
  pleinement fonctionnel une fois ré-emballé en carte.
- **Gabarit responsive** : comportement en largeurs réduites (repli des colonnes) à valider.
