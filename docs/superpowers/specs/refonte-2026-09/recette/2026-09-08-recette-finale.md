# Recette finale des treize écrans — lot 19b (2026-09-08)

Branche `fix/refonte-recette-finale`, sur `feat/refonte-lot-19c-cloture-suite` (sommet de la
pile `#19 → … → #45 → #46`, `925b035`, 3 056 tests). Binaire **release** de la pile complète,
empaqueté par `Scripts/recette-app.sh` (`md5 a09b789f1c27b8e6c74f0c45da3be84d`, 2026-09-08
07:39:09), lancé par `Scripts/recette-run.sh` dans un home jetable.

**État : 24 captures produites, couvrant les treize écrans de référence. Huit corrections de
finition livrées. Vingt-et-un écarts assumés confirmés. Onze écarts fonctionnels restants,
dont cinq sur l'outillage de recette lui-même.**

C'est la première fois que **`1b`** (mode séance plein écran), **`4b`** (pastille flottante),
**`4a`** (sélecteur de source) et **`3a`** (tiroir par-dessus la séance, pièce présentée) sont
vus dans l'application. Le correctif #42 est confirmé : `⌃⌘F` — l'item « Mode séance plein
écran » — substitue bien le contenu, et `Esc` en sort.

---

## Conditions de la passe

- **Écran** : déverrouillé, sauf deux interruptions de 90 s (06 h 41 → 06 h 43 et
  07 h 12 → 07 h 13) pendant lesquelles le sondage réglementaire a tourné. Aucune capture
  prise pendant un verrou.
- **Teams** : ouvert pendant toute la passe, **sans réunion** — la seule fenêtre `MSTeams`
  portait « Calendar | APRIL | laurent.deberti@april.com ». C'est ce qui permet de vérifier
  que la ligne Teams du sélecteur `4a` dit bien « Fenêtre ouverte · aucune réunion active ».
- **Instance de l'utilisateur** (pid 16538, `.build/arm64-apple-macosx/release/OneToOne`,
  fenêtre « NPA/LDB », 0,33 / 1 720 × 1 024) : **jamais touchée**. Aucun événement, aucun
  redimensionnement, aucun arrêt. Sa géométrie est identique au début et à la fin de la passe.
  Tout le pilotage passe par `AXUIElementCreateApplication(<mon pid>)` et
  `CGWindowListCopyWindowInfo` filtré sur `kCGWindowOwnerPID` ; jamais AppleScript, jamais un
  nom d'application, jamais un identifiant de bundle.
- **Store de production** : jamais ouvert. `lsof` vérifié à **chaque** lancement (dix-huit
  lancements) — zéro descripteur hors de
  `/private/tmp/recette-finale/home/Library/Application Support/OneToOne/`.
- **Écrans** : le poste a **deux** écrans — l'intégré (1 728 × 1 117 pt) et un
  « 27M2U » externe (1 920 × 1 080 pt, origine x = 1 728). Toutes les fenêtres de recette ont
  été placées sur l'**externe**, pour ne pas recouvrir la fenêtre de travail de l'utilisateur.
  Cf. écart (c) n° 11 : la contrainte « 1 728 est le maximum de ce poste », posée par la
  recette des vagues 1 à 4, ne tient plus.

---

## Captures produites

Dans `docs/superpowers/specs/refonte-2026-09/recette/finale/` :

