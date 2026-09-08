# One2One — spécifications de refonte

**Version 1 — 6 septembre 2026 · interne**
Réf. maquettes : `One2One Réunion.dc.html` — turns 1 à 6.

Document d'implémentation des six chantiers validés en maquette : structure de l'écran de réunion, type 1:1 manager, ressources et fiche projet, captures Teams/Zoom, 1:1 collaborateur, type atelier. Chaque chantier est spécifié pour être codé sans revenir à la maquette : dimensions, états, règles métier, modèle de données, critères d'acceptation.

---

## 1. Cadre commun

### 1.1 Principes de structure

- **Trois espaces, pas sept onglets.** `Réunion` (préparation + séance + relecture), `Rapport`, `Ressources`. Les anciens onglets Notes live, Transcription, Documents, Chat deviennent des zones ou des surfaces à l'intérieur de ces trois espaces.
- **Aucun onglet vide.** Toute entrée de navigation porte un compteur ou un état (`0 doc`, `12`, `✓`). Un espace sans contenu affiche une zone de dépôt active, jamais un écran vide.
- **Un sous-mode temporel** dans la barre d'onglets : `Préparer` / `En séance` / `Relire`. Il ne change pas la navigation, il change la disposition par défaut et le focus clavier.
- **L'audio est l'axe commun.** Note, transcription, capture, planche et action portent un `t` en secondes depuis le début de l'enregistrement. Tout élément horodaté est cliquable et déplace la tête de lecture.
- **Le rail de droite est permanent** (actions / risques / historique) sur les types multi-participants ; il est remplacé par les colonnes de réciprocité sur les types 1:1 et par le dock de planches sur l'atelier.
- **L'assistant est une surface, pas un onglet** : barre d'invocation persistante + `⌘K` partout.

### 1.2 Jetons visuels

Valeurs exactes utilisées dans les maquettes. À reprendre telles quelles ; aucune autre couleur ne doit être introduite.

| Jeton | Valeur | Emploi |
| --- | --- | --- |
| `bg/app` | `#f7f4ee` | Barre du haut, barre d'onglets |
| `bg/canvas` | `#faf8f4` | Fond de la zone de travail |
| `surface` | `#ffffff` | Cartes, rails, panneaux |
| `surface/alt` | `#fdfcfa` | Ligne de tableau alternée, sous-zones |
| `border/hair` | `rgba(0,0,0,.07)` | Séparateurs internes d'une carte |
| `border/card` | `rgba(0,0,0,.09)` | Contour de carte |
| `border/strong` | `rgba(0,0,0,.14)` | Bouton secondaire, champ |
| `ink/1 … ink/4` | `#1a1a1a` · `#2a2723` · `#4a453d` · `#6b6659` | Titre · corps · corps secondaire · libellé mono |
| `ink/muted` | `#7d7768` | Placeholder, métadonnée (jamais sous 11 px) |
| `accent/action` | `#2563d9` · bg `#eef2fd` · bg2 `#f7faff` · ink `#1b4dad` | Actions, liens, sélection, partage actif |
| `accent/report` | `#b8544c` · bg `#fbeceb` · ink `#8f3f38` | Rapport, décisions, retards, risques critiques |
| `accent/ok` | `#2f9e5f` · `#2f7d4e` · bg `#e8f3ec` | Tenu, assigné, capture active |
| `accent/warn` | `#d98324` · ink `#8a5a12` · bg `#f9efe0` | À surveiller, sans réponse, en cours |
| `accent/oneonone` | `#6b4d8f` · ink `#5c4180` · bg `#f4f1f6` | Type 1:1 : badge, confidentialité, sections de notes |
| `accent/workshop` | `#1f6b6b` · bg `#f2f8f7` | Type atelier : badge, planches, dock |
| `dark/*` (mode séance) | `#1c1a17` · `#191714` · `#221f1b` · `#232019` · `#2f2b26` | Fond · colonne transcription · carte · carte active · pilule |
| `dark/ink` | `#f2efe9` · `#e6e1d8` · `#c9c3b8` · `#9a9285` | Titre · corps · secondaire · libellé mono |
| `dark/accent` | `#9ab6f0` · `#e8b0aa` · `#e8c48a` | Action · décision · risque, sur fond sombre |

#### Typographie

| Rôle | Fonte / graisse / taille | Règle |
| --- | --- | --- |
| Titre de réunion | Plex Sans 600 · 13 → 14 px | Une ligne, ellipsis, jamais de retour |
| Titre de carte | Plex Sans 600 · 11,5 → 12 px | — |
| Libellé de section | Plex Mono 600 · 9,5 px · `letter-spacing .07em` · majuscules | Couleur `ink/4` minimum — jamais `ink/muted` |
| Corps | Plex Sans 400 · 12 → 12,5 px · `line-height 1.55` | Notes et transcription en 12,5 |
| Pilule / chip | Plex Sans 500 · 10 → 10,5 px | Rayon 11 px, padding 2–3 × 7–8 px |
| Timecode | Plex Mono 500 · 10 px | Toujours `mm:ss`, largeur fixe |

#### Géométrie

