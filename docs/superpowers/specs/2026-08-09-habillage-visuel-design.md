# Habillage visuel — appliquer le langage des captures à l'app existante

**Date** : 2026-08-09
**Statut** : validée
**Origine** : huit captures produites avec Claude Design (poste de pilotage, « À traiter »,
actions, projets, prise de notes en séance, capture éclair, éditeur à blocs, enregistrement
et résumé).

---

## Le problème

L'application couvre déjà l'essentiel des fonctions que montrent les captures : actions,
projets, réunions, notes, préparation de 1:1, enregistrement et transcription locale. Ce
qui manque n'est pas fonctionnel — c'est que **chaque écran a été habillé séparément**, sans
vocabulaire visuel commun. Il n'existe aucun fichier de jetons de design dans le dépôt ; le
seul thème est `MeetingTheme`, local à la réunion.

Les captures, elles, appliquent **le même vocabulaire sur les huit écrans**. C'est cette
cohérence qui les fait tenir ensemble, plus que le détail de tel ou tel écran.

Cette spec ne décrit donc ni des fonctions, ni des écrans : elle décrit un **langage
visuel** et la façon de l'appliquer à ce qui existe.

---

## Périmètre : l'habillage seul

### Dans le périmètre

- Un jeu de jetons (couleurs sémantiques, typographie, espacements, rayons).
- Les composants d'interface que les captures répètent.
- Le restylage des vues **existantes**, à fonctions constantes.

### Hors périmètre

- **Aucune fonction nouvelle.**
- **Aucun écran nouveau** — ni le tableau de bord (capture 1a), ni « À traiter » (1b).
- **Aucune réorganisation de la navigation.** Les captures ignorent Kanban, Eisenhower,
  Mail, Chatbot, Heatmap et Calendrier ; leur sort n'est pas tranché ici.
- **Rien sur l'éditeur Markdown.** L'éditeur a son propre chantier, avec sa propre
  approche (voir « Ce que cette spec ne couvre pas »).
- Aucun modèle de données nouveau. En particulier, l'objet `Décision` que les captures
  laissent entrevoir n'est pas créé ici.

---

## Le langage visuel des captures

> **Réserve de méthode.** Les valeurs ci-dessous sont **lues sur les images**. Elles sont
> assez précises pour travailler, mais elles doivent être confirmées sur les fichiers
> sources de Claude Design avant d'être figées. La règle en cas d'écart : le fichier
> source prime.

### Couleurs

| Rôle | Valeur proposée | Où on la voit |
|---|---|---|
| Fond de fenêtre (chrome) | crème `#EFEDE8` | barre latérale, pourtour des fenêtres |
| Fond de contenu | blanc `#FFFFFF` | listes, tableaux, cartes |
| Teinte de ligne alternée | `#FBFAF8` | tableaux Projets et Actions |
| Texte principal | quasi noir `#1D1D1F` | titres de ligne |
| Texte secondaire | gris `#8A8A8E` | sous-titres, codes projet, compteurs |
| Verbe / lien | bleu système `#0A6CFF` | `Ouvrir`, `Préparer`, `Relancer`, `Tout voir` |
| Urgence forte | rouge `#E5484D` | `12 j`, `27/07`, pastille rouge, badge `ACTION` |
| Urgence moyenne | orange `#E08000` | `5 j`, `6 semaines`, pastille orange |
| Nominal | vert `#2E7D52` | pastille verte, badge `Validé` |
| Accent manager | violet `#6E56CF` | badge `MANAGER`, encart `ASSISTANT` |
| Fonds de badge | teinte très claire du ton | pilules `Validé`, `En revue`, `MANAGER` |

Le bleu `#0a6cff` est déjà celui du handoff éditeur (`design_handoff_editor_blocs/README.md`) :
c'est la même valeur, à ne pas dupliquer sous un autre nom.

### Typographie

| Rôle | Caractéristiques |
|---|---|
| Titre d'écran | ~28 pt, demi-gras — « 4 entretiens, 2 à préparer » |
| Intitulé de section | ~11 pt, **petites capitales**, interlettrage élargi, gris — `COLLABORATEURS`, `TRAME`, `OÙ ÇA ATTERRIT`, `EN TROIS POINTS` |
| Titre de ligne | ~14–15 pt, medium |
| Sous-titre de ligne | ~12–13 pt, gris |
| Chasse fixe | codes projet (`ARC-118`, `PLT-023`), horaires (`09:30`, `18:42`), noms de commande (`/tableau`, `/mermaid`) |
| Chiffres | alignés à droite, chiffres tabulaires, négatifs en rouge |