| Fichier | Taille en pixels | Fenêtre |
|---|---|---|
| `1a-1280.png` `1a-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | 1 280 × 800 pt · 1 728 × 1 021 pt |
| `1b-1728.png` | 3 840 × 2 160 | **plein écran, 1 920 × 1 080 pt** — cf. note ci-dessous |
| `1c-1280.png` `1c-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `2a-1280.png` `2a-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `2b-1280.png` `2b-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `3a-1280.png` `3a-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | tiroir ouvert, `Chiffrage_Marine_v3.xlsx` présenté |
| `3b-1280.png` `3b-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | fiche projet en panneau |
| `3b-edition-1728.png` | 3 456 × 2 042 | fiche projet, bascule `Édition` |
| `4a-1728.png` | 3 456 × 2 042 | popover du sélecteur ouvert (capture de **région**) |
| `4b-1728.png` | 600 × 80 | la pastille seule, **300 × 40 pt**, telle qu'elle apparaît en `1b` |
| `5a-1280.png` `5a-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `5b-1280.png` `5b-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `6a-1280.png` `6a-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |
| `6b-1280.png` `6b-1728.png` | 2 560 × 1 600 · 3 456 × 2 042 | idem |

⚠️ **`1b-1728.png` mesure 1 920 × 1 080 pt, pas 1 728.** Le nom est celui que la consigne
fixe ; la taille est celle du plein écran, qui prend l'écran où la fenêtre se trouve — ici
l'externe. Le mettre à 1 728 aurait demandé de passer la fenêtre sur l'écran **intégré**,
c'est-à-dire de recouvrir la fenêtre de travail de l'utilisateur et de faire basculer son
espace pendant la capture. Le choix a été de ne pas le faire et de le dire. Même remarque
pour `4b-1728.png`, qui mesure ce que mesure la pastille : 300 × 40 pt.

⚠️ Les captures des écrans `3a`, `3b` et `4a` ont demandé **d'ouvrir la surface à la main** :
leur code de recette ne l'ouvre pas (écart (c) n° 8). La séquence exacte est en fin de fichier.

---

## Écran par écran

### 1a — Cockpit (`1a-cockpit.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Barre du haut, une ligne, fil d'Ariane cliquable | conforme | — |
| Titre de réunion en Plex Sans 600, ellipsis | conforme | correctif du lot 19c (écart n° 3) vérifié |
| Aucun libellé écrasé à 1 280 px | conforme | c'est le **titre** qui prend l'ellipsis, comme §2.1 |
| Menus de type et de modèle : chevron **à gauche** du libellé (`⌄ Projet`, `⌄ Auto`) | écart (c) n° 1 | AppKit place l'indicateur d'un `Menu` avant le label ; la maquette le veut après |
| Bandeau : quatre cartes égales, libellés mono, valeurs 20 px | conforme | — |
| Pile d'avatars : six pastilles de 19 px, initiales lisibles | **corrigé (a)** | la seconde lettre de chaque paire était mangée par la pastille voisine |
| Pastilles d'avatar toutes de la même teinte `bg/app` | écart (c) n° 2 | la maquette colore chaque pastille (`Participant.avatarColor`) |
| `100 %` avec espace insécable | écart assumé | typographie française ; la maquette écrit `100%` |
| Barre de progression des actions vide | assumé (données) | aucune action close dans le semis |
| Points de risque : 3 rouges, 1 ambre, 1 neutre | assumé | table `MeetingKPI.Level.teinte` du lot 19c |
| Carte notes ↔ transcription, `1fr 1px 1fr`, corps 12,5 px | conforme | — |
| Bascule `Speakers` absente de l'en-tête | écart (c) n° 3 | dépend de `transcriptionMode == .diarizeFirst`, faux par défaut |
| Transcription sans nom de locuteur | assumé | le semis ne pose pas de locuteur |
| Frise audio, marqueurs ronds / carrés / losanges, légende | conforme | — |
| Rail de 330 px, `Actions 12 / Risques 5 / Historique`, `Liste / Calendrier / Eisenhower` | conforme | — |
| `À ASSIGNER — 9` au lieu de 3 | assumé | lot 4 |
| Pilule de source (`04:12 ↗`) repliée caractère par caractère, creusant la carte de 80 px | **corrigé (a)** | pilule construite sur place, échappée au correctif des primitives |
| Bouton `Capture 3` dans la barre du haut | assumé | lot 1 n° 5 |
| Chips `/action /décision /risque /citer` alignées à droite | assumé | lot 2 n° 2 |
| Bande `Captures de la séance` en pied de colonne | conforme (ajout du lot 7) | la maquette 1a est antérieure au chantier 4 |

### 1b — Mode séance plein écran (`1b-mode-seance.png`) — **vu pour la première fois**

| Zone | Verdict | Cause |
|---|---|---|
| Palette `dark/*`, grille `78 \| 1fr \| 400` | conforme | — |
| Barre d'état : point, `En séance · P25_110`, temps, avatars, `Clore la séance` | conforme | — |
| Colonne temps : axe, ronds (note), carrés (décision), libellés mono, `⊕ Marquer ⌘M` | conforme | — |
| **Le corps d'une décision recouvre la note suivante** | écart (c) n° 4 | le bloc à deux lignes ne déclare qu'une ligne à sa rangée ; texte illisible |
| `TRANSCRIPTION LIVE` + `Suivre`, segments horodatés | conforme | — |
| Panneau assistant : question, suggestions, champ | conforme | — |
| `CAPTURÉ CETTE SÉANCE` : trois compteurs | conforme | — |
| Bandeau `EN ATTENTE  9 actions sans responsable` + `Assigner maintenant` | conforme (compte assumé) | lot 4 |
| Locuteur courant (`CP parle`) absent | assumé | pas de locuteur dans le semis |
| `Esc` ramène au cockpit | conforme | vérifié |