- Rayons : 4 (aperçu document) · 5–6 (bouton, chip carré) · 7–8 (carte) · 10 (panneau flottant) · 11 (pilule) · 16 (bloc audio).
- Densité : padding de carte 9–13 px ; `gap` vertical entre cartes 11–13 px ; hauteur de ligne de tableau 8 px de padding vertical.
- Largeurs fixes : rail actions **330 px** · rail 1:1 **320/356 px** · nav latérale **190 px** · palette outils **52 px** · colonne temps **78 px** · panneau fiche projet **430 px** · tiroir ressources **396 px** · colonne transcription (mode séance) **400 px**.
- Le reste est fluide : `grid-template-columns: 1fr <fixe>`, `min-width:0` obligatoire sur la colonne fluide pour que l'ellipsis fonctionne.
- Contraste : tout texte sous 12 px doit atteindre 4,5:1 — d'où `ink/4` pour les libellés mono et `ink/muted` réservé aux placeholders de 11,5 px et plus.

### 1.3 Modèle de données

Une réunion est un document autonome ; tout ce qui est produit en séance y est stocké (voir §8).

```ts
type MeetingType =
  | 'global' | 'project' | 'one_to_one' | 'architecture'
  | 'manager_1_1' | 'note' | 'workshop';

interface Meeting {
  id: string;
  title: string;
  ref: string;                 // "P25_110"
  type: MeetingType;
  projectId?: string;
  startedAt: string;           // ISO
  durationSec: number;
  participants: Participant[];
  templateId: string;          // template de rapport
  mode: 'prepare' | 'live' | 'review';
}

interface Participant {
  id: string;
  displayName: string;
  initials: string;
  role: string;                // Calendrier, Architecte, Ad-hoc…
  attendance: 'present' | 'declined' | 'absent';
  isSpeaker: boolean;
  avatarColor: string;
}

interface Note {
  id: string;
  meetingId: string;
  t: number;                   // secondes
  text: string;                // markdown restreint
  kind: 'note' | 'decision' | 'risk' | 'feedback'
      | 'promise' | 'request' | 'proof';
  visibility: 'private' | 'shared' | 'escalated';
  authorId: string;
  links: Ref[];
}

interface TranscriptSegment {
  id: string;
  t: number; tEnd: number;
  speakerId?: string;
  text: string;
  engine: 'cohere-mlx';
  confidence: number;
}

interface Action {
  id: string;
  meetingId: string;
  projectId?: string;
  title: string;
  ownerId: string | null;
  dueAt: string | null;
  effortMin: number | null;
  priority: 'normal' | 'urgent';
  status: 'open' | 'done' | 'dropped';
  sourceRef: Ref;              // { kind, id, t }
  carriedFromMeetingId?: string;
  deferralCount: number;
}

interface Ref {
  kind: 'transcript' | 'note' | 'capture' | 'board';
  id: string;
  t?: number;
}

interface Attachment {
  id: string;
  meetingId: string;
  scope: 'meeting' | 'project';
  kind: 'file' | 'link' | 'capture';
  mime: string;
  fileName: string;
  bytes: number;
  addedBy: string;
  addedAt: string;
  pinnedAtT?: number;
  extractedText?: string;
  presentState: 'idle' | 'onScreen';
  citations: number;
}

interface Capture extends Attachment {
  source: 'teams' | 'zoom' | 'screen' | 'region';
  trigger: 'manual' | 'share_change' | 'interval';
  t: number;
  ocrText: string;
  thumbUrl: string;
}

interface Board {
  id: string;
  meetingId: string;
  index: number;
  title: string;
  mode: 'sketch' | 'diagram' | 'ink';
  t: number;                   // timecode de création
  authorIds: string[];
  scene: unknown;              // JSON du moteur
  thumbPng: Blob;              // local
  updatedAt: string;
}

interface ProjectCard {
  projectId: string;
  status: 'ok' | 'watch' | 'risk';
  budgetSpent: number;
  budgetTotal: number;
  scopeText: string;
  tags: string[];
  milestones: { label: string; dueAt: string | null; state: string }[];
  risks: { label: string; level: 'high' | 'medium' | 'low' }[];
  contacts: { name: string; role: string }[];
  updatedAt: string;
  updatedBy: string;
}

interface OneOnOneThread {
  id: string;
  managerId: string;
  collaboratorId: string;
  myRole: 'manager' | 'collaborator';
  cadenceDays: number;
  meetings: string[];
  agenda: AgendaItem[];
  commitments: Commitment[];
  moodHistory: { meetingId: string; value: 1|2|3|4|5 }[];
  objectives: { label: string; progress: number }[];
  recurringTopics: { label: string; count: number }[];
}

interface Commitment {
  id: string;
  threadId: string;
  text: string;
  ownerSide: 'manager' | 'collaborator';
  dueAt: string | null;
  state: 'open' | 'kept' | 'missed';
  promisedAt: string;
  deferralCount: number;
  visibility: 'private' | 'shared' | 'escalated';
}

interface AgendaItem {
  id: string;
  text: string;
  addedBySide: 'manager' | 'collaborator';
  order: number;
  state: 'todo' | 'done' | 'deferred';
  visibility: 'private' | 'shared';
}
```

### 1.4 Raccourcis clavier (globaux)

