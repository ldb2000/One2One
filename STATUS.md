# État du projet

Dernière mise à jour : 2026-08-10 CEST

## Synthèse

**Fusion Note / Réunion — code terminé, vérification sur données réelles due.** Branche
`feat/fusion-note-reunion`, 43 commits. Les douze tâches de code du
[plan](docs/superpowers/plans/2026-08-10-fusion-note-reunion.md) sont livrées ; la
treizième — sauvegarde du store, migration, dix contrôles à l'écran — **n'a pas eu lieu**.
Voir la section datée du 2026-08-10 ci-dessous. Prochaine action : cette tâche 13.

**Réécriture de l'éditeur — décidée, verdict du prototype en attente.** La
réécriture de l'éditeur en reprenant l'architecture d'appflowy-editor
(AGPL-3.0 acceptée) est décidée, voir
[l'ADR de licence](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
Un prototype jetable (`Prototypes/BlockEditorProbe/`) a sondé le risque
central — une vue éditable par bloc en AppKit — et existe toujours ; son
verdict est **en attente** de la vérification à l'écran, qui n'a pas eu
lieu, voir [l'ADR de verdict](docs/adr/2026-08-08-verdict-prototype-blocs-appkit.md).
Le chantier ci-dessous (`feat/editeur-slash-blocs`) reste **en l'état** :
ni fusionné, ni abandonné ; sa propre vérification à l'écran reste due,
indépendamment du prototype. Prochaine action : la session de vérification
à l'écran du prototype.

**Vitrine `ActionsListView` — mise en page de la capture adoptée, écran dû.** Chantier
ouvert à partir de huit captures de design. Voir la
[spec](docs/superpowers/specs/2026-08-09-habillage-visuel-design.md), le
[plan d'habillage](docs/superpowers/plans/2026-08-09-habillage-vitrine-actions.md) et le
[plan correctif](docs/superpowers/plans/2026-08-09-vitrine-actions-mise-en-page-capture.md).
Branche `feat/habillage-vitrine-actions`, 17 commits.

**Correction de cap en cours de route.** Le premier plan a appliqué le *vocabulaire visuel*
de la capture aux informations existantes sans adopter sa *mise en page* : à l'écran, la
maquette n'était pas reconnaissable. Erreur d'interprétation, pas d'exécution — toutes les
revues étaient vertes. Le second plan corrige : la barre principale est devenue celle de la
capture, les contrôles secondaires sont montés en barre d'outils, la ligne s'est réduite à
cinq éléments avec un menu `⋮` au survol.

Livré : jetons `AppTheme` ; deux règles de date testées — `Urgence` (couleur, seuil sept
jours, 8 tests) et `Portee` (filtrage, 9 tests) ; composants `Avatar`, `MetaValue`,
`SegmentedFilter` (7 tests) ; « Grouper par » branché sur la vue liste avec un axe
« Échéance », les sections réutilisant la même fonction que le kanban.

**Rien n'a été vérifié à l'écran, sauf un survol de l'auteur qui a révélé deux défauts** —
« Grouper par » inopérant en liste (corrigé) et, trouvé dans la foulée par la revue, les
actions terminées rendues invisibles par la portée (corrigé). Une vingtaine de contrôles
restent dus. Trois sont prioritaires :

1. **cliquer `⋮`** — le mécanisme censé l'empêcher de déplier aussi la ligne n'a jamais été
   vérifié ; s'il bloque l'ouverture du menu, Modifier, Commentaires et Supprimer deviennent
   inatteignables sur les actions ouvertes ;
2. **survoler le titre et la case à cocher** — l'apparition de `⋮` dépend d'un `onHover`
   posé sur une vue de fond ; si le suivi ne porte pas au-dessus des sous-vues, même
   conséquence ;
3. **« Filtres → Terminées »** — vérifier que les actions terminées apparaissent bien.

Trois règles de date coexistent : `Urgence` (couleur), `Portee` (filtrage) et les seuils
propres de `taskStatus` (forme de la puce et infobulle, aujourd'hui/demain/48 h). Une action
due demain porte donc une puce « imminente » coloriée en gris « à venir ».

Dettes et arbitrages dus : `ListRow`, nommé par la spec, jamais extrait ; la spec interdit
toute fonction nouvelle alors que le filtre de portée et le groupement en liste en sont ;
l'axe « Échéance » ajouté à `ActionGrouping` fait apparaître un quatrième segment dans
`ActionsPanel`, écran non visé ; onze des vingt jetons d'`AppTheme` n'ont aucun consommateur
(catalogue publié d'avance pour la propagation) ; `CLAUDE.md` ligne 99 impose l'anglais pour
les symboles alors que `Views/DesignSystem/` est en français par décision explicite —
correction impossible tant que `CLAUDE.md` porte des changements non commités du chantier
éditeur ; et **aucun test n'exerce la chaîne de filtres**, où trois défauts ont pourtant été
trouvés.

Prochaine action de ce chantier : la session de vérification à l'écran, en commençant par
les trois contrôles prioritaires ci-dessus.

Le chantier actif est la refonte de l'éditeur Markdown en éditeur de blocs,
à partir du handoff [`design_handoff_editor_blocs/README.md`](design_handoff_editor_blocs/README.md).

- Branche : `feat/editeur-slash-blocs`
- Avance sur `master` : 113 commits
- Source de vérité : le Markdown reste le format stocké
- Moteur d'édition : AppKit / TextKit 1
- État du worktree : plusieurs changements de l'éditeur sont encore non
  commités ; ils ne doivent pas être mélangés avec les changements de
  migration de `OneToOneApp.swift`

## Fusion Note / Réunion (2026-08-10)

Branche `feat/fusion-note-reunion`, 43 commits, **non fusionnée et non poussée**.

**Livré.** `MeetingKind.note` et l'exclusion des statistiques (`MeetingStatsScope`) ;
`NoteFactory` ; les onglets et le chrome de `MeetingView` filtrés par kind ; l'indexation
Spotlight des réunions et des notes, avec l'ouverture depuis un résultat ; l'écran « Notes »
et la `NotesSection` des fiches réécrits sur `Meeting` ; la note rapide, la recherche
latérale et le gabarit de rapport repointés ; les commandes `/ajout-*` vers leur modèle
naturel ; `MailProjectMatcher` sur les participants des réunions. **Quatre modèles
supprimés** : `Note`, `NoteAttachment`, `ProjectInfoEntry`, `ProjectCollaboratorEntry` —
sans `SchemaV2`, la prémisse étant que `ZNOTE` est à zéro dans le store réel, ce qui reste
à vérifier (tâche 13, étape 2).

**Huit correctifs issus d'une revue à effort `xhigh`** (14 constats vérifiés, 6 réfutés),
tous en TDD, tous sur le prédicat qui supprime une note vide à la fermeture de l'écran —
suppression *sans* confirmation, là où la suppression explicite passe par un
`confirmationDialog` :

1. le contenu du 1:1 manager (`ManagerMeetingReport`, `ManagerReportItem`,
   `ActionTask.managerMeeting`) était invisible au prédicat, faute de relation inverse sur
   `Meeting` : un 1:1 rapporté basculé sur « Note » était supprimé avec son CR ;
2. le texte tapé dans les 0,3 s avant la fermeture n'atteignait jamais le modèle (débounce de
   l'éditeur non vidé au démontage) : la note était jugée vide et supprimée avec ce qu'on
   venait d'y écrire ;
3. les participants ad hoc, saisis à la main, et les statuts de présence ne comptaient pas ;
4. les colonnes JSON du rapport étaient lues par leurs façades, dont le getter avale toute
   erreur de décodage en `[]` ;
5. `isBeingDeleted` était un `@State` : deux écrans sur la même réunion se supprimaient le
   modèle sous les pieds (`MeetingScreenRegistry` porte désormais le compte et la
   suppression) ;
6. les quatre gardes de relation en cascade n'étaient couvertes par aucun test (table ajoutée,
   vérifiée par mutation) ;
7. l'ordre des gardes faisait fauter toute la transcription avant d'atteindre un scalaire ;
8. cinq commentaires promettaient plus que le code ne tient.

**Non appliqué, à arbitrer.** Le prédicat reste une liste blanche entretenue à la main sur
une partie des propriétés de `Meeting` : une propriété ajoutée demain tombe hors de la garde
sans qu'aucun test n'échoue. Le correctif de fond serait de conditionner la suppression
silencieuse à la **provenance** (« cet écran a créé cette note et rien ne l'a touchée »)
plutôt qu'au contenu. Choix structurant → à proposer en ADR, pas à décider en revue. La
moitié « texte » de la dérive est fermée par `Meeting.textualContent` et son test.

**Vérifié.** `swift test --skip CalendarImportEventTests` : **997 tests XCTest** (1 ignoré,
`CalendarImportEventTests`, crash d'environnement connu) **+ 301 tests Swift Testing, aucun
échec**.

**Non vérifié.** Rien n'a été vu à l'écran. La tâche 13 du plan reste entière : sauvegarde du
store, contrôle `ZNOTE = 0`, build sur la version **commitée** (l'arbre porte une modification
non commitée de `OneToOneApp.swift` qui retire `migrationPlan`), puis dix contrôles — dont
deux ajoutés par ces correctifs : la fermeture immédiatement après la frappe, et la même note
ouverte dans les deux fenêtres.

**Arbre de travail.** Il porte un chantier étranger non commité (éditeur de blocs, Mermaid
natif, `Services/Agent/`, `Vendor/`) : tous les commits de cette branche sont faits à chemins
explicites.

## Sûreté des données — axe 1 de la revue de mai appliqué (2026-08-09)

Six commits sur `master` (`8401536..d806a4b`), suite verte vérifiée par le coordinateur :
990 tests XCTest (1 ignoré, `CalendarImportEventTests`, crash d'environnement connu)
+ 138 tests Swift Testing, aucun échec.

Applique les trois correctifs de l'axe « sûreté des données » de la
[spec de reprise](docs/superpowers/specs/2026-08-09-revue-code-data-safety-perf-design.md),
issue de la branche `fix/code-review-data-safety-perf` jamais fusionnée :

1. **Dédoublonnage d'identifiants UUID au démarrage.** La règle vit dans
   `Services/IdentifierRepair.swift` (testée hors SwiftData) ; `repairStoreIfNeeded()`
   n'en est que le branchement. `TranscriptChunk.chunkId` est désormais couvert ;
   `SlideCapture.id` l'était déjà.
2. **La désynchronisation audio/transcription est nommée et affichée.**
   `TranscriptEditError.saveFailedAfterAudioCut` remonte jusqu'au bandeau d'erreurs de
   `MeetingView`. Auparavant l'erreur mourait dans un `print`.
3. **Le fichier temporaire est nettoyé sur échec** dans `AudioFileEditor.trim` et `.cut`,
   sur le modèle du `catch` que `split` avait déjà.

**Trois points à connaître, tous relevés en revue :**

**La réparation des identifiants arrive à temps par circonstance, pas par construction.**
`repairStoreIfNeeded()` tourne dans le `onAppear` de `ContentView`, donc après
`applicationDidFinishLaunching`. Elle tient parce qu'aucun code de démarrage ne lit ces
identifiants aujourd'hui. **Le premier qui le fera cassera l'invariant en silence, sans
qu'aucun test ne s'en aperçoive.**

**`deleteSegment` sauvegarde le contexte partagé avant de couper l'audio.** C'est
volontaire et cela fait deux choses : le `rollback()` de fin ne peut plus emporter la
saisie en cours d'un autre champ (`MeetingView` a une sauvegarde différée de 0,6 s sur
`summary`, `referencedAbsent`, `nextDeadline`), et un store non inscriptible est découvert
**avant** la coupe irréversible.

**Le chemin d'échec de `context.save()` n'est couvert par aucun test.** Un test sur store
fichier rendu non inscriptible serait possible mais fragile (WAL SQLite). Le comportement
du `rollback` n'est vérifié que par lecture de code.

**Reste dû :** les huit autres correctifs de la spec (axes « fil principal » et
« robustesse des entrées »), volontairement non traités. La branche
`fix/code-review-data-safety-perf` n'a jamais été poussée ; elle reste la seule copie du
code des huit correctifs restants et ne doit pas être supprimée avant qu'ils soient repris.

---

## Éditeur de blocs

### Diagrammes Mermaid

Le cycle complet est implémenté :

1. placeholder de chargement compact ;
2. diagramme rendu dans une carte sobre ;
3. barre d'actions au survol avec modification et duplication ;
4. source ouvert dans un cadre avec en-tête, numéros de ligne et bouton
   « Terminé » ;
5. carte d'erreur avec message et bouton « Ouvrir le source ».

Le rendu Mermaid a été repris pour un résultat plus professionnel : thème
clair/sombre dédié, espacements cohérents, libellés SVG natifs compatibles
avec `NSImage`, connecteurs fins et pointes de flèche stables dans AppKit.

Le chemin principal utilise désormais une copie locale modifiable de
BeautifulMermaidSwift 1.0.4 (`Vendor/BeautifulMermaidSwift`, licence MIT,
commit amont documenté dans son `README.md`) et ELK Swift 1.0.2. Le rendu est
natif AppKit/CoreGraphics, sans WebView pour les six familles prises en
charge. Le moteur Mermaid JavaScript emballé reste le fallback des syntaxes
non reconnues par le parseur natif. Une correction locale retourne le
contexte bitmap AppKit : l'amont produisait sinon une image verticalement
inversée sur macOS.

Défauts corrigés :

- `-->` n'est plus transformé en tiret cadratin par AppKit ;
- le source est masqué pendant l'aperçu ;
- seule la première ligne réserve la hauteur de l'image ;
- la hauteur est recalculée après le rendu asynchrone ;
- l'ancien cadre est invalidé immédiatement puis au cycle AppKit suivant
  lors du passage aperçu/source ;
- le hit-test suit maintenant le rectangle réellement peint au lieu du
  caractère TextKit sous la souris. Le bouton « Ouvrir le source » reste donc
  cliquable même lorsque l'image déborde encore de sa ligne réservée ;
- la borne de fin d'un bloc ouvert est désormais **incluse**
  (`MermaidBlockLayout.selectionTouches`) : flèche droite, Fin ou un clic en
  bout de ligne laissent le bloc en édition et une frappe s'ajoute à la fin
  du source ; « Terminé » place le curseur au-delà du séparateur (un `\n`
  est inséré si le bloc clôt le document) et reste le seul geste qui
  referme le bloc — l'ancien contournement souris (`openSelectionLocation`)
  est supprimé, devenu inutile ;
- la carte Mermaid terminée, le placeholder et l'erreur utilisent désormais
  la largeur de colonne commune (960 pt) et le SVG est centré à l'intérieur ;
- la première ligne du source Mermaid utilise une hauteur TextKit normale :
  l'en-tête est réservé par l'espacement de paragraphe, ce qui évite un
  curseur vertical surdimensionné ;
- l'en-tête d'un bloc Mermaid ouvert élargit temporairement le clip de dessin
  au conteneur TextKit : celui du second bloc reste visible lorsqu'il suit une
  carte Mermaid haute ;
- les parseurs natifs vendored (flowchart/state, sequence, class, er,
  xychart) **jettent** désormais sur toute ligne non consommée
  (`autonumber`, `activate` seul, `click`, notes, `style`…, commentaires
  `%%` exceptés) au lieu de l'ignorer en silence : le rendu natif échoue et
  `MermaidRenderer` retombe sur le moteur JavaScript compatible — plus
  d'image incomplète mise en cache (patch local documenté dans
  `Vendor/BeautifulMermaidSwift/README.md`) ;
- la barre d'actions du diagramme fermé expose « Modifier » et « Dupliquer » ;
  la duplication conserve le bloc Markdown complet et ses attributs visuels ;
- `/diagramme` insère un squelette complet et valide :

  ```mermaid
  flowchart TD
      A[Début] --> B[Fin]
  ```
- le squelette inséré n'est plus sélectionné en entier : le curseur est placé
  après le bloc, qui se rend immédiatement, et une première frappe ne peut
  plus effacer tout le source ;
- les frappes caractère par caractère, le remplacement d'une sélection
  interne et l'édition près du dernier caractère conservent désormais
  strictement le reste du source et le Markdown sérialisé ;
- le bloc mermaid **ouvert** affiche son propre diagramme dans son cadre, au-dessus
  du source (bande plafonnée à 240 pt, `MermaidSourceLayout.previewMaximumHeight`) :
  l'image est celle de la dernière fermeture, **jamais** un rendu relancé à la
  frappe — le correctif de superposition du 2026-08-08 reste intact.

**Double liseré de l'aperçu.** L'image de l'attachment porte déjà son propre
cadre arrondi et son liseré, à la largeur de la colonne ; ils tombent donc
exactement sur ceux de la carte. C'est **systématique**, pour le diagramme
rendu, le cadre d'erreur et le placeholder — ce n'est pas une hypothèse.
Point d'esthétique laissé au jugement de l'auteur.

**Cause racine de la carte peinte par-dessus le bloc précédent — trouvée et
corrigée (2026-08-08).** Une revue finale a jugé le chantier non fusionnable
et a cherché plus loin : la cause est un défaut **antérieur au chantier**.
Fait mesuré (script conservé :
`docs/mesures/mesure-textkit.swift`) :
en TextKit 1, `lineFragmentRect` **inclut** l'espace réservé par
`paragraphSpacingBefore` et `paragraphSpacing` ; c'est `lineFragmentUsedRect`
qui commence au sommet du texte. Toute la géométrie de la carte d'un bloc
mermaid ouvert s'ancrait sur le rect de fragment, et se peignait donc
au-dessus du bloc précédent, d'un montant égal à la bande réservée. Ce défaut
précède le chantier : avec l'ancienne bande de 43 pt, l'en-tête remontait
déjà de 43 pt dans le bloc du dessus. C'est l'explication du constat qui a
lancé le chantier (« on ne voit pas qui appartient à qui »), que la
spécification avait mal diagnostiqué comme un simple problème d'écart.

Second fait mesuré (`mesure-f2-leviers.swift`, `mesure-f2-delegue.swift`) :
TextKit 1 **ignore** `paragraphSpacingBefore` sur le premier paragraphe du
conteneur. Un bloc mermaid en tête de note ne réservait donc rien : en-tête
invisible, bouton « Terminé » incliquable — également un défaut préexistant.
Corrigé par un délégué `paragraphSpacingBeforeGlyphAt` **passe-plat**, qui
relit l'attribut dans le storage et le renvoie : mesuré neutre partout
ailleurs. À noter, car contre-intuitif : le délégué **remplace** la valeur de
l'attribut au lieu de s'y ajouter.

Six correctifs, tous relus :

1. `1ea10a4` — toute la géométrie de la carte ouverte ancrée sur
   `lineFragmentUsedRect` (cadre, en-tête, aperçu, bouton « Terminé », numéro
   de ligne de la gouttière). Mesures : distance bas du cadre → bas du
   source 38 → 10 pt ; écart visible sous la carte −10 → +18 pt. Emporte
   aussi deux défauts de même cause : la puce du dernier item d'une liste
   voisine d'une carte décrochait d'environ 9 pt, et le filet de citation
   courait jusqu'à 28 pt sous sa dernière ligne.
2. `c009c64` — bande réservée pour un bloc mermaid ouvert en tête de note
   (délégué ci-dessus).
3. `72a4bd6` — le restylage inclut désormais le bloc **précédent**, qui
   porte l'écart inter-blocs : sans cela, `/tableau` et `/diagramme`
   n'aéraient pas le bloc au-dessus d'eux jusqu'au prochain restylage.
4. `b5aa506` — la bande réservée est recalculée quand un rendu aboutit sur
   un bloc **ouvert** : la réservation était calculée sur le placeholder
   pendant que le dessin utilisait le diagramme livré entre-temps (144 pt de
   débord).
5. `96c1119` — l'écart visible sous une carte vaut désormais celui du
   dessus (28 pt des deux côtés ; auparavant 18 en dessous, le `max`
   absorbant le padding intérieur).
6. `8d88197` — quatre points de solidité : le hit-test des cases à cocher
   s'ancre sur le texte (avant : cliquer dans le **vide** sous le dernier
   item d'une checklist voisine d'une carte cochait la case) ; la somme
   `headerHeight + previewHeight + bodyTopPadding` a un point d'entrée
   unique, `MermaidSourceLayout.reservedBandHeight` ; la fabrique de test de
   géométrie est refermée derrière `#if DEBUG` ; le test de mise en page
   passe par le vrai chemin de dessin.

Le test qui manquait, et qui a été ajouté : sur un éditeur réellement mis en
page (`ensureLayout`), le cadre calculé doit tenir dans l'espace vertical du
bloc et ne jamais remonter au-dessus du bloc précédent. Les tests antérieurs
étaient tous algébriquement auto-cohérents et ne mettaient jamais en page un
storage réel — c'est pour cela que le défaut est passé. Vérifié : en
revenant au rect de fragment, quatre assertions repassent au rouge.

**La vérification à l'écran n'a pas eu lieu.** L'application n'a pas été
lancée, aucun rendu n'a été observé. Tout ce chantier repose sur des mesures
de mise en page. Contrôles restants à l'écran : les deux blocs mermaid
encadrant un bloc ouvert, un bloc en tête de note, un source invalide (cadre
d'erreur dans la bande), la frappe longue dans un bloc ouvert sans
superposition, le clic sur « Terminé », le redimensionnement de fenêtre bloc
ouvert, la densité générale d'une note enchaînant plusieurs cartes, et le
confort de lecture d'un diagramme réduit au plafond de 240 pt.

**Superposition carte/source pendant l'édition — cause racine trouvée et
corrigée (2026-08-08).** Constat d'écran : la carte rendue (ou le cadre
d'erreur « Parse error ») se peignait par-dessus/sous le source ouvert
pendant la frappe, sans laisser le temps de cliquer « Terminé ». Mécanisme
mesuré : chaque frappe dans un bloc ouvert relançait un rendu du source
**incomplet** (le natif strict jette → `WKWebView` à chaque caractère) et
chaque completion en vol rejouait `refreshClosedMermaidGeometry` avec une
plage **capturée au lancement** — périmée dès que le bloc avait grandi, la
garde « bloc encore ouvert ? » échouait et la géométrie fermée s'appliquait
sur le bloc en édition. Double correctif :

1. `StyleRenderer.applyMermaidAttachment` ne crée plus d'attachment ni ne
   lance de rendu tant que le bloc est ouvert — l'attachment existant est
   reposé tel quel (même instance, run uniforme) et le rendu du source
   final part à la fermeture ;
2. `refreshClosedMermaidGeometry` retrouve le bloc par l'**identité** de
   son attachment au moment où le rendu aboutit (attachment absent = rendu
   périmé, no-op) — plus jamais par une plage figée.

Trois tests de régression dans `StyleRendererMermaidTests` (identité de
l'attachment pendant l'édition, completion périmée après croissance du
bloc, attachment remplacé). L'effacement visuel de l'ancienne carte doit
encore être confirmé à l'écran après relance complète de l'application.

### Tableaux

`/tableau` insère une grille de trois colonnes, une rangée d'en-tête et deux
rangées de corps. Les libellés `Colonne 1`, `Colonne 2`, `Colonne 3` sont des
placeholders visuels et ne sont pas sérialisés.

Fonctions disponibles :

- grille `NSTextTable` à colonnes fixes et cellules de hauteur stable ;
- curseur placé dans la première cellule ;
- ajout d'une ligne sous la ligne active ;
- suppression de la ligne active ; si l'en-tête est sélectionné, suppression
  de la dernière ligne de corps ;
- ajout d'une colonne à gauche ou à droite ;
- suppression d'une colonne avec garde sur la dernière colonne ;
- permutation de lignes et colonnes avec annulation/rétablissement ;
- barre de pied `+` / `-`, compteur lignes/colonnes et action d'ajout de
  colonne ;
- menu de colonne depuis l'en-tête.

Le tri ascendant et descendant apparaît dans le menu, mais reste un `TODO`
dans `EditorTextView`.

En lecture seule (`.markdownReadOnly(true)`), les contrôles de tableau sont
entièrement inertes : `activeTableInView` (point d'entrée partagé
dessin/interaction) refuse un éditeur non éditable — ni pied `+`/`−`, ni
menu de colonne — et `keyDown` écarte les raccourcis ⌘⌥/⌘⌥⇧/⌘⌥⌃ + flèche
avant d'atteindre les handlers (P2 revue Codex).

### Manipulation des blocs

La gouttière gauche appartient désormais au bloc et ne recouvre plus ses
contrôles internes.

Implémenté dans le worktree :

- apparition au survol des boutons d'insertion et de poignée ;
- clic sur `+` : insertion d'une ligne `/` au-dessus du bloc ;
- clic sur la poignée : sélection du bloc et menu contextuel ;
- menu Monter, Descendre, Dupliquer, Modifier le source et Supprimer ;
- clic droit routé par le menu contextuel natif AppKit, ancré au point du
  clic même lorsque l'éditeur est décalé dans sa fenêtre ;
- déplacement clavier avec `⌥↑` / `⌥↓` ;
- glisser-déposer avec bloc atténué et trait bleu entre les blocs ;
- cadre bleu distinct de la sélection textuelle.
- espacement vertical de 10 pt à la fin de chaque bloc logique, porté à 28 pt
  (`BlockGutterLayout.cardBlockSpacing`) dès qu'un des deux blocs voisins dessine
  un cadre — mermaid, tableau, image, bloc de code. Seul `paragraphSpacing` le
  porte : y ajouter `paragraphSpacingBefore` doublerait l'écart, TextKit
  additionnant les deux.

Correctifs issus de la revue Codex du 2026-08-08 (P1) :

- la réécriture du glisser-déposer est extraite en fonction pure
  (`BlockMoveCommands.dragRewrite`) qui normalise le séparateur : déplacer
  le **dernier** bloc (sans `\n` final) ou déposer **en fin** de document
  ne colle plus deux blocs sur la même ligne (`"A\nB"` → `"BA\n"`, corrigé
  et couvert par 5 tests) ;
- le constat « pas d'undo sur les mutations de bloc » est **réfuté par
  l'expérience** : le bracket `shouldChangeText`(remplacement non
  nil)/`didChangeText` avec `allowsUndo` enregistre nativement l'inverse
  **attribué** (`md*` compris) — suppression, duplication, insertion `/` et
  drag avaient déjà un ⌘Z fonctionnel. Mesuré et verrouillé par
  `EditorTextViewBlockMutationUndoTests` (6 tests) ; le patron est
  centralisé dans `EditorTextView.replaceBlockCharactersRegisteringUndo`,
  dont la doc explique pourquoi il ne faut **pas** ajouter de
  `registerUndo` manuel par-dessus (inverse enregistré en double, mesuré).
  `swapAdjacentBlocks`/`applyTaskToggle` restent des cas différents : ils
  n'appellent pas le bracket.

Correctifs P2 de la même revue (lecture seule) :

- clic droit : menu natif d'AppKit, jamais le menu de bloc mutable ;
- gouttière : `blockGutterHit` refuse un éditeur non éditable (poignée `⠿`
  et `+` inertes) et le survol ne peint plus les affordances d'édition ;
- `BlockMoveCommands.moveUp/moveDown` portent la garde d'éditabilité
  (couvre ⌥↑/⌥↓ **et** Monter/Descendre du menu, qui mutent sans bracket
  `shouldChangeText`).

Côté images (P2) : `ImageAttachmentFactory.maxWidth` revient à **480 pt**
(limite des images ordinaires, jamais réajustées au conteneur par TextKit)
et la colonne mermaid a sa propre constante
`MermaidBlockLayout.columnWidth = 960` consommée par
`MermaidAttachmentFactory` — le passage global à 960 clippait les images
dans les éditeurs de 300–600 pt et cassait
`ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
(reverdi par ce découplage).

Le déplacement clavier est couvert par les tests existants. Le glisser-déposer
réel et le menu de bloc doivent encore être vérifiés dans une fenêtre AppKit,
notamment le dépôt après le dernier bloc et la conservation de la sélection.

## Fonctions Markdown déjà livrées

| Fonction | État |
|---|---|
| Menu `/` | 17 commandes, panneau limité à huit lignes visibles |
| Raccourcis à la frappe | `# `, `- `, `1. `, `> `, `[] `, `---` |
| Listes | marqueurs, cases cliquables, ⏎, Tab, ⇧Tab et ⌫ |
| Mentions `@` | recherche, création et ouverture de la fiche |
| Citations | filet vertical |
| Images | affichage, collage et déplacement |
| Liens | liens externes et routage interne injecté |
| Dates | popover avec date et heure |
| Blocs | sélection, menu, clavier et drag en cours de validation |

L'aller-retour Markdown a été vérifié auparavant sur 119 notes réelles,
sauvegardées dans `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`.

## Validation du 2026-08-08

Commandes passées sur le code actuel :

- `swift build` : **réussi** ;
- vérification ad hoc temporaire : **code de sortie 0**, script supprimé
  automatiquement ;
- `swift test --filter MermaidBlockLayoutTests/test_openSelectionLocation_atExclusiveEnd_isMovedBackInsideBlock` :
  **1 test, 0 échec** ;
- `swift test --filter MermaidSourceLayoutTests` : **8 tests, 0 échec** ;
- `swift test --filter Mermaid` : **82 tests, 0 échec** ;
- `swift test --filter Mermaid` après intégration native : **88 tests,
  0 échec**, dont 3 scénarios d'édition sans perte et le rendu bitmap natif ;
- `swift test --filter EditorTextViewMermaidClickTests` : **11 tests,
  0 échec** ;
- `swift test --filter SlashControllerTests` : **81 tests, 0 échec**, dont
  le nouveau test du squelette `/diagramme` ;
- `swift test --filter BlockGutterLayoutTests` : **4 tests, 0 échec**, dont
  le menu contextuel dans une fenêtre décalée ;
- `swift test --filter BlockGutterLayoutTests --filter StyleRendererTests
  --filter MarkdownTableRenderingTests --filter TableControlLayoutTests
  --filter SlashControllerTests` : **158 tests, 0 échec** ;
- capture native générée et inspectée : orientation corrigée, « Début » au-
  dessus de « Fin », flèche descendante, texte lisible ;
- `BuiltInTemplatesTests` : **4 tests, 0 échec** lorsqu'ils sont lancés avec
  la suite Slash.

Prochaine action : vérifier visuellement dans l'application la visibilité de
l'en-tête du second bloc et le clic sur le dernier caractère sans passage au
rendu ; « Terminé » doit rester l'action explicite.

## Validation du 2026-08-08 (correctifs P1 revue Codex)

- `swift test --filter Mermaid --filter BlockMoveCommandsTests
  --filter BlockGutterLayoutTests --filter EditorTextViewBlockMutationUndoTests` :
  **139 tests, 0 échec** (dont 5 `dragRewrite`, 6 undo, 7 parseurs stricts,
  4 `openBlockRange`, 2 `doneCaretPlacement`) ;
- balayage éditeur large (`SlashControllerTests`, `StyleRendererTests`,
  `TableControlLayoutTests`, `TableEditCommandsTests`,
  `MarkdownTableRenderingTests`, `ListEditingCommandsTests`,
  `EditorTextView*`, `EditorRepresentable*`, `BlockRangeTests`) :
  **312 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : la partie Swift Testing
  passe (**138 tests, 24 suites**) et, contrairement au constat précédent,
  l'exécution globale XCTest est allée au bout (pas de signal 6) avec
  **2 échecs préexistants étrangers aux correctifs** :
  `ImageAttachmentFactoryTests.test_scaledHeight_isRoundedToWholeNumber`
  (échec introduit par le changement **non commité** de `maxWidth` dans
  `ImageAttachmentFactory.swift` — vérifié : le test passe sur HEAD une
  fois le worktree remisé) et `MenuBarStatsTests.test_badge_twelve_compact`
  (test de barre de menu dépendant de l'heure, limite déjà connue).

## Validation du 2026-08-08 (correctifs P2 revue Codex)

- suites lecture seule et largeurs (`TableControlLayoutTests`,
  `TableEditCommandsTests`, `BlockGutterLayoutTests`,
  `BlockMoveCommandsTests`, `MermaidAttachmentFactoryTests`,
  `ImageAttachmentFactoryTests`, `StyleRendererTests`) : **0 échec**, dont
  6 nouveaux tests lecture seule et le `test_scaledHeight` reverdi ;
- balayage éditeur large (mêmes suites que la validation P1) :
  **325 tests, 0 échec** ;
- `swift test --skip CalendarImportEventTests` : exécution globale au bout,
  **un seul échec restant**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, limite connue hors chantier).

Séparation du hunk de migration (P2) : le retrait du
`OneToOneMigrationPlan` explicite dans `OneToOneApp.swift` reste dans le
worktree mais ne doit **pas** partir avec la PR éditeur — au moment du
commit, exclure `OneToOneApp.swift` (et le porter ensuite sur une branche
dédiée, ex. `git stash push -- OneToOne/OneToOneApp.swift` puis pop sur la
nouvelle branche). Une PR = une intention.

Prochaine action : vérifier en fenêtre réelle le nouveau geste « Terminé »
(curseur au-delà du séparateur, insertion du `\n` en fin de document), la
frappe en fin de source d'un bloc ouvert, et l'apparence d'une note en
lecture seule (aucune affordance de bloc/tableau) ; puis découper les
commits de la branche en excluant `OneToOneApp.swift`.

Correctif superposition/rendu en cours de frappe : validé par
`StyleRendererMermaidTests` (17 tests) et un balayage éditeur de 311 tests,
0 échec ; app dev reconstruite et installée (build 573) pour vérification à
l'écran du scénario exact (frappe longue dans un bloc ouvert, puis
« Terminé »).

Dernière mise à jour : 2026-08-08 09:14 CEST.

La commande globale `swift test` ne fournit pas actuellement un verdict
exploitable : le processus `xctest` termine avec le signal 6 pendant
l'exécution globale, sans assertion en échec dans les suites de l'éditeur.
Le phénomène est reproductible hors sandbox. Les suites voisines
`BuiltInTemplatesTests`, `SlashControllerTests` et toutes les suites Mermaid
passent lorsqu'elles sont lancées séparément.

Autres limites historiques du harnais :

- `CalendarImportEventTests` peut planter dans l'environnement de test
  (`bundleProxyForCurrentProcess is nil`) ;
- `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` dépend de l'heure :
  il place un créneau entre +2 h et +3 h après minuit et échoue donc si la suite
  est lancée entre minuit et 3 h du matin ;
- `MenuBarStatsTests.test_badge_twelve_compact` **a été supprimé le 2026-08-09**.
  Il était décrit ici comme dépendant de l'heure : c'était faux. Il affirmait
  `" ●12"` pour `hasOverdue: true`, alors que `MenubarBadgeText.suffix` rend
  volontairement `" ⚠12"` — son commentaire de code documente ce choix. Attente
  périmée, pas problème d'horloge. Conséquence à connaître : le glyphe `⚠` du cas
  « au moins une action en retard » n'a plus aucun test ;
- un test de montage de transcription est intermittent.

## Validation du 2026-08-08 (tâche 6 — aération des blocs-cartes et aperçu figé du bloc mermaid ouvert)

- `swift test --skip CalendarImportEventTests` : suite Swift Testing —
  **138 tests, 24 suites, 0 échec** ; suite XCTest — **940 tests, 1 test
  ignoré, 1 seul échec**, `MenuBarStatsTests.test_badge_twelve_compact`
  (dépendant de l'heure, préexistant, déjà documenté ci-dessus). Aucune
  régression du chantier.

**Étape 2 (`Scripts/bump-and-build.sh dev`) et étape 3 (vérification à
l'écran) n'ont pas été exécutées dans cette session** : elles demandent une
session graphique et un œil humain. Le chantier n'est donc **pas** validé
visuellement. Reste à faire, dans une note contenant, dans l'ordre, un
paragraphe, un bloc mermaid valide, un second bloc mermaid valide, un
tableau, après rendu des deux diagrammes puis clic dans le source du
**second** bloc :

1. les deux cartes rendues et le tableau sont nettement séparés (28 pt) ;
   deux paragraphes de texte restent serrés ;
2. le bloc ouvert affiche, dans son propre cadre : en-tête `mermaid` +
   « Terminé » en haut, puis son diagramme, puis un filet, puis le source
   numéroté ;
3. l'en-tête ne touche plus le cadre du bloc précédent ;
4. frapper plusieurs caractères dans le source : l'aperçu ne bouge pas et
   aucune carte ne se superpose au source ;
5. cliquer « Terminé » : le bloc se referme et le diagramme se met à jour ;
6. répéter avec un bloc mermaid placé en tout début de document ;
7. répéter avec un source volontairement invalide (`flowchart TD` puis
   `((((`) : le cadre d'erreur doit s'afficher dans la bande d'aperçu ;
8. redimensionner la fenêtre pendant qu'un bloc est ouvert et noter le
   comportement (limite connue ci-dessus).

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener les huit contrôles ci-dessus à
l'écran.

Dernière mise à jour : 2026-08-08 11:49 CEST.

## Validation du 2026-08-08 (revue finale — cause racine de la bande réservée)

Une revue finale a jugé le chantier non fusionnable et trouvé la cause
racine décrite dans « Diagrammes Mermaid » ci-dessus. Six correctifs
(`1ea10a4`, `c009c64`, `72a4bd6`, `b5aa506`, `96c1119`, `8d88197`), tous
relus.

- `swift test --skip CalendarImportEventTests` : **957 tests exécutés, 1
  ignoré, 1 seul échec** — `MenuBarStatsTests.test_badge_twelve_compact`,
  préexistant et dépendant de l'heure (documenté plus haut) ;
- `swift build -c release` : **réussi**.

**La vérification à l'écran n'a toujours pas eu lieu.** Elle reste entière,
avec les huit contrôles listés dans la section « Validation du 2026-08-08
(tâche 6) » ci-dessus, complétés par : la frappe longue dans un bloc ouvert
sans superposition, le clic sur « Terminé », et la densité générale d'une
note enchaînant plusieurs cartes.

Prochaine action : construire et lancer l'app de développement
(`Scripts/bump-and-build.sh dev`), puis mener à l'écran, dans l'ordre, les
huit contrôles de la section « tâche 6 » et les trois contrôles ajoutés
ci-dessus. C'est la seule chose qui manque avant de considérer ce chantier
fusionnable ; tout le reste (géométrie, tests, build release) est déjà
vérifié.

Dernière mise à jour : 2026-08-08 16:32 CEST.

## Dette immédiate

1. Vérifier à l'écran, après relance, le scénario exact de la dernière
   capture : carte d'erreur, clic sur « Ouvrir le source », disparition de la
   carte et édition du source.
2. Tester le glisser-déposer réel de blocs dans une `NSWindow`, y compris les
   première et dernière positions.
3. Implémenter ou retirer les commandes de tri du menu de colonne.
4. Ajouter les tests manquants de `/sommaire` : document sans titre, doublons,
   niveaux, aller-retour et héritage des attributs de frappe.
5. Stabiliser l'exécution globale XCTest + Swift Testing avant de considérer
   la suite complète comme verte.
6. Tester les diagrammes Mermaid hors des six familles natives (ou utilisant
   HTML, callbacks, tooltips et styles avancés) pour confirmer visuellement
   le fallback JavaScript sur un corpus de notes réelles.

## Défauts connus hors chantier

- le rappel choisi dans le popover de date n'est pas encore persisté ni
  déclenché ;
- mentions et dates utilisent encore largement le rendu des liens ordinaires ;
- `InlineHTML` n'est pas pris en charge par le parser ;
- l'emphase imbriquée complexe ne fait pas toujours un aller-retour strict ;
- le dépôt « à droite pour créer des colonnes de blocs » n'a pas d'équivalent
  Markdown et n'est pas prévu ;
- la poignée de gouttière d'un bloc mermaid **ouvert** s'aligne sur la première
  ligne de source, donc à côté du source et non en haut du cadre : elle se cale
  sur les rects de ligne, et la bande en-tête/aperçu vit dans l'espacement de
  paragraphe, hors ligne ;
- la hauteur réservée à la bande d'aperçu est calculée avec la largeur de colonne
  connue **au moment du stylage** : redimensionner la fenêtre pendant qu'un bloc
  est ouvert peut laisser un léger vide (ou un léger recouvrement) sous l'aperçu
  jusqu'au prochain restylage du bloc.

Issus des six correctifs de la revue finale (2026-08-08) :

- `MainActor.assumeIsolated` **élargi** : l'assertion d'isolation s'exécute
  désormais à chaque restylage ciblé, non plus seulement quand un bloc
  mermaid figure dans la plage. Aucun appelant actuel n'est hors fil
  principal, mais la surface d'exposition a grandi ;
- coût du restylage étendu : chaque frappe restyle aussi le bloc précédent.
  Sous un tableau, cela reconstruit son `NSTextTable` ; sous un bloc mermaid
  fermé, cela re-pose l'attachment. Le cache d'attachments évite le rendu,
  sauf éviction du `NSCache` — auquel cas un rendu peut repartir, pour un
  bloc **fermé** uniquement ;
- couverture : le cas tableau de l'écart sous une carte n'a pas de test de
  garde, et la symétrie 28/28 est prouvée en deux morceaux dont l'un pose la
  valeur à la main ;
- état mixte au chargement : ouvrir une note qui se termine par un bloc
  mermaid le style « fermé » alors que le curseur le touche. Antérieur à ce
  chantier ; l'effet net des correctifs y est positif (la bande est enfin
  réservée), mais l'état mérite un passage.

## Décisions structurantes

1. ~~Le Markdown reste la source de vérité ; aucun modèle de blocs persistant
   séparé n'est introduit.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
2. ~~TextKit 1 est conservé. Les marqueurs de liste et les contrôles sont
   dessinés par les composants AppKit existants.~~ **Annulée le 2026-08-08**
   par [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
3. Les couleurs libres ne sont pas sérialisées : pas de HTML inline ajouté
   uniquement pour la présentation.
4. ~~Aucun code AppFlowy n'est repris ; la référence sert uniquement au design
   et aux comportements.~~ **Annulée le 2026-08-08** par
   [l'ADR de réécriture](docs/adr/2026-08-08-reecriture-editeur-architecture-appflowy.md).
5. Les liens internes restent routés par une closure injectée dans l'éditeur.
6. BeautifulMermaidSwift est vendored comme cible SwiftPM locale afin de
   permettre les correctifs macOS et l'évolution du style dans ce dépôt ;
   ELK Swift reste une dépendance distante verrouillée en 1.0.2.
