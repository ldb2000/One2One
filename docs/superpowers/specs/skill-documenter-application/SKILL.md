---
name: documenter-application
description: Utiliser quand le code documenté d'un projet a changé et que /docs doit être réaligné, quand un test de documentation est rouge (test rouge : manifeste, ADR, chemin, symbole), ou quand un hook signale un écart de documentation (chemin ou symbole cité qui n'existe plus, modèle persisté ajouté sans mention, PR touchant un dossier listé dans docs/documentation.yml).
---

# Documenter l'application (documentation développeur, en français)

## Principe

La documentation doit être **vraie**, pas exhaustive : réalignée **par section**, jamais
régénérée ; des tests la rendent fausse bruyamment.

## La règle de placement

| Le fait | Sa place |
| --- | --- |
| Un service | section Services |
| Une vue | section Vues |
| Une décision et ses conséquences | un ADR |
| Un changement (quoi, quand) | le journal — jamais la documentation |

## Ce qu'est une section

Un état, au présent, sans date ni historique : (1) **ce que fait** le composant, (2) **où il
vit** (chemins vérifiés — `test -e`), (3) **ce qui le garde** (le test), (4) **ce à quoi il se
relie** (`voir §n` — jamais `STATUS.md`, un journal, une PR).

## Méthode

1. **Lire le manifeste** `docs/documentation.yml` (`references/manifeste.md`). Absent → le
   proposer, s'arrêter.
2. **Calculer l'écart, sans écrire** : `git diff --name-only <branche_principale>...HEAD` croisé
   avec les sections concernées, symboles orphelins, modèles persistés changés, décision sans
   ADR. Lister avant toute modification.
3. **Mettre à jour par section**, à sa place (table ci-dessus). Vérifier chemin et symbole avant
   de l'écrire.
4. **Relire le document entier**, pas seulement la section touchée.
5. **Vérifier** : commande `tests` du manifeste ; relire avec `references/regles-de-redaction.md`.
6. **Proposer un ADR** (« proposé ») pour une décision sans trace ; un ADR validé se supersède,
   jamais ne s'édite.
7. **Consigner** : un commit `docs(...)` par document ; un paragraphe « Documentation » en PR
   (réaligné, à trancher) ; régénérer les documents que le manifeste déclare générés (clé
   `genere_par:`).

## Garde-fous

- Pas de régénération ; une section se corrige en place, elle ne se supprime pas.
- `CLAUDE.md`, `docs/superpowers/`, un ADR validé : intouchables.
- Chemin ou symbole cité sans vérification → interdit.

## Erreurs fréquentes

| Faute | Correction |
| --- | --- |
| Service documenté en section Vues, par proximité | Un service va en Services |
| Narration façon journal des modifications | Décrire l'état présent, pas l'histoire |
| Ligne de « mise à jour » en pied de document | Journal des modifications interdit ici |
| Renvoi « Voir `STATUS.md` » | Renvoyer vers une section ou un ADR |
| Même explication écrite dans deux documents | Renvoyer (`voir §n`), ne pas dupliquer |
| Paragraphe de 14 lignes pour un compteur | Quatre éléments, pas le détail d'une PR |
| Incohérence laissée entre deux sections | Relire le document entier après modification |
| Index absent, non signalé | Proposer l'index : une ligne par document, public visé |