### 1c — Poste de pilotage (`1c-poste-de-pilotage.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Nav latérale 190 px, entrée active en carte blanche, bloc projet, bloc `ALERTES · 5` | conforme | — |
| En-tête : titre + `ref · type · date · durée · n participants` sur une ligne | conforme | — |
| `EN UNE PHRASE` + pilule `généré` + tags de sujets | conforme | — |
| `DÉCISIONS PRISES · 3` | conforme | — |
| Tableau d'actions : sept colonnes, `Tableau / Eisenhower / Calendrier`, pied `7 autres · tout afficher` | conforme | — |
| Frise pleine largeur avec étiquettes et `✂ Éditer` | conforme | — |
| **La barre du haut reste affichée** | écart assumé, décision D0 en attente | renvoyé par le lot 19c |
| Le sélecteur de mode reste visible | assumé | lot 5 n° 6 |
| `Notes 6`, `Documents 5`, compléments de `Synthèse` | assumé | lots 1, 5 |
| `Exporter ⌄` désactivé et peu lisible | écart (c) n° 5 | même famille que le bouton `Rapport` (corrigé, cf. (a)) |
| Grande zone vide entre le tableau et la barre d'assistant | observation | le semis est plus court que la fenêtre ; aucune carte vide |

### 2a — 1:1 mené, séance (`2a-1to1-manager-seance.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Barre du haut teintée `#f4f1f6`, badge `1:1`, pilule `● Privé — vous deux` | conforme | §3.1 |
| Carte personne, `DERNIER 1:1`, `RYTHME` | conforme | — |
| Ordre du jour co-construit, avatars d'auteur, item barré, item reporté `→ 18/09` | conforme | — |
| `RESTÉ EN SUSPENS` avec compteur d'occurrences | conforme | — |
| **`① COMMENT ÇA VA` écrit deux fois** | **corrigé (a)** | `MoodScale` et la section de notes rendaient tous deux le libellé |
| Échelle 5 crans, cran bordé, delta `↓ vs 21 août (Bien)` | conforme | — |
| `② SES SUJETS`, bloc privé isolé `● NOTE PRIVÉE — VOUS SEUL` | conforme | — |
| `③ FEEDBACK` : deux cartes côte à côte | conforme | — |
| **Le rail de droite débordait de 24 px hors du cadre** | **corrigé (a)** | rembourrage appliqué après le cadrage de la colonne centrale |
| `TENUS DEPUIS LE DERNIER 1:1` : `✗` en report avec `2× reporté`, `✓` pour les tenus | conforme | — |
| `CLÔTURER` : récap, planification, mention des notes privées | conforme | — |
| Bouton `Capture` présent en 1:1 | assumé | lot 11 n° 5, décision en attente |
| `Transcrire + Rapport 1:1` désactivé, blanc sur rouge à 45 % | **corrigé (a)** | passe en `report/bg` + `report/ink` |
| Anneau de focus violet sur la carte `CE QUE JE LUI DIS` | observation | le mode En séance donne le focus à l'éditeur (§2.2) |

### 2b — 1:1 mené, préparation (`2b-1to1-manager-preparation.png`)

| Zone | Verdict | Cause |
|---|---|---|
| En-tête violet, `14ᵉ 1:1`, badges, `Historique`, `Démarrer l'entretien` | conforme | — |
| `MORAL — 6 DERNIERS 1:1` : six barres, dernière colorée, tendance `en baisse` | conforme | — |
| `OBJECTIFS S2` : label, %, barre colorée par avancement | conforme | 10 % en `warn` là où la maquette met du violet : la **règle** chiffrée de §3.4 |
| `À NE PAS OUBLIER` : trois règles, dot coloré, `Mettre à l'ordre du jour` | conforme | — |
| **« Vous lui devez Retour sur la grille d'astreinte »** — phrase agrammaticale | écart (c) n° 6 | `ReminderRules` concatène un préfixe et un titre d'engagement |
| Troisième règle (réussite récente reconnue) absente | écart (c) n° 6 | même origine |
| `Engagements réciproques` : filtre, cinq colonnes, `8 tenus sur 11 · taux 73 %` | conforme (taux assumé) | — |
| `SUJETS RÉCURRENTS` : chips colorées par famille | conforme | — |
| `HISTORIQUE` : quatre séances | conforme | — |

### 3a — Tiroir Ressources (`3a-tiroir-ressources.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Tiroir de 396 px par-dessus la séance, en-tête `Ressources 4 séance 17 projet ＋ Importer ✕` | conforme | — |
| Filtres `Cette séance / Le projet / Captures / Liens` | conforme | — |
| Vignettes : icône typée, nom, `Ajouté par X · hh:mm · poids` | conforme | — |
| `À l'écran` / `Citer` / `Envoyer` **sur chaque vignette** | conforme | correctif du lot 19c (écart n° 8) vérifié |
| Pièce présentée bordée `accent/action`, `À l'écran` plein | conforme | — |
| Zone de dépôt permanente avec `⌘⇧V` | conforme | — |
| Pied `À L'ENVOI DU RAPPORT` : trois cases, deux cochées | conforme | — |
| Pilule `● Partage actif · 5 voient` dans la barre du haut | conforme | §4.2 |
| Carte `À l'écran`, scène d'aperçu, légende **sous** le document | conforme | — |
| Bande `ÉPINGLÉ DANS LA SÉANCE` | conforme | — |
| **Chips d'épinglage nommées `slide-0001-091912`** | écart (c) n° 7 | le nom de fichier brut d'une capture sort à l'écran |
| `4 séance` compte le lien | assumé | lot 6 n° 4 |
| Aperçu du document indisponible | assumé (données) | les pièces du semis sont des fichiers vides |
| **À 1 280 px, la carte notes s'effondre : ses libellés recouvrent la frise** | écart (c) n° 9 | la scène d'aperçu prend toute la hauteur restante |
| Le tiroir se ferme quand on presse `Présenter` | observation | il faut présenter **avant** d'ouvrir le tiroir |