| Raccourci | Effet |
| --- | --- |
| `⌘K` | Assistant — ouvre la barre d'invocation, contexte = réunion courante |
| `⌘M` | Marqueur sur l'axe temps à l'instant courant |
| `⌘⇧A` | Créer une action depuis la sélection (transcription, note, capture, planche) |
| `⌘⇧S` | Capture d'écran de la source configurée |
| `⌘⇧N` | Nouvelle ligne de note au timecode courant (depuis la pastille flottante aussi) |
| `⌘⇧V` | Coller un lien ou une image dans les ressources |
| `⌘⏎` | Valider le composeur (action, engagement, sujet d'ordre du jour) |
| `/` en début de ligne | Palette de commandes de note : `/action` `/décision` `/risque` `/citer` `/privé` `/engagement` `/feedback` `/promesse` `/demande` `/preuve` |

---

## 2. Chantier 1 — Structure de l'écran de réunion

**Réf. maquette :** options `1a` (cockpit, retenue comme base), `1b` (mode séance sombre), `1c` (poste de pilotage).

### 2.1 Barre du haut — une seule ligne

Hauteur 38 px, fond `bg/app`, bordure basse `border/card`, padding 9 × 14. Ordre et comportement de gauche à droite :

| Bloc | Largeur | Comportement |
| --- | --- | --- |
| Bouton panneau + fil d'Ariane | auto, `white-space:nowrap` | Segments : app › projet › (réunion). Le segment projet ouvre la fiche projet (chantier 3). |
| Titre de réunion | `flex:1; min-width:0` | Ellipsis. Éditable en place au double-clic. La référence `[P25_110]` reste dans le titre. |
| Bloc audio | auto, pilule 16 px, fond `ink/1` | `▶ mm:ss / mm:ss` + marqueur + édition. Clic sur le temps = saisie directe d'un timecode. |
| Type de réunion | auto | Menu (Globale, Projet, One-to-One, Architecture, 1:1 Manager, Note, Atelier). Changer le type recharge la disposition de l'espace Réunion, jamais le contenu. |
| Template de rapport | auto | Menu inchangé (Auto selon type, COPIL, 1:1 …). |
| Rapport | auto | `accent/report` plein. Libellé `Rapport ✓ (m:ss)` : coche = généré, durée = temps de génération. |
| `⋯` | 28 px | Exporter, Détails, Importer, Audio, Supprimer (inchangé). |

La deuxième ligne actuelle (breadcrumb dupliqué + bouton `+`) est supprimée : le `+` devient une entrée du menu de type.

### 2.2 Barre d'espaces

Hauteur 34 px. À gauche les trois espaces (onglet actif : soulignement 2 px `accent/report`). À droite le sélecteur de mode (`Préparer` / `En séance` / `Relire`, segmenté, actif en `ink/1` plein) puis la date.

| Mode | Disposition par défaut | Focus clavier |
| --- | --- | --- |
| Préparer | Actions ouvertes reportées + derniers points + alertes en colonne principale ; rail réduit | Composeur de sujet |
| En séance | Notes ↔ transcription à parts égales, KPI condensés en bandeau | Éditeur de notes |
| Relire | Résumé + décisions + tableau d'actions ; transcription repliée | Champ d'assignation de la première action non assignée |

### 2.3 Bandeau d'indicateurs (4 cartes égales)

Grille `repeat(4,1fr)`, `gap 10`, carte 10 × 12 px. Chaque carte : libellé mono, valeur 20 px/600, complément, puis une micro-visualisation.

- **Présence** — `présents/total` en %, pile d'avatars 19 px chevauchés de −6 px, max 6 puis `+n`. Clic = gestion des participants.
- **Actions** — total, nombre non assignées en `accent/report`, barre de progression (part `done` en `accent/ok`).
- **Décisions** — nombre + première décision en ellipsis. Clic = filtre les notes sur `kind:'decision'`.
- **Risques** — nombre + nombre critiques, points colorés par niveau (max 8 puis `+n`).

Un compteur à 0 reste affiché avec une invite (« Aucune décision — `/décision` dans les notes »), jamais une carte vide.

### 2.4 Notes ↔ transcription

Une seule carte, `grid-template-columns: 1fr 1px 1fr`. En-tête : titre, mention « synchronisées sur l'audio », bascule `Speakers`, bouton `Résumer`.

- **Colonne notes** — lignes `timecode | texte`, timecode en `accent/action`, cliquable. Une note `decision` porte une barre gauche 2 px `accent/report` ; `risk` en `accent/warn`. Composeur en bas avec les commandes `/` visibles en permanence (pas de découverte cachée).
- **Colonne transcription** — fond `surface/alt`, segments `timecode | Locuteur — texte`. Au survol, le segment prend le fond `accent/action bg` et révèle une rangée d'actions : `＋ Action` (plein), `Décision`, `Citer dans la note`. `⌘⇧A` agit sur le segment survolé ou la sélection de texte.
- **Création depuis une phrase** : ouvre le composeur d'action prérempli — `title` = phrase nettoyée (verbe à l'infinitif si détecté), `sourceRef` = `{kind:'transcript', id, t}`, `owner` = locuteur du segment si connu, sinon `null`. L'action apparaît immédiatement en tête du rail avec une animation de 150 ms.
- **Frise audio** en pied de carte (hauteur 22 px) : onde échantillonnée, tête de lecture 2 px `accent/action`, marqueurs ronds (note), carrés (capture, chantier 4), losanges (décision). Clic = déplacement, glisser = balayage.
- **Défilement lié** : bascule `Suivre` ; si active, la transcription suit la tête de lecture. Toute interaction manuelle la désactive et affiche `Reprendre le suivi`.

### 2.5 Rail d'actions (330 px, permanent)

