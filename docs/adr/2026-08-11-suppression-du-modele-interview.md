# Suppression du modèle `Interview`

Date : 2026-08-11
Statut : accepté
Branche : `feat/suppression-interview`, partie de `feat/fusion-note-reunion`

## Contexte

Le dépôt porte **deux modèles de 1:1** :

- `Meeting` de kind `.oneToOne` — 18 lignes dans le store réel, en usage courant, avec
  audio, transcription, rapport, actions, thèmes et participants ;
- `Interview` — 7 lignes, la plus récente du 23 mai 2026, plus rien depuis.

La refonte de la fiche collaborateur (spec du 2026-08-11) fond réunions, notes, décisions et
actions en **un seul fil chronologique**. Un fil alimenté par deux modèles de 1:1 impose de
dédoubler chaque calcul qui s'y appuie : le retard depuis le dernier 1:1, les compteurs
d'en-tête, le graphe d'écart. La question ne pouvait pas rester ouverte.

## Ce que portent réellement les 7 lignes

Relevé sur le store réel le 2026-08-11, sur **les 17 champs** d'`Interview` :

| pk | date | heure | personne | contenu |
|---|---|---|---|---|
| 7 | 23/05 | 07:47:59 | PAOLI Nicolas | aucun |
| 6 | 23/05 | 07:48:00 | PAOLI Nicolas | aucun |
| 5 | 04/05 | 12:33:53 | THEDREZ Wilfried | aucun |
| 4 | 04/05 | 12:34:14 | THEDREZ Wilfried | aucun |
| 3 | 29/04 | 11:51:04 | ORSET Jean-Baptiste | aucun |
| 2 | 22/04 | 08:55:25 | THEDREZ Wilfried | aucun |
| 1 | 22/04 | 17:37:46 | THEDREZ Wilfried | aucun |

Aucune note, aucune évaluation, aucun champ de recrutement (CV, LinkedIn, points
positifs/négatifs), aucun projet, aucune alerte, aucun lien d'enregistrement, aucun fichier
source. Aucune action (`ActionTask.interview` : 0), aucune alerte rattachée
(`ProjectAlert.interview` : 0), aucune pièce jointe (`ZINTERVIEWATTACHMENT` : 0).

Leur seul contenu est « il s'est passé quelque chose avec cette personne, ce jour-là ». Et
trois d'entre elles doublent une réunion `.oneToOne` enregistrée avec la même personne à
moins de deux jours (23/05 Paoli, 04/05 Thedrez, 29/04 Orset).

## La cause

`CollaboratorDetailView.addInterview()` (`DetailsViews.swift:1101`) crée un `Interview` vide,
l'insère et le sauvegarde **immédiatement** :

```swift
let newInterview = Interview(date: Date(), notes: "")
newInterview.collaborator = collaborator
context.insert(newInterview)
saveContext()
```

Aucun éditeur ne s'ouvre, rien ne demande de contenu. Les écarts d'une seconde (pk 7/6) et
de vingt-et-une secondes (pk 5/4) sont des doubles déclenchements du bouton. Le modèle n'est
pas mort de désuétude : il est alimenté par un geste qui ne produit rien.

## Décision

**Supprimer `Interview` et `InterviewAttachment`**, ainsi que les relations
`ActionTask.interview` et `ProjectAlert.interview`. Le 1:1 devient `Meeting` de kind
`.oneToOne`, et lui seul.

Les 7 lignes disparaissent avec l'entité, par migration légère — sans `SchemaV2`, comme pour
`Note` et les entrées datées de projet, et pour la même raison : **il n'y a rien à
préserver**. Un `SchemaV2` avec stage de migration n'a de valeur que s'il porte des données
d'un schéma à l'autre ; ici la vérification champ par champ ci-dessus établit qu'il n'y en a
aucune. Le précédent du 2026-08-10 (quatre modèles supprimés sans `SchemaV2`) s'est vérifié
sur le store réel : les tables ont été retirées, les 162 réunions d'alors sont intactes.