### 3b — Fiche projet en panneau (`3b-fiche-projet.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Panneau de 430 px depuis la droite, en-tête, bascule `Édition`, `✕` | conforme | — |
| `STATUT` (point + menu), `BUDGET CONSOMMÉ` valeur / total + barre | conforme | — |
| `JALONS` (état, libellé, date ou `bloqué`), `PÉRIMÈTRE & CONTEXTE` + tags, `RISQUES`, `INTERLOCUTEURS` | conforme | — |
| Pied : mention de visibilité **hors édition** | conforme | correctif du lot 19c (écart n° 10) vérifié |
| En édition : `＋ ajouter`, champs de date, `⊖`, chevrons, `Nouveau jalon…`, `Annuler` / `Enregistrer` | conforme | — |
| **En édition, le point de statut sort noir** au lieu d'ambre | écart (c) n° 10 | un `Image(systemName:)` dans un label de `Menu` est rendu en *template* par AppKit, qui écrase `foregroundStyle`. Corriger demande de changer le mécanisme que `Tests/RefonteFinitionsTests.swift` fige — donc une décision, pas une finition |
| En édition, les cellules de risque et d'interlocuteur coupent sans ellipsis | écart (c) n° 10 | ce sont des `TextField` SwiftUI : couper sans marque est leur comportement natif ; deux colonnes de ~200 px dans un panneau de 430 |
| Barre de budget **verte** à 65,6 % | assumé, décision en attente | lot 9 |
| Budget en champs sans séparateur ni `€` en édition | assumé | lot 9 n° 3 |
| Chips de thèmes en grille adaptative | assumé | lot 9 n° 6 |
| La colonne principale n'est pas atténuée à 55 % | écart (c) n° 10 | §4.3 le demande |
| Encart `Suggestions de l'assistant` absent | non vérifiable | aucun endpoint IA configuré dans le home jetable |

### 4a — Sélecteur de source (`4a-capture-selecteur.png`) — **vu pour la première fois**

| Zone | Verdict | Cause |
|---|---|---|
| Popover, en-tête `QUE CAPTURER ?` + `⌘⇧S` | conforme | 372 px là où §5.1 dit 346 |
| Trois sources, vignette 44 × 30, libellé, sous-titre d'état, point `ok` si active | conforme | — |
| **`Microsoft Teams — Fenêtre ouverte · aucune réunion active`** | conforme | vérifié avec Teams ouvert, sans réunion |
| `Zoom — Aucune réunion active`, `Écran entier — Ou une zone à la souris` | conforme | — |
| Bascule `Capturer à chaque changement de partage` activée | conforme | — |
| Explication de l'indisponibilité (« Choisissez d'abord une source… ») | conforme | §5.1 |
| Bascule `Toutes les 2 minutes` désactivée | conforme | — |
| Mention de confiance | conforme | — |
| `Capturer maintenant`, bouton primaire | conforme | — |
| Bande de captures en pied de colonne, marqueurs carrés sur la frise, légende `■ = capture` | conforme | — |
| Une infobulle `.help()` s'était glissée dans la première capture | incident d'outillage | pointeur posé sur le popover ; repris après déplacement du curseur |

### 4b — Pastille flottante (`4b-pastille-flottante.png`) — **vue pour la première fois**

