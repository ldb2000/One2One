---
name: documenter-application
description: Utiliser quand le code documenté d'un projet a changé et que /docs doit être réaligné, ou quand un hook signale un écart de documentation (chemin ou symbole cité qui n'existe plus, modèle persisté ajouté sans mention, PR touchant un dossier listé dans docs/documentation.yml).
---

# Documenter l'application (documentation développeur, en français)

## Principe

La documentation doit être **vraie**, pas exhaustive : on la réaligne **par section**, jamais en
la régénérant, et des tests la rendent fausse bruyamment.

## Hors périmètre

Documentation utilisateur, `CLAUDE.md` : jamais.

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
2. **Calculer l'écart, sans écrire** : `git diff <branche_principale>...HEAD` croisé avec les
   sections concernées, les symboles orphelins, les modèles persistés changés, une décision sans
   ADR. Lister avant toute modification.
3. **Mettre à jour par section**, à sa place (table ci-dessus). Vérifier chaque chemin et
   symbole avant de l'écrire.
4. **Relire le document entier**, pas seulement la section touchée.
5. **Vérifier** : commande `tests` du manifeste ; relire avec `references/regles-de-redaction.md`.
6. **Proposer un ADR** (« proposé ») pour une décision sans trace ; un ADR validé se supersède,
   ne s'édite jamais.
7. **Consigner** : un commit `docs(...)` par document ; régénérer `docs/decisions.md` via le
   script du manifeste.

## Garde-fous

- Régénérer un document, supprimer une section sans écart avéré → interdit.
- Toucher `CLAUDE.md`, `docs/superpowers/`, un ADR validé → interdit.
- Citer un chemin ou symbole non vérifié → interdit.
- Index absent → à signaler.

## Erreurs fréquentes (observées lors de la ligne rouge)

| Faute | Correction |
| --- | --- |
| Service documenté en section Vues, par proximité | Un service va en Services |
| Narration façon changelog (« avant cette unification… ») | Décrire l'état présent, pas l'histoire |
| Ligne de « mise à jour » en pied de document | Aucun changelog dans la doc : ça va au journal |
| Renvoi « Voir `STATUS.md` » | Renvoyer vers une section ou un ADR |
| Même explication écrite dans deux documents | Renvoyer (`voir §n`), ne pas dupliquer |
| Paragraphe de 14 lignes pour un compteur | Quatre éléments, pas le détail d'une PR |
| Incohérence laissée entre deux sections | Relire le document entier après modification |
| Index absent, non signalé | Signaler l'absence d'index |