- Trois onglets : `Actions n` / `Risques n` / `Historique`. Vues d'actions : **Liste** · **Calendrier** · **Eisenhower** (Kanban et Post-it supprimés du contexte réunion).
- Groupes ordonnés : `À ASSIGNER` (barre gauche `accent/report`) → `MES ACTIONS` → `REPORTÉES DU <date>` (compact, une ligne par action).
- Carte d'action : titre 11,5 px sur 2 lignes max, puis pilules d'édition rapide. Une pilule vide est une **invite** en `accent/action` (`＋ assigner`, `＋ échéance`) ; renseignée elle passe en `accent/ok` ou neutre. Un clic ouvre un sélecteur inline (pas de modale) ; `Tab` passe au champ suivant.
- Suggestion de responsable : locuteur de la phrase source, puis dernier porteur d'une action de même préfixe de titre, puis participant unique restant.
- Composeur en pied, toujours visible : champ + pilules par défaut (`Moi`, `Demain`, `!`, durée). `⌘⏎` crée et vide le champ sans perdre le focus.

### 2.6 Mode séance plein écran (option 1b)

- Palette sombre `dark/*`. Grille `78px | 1fr | 400px`. Aucun chrome hors la barre d'état (point d'enregistrement, titre, temps, avatars, locuteur courant, `Clore la séance`).
- **Colonne temps** : axe vertical 3 px, portion écoulée `#e04b3f` ; marqueurs — rond `dark/accent action` pour une note, carré 3 px de rayon `accent/report` pour une décision, trait plein `dark/ink` pour la position courante. Libellé mono à gauche, aligné à 30 px du rail.
- Bandeau bas « `EN ATTENTE — n actions sans responsable` » + `Assigner maintenant` : ouvre une file d'assignation en 3 clics (responsable → échéance → suivante).
- Panneau assistant en bas de colonne droite : question, réponse, puces de sources horodatées cliquables.
- Sortie du mode : `Esc` demande confirmation si l'enregistrement tourne.

### 2.7 Poste de pilotage (option 1c)

- Nav latérale 190 px, entrées `Synthèse · Notes n · Transcription mm′ · Actions n · Rapport ✓ · Documents ＋ · Assistant` ; l'entrée active est une carte blanche avec ombre 1 px. Bloc projet et bloc `ALERTES` en pied.
- Colonne principale : en-tête de réunion (titre + métadonnées sur une ligne : `ref · type · date · durée · n participants`), carte `EN UNE PHRASE` (résumé généré + tags de sujets), carte `DÉCISIONS PRISES`, puis tableau d'actions.
- **Tableau d'actions** — colonnes `20px | 1fr | 108 | 92 | 62 | 76 | 30` : état, intitulé, responsable, échéance, charge, source (`mm:ss ↗`), menu. Édition inline sur chaque cellule ; `↑↓` navigue, `Espace` coche, `⌥↑↓` réordonne. Pied : composeur + `n autres · tout afficher`.
- Frise audio en pied d'écran, pleine largeur, avec étiquettes de marqueurs (`04:12`, `DÉCISION`) et bouton `✂ Éditer` qui ouvre la modale d'édition audio existante.

### Critères d'acceptation — chantier 1

1. Aucun espace ne peut afficher une zone vide sans invite d'action.
2. Créer une action depuis une phrase de transcription prend un clic et conserve `sourceRef` ; le lien `mm:ss ↗` replace la lecture au bon endroit à ±1 s.
3. Assigner responsable + échéance à une action se fait sans quitter le rail ni ouvrir de modale.
4. Le passage `Préparer → En séance → Relire` ne perd aucune saisie en cours.
5. Sur une fenêtre de 1280 px, aucune colonne fixe ne se chevauche ; la colonne fluide fait au moins 520 px.

---

## 3. Chantier 2 — Type 1:1 côté manager

**Réf. maquette :** `2a` (le fil, écran de séance) et `2b` (le suivi, écran de préparation). Les deux sont à implémenter : `2b` s'ouvre par défaut en mode `Préparer`, `2a` en mode `En séance`.

### 3.1 Règles propres au type

- Éléments **retirés** : présence/quorum, projets affectés, vues Kanban et Post-it, capture d'écran (conservée mais reléguée dans `⋯`).
- Éléments **ajoutés** : rôle déclaré, confidentialité par ligne, ordre du jour co-construit, humeur, engagements par côté, historique du fil.
- Badge de type `1:1` en `accent/oneonone`, fond de barre `#f4f1f6` : c'est le seul type qui change la couleur de la barre du haut.

### 3.2 Confidentialité — trois niveaux

| Niveau | Marque visuelle | Règle |
| --- | --- | --- |
| `private` | Point 6 px `accent/oneonone` + barre gauche 2 px sur le bloc de note | Jamais dans le récap, l'export, le rapport, ni les réponses de l'assistant partagé. Défaut pour le côté collaborateur. |
| `shared` | Pilule `Partagé` sur fond `#f4f1f6` | Visible par les deux personnes du fil. Défaut pour le côté manager. |
| `escalated` | Pilule bordée `accent/report` | Visible RH / N+1. Demande une confirmation explicite à la première utilisation par réunion. |

La bascule se fait par ligne (menu de la ligne ou `/privé`) et par défaut au niveau de la réunion. Le bouton de clôture affiche systématiquement le compte des lignes exclues.

### 3.3 Écran de séance (2a) — grille `300 | 1fr | 320`

**Colonne gauche**