| Zone | Verdict | Cause |
|---|---|---|
| Fenêtre flottante ~300 × 40, rayon 22, fond sombre, ombre portée | conforme | — |
| Contenu : point, temps mono, séparateur, `◫ Capturer` plein, `✎ Note`, compteur | conforme | — |
| Apparaît **automatiquement** en mode séance (`sessionPillMode = .sessionOnly`) | conforme | `shouldPresentPill` vérifié à l'écran |
| Disparaît à la sortie du mode séance | conforme | — |
| `panel.level = .floating`, donc au-dessus de Teams | conforme par lecture | non vérifiable sans une réunion Teams réelle |
| Point d'enregistrement gris, temps `--:--` | assumé (données) | aucun enregistrement ne tourne |
| Mini-panneau de confirmation après capture | non vérifié | demande une capture réelle (autorisation « Enregistrement de l'écran » non héritée par un bundle ad hoc) |

### 5a — 1:1 subi, séance (`5a-1to1-collaborateur-seance.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Pilule `Je suis le collaborateur` dans la barre | conforme | §6.1, obligatoire |
| `CE QUE JE VEUX DIRE` : items numérotés, poignée `⠿`, mention « Visible de vous seul… » | conforme | — |
| `MES DEMANDES EN COURS` : statut coloré + historique court | conforme | — |
| Notes en deux sections `CE QU'IL M'A DIT` / `CE QUE J'AI DIT` | conforme | — |
| **Chaque ligne de notes est un bloc `● POUR MOI SEUL`** | écart (c) n° 12 | le défaut `private` du côté collaborateur s'applique à tout le semis ; la colonne devient une pile de blocs encadrés là où la maquette n'en isole qu'un |
| `CE QUE J'AI LIVRÉ` : généré, `Citer` par ligne, action bloquée en `warn` | conforme | — |
| `CE QU'IL M'A PROMIS` : tri par retard, barre gauche `report`, `Promise le …`, `n reports`, `Relancer` | conforme | — |
| `EN SORTANT` : récap, dossier annuel, compte des lignes privées | conforme | — |
| **Le rail de droite débordait hors du cadre** | **corrigé (a)** | même cause que 2a |
| `Samedi` au lieu de `Vendredi` | assumé | listé |
| La pilule `● privé` est en tête de **section** et non de chaque carte | écart (c) n° 12 | §6.2 la veut par carte |
| Un titre de réunion apparaît dans `CE QUE J'AI LIVRÉ` | écart (c) n° 12 | le générateur y verse les réunions autant que les actions |

### 5b — 1:1 subi, préparation (`5b-1to1-collaborateur-preparation.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Carte étroite centrée, en-tête violet, pilule `Collaborateur` | conforme | — |
| `RESTÉ SANS RÉPONSE` : cases, ancienneté | conforme | — |
| `CE QUE J'AI LIVRÉ DEPUIS` : `✓` et `◐` avec cause | conforme | — |
| `CE QUE JE VEUX OBTENIR` : cases cochées + `Ajouter…` | conforme | — |
| `Partager les sujets à Yann`, mention de provenance | conforme | — |
| **Bouton primaire illisible dans son état accompli** | **corrigé (a)** | blanc sur violet à 55 % d'opacité → `oneonone/bg` + `oneonone/ink` |
| Libellé `Ordre du jour prêt · 2 sujets` au lieu de `En faire mon ordre du jour` | conforme (état atteint) | l'ordre du jour est déjà versé par le semis |
| Mention de provenance en `ink/muted` sous 11,5 px | **corrigé (a)** | passe en `ink/4` |

### 6a — Atelier, planche plein cadre (`6a-atelier-planche.png`)

| Zone | Verdict | Cause |
|---|---|---|
| Badge `ATELIER` teal, pilule `● Local · hors ligne` | conforme | et **non tronqué à 1 280 px** |
| Barre d'outils : modes, cinq couleurs (anneau sur l'active), trois épaisseurs, `Planche n sur m · dernière modif.`, `Exporter PNG / SVG` | conforme | — |
| Palette verticale 52 px, neuf outils, `↺ ↻` en pied | conforme | — |
| Toile `#fdfcfa` à points de 18 px, planche rendue | conforme | le correctif du lot 16 (chargement différé) tient |
| Dock 314 px, onglets **`Planches 4 / Captures 1 / Pièces 1`** | conforme | l'exigence « dock avec les onglets Captures/Pièces » est tenue |
| Vignette active bordée teal sur `#f2f8f7`, `＋ Planche` teal + `Dupliquer` | conforme | — |
| **Les deux boutons collaient la liste tronquée** | **corrigé (a)** | 10 px de respiration au-dessus |
| `SUR CETTE PLANCHE` : invite non vide | conforme | « aucune zone vide sans invite » |
| `PIÈCES & CAPTURES`, zone de dépôt, barre assistant | conforme | — |
| Zone de dépôt en `ink/muted` sous 11,5 px | **corrigé (a)** | passe en `ink/4` |
| Pilule de présence absente | conforme | D11 : mono-utilisateur |
| La planche ouverte est la **première**, la maquette montre la troisième | assumé (semis) | — |

### 6b — Atelier, planche de séance (`6b-atelier-planche-de-seance.png`)

| Zone | Verdict | Cause |
|---|---|---|
| En-tête `ATELIER` + `4 sept. · 1 h 02 · 4 participants · 6 éléments produits` + `Tout exporter` | conforme | — |
| Liste chronologique : colonne timecode, carte par élément, pied type / titre / auteur | conforme | — |
| Barre d'espaces masquée en Relire | conforme | `MeetingSpacesBar.estMasquee` |
| **Les aperçus sont vides** : cadre + nom du mode, aucune image | écart (c) n° 13 | `Board.thumbPng` n'est pas régénéré par le semis ; `6a` rend la scène par son moteur, `6b` attend une vignette |
| Encart de clôture (`Joindre au rapport`) sous la ligne de flottaison | observation | la liste défile |

