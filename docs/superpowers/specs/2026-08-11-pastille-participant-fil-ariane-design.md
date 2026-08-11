# Pastille « participant » dans le fil d'Ariane — design

Date : 2026-08-11
Branche : `feat/pastille-participant-fil-ariane`

## Le manque

Une réunion ne peut être rattachée à quelqu'un que par un seul chemin :
onglet **Vue d'ensemble** → carte **Présence** → bouton « Gérer les participants » →
`ManageParticipantsSheet`. Trois niveaux, et rien dans le fil d'Ariane ne dit à qui la
réunion appartient.

Le manque se voit surtout depuis que le badge de type est éditable sur toutes les
réunions (`MeetingTopChromeBar`, `Picker` sur `MeetingKind.allCases`) : basculer une note
en « One-to-One » produit un 1:1 **sans interlocuteur**, et le geste qui permettrait de le
réparer est ailleurs, sous un autre nom. Constaté à l'écran le 2026-08-10 en déroulant le
contrôle 3 de la tâche 13 du plan de fusion Note/Réunion.

Le manque préexiste à cette fusion : le `Picker` sur tous les types était déjà là. C'est
pourquoi ce travail est une branche séparée, et non une suite de `feat/fusion-note-reunion`.

## Ce qu'on ajoute

Une pastille dans le fil d'Ariane, après le badge de type :

```
One2One  ›  REFSI  ›  Point budget  ›  [1:1]  ›  [Alice Martin]
```

**Ce qu'elle affiche** — trois états, dans l'ordre de fréquence :

| Participants | Libellé |
|---|---|
| aucun | `+ Qui ?` |
| un | son nom |
| plusieurs | « N participants » |

**Ce que le menu contient**, dans cet ordre :

1. les **participants actuels**, cochés — toujours listés, même non épinglés, sinon on ne
   pourrait plus les retirer ;
2. les **épinglés** (`pinLevel == 2`) puis les **favoris** (`pinLevel == 1`), triés par nom,
   non archivés, non ad hoc ;
3. un séparateur, puis **« Gérer les participants… »**, qui ouvre `ManageParticipantsSheet`
   telle quelle.

Cliquer une ligne **bascule** l'appartenance : ajoute (statut « présent ») ou retire. La
coche dit l'état *avant* le clic — aucune suppression surprise, et le même geste vaut pour
tous les types de réunion.

### Pourquoi `pinLevel` et pas l'annuaire entier

Mesuré sur le store réel le 2026-08-10 : **366 collaborateurs**, dont 88 ad hoc et
**13 épinglés ou favoris** (11 en `pinLevel 2`, 2 en `pinLevel 1`). Un menu de 366 entrées
est inutilisable ; `pinLevel` est un classement que l'utilisateur entretient déjà pour sa
barre latérale, il ne coûte aucun nouveau réglage et aucune requête — c'est un scalaire, il
ne fait fauter aucune relation.

Les collaborateurs hors liste courte restent atteignables par « Gérer les participants… »,
où vivent déjà la recherche et la création ad hoc.

## Architecture

`MeetingTopChromeBar` est **purement présentationnelle** — son en-tête l'affirme et la
règle est tenue. La pastille ne l'entame pas :

| Composant | Rôle | Dépend de |
|---|---|---|
| `ParticipantShortlist` | fonction pure : construit la liste courte et son état de coche | `Collaborator` seul |
| `MeetingTopChromeBar` | affiche la pastille et le menu | reçoit la liste et deux closures |
| `MeetingView` | écrit | `addParticipant` / `removeParticipant`, **inchangés** |

Nouvelles entrées de `MeetingTopChromeBar` :

```swift
let participantChoices: [ParticipantChoice]   // nom + coché
let onToggleParticipant: (Collaborator) -> Void
let onManageParticipants: () -> Void
```

`MeetingView` les câble sur ce qui existe : `addParticipant(_:)` (qui pose déjà le statut
« présent »), `removeParticipant(_:)` (qui nettoie déjà le statut) et
`showParticipantsSheet = true`.

`ParticipantShortlist` est un `enum` namespace à fonctions statiques pures, comme les
autres services du dépôt :

```swift
/// Une ligne du menu : le collaborateur, et s'il est déjà participant.
struct ParticipantChoice: Identifiable {
    let collaborator: Collaborator
    let isParticipant: Bool
    var id: PersistentIdentifier { collaborator.persistentModelID }
}

static func compute(participants: [Collaborator],
                    directory: [Collaborator],
                    limit: Int = 12) -> [ParticipantChoice]

/// Libellé de la pastille : « + Qui ? », le nom, ou « N participants ».
static func label(for participants: [Collaborator]) -> String
```

## Tests

Sur `ParticipantShortlist`, sans interface :

- un participant **non épinglé** figure dans la liste, coché — sinon il devient impossible
  à retirer depuis la pastille ;
- les participants viennent avant les suggestions ;
- `pinLevel 2` avant `pinLevel 1`, chaque groupe trié par nom ;
- les archivés et les ad hoc de l'annuaire sont écartés des suggestions — mais un ad hoc
  **déjà participant** reste listé (règle 1) ;
- aucun doublon quand un participant est aussi épinglé ;
- le plafond s'applique aux suggestions, jamais aux participants.

`ParticipantShortlist.label(for:)` est testée sur ses trois états : aucun participant, un
seul (son nom), plusieurs (le compte).

Le câblage SwiftUI lui-même n'est pas testable en unitaire : il est couvert par un contrôle
à l'écran, ajouté à la liste de vérification.

## Hors périmètre (YAGNI)

- pas de recherche dans le menu — la feuille l'a déjà ;
- pas de création de participant ad hoc depuis la pastille ;
- pas de statut présent/refusé/en attente depuis la pastille ;
- pas de pastille « projet » : le projet est déjà dans le fil d'Ariane, et le rattacher est
  un autre geste, avec ses propres conséquences (statistiques, heatmap).

## Points laissés ouverts

- **Un 1:1 à deux interlocuteurs reste possible.** Le menu à coches n'impose pas la
  cardinalité 1 du type « One-to-One ». Arbitrage retenu : ne rien interdire ici, parce
  qu'un garde-fou qui retire quelqu'un sans le dire est pire que l'incohérence qu'il
  corrige. Si le besoin se confirme, ce sera un avertissement, pas un retrait automatique.
- **Aucun ordre par fréquence ou récence.** Il faudrait faire fauter la relation `meetings`
  de chaque collaborateur — 366 relations à l'ouverture d'un menu. `pinLevel` répond au
  besoin sans ce coût.
