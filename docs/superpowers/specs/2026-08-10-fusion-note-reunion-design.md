# Fusion Note / Réunion — une note est une réunion avec soi-même

**Date** : 2026-08-10
**Statut** : validée
**Origine** : constat d'usage de l'auteur — « une Note n'est qu'une réunion avec moi-même, et
je n'ai rien dans Note ». Vérifié sur le store réel avant rédaction.

---

## Le constat

Lecture d'une copie de `~/Library/Application Support/OneToOne/OneToOne.store` (33 Mo) :

| Table | Lignes |
|---|---|
| `ZNOTE` | **0** |
| `ZNOTEATTACHMENT` | **0** |
| `ZPROJECTINFOENTRY` | **0** |
| `ZPROJECTCOLLABORATORENTRY` | **0** |
| `ZMEETING` | **163** (83 globales, 53 projet, 17 one-to-one, 6 archi, 4 manager) |

Quatre modèles de « texte libre daté » coexistent, **tous vides**. Tout ce qui est réellement
produit passe par `Meeting`. L'intuition de départ portait sur `Note` seule ; la mesure montre
que le même raisonnement vaut pour les deux entrées typées de `Project`.

Deux effets de bord du modèle actuel méritent d'être nommés :

- **`Note` n'est pas dans `BackupService`.** Une note n'a jamais été sauvegardée ni restaurée.
- **L'index Spotlight ne contient aucun contenu.** `SpotlightIndexService` indexe les projets,
  les collaborateurs, `ProjectInfoEntry` et `ProjectCollaboratorEntry` — soit, en pratique, des
  noms de projets et de personnes et rien d'autre, puisque les deux types datés sont vides.
  `Meeting` n'est indexé nulle part.

## La décision

**Une note devient un `Meeting` de kind `.note`.** Les quatre modèles vides disparaissent ;
chaque geste qu'ils portaient est reporté sur le modèle qui lui correspond naturellement.

---

## Périmètre

### Dans le périmètre

- Suppression de `Note`, `NoteAttachment`, `ProjectInfoEntry`, `ProjectCollaboratorEntry`.
- Ajout de `MeetingKind.note` et des règles qui l'accompagnent.
- Réécriture des écrans et services qui lisaient ces quatre modèles.
- Indexation Spotlight des réunions (le trou décrit ci-dessus).

### Hors périmètre

- Renommer `Meeting.liveNotes` (traverse `BackupService`, `ReportTemplating`, les gabarits).
- Toute évolution du format de stockage des notes (voir l'étude
  `2026-08-10-json-canonique-notes-design.md`, sans rapport avec ce document).
- Indexer les transcriptions dans Spotlight.

---

## 1. Modèle et schéma

`MeetingKind` gagne `case note = "note"`, libellé « Note », symbole `note.text`.

Une note est un `Meeting` où :

| Rôle | Champ |
|---|---|
| corps | `liveNotes` — champ que relie déjà l'onglet « Notes live » (`MeetingView:567`) |
| projet | `Meeting.project` |
| collaborateur | `Meeting.participants` — le kind `.note` la distingue d'un vrai 1:1 |
| pièces jointes | `MeetingAttachment`, en remplacement de `NoteAttachment` |
| date | `Meeting.date` ; `createdAt`/`updatedAt` de `Note` disparaissent, le tri se fait sur `date` |

Le nom `liveNotes` sonne faux pour une note. Il est conservé (voir hors périmètre) ; l'onglet
s'intitule « Note » à l'écran.

**Suppressions** : les quatre modèles, plus les relations `Project.notes`, `Collaborator.notes`,
`Project.infoEntries`, `Project.collaboratorEntries`.

### Les exclusions obligatoires

Ni `MenuBarStats` (`Services/MenuBarStats.swift:74`, qui boucle sur toutes les réunions) ni
`MeetingHeatmapView` (`:176`) ne filtrent par kind. Sans exclusion, une note prendrait du
« temps passé » et noircirait la heatmap. C'est la contrepartie exacte du choix d'un kind dédié :
la règle `kind != .note` doit être écrite, pas supposée.

Même famille de défaut dans la fiche collaborateur : `GroupBox("Réunions")` (`DetailsViews:1157`)
itère `collaborator.meetings` et ferait donc remonter les notes **en double**, juste au-dessus de
`NotesSection`. Le kind y est exclu aussi.