- **Carte personne** : avatar 34 px, nom, rôle, ancienneté ; deux métriques `DERNIER 1:1` et `RYTHME` (issus de `cadenceDays`).
- **Ordre du jour** : items marqués par l'avatar 16 px de celui qui l'a ajouté ; glisser pour réordonner (`order`) ; un item traité est barré ; un item reporté affiche `→ <date du prochain>` et migre automatiquement dans le fil suivant. Composeur en bas.
- **Resté en suspens** : items dont `state='deferred'` ou sujets récurrents non tranchés, avec le nombre d'occurrences.
- Barre assistant en pied, contexte = fil (`threadId`), pas seulement la réunion.

**Colonne centrale — notes en trois temps**

1. `① COMMENT ÇA VA` — échelle 5 crans (`Difficile · Sous tension · Ça va · Bien · Très bien`) ; cran choisi bordé de sa couleur ; delta affiché par rapport au 1:1 précédent (`↓ vs 21 août (Bien)`). Écrit `moodHistory`.
2. `② SES SUJETS` — notes horodatées, une par sujet abordé ; un bloc `private` est visuellement isolé (fond `bg/canvas`, barre gauche, libellé `● NOTE PRIVÉE — VOUS SEUL`).
3. `③ FEEDBACK — DANS LES DEUX SENS` — deux cartes côte à côte, `CE QUE JE LUI DIS` / `CE QU'IL ME DIT`. Les deux sont obligatoires pour marquer le 1:1 « complet » (indicateur de qualité, non bloquant).

**Colonne droite — engagements**

- Deux groupes titrés par avatar : `Moi · n` et `<Prénom> · n`. Carte = texte + pilules (échéance, criticité, confidentialité).
- `TENUS DEPUIS LE DERNIER 1:1` : `✓` tenu, `✗` manqué en `accent/report` avec `n× reporté` — y compris pour le manager, sans exception.
- `CLÔTURER` : `Envoyer le récap` (primaire `accent/oneonone`), `Planifier le prochain — <date calculée>`, mention « Les notes privées ne sont jamais incluses ».

### 3.4 Écran de préparation (2b)

- **Moral — 6 derniers 1:1** : histogramme 6 barres, hauteur = valeur 1–5, dernière barre colorée selon le niveau ; tendance calculée sur 3 points (`en baisse` si moyenne des 2 derniers < moyenne des 3 précédents − 0,5). Phrase d'explication = sujet récurrent le plus cité sur la période.
- **Objectifs** : label + pourcentage + barre ; couleur par avancement (<30 % `warn`, <70 % neutre/violet, ≥70 % `ok`). Date de revue en pied.
- **À ne pas oublier** — règles de génération, dans cet ordre : (1) engagement du manager en retard, (2) sujet évoqué ≥ 3 fois sans décision, (3) réussite récente non encore reconnue. Bouton `Mettre à l'ordre du jour` qui crée les `AgendaItem` correspondants.
- **Engagements réciproques** : tableau `20 | 1fr | 92 | 84 | 96` (état, engagement, porteur, échéance, pris le), filtre `Les deux / Moi / <Prénom>`, pied avec taux de tenue (`kept / (kept+missed)`).
- **Sujets récurrents** : chips `label · n` colorées par famille (charge → warn, carrière → violet, reconnaissance → ok).
- **Historique** : 4 dernières séances, une ligne chacune, cliquable vers la réunion.

### Critères d'acceptation — chantier 2

1. Une note privée n'apparaît dans aucun export, rapport, récap ou réponse d'assistant : test automatisé obligatoire.
2. Un engagement manqué côté manager est visible aussi bien dans `2a` que dans `2b`, avec son compteur de reports.
3. Le moral saisi en séance alimente immédiatement l'histogramme de préparation suivant.
4. Un item d'ordre du jour non traité migre automatiquement vers le 1:1 suivant du même fil.

---

## 4. Chantier 3 — Ressources en séance et fiche projet

**Réf. maquette :** `3a` (tiroir ressources + partage) et `3b` (fiche projet en panneau).

### 4.1 Tiroir ressources (396 px)

- Ouverture : espace `Ressources`, bouton `Capture`, glisser-déposer n'importe où sur la fenêtre, `⌘⇧V`. Le tiroir se superpose sans démonter la séance (la colonne principale reste interactive).
- En-tête : `Ressources` + compteurs `n séance` / `n projet` + `＋ Importer`. Filtres : `Cette séance` · `Le projet` · `Captures` · `Liens`.
- Vignette : icône type 34 × 40 (XLS/PDF/PNG/URL avec fond dédié), nom en ellipsis, `Ajouté par X · hh:mm · poids`, puis actions `À l'écran` / `Présenter`, `Citer`, `Envoyer`. La pièce présentée porte une bordure `accent/action` et l'état `À l'écran` plein.
- Zone de dépôt permanente en fin de liste : « Glissez un fichier, collez un lien, ou capturez l'écran — `⌘⇧V` ».
- Pied `À L'ENVOI DU RAPPORT` : trois cases — joindre les pièces épinglées, donner l'accès aux participants, verser dans les documents du projet. Valeurs par défaut : les deux premières cochées.

### 4.2 Zone « À l'écran »

