# Fiche collaborateur v3 — ce que le modèle doit fournir

Date : 2026-08-11
Branche : `feat/fiche-collaborateur-v3`, partie de `feat/fusion-note-reunion`
Complète : `SPEC-Fiche-Collaborateur.md` (mise en page, jetons, clavier), fournie par l'auteur.

Ce document ne redit pas la mise en page. Il traite **la seule chose que la spec visuelle ne
pouvait pas trancher** : ce que le modèle sait nourrir, ce qu'il faut lui ajouter, et ce
qu'aucun calcul ne peut deviner.

## 1. Ce que le modèle nourrit déjà

| Élément de la fiche | Source |
|---|---|
| fil : 1:1, notes, réunions | `Meeting` et son `kind` — un seul modèle depuis la suppression d'`Interview` (ADR du 2026-08-11) |
| fil : actions | `ActionTask.meeting` / `.collaborator` |
| badge « N actions produites » | `meeting.tasks.count` |
| épinglé / favori | `Collaborator.pinLevel` (2 et 1) |
| projets portés | `projectsAsManager` + `projectsAsArchitect` |
| prep « 4 points sur 6 » | cases `- [ ]` de `Meeting.prepNotes` |
| décisions du fil | `Meeting.decisions`, à la date de leur réunion |

## 2. Ce qu'il faut ajouter à `Collaborator`

Trois propriétés à valeur par défaut — migration légère, sans `SchemaV2`.

| Propriété | Type | Défaut | Pourquoi |
|---|---|---|---|
| `oneToOneCadenceRaw` | `String` (+ wrapper `OneToOneCadence`) | **`aucune`** | calcule le retard affiché en en-tête et les seuils du graphe d'écart |
| `entity` | `Entity?` | `nil` | la spec l'affiche en sous-titre et l'édite ; `Entity` n'était reliée qu'aux projets |
| `manager` | `Collaborator?` | `nil` = « Moi » | picker de la feuille d'édition |

**Le défaut de cadence est `aucune`, pas « toutes les 2 semaines ».** Un défaut actif
déclarerait en retard, du jour au lendemain, les 366 fiches de l'annuaire — dont 88 ad hoc et
des dizaines jamais revues depuis un import calendrier. Le retard ne s'affiche que si un
rythme a été choisi : c'est un engagement de l'utilisateur, pas une supposition de l'app.

Enum persisté en `…Raw: String` + wrapper calculé, comme le reste du dépôt (contournement du
bug SwiftData sur les enums).

## 3. Le compteur « engagements » — définition et limite

**Définition de l'auteur, mot pour mot :**

> Un engagement pris en 1:1 et non soldé : une ligne de note qualifiée décision ou action
> pendant un entretien, qui n'a été ni cochée ni explicitement reprise depuis. Distinct du
> compteur « ouvertes » juste à côté — celui-là compte toutes les actions du backlog, quelle
> que soit leur origine ; « engagements » ne compte que ce qui a été promis de vive voix,
> devant vous, et qui traîne.
>
> Le point de fond que ça révèle : ce compteur est un indicateur de **confiance**, pas de
> charge. D'où des seuils de couleur très bas — rouge au-delà de 3, alors que « ouvertes »
> reste noir à 10. Deux promesses non tenues depuis six semaines abîment plus la relation que
> dix actions en cours.

Deux compteurs, deux natures. `ouvertes` mesure une charge et se lit en noir jusqu'à 10 ;
`engagements` mesure une dette morale et passe au rouge à partir de 4. Aucun code ne doit les
calculer par la même fonction ni les colorer par le même seuil.

### 3.1 Ce qui est calculable aujourd'hui

Relevé sur le store réel le 2026-08-11 :

| Matière | Volume | État disponible |
|---|---|---|
| actions nées en 1:1 ou 1:1 manager | **67** | `isCompleted` → soldé |
| réunions 1:1 portant des décisions | **10** | **aucun** |
| notes de 1:1 portant des cases à cocher | **0** | la case elle-même |

Donc, en v1 : **un engagement est une action née en 1:1 ou en 1:1 manager, encore ouverte.**
C'est la seule matière qui porte à la fois une origine « de vive voix » et un état.

### 3.2 Ce qu'aucun calcul ne peut deviner

Deux morceaux de la définition n'ont **pas** de support dans le modèle :

- **une décision n'a pas d'état.** `Meeting.decisions` est un tableau de chaînes dans une
  colonne JSON. Rien ne peut la marquer soldée, donc une décision comptée comme engagement
  y resterait pour toujours — un compteur qui ne redescend jamais cesse d'être lu.
- **« explicitement reprise depuis » n'est pas dérivable.** Reprendre un engagement est un
  geste humain ; l'app ne peut ni le déduire d'une répétition de texte, ni le distinguer d'un
  simple rappel.

**Conséquence, à trancher avant d'implémenter le compteur complet :** honorer la définition
entière demande un *geste* — solder un engagement d'un clic, sur la ligne du fil. C'est une
décision de produit, pas d'implémentation : elle ajoute un état à la décision (donc un modèle
ou une colonne), et un contrôle à l'écran. La v1 s'en tient aux actions ; la fiche affiche
alors un compteur juste mais incomplet, et le dit.

## 4. Ce qui reste ouvert

- Le **seuil de couleur** d'`engagements` est donné (rouge > 3) ; celui du retard de 1:1
  dépend de la cadence choisie et reste à formuler : « en retard » à partir de combien de
  fois la période ?
- La spec visuelle montre « 11 sem. / dernier 1:1 » en `warn`. Sans cadence renseignée
  (défaut), ce compteur affiche l'écart **sans couleur** : un écart n'est un retard que
  relativement à un rythme convenu.
