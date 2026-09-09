# ADR — Architecture Decision Records

Ce dossier contient les décisions d'architecture validées du projet OneToOne.

## Convention de nommage

Les fichiers sont datés et nommés selon le format :

```text
YYYY-MM-DD-titre-court.md
```

Exemple :

```text
2026-08-08-source-de-verite-markdown.md
```

## Contenu attendu

Chaque ADR doit préciser au minimum :

- le contexte et le problème à résoudre ;
- la décision retenue ;
- les alternatives étudiées ;
- les conséquences positives et négatives ;
- le statut et la date de validation.

Une décision structurante doit être proposée avant d'être inscrite. Une ADR validée ne doit pas être modifiée silencieusement : si la décision évolue, créer une nouvelle ADR qui référence l'ancienne.

## Index

Les décisions validées, de la plus récente à la plus ancienne.

| Date | Décision | Sujet |
|---|---|---|
| 2026-09-09 | [Un routeur pour la fenêtre principale](2026-09-09-routeur-de-navigation.md) | `MainRoute` / `MainRouter` / `MainDetailView` : la barre latérale sélectionne une route (D0) |
| 2026-09-09 | [⌘K va à la palette, l'assistant passe à ⌘⇧K](2026-09-09-palette-commande-k.md) | `AppShortcut` : la table des raccourcis sort de l'écran de réunion (D1) |
| 2026-09-08 | [Refonte de l'écran de réunion — bilan des décisions D0 à D11](2026-09-08-refonte-ecran-reunion-bilan.md) | les vingt lots de la refonte : décisions telles qu'appliquées, écarts assumés avec les maquettes, dettes |
| 2026-09-07 | [Moteur de planches : Excalidraw embarqué](2026-09-07-moteur-de-planches-excalidraw-embarque.md) | `WKWebView` + bundle local inliné plutôt qu'un moteur natif (D6) |
| 2026-09-07 | [Pièces copiées, jamais référencées](2026-09-07-pieces-copiees-jamais-referencees.md) | politique unique de stockage des fichiers déposés (D5) |
| 2026-09-05 | [Niveau de raisonnement configurable](2026-09-05-raisonnement-configurable.md) | réglage par profil, et ce que chaque endpoint honore réellement |
| 2026-09-05 | [Catalogues IA et retrait de Direct](2026-09-05-catalogues-ia-retrait-direct.md) | migration des anciens profils Direct vers LM Studio |
| 2026-09-05 | [Endpoints IA configurables](2026-09-05-endpoints-ia-configurables.md) | profils, Trousseau, transport compatible OpenAI |
| 2026-09-05 | [RAG — inventaire du pipeline](2026-09-05-rag-pipeline-inventaire.md) | indexation, recherche hybride, embeddings |
| 2026-09-02 | [Capture de slides : polling et empreinte](2026-09-02-capture-slides-polling-empreinte.md) | détection par différence d'image (précurseur de D7) |
| 2026-08-11 | [Suppression du modèle `Interview`](2026-08-11-suppression-du-modele-interview.md) | les entretiens deviennent des `Meeting` d'un `kind` donné |
| 2026-08-08 | [Réécriture de l'éditeur, architecture inspirée d'AppFlowy](2026-08-08-reecriture-editeur-architecture-appflowy.md) | conception reprise, aucun code |
| 2026-08-08 | [Verdict du prototype de blocs AppKit](2026-08-08-verdict-prototype-blocs-appkit.md) | le markdown reste la source de vérité |

