# Refonte de l'écran de réunion — bilan des décisions D0 à D11

- **Statut** : accepté, 2026-09-08.
- **Portée** : les vingt lots de la refonte 2026-09 (0A → 19c).
- **Références** : spec `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` (branche
  `docs/refonte-reunion-programme`) ; plan directeur
  `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`, §4 pour les décisions ;
  comptes rendus de session `docs/superpowers/specs/refonte-2026-09/journal-des-lots.md` ;
  recette `docs/superpowers/specs/refonte-2026-09/recette/2026-09-07-recette-vagues-1-4.md`.

## Contexte et problème

L'écran de réunion avait sept onglets, une barre latérale droite configurable, un dashboard
personnalisable, et une cinquantaine de `@State` dans `MeetingView.swift` dont huit
descendaient en `@Binding` sur deux niveaux. Treize captures de maquette et une spécification
en douze sections décrivaient un autre écran : trois espaces, trois modes temporels, un rail
d'actions permanent, un tiroir de ressources, un mode séance plein écran, deux écrans de 1:1
par rôle, des planches d'atelier, et un rapport dont chaque ligne remonte à sa source.

Douze décisions structurantes ont été posées avant le premier lot, et arbitrées le
2026-09-07. Cet ADR consigne **ce qui a réellement été fait**, décision par décision, avec où
le vérifier — puis ce que la refonte a assumé de ne pas reproduire, et ce qu'elle laisse.

## Les décisions, telles qu'appliquées

| # | Décision retenue | Appliquée comment | Où le vérifier |
|---|---|---|---|
| **D0** | La capture `1c` est la **disposition du mode Relire**, pas un quatrième mode | `MeetingSpaceView` route `mode == .review` vers le poste de pilotage ; `MeetingSpacesBar.estMasquee` retire la barre d'espaces dans l'espace Réunion en Relire, où la nav latérale de 190 px la remplace — et la laisse dans Rapport et Ressources, qui n'en ont pas | `Views/Meeting/Spaces/Review/**`, `Tests/ReviewStateTests.swift` |
| **D1** | Les notes horodatées sont une **table** (`MeetingNote`), pas du markdown enrichi de marqueurs | Une ligne par note : `t`, `kind`, `visibility`, `sourceRef` en trois colonnes plates, `orderIndex`. `liveNotes` n'est pas effacé et est importé une fois en une note `t = 0` ; le chemin markdown du type `Note` n'a pas été touché | `Models/MeetingNote.swift`, `MeetingNoteStore.importLiveNotesIfNeeded` |
| **D2** | IBM Plex **embarquée**, avec repli système explicite | Cinq fichiers OFL dans `Resources/Fonts`, enregistrés en portée `.process` au premier usage ; `Font.plexSans`/`plexMono` retombent sur la fonte système si le nom PostScript ne résout pas. Le lot 19c a ajouté les pendants `NSFont`, sans quoi les `NSViewRepresentable` sortaient en fonte système | `Views/DesignSystem/One2OneTypography.swift` |
| **D3** | Le 1:1 est un **domaine** (`OneOnOneThread` + quatre tables), pas des colonnes JSON sur `Collaborator` | Fil créé paresseusement au premier 1:1 ; engagements, ordre du jour, humeurs et objectifs en cascade. `Meeting` et `Collaborator` étaient déjà des objets « dieu » | `Models/OneOnOneModels.swift`, `Services/OneOnOne/**` |
| **D4** | `myRole` **déduit du type** de réunion, jamais saisi | `1:1` = je mène, `1:1 Manager` = je suis mené ; badge obligatoire côté collaborateur ; le manager reste résolu par `AppSettings.managerEmail` | `OneOnOneThreadStore`, `Views/Meeting/OneOnOne/**` |
| **D5** | Les pièces déposées sont **copiées**, jamais référencées | Copie sous `recordings/<uuid>/documents/` ; les `MeetingAttachment` antérieurs sont copiés paresseusement à la première ouverture, ou marqués orphelins si la source a disparu | ADR `2026-09-07-pieces-copiees-jamais-referencees.md` |
| **D6** | **Excalidraw embarqué** dans un `WKWebView` pour les planches | Bundle local inliné (aucun CDN, comme `MermaidResourceLocator`), un seul `WKWebView` vivant par réunion, trois modes de palette, derrière le drapeau `workshopEnabled`. Scène et vignette sur disque, jamais en base | ADR `2026-09-07-moteur-de-planches-excalidraw-embarque.md`, `Views/Meeting/Workshop/**` |
| **D7** | Le changement de partage se détecte par **différence d'image** | `CaptureCoordinator` repris de Teams-Capture : `detectsAutomatically` sur `SlideDetector`, `periodicCapture` armant l'écriture au prochain tick stable. Le titre de fenêtre ne sert qu'à repérer la réunion active | `Views/Meeting/Capture/**`, `Services/Capture/**` |
| **D8** | Le dashboard personnalisable est **retiré**, son code supprimé au lot 19 | Débranché au lot 1, supprimé au lot 19a : `OverviewDashboard`, `PanelLayoutEntry`, `DashboardGridLayout`, `MeetingTabsUnderline`, `CollaboratorDetailView`. La colonne `AppSettings.rightSidebarLayoutJSON` survit sans lecteur (une suppression de colonne casserait la lightweight migration) | `docs/cleanup-report.md` §8 |
| **D9** | `escalated` **exclu** du récap collaborateur, inclus dans un export « Escalade » explicite, sans trace d'accès | `ConfidentialityFilter` est **la** règle de sortie, écrite une fois ; gabarit `d11_escalade` pour l'unique audience `.hr` ; confirmation à la première utilisation par réunion | `Services/ConfidentialityFilter.swift` |
| **D10** | ~~Calendrier et Eisenhower **restent dans le rail** de 330 px, en rendu compact~~ — **amendée le 2026-09-08** : le rail n'affiche que la liste | Le sélecteur `Liste / Calendrier / Eisenhower` a été retiré du rail sur retour d'usage (voir « D10 amendée » ci-dessous) | `Views/Meeting/Spaces/Rail/ActionsRail.swift` |
| **D11** | Édition des planches **mono-utilisateur**, pilule de présence masquée | La spec le prévoit (« sinon masquée ») | `Views/Meeting/Workshop/**` |