---

## Corrections de finition livrées (a)

| # | Écran(s) | Fichier | Correction |
|---|---|---|---|
| 1 | 1a, 1c, 3a, 3b | `Spaces/Rail/ActionCard.swift` | la pilule de source (`04:12 ↗`) prend `lineLimit(1)` + `fixedSize`. Elle se repliait caractère par caractère — rendue en filet vertical de 14 px, creusant la carte d'un vide de 80 px — puis en deux lignes sur la carte suivante. Même défaut que les primitives `Chip` / `InvitePill` / `Pill` corrigées à la recette des vagues 1-4 ; celle-ci, construite sur place, leur avait échappé |
| 2 | 2a, 5a | `OneOnOne/Manager/ManagerSessionView.swift`, `OneOnOne/Collaborator/CollaboratorSessionView.swift` | le rembourrage de la colonne centrale passe **avant** son cadrage. Posé après, il s'ajoutait à la largeur : la colonne mesurait 24 px de trop et poussait le rail de droite hors du cadre — cartes d'engagement, `2× reporté` et `Envoyer le récap` coupés net |
| 3 | 2a | `Spaces/Notes/TimedNotesColumn+OneOnOne.swift`, `OneOnOne/Manager/ManagerNotesColumn.swift` | `① COMMENT ÇA VA` n'est plus rendu deux fois : `OneOnOneNotesSection` gagne `montreLeLibelle`, faux pour la section que `MoodScale` titre déjà |
| 4 | 6a | `Workshop/WorkshopDock.swift` | 10 px au-dessus de `＋ Planche` / `Dupliquer`. La liste des planches est bornée à 260 px et se coupe au milieu d'une vignette ; collés à cette coupe, les boutons se lisaient comme s'ils recouvraient la carte |
| 5 | 2a, 2b, 5a, 5b, 6a, 6b | `Meeting/MeetingTopChromeBar.swift` | le bouton `Rapport` indisponible change de registre au lieu de s'éclaircir : `report/bg` + `report/ink` (≈ 6:1) au lieu de blanc sur `report` à 45 % d'opacité (< 2:1) |
| 6 | 5b | `OneOnOne/CollaboratorPrep/CollaboratorPrepView.swift` | même remède pour le bouton primaire dans son état accompli : `oneonone/bg` + `oneonone/ink` |
| 7 | 1a, 3a, 3b, 4a | `DesignSystem/Components/Refonte/AvatarStack.swift` | les initiales se centrent dans la **partie visible** de la pastille. La géométrie de §1.2 (19 px, chevauchement −6) est inchangée ; c'est le glyphe qui se recentre — on lisait « C̸A CF LC LS NL PY » là où le semis dit « CA CP LD LS NL PY » |
| 8 | 3a, 5a, 5b, 6a | six fichiers de vue | six libellés de 11 px passent de `ink/muted` à `ink/4` : §1.2 réserve `ink/muted` aux placeholders de 11,5 px et plus, et exige 4,5:1 sous 12 px |

Aucune couleur hors `One2OneToken`, aucune fonte hors `Font.plexSans` / `.plexMono`, aucun
service ni modèle touché, `MeetingView.swift` intact, aucun comportement testé modifié.

**Une correction tentée et retirée** : le recouvrement des décisions en mode séance (écart (c)
n° 4). Deux remèdes essayés — `fixedSize(vertical:)` sur le bloc, puis un `Text` concaténé
comme dans la branche claire — n'ont rien changé : la rangée ne lit pas la hauteur du second
enfant, et la cause n'est ni dans le bloc ni dans son conteneur. Les deux essais ont été
**annulés** plutôt que laissés dans la branche.

---

## Écarts assumés confirmés (21)

Tous relevés sur les captures et **non touchés** : pile d'avatars triée par nom et initiales
`PY` (lot 1 n° 2 et 3) ; chips `/…` alignées à droite (lot 2 n° 2) ; `À ASSIGNER — 9` et
`EN ATTENTE 9` au lieu de 3 (lot 4) ; bouton `Capture` dans la barre du haut, y compris en 1:1
(lot 1 n° 5, lot 11 n° 5) ; `Notes 6` au lieu de 5, `Documents 5` au lieu de `Documents ＋`,
compléments de `Synthèse` et `Assistant`, sélecteur de mode conservé dans le poste de
pilotage, titres du bloc `ALERTES` (lot 5 n° 1, 2, 3, 6, 7) ; barre du haut affichée en mode
Relire (décision D0) ; `4 séance` comptant le lien (lot 6 n° 4) ; barre de budget verte à
65,6 %, budget en champs inline, chevrons de réordonnancement des jalons, chips de thèmes en
grille adaptative (lot 9 n° 1, 3, 4, 6) ; teinte neutre d'un risque faible et rond ambre du
risque sur la frise (lot 2 n° 5, table du lot 19c) ; `Samedi` au lieu de `Vendredi` et
`1 janv.` au lieu de `Janvier` (lot 13) ; taux `73 %` (lot 12) ; objectif à 10 % en `warn` là
où la maquette met du violet (règle §3.4 contre maquette) ; transcription et locuteur courant
sans nom, planche ouverte au premier rang (semis) ; `100 %` avec espace insécable.