- Carte en haut de la colonne principale : nom du document + page courante, boutons `Annoter`, `Épingler à mm:ss`, `Arrêter le partage`.
- Scène de prévisualisation : conteneur flex colonne, document centré, légende « Aperçu — les participants voient la même page » **sous** le document (jamais en absolu par-dessus).
- État de partage remonté dans la barre du haut : pilule `accent/action` pleine `● Partage actif · n voient`. Sans partage, la pilule disparaît (pas d'état grisé).
- Annotation : calque de dessin simple (rectangle, flèche, texte) sauvegardé comme `Capture` dérivée, jamais comme modification du fichier source.
- Épinglage : crée `pinnedAtT`, ajoute un marqueur sur la frise, et insère dans la note courante une puce `◫ <nom> · p.n` cliquable.
- Bande `ÉPINGLÉ DANS LA SÉANCE` : chips horodatées, celle du moment courant en `accent/action`.

### 4.3 Fiche projet (panneau 430 px)

- Déclencheur : segment projet du fil d'Ariane (bordé `accent/action` pour signaler qu'il est cliquable). Le panneau glisse depuis la droite, ombre `-8px 0 24px rgba(0,0,0,.07)`, la colonne principale passe à 55 % d'opacité et reste consultable.
- En-tête : `FICHE PROJET`, nom, `ref · n réunions · dernière mise à jour <quand> par <qui>`, bascule `Édition`, fermeture `✕` (ou `Esc`).
- Contenu : statut (menu à 3 valeurs avec point coloré) · budget consommé (valeur / total + barre, couleur par ratio : <70 % ok, <90 % warn, ≥90 % report) · **jalons** (état, libellé, date ou `bloqué`, ligne d'ajout inline) · **périmètre & contexte** (texte libre + tags avec chip `＋`) · **risques** (niveau + libellé + `＋ Ajouter`) · **interlocuteurs** (nom — rôle).
- **Suggestions de l'assistant** : encart listant les mises à jour déduites de la séance (budget, statut de jalon…), bouton `Revoir` → diff champ par champ, acceptation individuelle. Jamais d'écriture automatique.
- Pied : mention de visibilité (« toute l'équipe projet · reprise en préparation de la prochaine réunion »), `Annuler` / `Enregistrer`. Enregistrement optimiste avec possibilité d'annuler pendant 5 s.

### Critères d'acceptation — chantier 3

1. Déposer un fichier pendant la séance ne provoque aucun changement d'écran ni perte de focus de saisie.
2. L'état de partage est lisible depuis la barre du haut sans ouvrir le tiroir.
3. Une pièce épinglée est retrouvable par son timecode et citée automatiquement dans le rapport.
4. Aucune modification de la fiche projet n'est écrite sans validation humaine explicite.

---

## 5. Chantier 4 — Captures Teams / Zoom

**Réf. maquette :** `4a` (sélecteur de source + bande de captures) et `4b` (pastille flottante en mode séance).

### 5.1 Sélecteur de source (popover 346 px)

- Ouvert par le bouton `Capture` ou `⌘⇧S` (première utilisation ; ensuite `⌘⇧S` capture directement la dernière source valide).
- Liste de sources détectées : vignette 44 × 30 avec le nom du produit, libellé, sous-titre d'état (`Réunion · partage de X en cours`, `Aucune réunion active`), point `accent/ok` si active. Sources : Teams, Zoom, Écran entier, Zone à la souris.
- Deux bascules : **Capturer à chaque changement de partage** (par défaut activée) et **Toutes les 2 minutes** (désactivée). Une source inactive rend la première bascule indisponible avec l'explication.
- Mention de confiance obligatoire : « Rien n'est envoyé à Teams ou Zoom : One2One lit la fenêtre, comme une capture système. »
- Bouton primaire `Capturer maintenant`.

### 5.2 État visible

- Barre du haut : pilule `accent/ok` bordée `● Capture · <Source> n ⌄` — le compteur est le nombre de captures de la séance ; le chevron réouvre le sélecteur. Sans capture configurée : bouton neutre `Capture`.
- Frise audio : marqueur carré 12 px `#3d5180` par capture, `accent/action` pour la dernière. Légende `■ = capture`.
- Détection d'échec (fenêtre fermée, permission refusée) : la pilule passe en `accent/warn` avec `Source perdue` et un lien de reconfiguration ; aucune boîte de dialogue bloquante en séance.

### 5.3 Bande de captures

- Carte en pied de colonne : en-tête `Captures de la séance` + `n · source X` + mention du déclencheur automatique.
- Vignettes 132 × 76, légende `mm:ss · auto|⌘⇧S`, sélection bordée 2 px. Dernière tuile = zone de capture manuelle.
- Colonne d'état à droite : texte extrait et cherchable, rattachement au timecode, case `Joindre au rapport`.
- Une capture insérée dans une note s'affiche en carte 56 × 36 + titre + première ligne d'OCR + `Agrandir`. Une action issue d'une capture porte la pilule `◫ mm:ss`.
- OCR : exécuté localement, stocké dans `ocrText`, indexé pour la recherche et pour l'assistant. Si l'OCR échoue, la capture reste utilisable sans texte.

### 5.4 Pastille flottante (mode séance)

- Fenêtre toujours au-dessus, ~300 × 40, rayon 22, fond `rgba(20,18,15,.94)`, ombre portée forte, déplaçable et magnétisée aux coins.
- Contenu : point d'enregistrement rouge pulsant, temps mono, séparateur, `◫ Capturer` (plein `accent/action`), `✎ Note`, compteur de captures.
- Après capture : mini-panneau de confirmation 186 px pendant 4 s — `CAPTURÉ · mm:ss`, vignette, première ligne d'OCR, `＋ Action depuis la capture`.
- Raccourcis actifs même quand One2One n'a pas le focus : `⌘⇧S`, `⌘⇧N`.

### Critères d'acceptation — chantier 4

1. À tout instant, l'utilisateur peut dire si la capture est armée, sur quelle source, et combien de captures existent — sans ouvrir de menu.
2. Une capture manuelle depuis la pastille ne demande aucun retour dans l'application.
3. Chaque capture est reliée à un timecode et retrouvable depuis la frise.
4. Le texte extrait est cherchable dans la réunion et exploitable par l'assistant.

---

## 6. Chantier 5 — Type 1:1 côté collaborateur

**Réf. maquette :** `5a` (mon 1:1) et `5b` (préparation en 2 minutes). Même entité `OneOnOneThread` que le chantier 2, avec `myRole = 'collaborator'`.

### 6.1 Inversions par rapport au côté manager

| Élément | Manager | Collaborateur |
| --- | --- | --- |
| Visibilité par défaut des notes | `shared` | `private` — le partage est un geste explicite par ligne |
| Badge de rôle | implicite | Pilule `Je suis le collaborateur` dans la barre, obligatoire |
| Colonne de droite | Engagements des deux côtés | `CE QUE J'AI LIVRÉ` (auto) + `CE QU'IL M'A PROMIS` |
| Colonne de gauche | Ordre du jour partagé | `CE QUE JE VEUX DIRE` (privé, ordonnable) + `MES DEMANDES EN COURS` |
| Clôture | Envoyer le récap au collaborateur | `Envoyer mon récap` + `Verser dans mon dossier annuel` |

### 6.2 Écran de séance (5a) — grille `308 | 1fr | 356`

- **Mes sujets** : items numérotés, poignée de glissement `⠿`, tous `private` par défaut avec la pilule `● privé` en tête de carte. Mention explicite : « Visible de vous seul. Vous choisissez à la fin ce qui part dans le récap partagé. »
- **Mes demandes en cours** : libellé + statut (`Sans réponse` warn, `En attente` warn, `Accordé` ok, `Refusé` report) + historique court (`Demandé le … · relancé n fois`). Une demande sans réponse depuis plus de 60 jours passe en `accent/report`.
- **Notes** en deux sections : `CE QU'IL M'A DIT` et `CE QUE J'AI DIT`. Les engagements verbaux du manager sont saisis par `/promesse` et créent un `Commitment` côté `manager`.
- **Ce que j'ai livré** : généré automatiquement depuis les `Action` closes et les réunions où l'utilisateur a un rôle actif, depuis la date du 1:1 précédent. Chaque ligne a un bouton `Citer` qui l'insère dans les notes comme `kind:'proof'`. Une action bloquée apparaît en `warn` avec sa cause.
- **Ce qu'il m'a promis** : cartes triées par retard décroissant ; barre gauche `accent/report` si en retard ; pilules `Promise le …`, `n reports`, `Relancer` (crée un rappel et un item d'ordre du jour pour le prochain 1:1).
- Pied : `Envoyer mon récap`, `Verser dans mon dossier annuel`, et le compte des lignes privées exclues.

### 6.3 Écran de préparation (5b)

- Trois blocs : `RESTÉ SANS RÉPONSE` (cases à cocher, ancienneté), `CE QUE J'AI LIVRÉ DEPUIS` (auto), `CE QUE JE VEUX OBTENIR` (cases cochées = à porter en séance).
- Deux actions : `En faire mon ordre du jour` (crée les `AgendaItem` privés dans l'ordre coché) et `Partager les sujets à <manager>` (les passe en `shared`).
- Mention de provenance : « Généré depuis vos actions, vos réunions et l'historique des 1:1 — modifiable avant partage. »

### Critères d'acceptation — chantier 5

1. Le rôle est visible en permanence ; on ne peut pas confondre un 1:1 mené et un 1:1 subi.
2. Aucune note du collaborateur ne devient visible du manager sans un geste explicite sur cette ligne.
3. La liste « ce que j'ai livré » se remplit sans saisie manuelle et se cite en un clic.
4. Une promesse du manager non tenue remonte automatiquement à la préparation suivante.

---

## 7. Chantier 6 — Type atelier : planches locales

**Réf. maquette :** `6a` (planche plein cadre) et `6b` (planche de séance). Badge `ATELIER` en `accent/workshop`.

### 7.1 Modes de planche

| Mode | Moteur | Palette |
| --- | --- | --- |
| `sketch` (Croquis) | Moteur type Excalidraw embarqué localement (rendu main levée) | Crayon, rectangle, ellipse, flèche, ligne, texte, post-it, image, gomme |
| `diagram` (Schéma) | Moteur de formes et connecteurs type draw.io, embarqué | Bibliothèque de formes (serveur, base, file, acteur, zone), connecteurs magnétisés, points d'ancrage, alignement, calques |
| `ink` (Manuscrit) | Tracé stylet/trackpad, pression si disponible | Stylo (3 épaisseurs), surligneur, gomme, règle, lasso de sélection |

Le changement de mode ne convertit pas la planche : il crée une nouvelle planche, sauf si la planche courante est vide. Le mode est stocké dans `Board.mode` et affiché sur la vignette.

### 7.2 Écran plein cadre (6a) — grille `52 | 1fr | 314`

- **Barre d'outils** (2ᵉ ligne, 32 px) : sélecteur de mode segmenté, 5 couleurs (`ink/1`, action, report, ok, warn) — la couleur active porte un anneau blanc + contour, 3 épaisseurs, à droite `Planche n sur m · dernière modif. il y a Xs` et `Exporter PNG / SVG`.
- **Palette verticale** 52 px : outils 32 × 32, rayon 7 ; l'outil actif est `ink/1` plein. `↺ ↻` en pied (undo/redo par planche, profondeur 100).
- **Toile** : fond `#fdfcfa` + grille de points 18 px (`radial-gradient`), zoom 25–400 % (molette + `⌘±`), panoramique à l'espace ou au clic milieu, `⇧⌘0` pour ajuster.
- **Présence** : pilule flottante en bas à droite avec les avatars de ceux qui dessinent (si édition partagée activée), sinon masquée.
- **Dock droit**, trois onglets : `Planches n` / `Captures n` / `Pièces n`.
  - *Planches* : vignette 60 × 40 + mode + titre + `mm:ss · auteur` ; la planche active est bordée `accent/workshop` sur fond `#f2f8f7`. Boutons `＋ Planche` (primaire teal) et `Dupliquer`. Glisser pour réordonner.
  - *Sur cette planche* : liste des éléments annotés comme question/risque (puce colorée), avec `＋ Action depuis la sélection` et `Épingler à mm:ss`.
  - *Pièces & captures* : vignettes avec `Sur la planche` / `Insérer` — insérer place l'image comme objet verrouillé de la planche, une copie locale, jamais une référence externe.
- Barre assistant en pied du dock : « L'assistant peut décrire les planches dans le rapport » (génère une légende textuelle à partir des libellés d'objets).

### 7.3 Planche de séance (6b)

- Liste chronologique : colonne timecode 40 px + carte par élément produit (planche, capture, manuscrit), aperçu 76–96 px de haut, pied avec type, titre et auteur.
- Encart de clôture : rappel du stockage local et `Joindre au rapport` (primaire teal). Exports proposés : PNG, SVG, `.excalidraw`, `.drawio` — en secours seulement, le format de référence reste la réunion.

### 7.4 Stockage et performances

- `Board.scene` est du JSON stocké dans la réunion ; `thumbPng` est un blob local régénéré au plus toutes les 5 s (debounce) et à chaque changement de planche.
- Sauvegarde locale à chaque idle de 400 ms ; aucune requête réseau, aucun compte, fonctionnement complet hors ligne.
- Limites cibles : 2 000 objets par planche à 60 fps, 40 planches par réunion, image insérée redimensionnée à 2 048 px max sur le grand côté.
- Les moteurs sont embarqués dans l'application (pas d'iframe distante, pas de CDN).

### Critères d'acceptation — chantier 6

1. Une planche se crée, se dessine et se retrouve horodatée sans aucun accès réseau (test en mode avion).
2. Les trois modes sont accessibles en un clic et conservent chacun leur palette.
3. Un fichier déposé est copié dans la réunion : supprimer l'original du disque ne casse rien.
4. Une sélection d'objets se transforme en action avec `sourceRef` de type `board`.
5. Le rapport d'atelier contient les planches dans l'ordre du temps.

---

## 8. Transverse — stockage, confidentialité, rapport

- **Local d'abord** : audio, transcription, notes, captures, planches et pièces vivent dans le document de réunion. Toute fonction distante est optionnelle et signalée.
- **Copie, jamais référence** : un fichier déposé ou une image insérée est copié dans la réunion.
- **Chaîne de citation** : tout élément dérivé (action, note, entrée de rapport) conserve `sourceRef` avec son `t`. Le rapport rend ces références cliquables.
- **Filtre de confidentialité unique** : une seule fonction `isExportable(item, audience)` traverse rapport, export, récap 1:1 et assistant. Aucune vue ne réimplémente la règle.
- **Rapport** : les templates existants restent ; ils gagnent des blocs optionnels — pièces épinglées, captures jointes, planches d'atelier, engagements réciproques (1:1), mises à jour de fiche projet acceptées.

---

## 9. Ordre de développement conseillé

1. **Socle** — barre du haut sur une ligne, trois espaces, modes temporels, jetons visuels et contraste (chantier 1, §2.1–2.3).
2. **Notes ↔ transcription + rail d'actions** avec création depuis une phrase (§2.4–2.5) : c'est ce qui supprime le plus de friction en séance.
3. **Ressources et captures** (chantiers 3 et 4) : même modèle `Attachment`, à faire ensemble.
4. **Fiche projet** (§4.3) avec suggestions non automatiques.
5. **Types 1:1** (chantiers 2 puis 5) : une seule entité `OneOnOneThread`, deux rôles, filtre de confidentialité partagé.
6. **Atelier** (chantier 6) : le plus lourd techniquement, à isoler derrière un drapeau de fonctionnalité.

---

## 10. Points à trancher

- Édition simultanée des planches : réellement multi-utilisateurs (nécessite un transport local ou un serveur d'équipe) ou mono-utilisateur avec présence affichée seulement ?
- Détection du changement de partage Teams/Zoom : par API de fenêtre ou par différence d'image ? La deuxième option est portable mais consomme davantage.
- Niveau `escalated` des notes 1:1 : qui le voit exactement, et faut-il une trace d'accès ?
- Vues d'actions `Calendrier` et `Eisenhower` : conservées dans le rail à 330 px ou déportées dans l'espace `Rapport` ?
