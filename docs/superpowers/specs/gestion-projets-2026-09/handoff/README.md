# Handoff — Refonte de la gestion des projets (OneToOne, macOS / SwiftUI)

## Vue d'ensemble

Aujourd'hui, retrouver un projet passe uniquement par l'arbre `Projets par Entité` de
`Views/Sidebar.swift` (déplier une entité, scroller), et l'écran projet
(`Views/DetailsViews.swift` → `ProjectDetailView`) est un formulaire à plat où tous les champs
ont le même poids. La refonte :

1. sort la navigation projets de l'arbre → une **section « Projets »** dans la sidebar
   (Portfolio / À risque / Mes réunions projets / Actions projets, + Épinglés + Récents) ;
2. ajoute un écran **Portfolio** plein écran : tableau triable + facettes + vues enregistrées ;
3. ajoute une **palette ⌘K** (projets, actions) ;
4. refond l'**écran projet** en écran de pilotage : statut/risque/phase en tête, actions,
   réunions & CR, interlocuteurs, mails ; le formulaire complet passe dans un onglet
   « Fiche complète » ; la heatmap 52 semaines devient une mini-stat « rythme » ;
5. ajoute une vue **À risque** groupée par motif.

## À propos des fichiers de design

`Gestion des projets.dc.html` est une **référence de design en HTML** — une maquette du rendu
et du comportement visés, **pas du code à reprendre**. Le travail consiste à recréer ces écrans
dans l'environnement existant de l'app : **SwiftUI / SwiftData, macOS**, en réutilisant les
composants et jetons déjà présents (`Views/DesignSystem/One2OneTokens.swift`,
`One2OneTypography.swift`, `RiskLevelTint.swift`, `ProjectCardPanel.swift`).

Ouvrir le fichier dans un navigateur : c'est un canvas, on peut zoomer/panoramer. Les options
sont identifiées par un badge (`0a`, `1a`, `1c`, `1d`, `1f`, `2a`, `2b`).

## Fidélité

**Haute fidélité (hifi).** Couleurs, typographie, espacements et densités sont ceux de la charte
du programme de refonte (`One2OneToken`). À recréer au pixel près avec les composants SwiftUI
existants. Les icônes du HTML sont des **placeholders** : utiliser les SF Symbols déjà nommés
dans `Sidebar.swift` (voir « Assets »).

## Écrans

### 0a — Existant (référence, à ne pas implémenter)

Recréation de l'écran actuel (sidebar + `ProjectDetailView`) pour comparaison. Sert de base de
diff pendant le développement.

### 2a — Sidebar avec section « Projets » (structure retenue)

**Rôle** : la sidebar cesse d'être le catalogue de projets ; elle devient un point d'accès.

Ordre de la `List`, inchangé pour ce qui existe déjà (`Sidebar.swift` l. 178-215) :

1. Tableau de bord · Assistant IA · Actions · Réunions · Notes · Suivi manager ·
   Tous les Collaborateurs — inchangés