L'intitulé en petites capitales grises est le marqueur le plus caractéristique du jeu : il
apparaît sur sept des huit captures.

### Densité et espacements

- Barre latérale : ~230–260 pt, élément sélectionné en rectangle arrondi gris.
- Lignes de liste : aérées, séparateur fin pleine largeur, pas de bordure de carte.
- Marge de contenu : ~24–32 pt.
- Compteurs de la barre latérale : alignés à droite, gris, sans pastille — sauf le compteur
  d'alerte (`À traiter 14`) qui prend une pastille rouge pleine.

### Motifs récurrents

Trois motifs structurent presque toutes les listes des captures :

1. **Pastille d'état à gauche** — rouge / orange / vert, devant une personne ou un projet.
2. **Métadonnée à droite, colorée par l'urgence** — `12 j`, `6 semaines`, `27/07`. La
   couleur porte l'information ; le libellé reste court.
3. **Verbe d'action en bleu, tout à droite** — un seul verbe par ligne, jamais deux.

Et pour les actions principales : **bouton noir plein** (`Clore le 1:1`, `Arrêter`,
`Valider et créer les 2 actions`), au plus un par écran.

---

## Les composants à extraire

Les huit captures se composent presque entièrement de huit éléments :

| Composant | Rôle | Captures |
|---|---|---|
| `SectionLabel` | intitulé en petites capitales grises | 1a, 2a, 2b, 3b, 1e |
| `StatusDot` | pastille d'état 8 pt | 1a, 1b, 1e |
| `TypeBadge` | pilule teintée de type ou d'état | 1b, 1e, 2a, 2b |
| `MetaValue` | métadonnée à droite, colorée par l'urgence | 1a, 1b, 3 |
| `VerbButton` | verbe bleu aligné à droite | 1a, 1b |
| `ListRow` | ligne aérée à séparateur fin | 1a, 1b, 3 |
| `SegmentedFilter` | filtres à compteur intégré | 3 |
| `Avatar` | initiales sur fond pastel | 1a, 1b, 3, 2b |

C'est peu, et c'est le point : la trousse est petite parce que les captures sont
disciplinées.

---

## Approches étudiées

### 1. Jetons seuls, adoption écran par écran — écartée

Écrire les jetons, puis s'y conformer au fil des vues touchées. Le plus sûr, mais 50 vues
font une longue traîne et l'application reste bigarrée pendant toute la transition. Surtout,
sans composants partagés, la cohérence repose entièrement sur la discipline de celui qui
édite — c'est exactement ce qui a produit la situation actuelle.

### 2. Trousse complète d'abord, adoption ensuite — écartée

Dessiner jetons et composants à partir des huit captures avant de toucher aux vues. La
trousse serait complète d'emblée, mais elle serait **spéculative** : on dessinerait des
composants d'après des images, sans qu'aucun ait été confronté à une vue réelle. Et rien
ne changerait à l'écran avant longtemps.

### 3. Vitrine, extraction, propagation — retenue

Restyler **un seul** écran de bout en bout, en extraire les jetons et les composants qui ont
réellement servi, puis propager.

Pourquoi celle-ci : les jetons sortent d'un usage réel plutôt que d'une lecture d'image ; le
résultat est visible dès le premier écran ; et la trousse extraite est validée par un cas
concret. Le prix est un premier écran un peu plus cher et une reprise à l'extraction.

En pratique, c'est **3 puis 2** : une fois la trousse extraite, la propagation se fait par
composition, comme dans l'approche 2.

---

## Sous-projet 1 — la vitrine `ActionsListView`

### Pourquoi cet écran

La capture 3 lui correspond presque au pixel, c'est un écran d'usage quotidien, et il
exerce à lui seul quatre des huit composants — `ListRow`, `MetaValue`, `Avatar`,
`SegmentedFilter` — plus la chasse fixe et la règle de couleur d'urgence.

### État actuel, vérifié

`OneToOne/Views/ActionsListView.swift`, 731 lignes. La ligne est déjà isolée dans
`ActionTaskRow`, avec des sections distinctes pour les actions ouvertes (« GitHub-style »)
et terminées (« note-style »). Aucun jeton partagé.

### Cible

- Filtres segmentés à **compteur intégré** : `En retard 7`, `Cette semaine 11`, `Toutes 43`.
  Le filtre actif est un rectangle arrondi noir plein, texte blanc ; les autres, contour fin
  sur fond clair.
- `Grouper par : échéance` aligné à droite, en gris, avec chevron.
- Lignes : case à cocher, titre, puis à droite le code projet en chasse fixe grise, l'avatar
  à initiales, et l'échéance.
