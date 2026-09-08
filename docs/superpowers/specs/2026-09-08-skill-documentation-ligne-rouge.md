# Ligne rouge — documenter sans le skill (2026-09-08)

Scénario : PR #51, `Services/Meeting/` et `Views/Meeting/Spaces/` modifiés.

| # | Faute observée (verbatim ou extrait du diff) | Catégorie |
| --- | --- | --- |
| 1 | Un **service** (`Services/Meeting/MeetingActionCounts.swift`) documenté dans la section **« Couche Views »** (§8) au lieu de « Couche Services » (§6) : la section a été choisie par proximité du sujet, pas par la structure du document | mauvaise section |
| 2 | Documentation écrite comme un **journal des modifications** : « Avant cette unification (2026-09-08)… », « …qui a remplacé les deux définitions divergentes… » | narration |
| 3 | **Ligne de « mise à jour » en pied de fichier** ajoutée sous une ligne du même type : le document accumule un changelog qui ne dit rien de l'architecture | narration / duplication avec le journal |
| 4 | Renvoi « **Voir `STATUS.md`** » depuis la documentation : renvoie vers un compte rendu de session, qui sera réécrit | périmètre |
| 5 | **Même explication écrite deux fois** (§8 d'`architecture.md` et §8 de `cleanup-report.md`) | duplication |
| 6 | Paragraphe de 14 lignes pour un service de comptage : niveau de détail d'une PR, pas d'une architecture (les sept surfaces branchées, le bug corrigé) | densité |
| 7 | Aucune vérification que le document reste cohérent ailleurs : `MeetingKPIBuilder` est cité en §8 comme calculant `actions` ; le texte ajouté dit qu'il « délègue » — deux phrases contradictoires à 10 lignes d'écart | incohérence interne |
| 8 | Pas d'index (`docs/README.md` n'existe pas) : non signalé | omission |

## Ce qu'il a bien fait

- Français
- Aucune régénération
- `CLAUDE.md` et ADR non touchés
- Chemins vérifiés
- Commit sur une branche
- Rapport avec diff

## Rationalisations exprimées par l'agent (verbatim)

- « `STATUS.md` was already updated by PR #51 itself and is outside `/docs`, so left untouched. »
- « its "écarts assumés" entries concern unrelated counters »

## Conclusion

Les fautes sont de forme et de placement, pas de discipline — le skill devra donc donner la **forme attendue d'une section** plutôt que des interdits.