### Schéma

`SchemaVersions.swift` prévient qu'une suppression de type demande un `SchemaV2` avec un snapshot
*nested* des trente modèles. **Ce n'est pas fait ici, et c'est un écart assumé** : le snapshot
nested existe pour préserver des données, et les quatre tables en sont dépourvues. Les types sont
retirés de `SchemaV1.models` et la migration légère supprime les entités orphelines.

Garantie associée, manuelle : **copier `~/Library/Application Support/OneToOne/` en entier avant
le premier lancement du nouveau build**. Si CoreData refuse la suppression d'entité, cela se voit
au premier lancement et on bascule sur un `SchemaV2` complet.

---

## 2. Les écrans

**Entrée « Notes »** (`AllNotesView`, 349 l.) — conservée dans la barre latérale, mais alimentée
par un `@Query` sur `Meeting` filtré `.note`. Recherche, portée (Toutes / Projet / Collaborateur)
et création inchangées. Ouvrir une note ouvre `MeetingView` au lieu d'une feuille markdown. Le
tunnel « ajouter au rapport manager » dupliqué ici (~100 l.) **disparaît** : `MeetingView` porte
déjà `ManagerClassificationSheet` (`:271`).

**`NotesSection`** (355 l., montée dans les deux fiches) — conservée aux deux endroits, réécrite
sur `Meeting` `.note` : côté projet `meeting.project == project`, côté collaborateur
`participants.contains(collaborator)`. L'édition en ligne cède la place à l'ouverture dans
`MeetingView` ; les pièces jointes passent par l'onglet Documents.

**`MeetingView`** — onglets filtrés par kind. Pour `.note` : « Note » (ex-Notes live) et
« Documents » ; masqués : Vue d'ensemble, Préparation, Transcription, Rapport, ainsi que la barre
d'enregistrement. Le sélecteur de kind de `MeetingTopChromeBar` reste : le passer sur
« One-to-One » rouvre les six onglets — c'est le chemin « finalement il y a eu une vraie
réunion ». Le titre de fenêtre vide retombe sur « Note » au lieu de « Réunion ».

**`QuickNotePopover`** — aucun changement visuel. `Note(body:)` devient un `Meeting` `.note`
avec `liveNotes = texte`, cible projet → `meeting.project`, cible collaborateur →
`participants = [c]`.

**Fiche projet** — les `GroupBox` « Infos projet / REX » (`DetailsViews:204`) et
« Informations / actions collaborateurs » (`:269`) sont supprimés. `NotesSection`, déjà présente
ligne 655, reprend les infos ; les actions collaborateur rejoignent la vue Actions via `ActionTask`.

**`MeetingsListView`** — les notes en sont **exclues** et « Note » est retiré de son menu de
filtre Type. Une entrée dédiée existe ; mélanger les notes aux 163 réunions rendrait le compteur
et les filtres ambigus.

**Recherche de la barre latérale** — `noteMatches` (`Sidebar:146`) porte sur `Meeting.title` et
`liveNotes` ; `projectMatches` et `collabMatches` suivent les nouvelles relations.

**`RAGChatView:110`** — le filtre par kind gagne « Note » sans une ligne de code (il itère
`allCases`). Souhaitable ici : interroger ses notes par l'IA.

---

## 3. Services et commandes

### Commandes de l'assistant

| Commande | Devient |
|---|---|
| `/ajout-projet <projet> \| <info>` | une note `.note`, `project` renseigné, titre `REX` si `project.phase == "Build"`, sinon `Info projet` |
| `/ajout-info-collab-projet <projet> \| <collab> \| <info>` | une note `.note`, `project` + `participants = [collab]`, titre `Info <collab>` |
| `/ajout-action-collab-projet <projet> \| <collab> \| <action>` | un `ActionTask(project:, collaborator:, destinataire: .collaborateur)` |

La catégorie que portait `ProjectInfoEntry` (`REX` / `Information`) est reportée sur le **titre**
de la note plutôt que sur un champ dédié : lisible dans les listes, aucune machinerie nouvelle.

`ProjectCollaboratorEntry` portait `isCompleted` — c'était une action déguisée. `ActionTask` et
`ActionAudience.collaborateur` existent pour exactement ce cas.