---

## Écarts fonctionnels restants (c), avec recommandation

| # | Écart | Recommandation |
|---|---|---|
| 1 | Les menus de type et de modèle rendent leur chevron **à gauche** du libellé (`⌄ Projet`) | AppKit place l'indicateur d'un `Menu` avant son label. Reproduire l'ordre de la maquette demande de rendre le chevron soi-même dans le label et de masquer l'indicateur — c'est déjà ce que fait le menu de statut de la fiche projet. À généraliser, ou à assumer |
| 2 | La pile d'avatars est monochrome | La maquette colore chaque pastille. `Participant.avatarColor` existe dans le modèle de §1.3 mais n'est pas alimenté. Choisir une rotation de teintes **dans** `One2OneToken` est une décision de charte : à trancher avant de coder |
| 3 | La bascule `Speakers` ne s'affiche jamais | Elle est **correcte** : `showsSpeakerToggle: settings.transcriptionMode == .diarizeFirst`, figé par un test de lecture des sources. Le défaut est dans le semis, qui laisse le mode par défaut `transcriptionOnly` et ne pose aucun locuteur. Une seule décision de semis règle les deux : poser `transcriptionMode = .diarizeFirst` et des locuteurs sur les quatre segments de `RefonteDemoSeed` |
| 4 | **En mode séance, le corps d'une décision recouvre la note suivante** — texte illisible | Le plus grave des onze : il touche l'écran que le correctif #42 vient de rendre atteignable. La rangée est un `HStack(alignment: .firstTextBaseline)` qui porte une barre de 2 px en `maxHeight: .infinity` ; la piste à creuser est l'interaction de cette barre sans ligne de base avec un enfant de deux lignes. Un lot dédié, avec reproduction hors application comme pour le correctif #42 |
| 5 | Boutons désactivés peu lisibles au-delà du bouton `Rapport` (`Exporter ⌄` en 1c, `Enregistrer` de la fiche en édition, `Partager la ligne` en 5a) | Le remède appliqué au bouton `Rapport` (changer de registre plutôt que d'éclaircir) est généralisable en un style partagé. Une passe de contraste sur les états désactivés |
| 6 | `À NE PAS OUBLIER` produit des phrases agrammaticales (« Vous lui devez Retour sur la grille d'astreinte ») et n'émet que deux des trois règles | `ReminderRules` concatène un préfixe et un titre d'engagement. C'est une fonction pure testée : la corriger demande de revoir ses gabarits et ses tests. Lot dédié |
| 7 | Les chips de la bande `ÉPINGLÉ DANS LA SÉANCE` affichent des noms de fichier bruts (`slide-0001-091912`) | Une capture doit se nommer par son timecode ou sa première ligne d'OCR, jamais par le nom que le détecteur de diapositives lui a donné |
| 8 | **Trois codes de recette sur douze n'ouvrent pas l'écran qu'ils nomment** : `3a` (tiroir), `3b` (fiche projet), `4a` (sélecteur) rendent le cockpit nu | `RecetteScreen` choisit la réunion et le mode, rien de plus. Lui faire porter aussi l'état d'écran (`resources.isDrawerOpen`, `showProjectCard`, ouverture du sélecteur) touche `MeetingScreenModel` et la table testée : c'est un petit lot, pas une finition. En attendant, la séquence manuelle est en fin de fichier |
| 9 | À 1 280 px avec un document présenté, la carte notes ↔ transcription s'effondre et ses libellés recouvrent la frise | Borner la hauteur de la scène d'aperçu (`maxHeight`) pour que la carte notes garde un minimum, ou rendre la colonne principale défilante. À 1 728 px le défaut n'apparaît pas |
| 10 | Fiche projet en édition : point de statut noir, cellules coupées sans marque, colonne principale non atténuée | Le point noir vient du rendu *template* qu'AppKit applique à un `Image(systemName:)` dans un label de `Menu`. Le corriger demande une image non-template — donc de changer le mécanisme que `Tests/RefonteFinitionsTests.swift` fige explicitement. **Décision demandée** : autoriser la modification de ce test, ou assumer le point noir |
| 11 | L'outillage de recette ment sur deux points, et l'un l'a rendue inutilisable pendant vingt minutes | **(a)** `--reset` ne réinitialise **pas** les réglages : les `UserDefaults` d'un bundle atterrissent dans `~/Library/Preferences/com.onetoone.app.recette.plist`, hors du home jetable — `cfprefsd` n'honore pas `CFFIXED_USER_HOME`. L'en-tête de `recette-run.sh` affirme le contraire. **(b)** Tuer une instance par `kill -9` rend le lancement **suivant** inutilisable : macOS le traite comme une reprise après plantage, rouvre la fenêtre de réunion **sans** le jeton de recette, et l'écran reste sur son indicateur d'attente. Il faut un `terminate()` par pid. À écrire dans `recette-run.sh` (un `--quit <pid>`) et dans les cinq pièges de `CLAUDE.md`. **(c)** Le poste a un second écran de 1 920 × 1 080 : « 1 728 est le maximum » est faux depuis qu'il est branché |
| 12 | 1:1 subi : toutes les lignes de notes sont des blocs privés encadrés, la pilule `● privé` est en tête de section et non de carte, et un titre de réunion se glisse dans `CE QUE J'AI LIVRÉ` | Les trois sont des questions de semis et de rendu de §6.2. Le semis devrait marquer `shared` ce que le manager a dit et n'isoler qu'une ligne, comme la maquette |
| 13 | Planche de séance (6b) : les aperçus sont vides | `Board.thumbPng` n'est pas régénéré par le semis. Soit le semis rend les vignettes, soit `6b` rend la scène par le moteur comme `6a` le fait |

---

## Incidents de la passe

1. **Un item de menu pressé par erreur.** La recherche d'élément par motif *approchant* a
   pressé « Coller dans les ressources » au lieu de « Ressources… » — le premier élément dont
   un libellé *contenait* « ressources ». Le presse-papiers de la session a donc été collé
   dans les ressources de la réunion de recette, dans le **store jetable**, effacé au
   `--reset` suivant. Aucune donnée n'est sortie de la machine. L'outil presse désormais
   l'élément dont le libellé est **exactement** celui demandé, et ne retombe sur l'approchant
   qu'à défaut.
2. **Un item de menu sans effet.** `MeetingCommands` prend ses actions dans une
   `focusedValue`, nulle quand la fenêtre de réunion n'est pas la fenêtre clé : trois appuis
   sur « Ressources… » n'ont rien fait avant qu'on active la fenêtre au préalable.
3. **Une infobulle dans une capture.** Le pointeur, posé sur le popover de `4a`, y a ouvert
   son infobulle `.help()`. Capture reprise après avoir déplacé le curseur **dans la fenêtre
   de recette, sur l'écran externe**.

---

## Procédure exacte, pour refaire cette passe

```bash
swift build -c release
Scripts/recette-app.sh /tmp/recette-finale          # vérifie la fraîcheur, affiche le md5

# Les dix écrans directs, aux deux largeurs
for c in 1a 1c 2a 2b 5a 5b 6a 6b; do
  Scripts/recette-run.sh --app /tmp/recette-finale/OneToOne.app --screen "$c" --reset
  # attendre que la fenêtre porte le TITRE de la réunion (et non « OneToOne ») :
  # tant qu'elle s'appelle « OneToOne », le jeton n'a pas résolu la réunion
  # redimensionner par AX (pid), capturer par `screencapture -l <numéro>`
  # puis **terminate()** par pid — jamais kill -9
done
```

Les trois écrans dont le code n'ouvre pas la surface :

- **`3a`** — `--screen 3a`, puis *dans cet ordre* : presser `Présenter` sur la carte
  `Chiffrage_Marine_v3.xlsx` (le **plus proche verticalement** du nom : les quatre vignettes
  ont chacune son bouton), **puis** l'item de menu `Ressources…`. Présenter referme le tiroir,
  donc l'inverse ne marche pas.
- **`3b`** — `--screen 3b`, puis presser le segment `S/D — Modernisation CI/CD` du fil
  d'Ariane. Pour `3b-edition`, presser ensuite `Édition`.
- **`4a`** — `--screen 4a`, puis presser la pilule `Capture 3`. Un popover est une **fenêtre à
  part** : `screencapture -l` de la fenêtre de réunion ne le montre pas, il faut une capture de
  **région** (`-R x,y,w,h`). Déplacer le pointeur hors du popover d'abord.

Et les deux du mode séance :

- **`1b` et `4b`** — `--screen 1b`, puis l'item de menu `Mode séance plein écran`. La fenêtre
  de réunion passe en plein écran sur l'écran où elle se trouve ; la pastille apparaît **seule**
  dans une fenêtre de couche > 0, à capturer par son numéro. `Esc` sort des deux.