- **Échéance colorée par l'urgence.** La règle, déduite des captures 3 et 1a :
  **rouge** si dépassée de plus de sept jours (`27/07`, `31/07`, `12 j`, `8 j`) ;
  **orange** si dépassée de sept jours ou moins (`03/08`, `06/08`, `5 j`, `2 j`) ;
  **grise** si à venir (`11/08`, `18/08`). Le seuil de sept jours est inféré des deux
  captures et reste à confirmer ; c'est la seule règle de couleur conditionnelle du jeu,
  et elle appartient aux jetons, pas aux vues.
- Séparateur fin pleine largeur entre les lignes, teinte alternée très légère.
- Un tiret cadratin `—` pour un code projet absent, jamais une case vide.

### Critère de fin

L'écran est fini quand il est visuellement conforme à la capture 3 **et** qu'aucun
comportement n'a changé : mêmes filtres, mêmes mutations, mêmes tris. Un écart fonctionnel,
même minime, est un défaut — le périmètre est l'habillage.

---

## Sous-projet 2 — l'extraction de la trousse

Une fois la vitrine conforme, extraire vers `OneToOne/Views/DesignSystem/` :

- `AppTheme.swift` — les jetons, en `enum` de constantes statiques, sur le patron de
  `MeetingTheme` (conforme à la convention du dépôt : services et thèmes en `enum` namespace).
- `Components/` — les composants qui ont **réellement servi** dans la vitrine. Un composant
  qu'aucune vue n'utilise n'est pas extrait ; il attendra la vue qui en a besoin.

Règle : l'extraction ne change pas l'apparence de la vitrine. Si elle la change, c'est que le
composant ne correspond pas à l'usage.

---

## Sous-projet 3 — la propagation

Par usage décroissant, une vue par lot :

1. `ProjectListView` — capture 1e. Valide le vocabulaire « tableau » : en-tête en petites
   capitales, pastille d'état, badges `Validé` / `En revue` / `En cours` / `—`, porteur.
   C'est la vue qui fera émerger `TableHeader` s'il manque.
2. `MeetingsListView`
3. `AllNotesView`
4. `PrepWindow`
5. Le reste, au fil des besoins.

Chaque vue propagée peut faire apparaître un composant manquant : on l'ajoute à la trousse à
ce moment-là, pas avant.

---

## Non-objectifs

- Ne pas introduire de dépendance nouvelle. La trousse est du SwiftUI ordinaire.
- Ne pas réécrire les vues : les restyler. Une vue dont la structure est saine garde sa
  structure.
- Ne pas toucher aux modèles SwiftData.
- Ne pas traiter l'éditeur Markdown.

---

## Questions ouvertes

1. **Mode sombre.** Les captures ne définissent que le mode clair. Proposition : dériver le
   sombre des jetons sémantiques, sans le spécifier écran par écran, et le vérifier à
   l'usage. À confirmer.
2. **Sort des vues absentes des captures.** Kanban, Eisenhower, Mail, Chatbot, Heatmap,
   Calendrier ne figurent nulle part dans les huit écrans. Elles reçoivent les jetons comme
   les autres, mais la question « faut-il les garder ? » est explicitement reportée.
3. **Valeurs exactes.** Les couleurs et tailles ci-dessus sont lues sur les images ; elles
   doivent être confrontées aux fichiers sources de Claude Design avant d'être figées dans
   `AppTheme.swift`.

---

## Ce que cette spec ne couvre pas

L'analyse des huit captures a fait apparaître trois autres chantiers, **volontairement
laissés de côté** ici. Ils sont consignés pour mémoire, chacun mériterait sa propre spec :

- **La note qualifiée** (captures 2a, 2b) — une ligne de note se promeut en action, décision
  ou point manager, et la capture éclair `⌥Espace` la range automatiquement. Deux des trois
  objets existent déjà (`ActionTask`, `ManagerReportItem`, ce dernier portant déjà la
  provenance en offsets UTF-16) ; `Décision` manque.
- **Le poste de pilotage** (captures 1a, 1b) — tableau de bord et « À traiter ». Moins cher
  qu'il n'y paraît : ce sont des **requêtes** sur des objets existants, pas de nouveaux
  modèles.
- **L'enregistrement et le bloc `/résumé`** (capture 3b) — l'enregistrement et Whisper local
  existent ; le bloc `/résumé` et sa validation (« rien n'est créé sans validation ») non.

Et l'**éditeur à blocs** (capture 3a) reste un chantier à part entière, avec son approche
propre : sortir les blocs-cartes du flux TextKit en vraies `NSView` ancrées, ce qui supprime
par construction la classe de défauts des trois derniers chantiers. Il ne dépend pas de cette
spec, et cette spec ne dépend pas de lui.