Le `@Query` de notes du contexte IA (`ChatbotView:39`) passe sur `.note`. `type:note` est ajouté
au vocabulaire de `/cherche`, qui accepte déjà `type:1:1|projet|archi|globale`.

### Recherche locale du chatbot

Trois réponses hors-ligne lisent les tables supprimées et se repointent sur les notes, en
suivant la convention de titre ci-dessus :

- `responseForProjectInfoQuery` (`ChatbotView:1080`) → les notes `.note` du projet ;
- `responseForRexQuery` (`:1128-1132`) → les notes du projet dont le titre vaut `REX` ;
- `responseForCollaboratorProjectQuery` (`:1148`) → les notes du projet dont `participants`
  contient le collaborateur cherché.

### `MailProjectMatcher`

`projectEntries(from:)` (`:43-53`) construisait la liste d'emails d'un projet — le signal
« expéditeur » du rattachement automatique des mails — **à partir de `collaboratorEntries`**.
Comme cette table est vide, cette liste ne contient aujourd'hui que le chef de projet et
l'architecte technique.

Elle est **rebranchée sur les participants des réunions du projet** : 918 liens
participant → réunion existent réellement, contre zéro entrée collaborateur. Le signal
expéditeur cesse d'être théorique. La signature devient
`projectEntries(from projects: [Project], meetings: [Meeting])` — il n'existe pas de relation
inverse `Project.meetings`, les réunions sont donc passées par le seul appelant
(`MailAutoIndexService:126`), qui récupère déjà ses projets du contexte.

C'est une amélioration fonctionnelle, donc un élargissement assumé du périmètre.

### `ReportTemplating`

`collabNotes` (`:181`) : le `FetchDescriptor<Note>` devient un fetch de `Meeting` `.note` dont
`participants` contient le collaborateur. La variable de gabarit ne change ni de nom ni de rendu.

### `BackupService`

`ProjectInfoEntryDTO` et `ProjectCollaboratorEntryDTO` sont retirés, ainsi que leurs tableaux
dans `ProjectDTO` et les branches export/import correspondantes. Les sauvegardes déjà écrites
restent lisibles : `JSONDecoder` ignore les clés qu'aucune propriété ne réclame, et ces tableaux
sont vides. **Gain net** : les notes entrent dans la sauvegarde, ce qu'elles n'ont jamais fait.

### `SpotlightIndexService`

`makeInfoItem`, `makeCollaboratorEntryItem` et leurs identifiants disparaissent. En remplacement,
**toutes les réunions sont indexées, notes comprises** :

- `makeMeetingItem(_:)`, domaine `"meetings"` : titre, `shortSummary`, `liveNotes`, `notes`, nom
  du projet et noms des participants en mots-clés. **Ni `rawTranscript` ni `mergedTranscript`** —
  volumineux, et déjà interrogeables par le RAG.
- `index(meeting:)`, `remove(meeting:)`, et `makeMeetingItemForTesting` sur le modèle du hook
  collaborateur existant.
- `indexAll(projects:collaborators:meetings:)`, appelé depuis `OneToOneApp:259` et
  `SettingsView:1106`.
- `fetchIndexedItemCount` gagne `domainIdentifier == 'meetings'` et perd `project-info` et
  `project-collaborator-info`.

**Où l'indexation se déclenche.** L'éditeur de notes live appelle `saveContext()` à chaque frappe
(`MeetingView:567-568`) ; y accrocher l'indexation martèlerait CoreSpotlight. Donc :

- `index(meeting:)` à la fermeture de `MeetingView` (`onDisappear`), et juste après une création
  par `NoteFactory` (note rapide, commandes du chatbot) ;
- `remove(meeting:)` dans `MeetingView.deleteMeeting()` (`:2637`) et
  `MeetingsListView.deleteMeetings(offsets:)` ;
- le `indexAll` du démarrage rattrape le reste (imports calendrier, éditions hors de ces chemins).

Les deux `index(project:)` de `ChatbotView` (`:933`, `:974`) deviennent des `index(meeting:)`.

Effet net : l'index passe d'environ zéro item de contenu à environ 163.

### Inchangés

`ExportService`, `AIIngestionService`, `PrepCarryoverService`, et `NoteMergeService` — qui malgré
son nom fusionne transcription et notes live d'une réunion, sans rapport avec le modèle `Note`.

---

## 4. Vérification

### Trois extractions, pour rendre le design testable