2. **NOUVEAU — `Section` « Projets »** (`DisclosureGroup`, `@AppStorage("sidebar.projectsExpanded")`) :
   - **Portfolio** — badge = nb de projets actifs (62 dans la maquette). Sélectionné = fond
     accent, texte blanc, radius 6.
   - **À risque** — badge rouge = nb de projets en alerte (7). Icône teintée `report` (#B8544C).
   - **Mes réunions projets** — réunions dont `meeting.project != nil`.
   - **Actions projets** — badge = nb d'actions ouvertes portées par un projet (23).
   - Sous-titre `ÉPINGLÉS` (mono 9,5 pt, majuscules, tracking .07em, `ink4`) puis 3 à 5 projets
     épinglés : pastille de statut 10 px + nom tronqué. Épinglage à ajouter sur `Project`
     (même logique que `Collaborator.pinLevel`).
   - Sous-titre `RÉCENTS` puis les 3 derniers projets ouverts (nom seul, sans pastille).
3. Collaborateurs (+ pastilles pinned/favourites/both) · Archives · Projets Archivés ·
   Paramètres · pied Jobs — inchangés.

**Supprimé** : le `DisclosureGroup` « Projets par Entité » et ses sous-groupes par entité.
Le drag & drop projet → entité (`dropDestination`) est reporté sur la sélection multiple du
Portfolio (action « Déplacer vers une entité »).

Largeur sidebar : inchangée (~250 px). Fond : celui de la sidebar système.

### 2b — Variante prudente

Identique à 2a, mais le `DisclosureGroup` « Projets par Entité » est conservé **sous** la
section Projets, **replié par défaut** (`sidebar.projectsExpanded = false`). À retenir si la
suppression de l'arbre est jugée trop brutale pour la première livraison.

### 1a — Portfolio (écran principal)

**Rôle** : trouver un projet par filtre plutôt que par dépliage.

Structure verticale :

| Zone | Hauteur | Contenu |
| --- | --- | --- |
| En-tête | ~48 px | Titre `Projets` (Plex Sans 600, 17 pt, `ink1`), sous-titre `62 actifs · 8 entités · 14 archivés` (12 pt, `inkMuted`), à droite : segmenté `Tableau / Groupé par entité` + bouton plein `＋ Nouveau projet` (fond `action`, texte blanc, radius 6, 12 pt) |
| Barre de filtres | ~42 px | Champ de recherche 230 px (`surface`, bord `strongBorder`, radius 6) ; chips actives (fond `actionBg`, bord `action` 25 %, texte `actionInk`, radius 20, 12 pt/500, croix à droite) ; chips inactives en tirets (`1px dashed rgba(0,0,0,.22)`, texte `ink4`) : Phase, Risque, Chef de projet ; à droite le sélecteur de **vue enregistrée** |
| En-tête de tableau | 30 px | Libellés mono 9,5 pt majuscules tracking .07em, `ink4`, fond `bgApp`, bord bas `hair` |
| Lignes | 44 px | Voir ci-dessous |
| Pied | — | Compteur + rappel sélection multiple |

**Colonnes** (grille CSS `22px | 1fr | 88 | 92 | 88 | 126 | 78`) :
pastille de statut (9 px) · Projet (nom 13 pt/500 `ink1` + `code · type` en mono 10,5 pt
`inkMuted`) · Entité · Phase (badge) · Risque (badge) · Chef de projet · Dernière réunion.

Lignes alternées `surface` / `surfaceAlt`, séparateur `rgba(0,0,0,.05)`.

**Badges de phase** (fond / texte) : Cadrage `actionBg` / `actionInk` · Design `oneOnOneBg` /
`oneOnOneInk` · Build `workshopBg` / `workshop` · Run `okBg` / `okDeep`. Radius 4, 11,5 pt.

**Badges de risque** : Faible → `okBg`/`okDeep` · Modéré → `warnBg`/`warnInk` ·
Élevé & Critique → `reportBg`/`reportInk` · absent → tiret `inkMuted`
(réutiliser `RiskLevelTint` / `MeetingKPI.Level.teinte`).

**Pastille de statut** : Green `ok` · Yellow `warn` · Red `report` · Unknown `inkMuted`
(la table existante `StatusIcon` de `ProjectListView.swift` doit être migrée sur ces jetons).

Tri : clic sur l'en-tête (`↑`/`↓`). Sélection multiple : ⇧-clic, la barre d'actions en lot
existante (`multiSelectBar`, phase / statut / entité / archiver / supprimer) est réutilisée.

### 1c — Palette ⌘K

Feuille modale 560 px de large, centrée haut, `surface`, radius 10, bord `strongBorder`,
ombre `0 18px 40px rgba(0,0,0,.16)`.

- Champ : hauteur 44 px, texte 15 pt, `esc` en pastille mono à droite.
- Groupes `PROJETS` puis `ACTIONS` (libellés mono 9,5 pt majuscules `ink4`).
- Ligne projet : pastille de statut · nom (surlignage du terme trouvé, fond `#FFE9A8`) ·
  sous-ligne mono 10,5 pt `code · entité · phase · chef de projet` · `↩` à droite.
- Ligne sélectionnée : fond `actionBg`, radius 7.
- Actions : « Créer un projet "x" », « Chercher "x" dans les CR et mails ».
- Pied : `↑↓ naviguer · ↩ ouvrir · ⌘↩ épingler` (mono 10,5 pt, fond `bgCanvas`).

La recherche reprend les prédicats déjà écrits dans `Sidebar.swift` :
`projectMatches` (nom, code, domaine, notes) — y ajouter le sponsor.

### 1d — Écran projet (remplace ProjectDetailView en écran par défaut)

**Fil d'Ariane** : `Portfolio / <entité> / <code>` (mono 11 pt, segments cliquables `action`).

**En-tête** : nom du projet en Plex Sans 600 / 21 pt / 1.25 ; sous la ligne de titre, une rangée
de pilules : statut (pastille + libellé, fond `okBg`/`warnBg`/`reportBg`), phase, type, entité,
puis l'alerte de deadline en `reportInk` si J−7 ou moins. À droite : `☆ Épingler` (bouton
bordé), `Démarrer une réunion` (bouton plein `action`), menu `···`.