### D10 amendée — le rail n'affiche que la liste (2026-09-08)

La décision d'origine tenait à un seul argument : « la capture `1a` fait foi », et la capture
montre bien la rangée `Liste / Calendrier / Eisenhower` sous les onglets du rail. À l'usage,
la rangée ne servait pas. Trois raisons, dans l'ordre où elles se sont imposées :

- **330 px ne sont pas une matrice.** Un quadrant d'Eisenhower compact tombe à 54 px de haut et
  une cellule de calendrier à 32 px avec **une** action visible : on y voit qu'il y a des
  actions, pas lesquelles. Le rendu compact était honnête, la surface ne l'était pas.
- **Ce n'est pas le geste de la séance.** En séance on lit une liste et on assigne ; on trie par
  urgence et importance après, sur l'écran Actions plein, qui garde ses cinq vues.
- **La rangée coûtait 34 px** sur la seule colonne où la hauteur manque, et un niveau de
  navigation de plus sous un premier niveau (`Actions / Risques / Historique`) qui, lui, sert.

Ce qui reste, et ce n'est pas du code mort : `ActionsViewMode.railCases` et la persistance
`MeetingScreenModel.railViewMode` (les cinq vues de `ActionsListView` s'en servent), le rendu
compact de `CalendarBoard` et `EisenhowerBoard` et ses tests (`ActionsBoardsCompactTests`).
Le rail est le seul appelant qui disparaisse.

## Écarts assumés avec les captures

Consolidés depuis les comptes rendus de lot. Ils sont **visibles** et **volontaires** : la
spécification a été suivie contre la maquette, ou la reproduction aurait coûté un changement
hors périmètre.

| Écart | Où | Pourquoi assumé |
|---|---|---|
| Ordre de la pile d'avatars | barre du haut (lot 1) | l'ordre du modèle, pas celui de la capture — à trancher |
| Titres du bloc `ALERTES` et nom de projet | poste de pilotage (lot 5) | `RefonteDemoSeed` est gelé pour les lots livrés ; ce sont des données de semis, pas du rendu |
| Compteurs `Notes 6`, `EN ATTENTE 9` | bandeau, préparation (lots 1, 12) | le semis ne produit pas les mêmes nombres que la maquette |
| Format de date des jalons en édition | fiche projet (lot 9) | `30/09/2025` au lieu de `30 sept.` : c'est le format d'un champ de saisie |
| Icône de l'espace `Notes` | barre d'espaces (recette) | barre oblique au lieu d'un crayon ; la spec ne chiffre pas les symboles |
| Ordre et métadonnée des pièces du tiroir | ressources (recette) | la pièce présentée reste à sa place ; métadonnée `09:42 · 213 Ko` au lieu de `Repris du projet` |
| Marqueur de risque en rond ambre sur la frise | notes ↔ transcription (lot 2) | la maquette le dessine autrement ; sans incidence fonctionnelle |
| Ordre vertical de l'écran `4a` | sélecteur de capture (lot 7) | déplacer la frise hors de la carte aurait touché la disposition des lots 2, 4 et 5 |
| Badge `ATELIER` tronqué sous 1 616 px | fil d'Ariane (lot 16) | masquer le fil sous une largeur seuil est un arbitrage, pas une finition |
| Titre de la 14ᵉ séance d'un fil | en-tête 1:1 (lots 11, 12) | la clé d'idempotence `1:1 — <prénom> · <n>` prime sur le libellé de la capture |
| Objectif ambre au lieu de violet, phrase de tendance, taux `73 %`, tri par retard | préparation 1:1 (lot 12) | la spec fait foi là où elle contredit la maquette |
| « Zone à la souris » non sélectionnable | sélecteur de capture (lot 7) | `CaptureSource.region` est dans le modèle, personne ne l'écrit |
| Calques du mode Schéma | atelier (lot 17) | mentionnés dans la table §7.1, non faits — à arbitrer |

## Ce que le lot 19c laisse ouvert

**Décisions produit, en attente** (détail et formulation dans `STATUS.md`) : les lignes de
démonstration écrites dans le store de production au lot 9 ; la teinte de la barre de budget à
65,6 % (règle chiffrée ou maquette) ; l'ordre des avatars ; le contraste `ok/deep` sur `ok/bg`
mesuré à 4,43:1, sous le seuil de 4,5 ; les compteurs `Notes 6` et `EN ATTENTE 9` ; le bouton
`Capture` en 1:1 (le reléguer dans `⋯` comme la maquette 2a) ; la **barre du haut en mode
Relire** — la masquer, comme le montre `1c`, prive de l'accès au type, au template et au `⋯`,
c'est un arbitrage relevant de D0 et non une finition ; le **conflit `⌘⏎`**, que le menu emploie
pour « Générer le rapport » là où la spec §1.4 le veut pour valider un composeur ; le rail
invisible sous 850 px, qui rend le composeur d'action injoignable.

**Dettes techniques** : la table complète est dans `docs/cleanup-report.md` §8 et
`docs/architecture.md` §13. Les trois qui touchent ce lot :

- **Trois doublons de raccourci** — `⌘K`, `⌘M` et `⌃⌘F` sont redéclarés dans
  `Views/Meeting/Session/**`, chacun avec son commentaire justificatif. Le dossier est tenu
  par un correctif concurrent ; les trois sont inscrits comme **exceptions nommées** dans
  `Tests/MeetingShortcutsTests.swift`, donc toute occurrence nouvelle casse le test.
- **`Commitment.linkedAction` n'est pas sauvegardée** — `ActionTask` n'expose pas d'identité
  stable, et relier par titre créerait de faux liens entre deux actions homonymes.
- **Le composeur `＋ Action` ne prend pas le clavier** — il faudrait un jeton de focus dans
  `MeetingScreenModel` et une reprise du composeur : une intention à part.

**Recette visuelle** : les douze écrans restent à recapturer avec le binaire de la pile
complète, écran déverrouillé et sans réunion Teams (lot 19b). Le lot 19c a rendu l'outillage
digne de confiance — binaire périmé refusé, bundle de recette isolé, verrou et appel détectés —
mais n'a lancé aucune application graphique.

## Conséquences

**Positives.** L'écran a une structure nommée (espaces × modes) et une seule source d'état
(`MeetingScreenModel`) ; les règles métier sont des fonctions pures testées avant leur vue ;
les couleurs et les fontes ont une source unique ; les raccourcis ont une table qu'un test
défend ; la sauvegarde couvre les neuf tables du modèle cible ; les scripts de recette ne
peuvent plus produire deux heures d'observations fausses en silence.

**Négatives.** `MeetingView.swift` reste le plus gros fichier de `Views/` malgré la règle
« on n'y ajoute rien » ; le dépôt porte ~3 000 lignes de code mort **hors** refonte qu'aucun
lot n'avait le droit de retirer ; deux mécanismes d'engagement coexistent (`EngagementLedger`
dérivé, `Commitment` en table), par choix, pour ne pas compter deux fois ; une colonne sans
lecteur attend la prochaine version de schéma.

## Alternatives étudiées

Chaque alternative est celle de la colonne « Options » du §4 du plan directeur. Les deux plus
lourdes de conséquence, écartées : un **moteur de planches natif** écrit de zéro (D6 b),
incapable de tenir 2 000 objets à 60 fps, l'annulation sur 100 pas, une bibliothèque de formes
et des connecteurs dans le délai ; et le **stockage des notes en markdown enrichi de
marqueurs** `[04:12]` reparsés (D1 b), qui ne permet ni confidentialité par ligne, ni `kind`,
ni chaîne de citation, ni `isExportable` — tout ce dont le rapport et le récap 1:1 dépendent.

## Suite

Le programme s'achève sur la **recette finale (lot 19b)** : recapture des douze écrans à
1 280 et 1 920 px et comparaison aux références. Les décisions produit listées ci-dessus
attendent Laurent ; aucune ne bloque la fusion de la pile.