Instruction de l'auteur, le 2026-08-11 : « Il faut les supprimer si on a rien dedans. » La
condition est vérifiée ci-dessus, exhaustivement.

## Correction du 2026-08-11 — `Interview` portait trois choses, pas une

La première version de cet ADR ne décrivait qu'un modèle mort. La lecture du code en a
montré **trois usages**, dont deux vivants :

1. **le 1:1 mort** — les 7 lignes vides décrites plus haut ;
2. **l'import de documents** — `AIIngestionService.applyExtractedData` créait un `Interview`
   de type « Import PDF » / « Import PPTX » pour recevoir le texte extrait, et cet objet
   servait d'**ancre au retour arrière** de l'import (`lastImportReceipt`, `canRollback`) ;
3. **le recrutement** — `analyzeCandidateFile`, les champs CV / LinkedIn / points
   positifs-négatifs / évaluation, et un export markdown dédié (`InterviewType.job`).

Aucune ligne des types « import » ou « job » n'existe dans le store : ces deux chemins n'ont
rien laissé. Mais supprimer le modèle sans les repointer aurait cassé le retour arrière de
l'import — une régression, pas un nettoyage.

**Règle retenue, énoncée par l'auteur :** *« Une interview n'est pas plus qu'un meeting avec
une préparation. On pourra le tagger Interview pour rechercher tous les interviews. »*

Elle tranche les trois cas d'un coup, sans modèle intermédiaire :

- l'import produit désormais un **reçu** : une note (`Meeting` kind `.note`) titrée du
  fichier, portant le texte extrait, **tagguée « Import »** — donc listée, cherchable dans
  Spotlight et dans l'assistant, ce que l'`Interview` invisible n'était pas ;
- le recrutement, quand il reviendra, sera une réunion avec préparation, tagguée. Rien à
  migrer : aucune ligne de ce type n'existe ;
- le 1:1 est un `Meeting` de kind `.oneToOne`.

Le thème (`MeetingTag`) remplace le type d'entretien : un filtre, pas une classe.

## Conséquences

- `InterviewView` disparaît — **1 209 lignes**, la plus grosse vue du dépôt après
  `MeetingView`. Avec elle partent les champs de recrutement (CV, LinkedIn, évaluation) qui
  n'ont d'équivalent nulle part dans `Meeting`.
- **Si un entretien de recrutement doit être suivi un jour**, ce sera un kind de `Meeting`
  ou un modèle neuf, conçu pour ça — pas la réanimation de celui-ci, dont l'écran n'a rien
  produit en quatre mois.
- **Format de sauvegarde** : `BackupService` sérialise et restaure les entretiens. La clé
  `interviews` d'une sauvegarde ancienne est désormais **ignorée** à la restauration, sans
  erreur. Perdre une ligne vide n'est pas une perte ; échouer à restaurer le reste en
  serait une.
- **L'import garde son reçu et son retour arrière**, sous forme de note tagguée (cf. la
  correction ci-dessus). C'est la seule fonction vivante qui dépendait du modèle.
- Treize fichiers source et cinq fichiers de test citent `Interview` : la suppression se
  fait par étapes, lecteurs d'abord, modèle en dernier, chaque étape vérifiée.
- Le bouton qui produisait ces lignes disparaît avec la vue. La fiche collaborateur v3 ne
  le réintroduit pas : elle propose « Créer le premier 1:1 », qui ouvre une réunion.

## Alternatives écartées

- **Convertir les 7 en réunions 1:1.** Trois auraient doublé une réunion déjà présente,
  ajoutant au fil exactement le bruit que la refonte veut supprimer, pour ne rien porter.
- **Garder `Interview` hors du fil.** Deux notions de 1:1 continueraient de coexister, et
  chaque calcul de la fiche aurait dû choisir laquelle compter — ou les deux.
- **Convertir seulement les deux du 22/04**, sans réunion en face. Elles ne portent qu'une
  date et une heure ; la réunion créée serait vide, donc invisible dans un fil qui masque
  ce qui n'a rien produit.