**Onglets** (13 pt, soulignement 2 px `action` sur l'actif) :
`Pilotage` · `Réunions & CR` · `Actions` (badge) · `Mails` (badge) · `Documents` ·
`Fiche complète`. « Fiche complète » = l'actuel `ProjectDetailView` tel quel, non refondu.

**Onglet Pilotage** — grille `1fr / 330px`, gap 16, padding 16/22.

Colonne principale :
- **4 tuiles** (grille 4 × 1fr, gap 10, carte `surface`, bord `cardBorder`, radius 7,
  padding 11/12) : Actions ouvertes (dont en retard, en `reportInk`), Dernière réunion,
  **Rythme** (mini-histogramme 8 barres de 7 px, dégradé `okBg → ok` — remplace la heatmap
  52 semaines), Charge (`budgetCons`/`plannedDays` + barre 4 px).
- **Actions en cours** : cases 14 px (bord `report` si en retard, sinon `rgba(0,0,0,.24)`),
  titre 13 pt, sous-ligne responsable/origine 11,5 pt `inkMuted`, échéance à droite en mono
  11 pt (rouge si retard). Lien « Tout voir » vers l'onglet Actions.
- **Dernières réunions** : date mono 11 pt sur 44 px + badge de type (COPIL `reportBg`,
  Atelier `workshopBg`, 1:1 `oneOnOneBg`) + titre + résumé de décision 12 pt / 1.45.
- **Périmètre & contexte** : `project.scopeText`, 13 pt / 1.55, `text-wrap: pretty` ;
  pied pointillé « Cliquer pour éditer · dernière mise à jour par X, hier ».

Colonne latérale (330 px, = `One2OneToken.projectPanelWidth` moins les marges) :
Interlocuteurs (avatars 26 px, rôle, raccourci `1:1 ▸`, ligne pointillée pour un rôle vide) ·
Risque (niveau + description, lien `Modifier`) · Mails liés (3 derniers + encart
`✦ 3 mails à rattacher` sur fond `actionBg`) · Identité (code, domaine, jours, fin de design,
DAT/DIT + lien « Voir la fiche complète »).

**Édition** : lecture d'abord, **édition au clic sur le champ** (in-place). Réutiliser le
mécanisme de brouillon de `ProjectCardPanel` (`ProjectCardDraft`, enregistrement optimiste +
`UndoBanner` 5 s) plutôt que les `Binding` directs de `ProjectDetailView`.

### 1f — Vue « À risque »

Liste groupée par **motif**, pas par entité. Trois groupes, chacun avec un titre mono 9,5 pt
teinté et une carte contenant les lignes (bord gauche 3 px de la teinte du groupe) :

1. **Jalon dépassé** (`report`) — jalon + retard + responsable → action `Replanifier`
2. **Sans réunion depuis 30 j** (`warn`) — dernière réunion → action `Planifier`
3. **Fiche incomplète** (`inkMuted` / `#DDD7CC`) — champ manquant (sponsor, chef de projet,
   statut) → action `Compléter`

Règles de calcul à implémenter côté service (proposition) :
`jalon.dueDate < today && state != .done` · `max(meeting.date) < today-30j` ·
`sponsor.isEmpty || projectManager == nil || status == "Unknown"`.

## Interactions & comportement

- **⌘K** : ouvre la palette depuis n'importe quel écran (à ajouter aux `HotkeySpec`).
- **Portfolio → projet** : clic sur une ligne → écran projet (onglet Pilotage).
- **Chips de filtre** : clic → menu de valeurs ; les filtres se cumulent (ET) ;
  la combinaison peut être enregistrée comme « vue » (persistée dans `AppSettings`).
- **Sélection multiple** : ⇧-clic sur les lignes → barre d'actions en lot existante.
- **Épingler** : `☆` de l'en-tête projet et `⌘↩` dans la palette ; alimente la sous-section
  Épinglés de la sidebar.
- **Récents** : file FIFO des 5 derniers projets ouverts, persistée (`@AppStorage`).
- **Édition in-place** : clic sur une valeur → champ actif ; `⏎` valide, `esc` annule ;
  bandeau d'annulation 5 s après enregistrement.
- Aucune animation particulière au-delà des transitions SwiftUI par défaut (`.snappy`).

## État

| État | Portée | Note |
| --- | --- | --- |
| `portfolio.searchText` + debounce 250 ms | vue | même debounce que `Sidebar.searchDebounceTask` |
| `portfolio.filters` (entité, phase, statut, risque, chef de projet) | vue, persistable | une vue enregistrée = un jeu de filtres nommé |
| `portfolio.sort` (colonne, sens) | vue | défaut : nom ↑ |
| `portfolio.selection: Set<PersistentIdentifier>` | vue | réutilise `selectedProjectIDs` |
| `project.pinned` | modèle | nouveau champ sur `Project` |
| `recentProjectIDs: [UUID]` | app | `@AppStorage`, max 5, via `Project.stableID` |
| `projectTab` (Pilotage / Réunions / Actions / Mails / Documents / Fiche) | vue | |
| `draft: ProjectCardDraft` + `undoSnapshot` | vue | existant, à réutiliser |

Données : tout est déjà dans `Project`, `ProjectMilestone`, `ProjectAlert`, `ProjectContact`,
`ActionTask`, `ProjectMail`, `Meeting`. **Seul ajout nécessaire** : `Project.pinned: Bool`
(+ migration) et, si l'on veut la colonne « Dernière réunion » sans recalcul,
un cache dérivé de `MeetingStatsScope.held`.

## Jetons de design

Tous existent déjà dans `Views/DesignSystem/One2OneTokens.swift` — **ne rien ajouter** :

Fonds `bgApp #F7F4EE` · `bgCanvas #FAF8F4` · `surface #FFFFFF` · `surfaceAlt #FDFCFA`
Bords `hair` noir 7 % · `cardBorder` 9 % · `strongBorder` 14 %
Encres `ink1 #1A1A1A` · `ink2 #2A2723` · `ink3 #4A453D` · `ink4 #6B6659` · `inkMuted #7D7768`
(jamais sous 11,5 px)
Accents `action #2563D9` / `actionBg #EEF2FD` / `actionInk #1B4DAD` ·
`report #B8544C` / `reportBg #FBECEB` / `reportInk #8F3F38` ·
`ok #2F9E5F` / `okDeep #2F7D4E` / `okBg #E8F3EC` ·
`warn #D98324` / `warnInk #8A5A12` / `warnBg #F9EFE0` ·
`oneOnOne #6B4D8F` / `oneOnOneInk #5C4180` / `oneOnOneBg #F4F1F6` ·
`workshop #1F6B6B` / `workshopBg #F2F8F7`

Rayons `radiusButton 6` · `radiusCard 7` · `radiusPanel 10` · `radiusPill 11`
Densités `cardPaddingMin 9` · `cardPaddingMax 13` · `cardGap 12` · `tableRowPaddingV 8`
Largeurs `projectPanelWidth 430` (colonne latérale 1d : 330 dans le contenu + marges)

Typographie — `One2OneTypography.swift`, IBM Plex embarqué :
- Titre d'écran : `plexSans(17, .semibold)` ; titre de projet : `plexSans(21, .semibold)`
- Corps : `plexSans(13)` · secondaire : `plexSans(12)` · méta : `plexSans(11.5)`
- Libellé de section : modificateur `.sectionLabel()` (Plex Mono 600, 9,5 pt, majuscules,
  tracking .07em, `ink4`) — utilisé pour tous les en-têtes de colonnes et de cartes
- Codes projet, dates, compteurs : `plexMono(10.5–11, .medium)`

Contraste : jamais de texte sous 11,5 px en `inkMuted` ; badges toujours à pleine opacité.

## Assets

Aucune image. Icônes = SF Symbols, ceux déjà utilisés dans `Sidebar.swift` :
`chart.bar.fill` (Tableau de bord), `bubble.left.and.text.bubble.right.fill` (Assistant IA),
`checklist` (Actions), `person.3` (Réunions), `note.text` (Notes),
`person.crop.square.filled.and.at.rectangle` (Suivi manager), `person.3.sequence`
(Tous les Collaborateurs), `archivebox`, `gear`, `pin.fill`, `star.fill`, `person.2.fill`.
Pour les nouvelles entrées : `square.grid.3x3.fill` (Portfolio),
`exclamationmark.triangle.fill` ou `diamond.fill` (À risque), `clock` (Mes réunions projets),
`line.3.horizontal` (Actions projets), `magnifyingglass` (⌘K).
Les glyphes du HTML (▦ ◈ ◷ ≣ …) sont **des placeholders**, à ne pas reprendre.

## Captures

`screenshots/` (PNG 2×, une par écran) :
`0a-existant.png` · `2a-sidebar-section-projets.png` ·
`2b-sidebar-variante-arbre-replie.png` · `1a-portfolio.png` · `1c-palette-cmdk.png` ·
`1d-ecran-projet-pilotage.png` · `1f-vue-a-risque.png`

## Fichiers

- `Gestion des projets.dc.html` — la maquette (canvas ; badges `0a`, `1a`, `1c`, `1d`, `1f`,
  `2a`, `2b`)
- `support.js` — runtime de rendu de la maquette, sans intérêt pour l'implémentation

Fichiers du dépôt concernés :
`OneToOne/Views/Sidebar.swift` (section Projets) ·
`OneToOne/Views/ProjectListView.swift` (à remplacer par le Portfolio) ·
`OneToOne/Views/DetailsViews.swift` (`ProjectDetailView` → onglet « Fiche complète ») ·
`OneToOne/Views/Project/ProjectCardPanel.swift` (brouillon + UndoBanner à réutiliser) ·
`OneToOne/Views/MeetingHeatmapView.swift` (remplacée par la tuile Rythme sur l'écran projet) ·
`OneToOne/Models/Project.swift` (champ `pinned`) ·
`OneToOne/Views/DesignSystem/One2OneTokens.swift` et `One2OneTypography.swift` (source des valeurs)

## Ordre de livraison suggéré

1. Section « Projets » dans la sidebar en variante **2b** (rien n'est retiré) + champ `pinned`
2. Écran **Portfolio** (1a) avec recherche, tri, facettes
3. Palette **⌘K** (1c)
4. Écran projet **Pilotage** (1d), l'existant devenant l'onglet « Fiche complète »
5. Vue **À risque** (1f)
6. Bascule sidebar sur **2a** (retrait de l'arbre) une fois le Portfolio adopté