Aucun refactor gratuit : uniquement là où la logique devient partagée.

- `MeetingStatsScope.held(_:)` — filtre `kind != .note`. Trois appelants : `MenuBarStats` et les
  deux montages de `MeetingHeatmapView` (`DetailsViews:53` et `:902`).
- `NoteFactory.make(body:title:project:collaborator:)` → `Meeting`. Cinq appelants :
  `QuickNotePopover`, la liste « Notes », `NotesSection`, deux commandes du chatbot.
- `MeetingView.visibleTabs(for:)` — statique et pure, pour tester le masquage sans instancier la vue.

### Tests à écrire (TDD — ils tombent avant le code)

| Cible | Ce qu'on affirme |
|---|---|
| `MeetingStatsScope` | une `.note` du jour n'ajoute rien au temps passé ni aux compartiments de heatmap ; une `.oneToOne` si |
| `NoteFactory` | kind `.note`, corps dans `liveNotes`, `project` posé, collaborateur dans `participants` |
| `visibleTabs(for:)` | `.note` → « Note » + « Documents » ; `.oneToOne` → les six |
| Prédicats des listes | la note d'un projet apparaît dans la fiche de ce projet et pas d'un autre ; idem par participant |
| Commandes chatbot | `/ajout-action-collab-projet` crée un `ActionTask` et **aucune** note |
| `makeMeetingItem` | titre, description et mots-clés attendus pour une note et pour un 1:1 ; **absence** de transcription dans l'item |

**Tests existants à reprendre** — quatre fichiers déclarent les modèles supprimés dans leur
`ModelContainer` : `ManagerCRGeneratorTests`, `ManagerReportServiceTests`,
`QuickLaunchRouterTests`, `QuickLaunchURLHandlerTests`. `MailProjectMatcherTests` construit
des `ProjectEntry` à la main et n'est pas touché par la nouvelle signature.

### Ce qu'aucun test ne couvrira

La suppression des quatre entités dans un store existant. Simuler l'ancien schéma exigerait de
conserver les classes supprimées dans la cible de test, ce qui annulerait la suppression. La
garantie est manuelle : copie complète du dossier avant premier lancement, restauration si
CoreData refuse. Le dépôt a déjà cette habitude (`OneToOne.store.before-fix`, deux dossiers
`OneToOne.backup-*`).

### Contrôles à l'écran

1. note rapide depuis le menubar → elle apparaît dans « Notes » ;
2. l'ouvrir → deux onglets, pas six, pas de barre d'enregistrement ;
3. changer son kind en « One-to-One » → les six onglets reviennent ;
4. temps passé du menubar et heatmap **inchangés** après création d'une note ;
5. fiche collaborateur → la note est dans `NotesSection` et **pas** en double dans « Réunions » ;
6. fiche projet → les deux anciens `GroupBox` ont disparu, `NotesSection` les remplace ;
7. sauvegarder puis restaurer → la note survit (ce qui n'a jamais été vrai) ;
8. Spotlight → une recherche sur un mot d'une note la remonte.

### Vérification standard

`swift test --skip CalendarImportEventTests`, puis mise à jour de `STATUS.md` en fin de session.

---

## Risques et arbitrages assumés

| Arbitrage | Contrepartie acceptée |
|---|---|
| Pas de `SchemaV2` avec snapshot nested | Repose sur le fait que les quatre tables sont vides ; garantie manuelle par copie du store |
| Collaborateur porté par `participants` | « Réunions avec X » inclurait les notes sans le filtre de kind ; d'où les exclusions explicites |
| `liveNotes` conservé comme corps | Nom trompeur pour une note ; renommer traverserait sauvegarde, gabarits et rapports |
| Catégorie `REX` / `Information` reportée sur le titre | Plus de champ typé ; le filtrage par catégorie devient une recherche textuelle |
| Périmètre élargi aux trois modèles vides | Une PR plus large que « une intention » au sens strict ; justifié par un geste unique et une seule migration |
| `MailProjectMatcher` rebranché sur les participants des réunions | Change le comportement du rattachement automatique des mails, au lieu de le laisser inerte ; élargissement assumé |

## Ce qui n'est pas décidé ici

- Le sort de `Meeting.notes` (champ distinct de `liveNotes`, encore lu par les gabarits).
- L'indexation des transcriptions.
- Le renommage de `liveNotes`.
