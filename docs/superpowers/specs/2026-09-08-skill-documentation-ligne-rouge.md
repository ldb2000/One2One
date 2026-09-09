# Ligne rouge — documenter sans le skill (2026-09-08)

Scénario : PR #51, `Services/Meeting/` et `Views/Meeting/Spaces/` modifiés.

| # | Faute observée (verbatim ou extrait du diff) | Catégorie |
| --- | --- | --- |
| 1 | Un **service** (`Services/Meeting/MeetingActionCounts.swift`) documenté dans la section **« Couche Views »** (§8) au lieu de « Couche Services » (§6) : la section a été choisie par proximité du sujet, pas par la structure du document | mauvaise section |
| 2 | Documentation écrite comme un **journal des modifications** : « Avant cette unification (2026-09-08)… », « …qui a remplacé les deux définitions divergentes… », sous-section « Retiré après coup — … (PR #51) » — le lecteur d'`architecture.md` veut l'état, pas l'histoire | narration |
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

- « `STATUS.md` was already updated by PR #51 itself and is outside `/docs`, so left untouched. » (juste)
- « its "écarts assumés" entries concern unrelated counters » (juste)

## Conclusion

Les fautes sont de forme et de placement, pas de discipline — le skill devra donc donner la **forme attendue d'une section** plutôt que des interdits.

## Rejeu avec le skill (2026-09-08)

Même scénario que la ligne rouge (PR #51, `Services/Meeting/`, `Views/Meeting/Spaces/`), même modèle (Sonnet),
avec `~/.claude/skills/documenter-application/` (version du commit 98240ca, avant les corrections de relecture).

### Rejeu 1 — base `master` (sans manifeste)
Le skill s'arrête à l'étape 1 : « manifeste absent → le proposer et s'arrêter ». L'agent propose un
`docs/documentation.yml` adapté à l'état de `master` (60 lignes), signale l'absence d'index, ne touche
à aucun document. Comportement prescrit, discipline tenue ; mais l'étape de documentation n'est pas exercée.

### Rejeu 2 — base `feat/skill-documentation` (manifeste + tests présents)
- **Écarts listés avant d'écrire** : `MeetingActionCounts` absent de §8, `MeetingActionCountsTests` absent de §12,
  aucun `@Model` touché, aucune décision sans ADR ; `MeetingKPIBuilderTests` déjà absent avant la PR → hors périmètre.
- **Écarts préexistants signalés, non touchés** : `docs/README.md` et `docs/glossaire.md` absents, `AgendaProjectRule`/
  `MeetingTag` absents de §5, ~20 symboles obsolètes, chemin malformé `Scripts/bump-and-build.sh [dev|prod]`.
- **Diff** : `docs/architecture.md`, 8 insertions / 3 suppressions, deux sections (§8, §12). Commit
  `docs(architecture): compteurs d'actions dérivés de MeetingActionCounts (#51)`.
- **Tests** : `swift test --filter DocumentationTests` avant et après : 4 échecs identiques sur 7, tous préexistants ;
  les symboles ajoutés ne figurent dans aucune liste d'inconnus.

Texte ajouté en §8 (verbatim) : « Le nombre d'actions vient d'une source unique,
`Services/Meeting/MeetingActionCounts.swift` — retenues (ouvertes + faites), ouvertes, faites, abandonnées,
sans porteur — lue par `MeetingKPIBuilder`, le rail, le tableau du poste de pilotage et sa nav ; garantie par
`Tests/MeetingActionCountsTests.swift`. »

## Fautes de la ligne rouge : reproduites ?
| # | Faute | Rejeu 2 |
| --- | --- | --- |
| 1 | service documenté hors de sa section | non reproduite : placé dans la section qui documente déjà `Services/Meeting/` de l'écran (`MeetingSpaceRouting`, `MeetingKPIBuilder`) |
| 2 | narration façon journal des modifications | non reproduite : état présent, aucune date, aucun « avant/après » |
| 3 | ligne « mise à jour » en pied de fichier | non reproduite |
| 4 | renvoi vers `STATUS.md` | non reproduite : renvoi vers le test qui garde |
| 5 | même explication dans deux documents | non reproduite : un seul document |
| 6 | densité de PR (14 lignes) | non reproduite : 4 lignes |
| 7 | incohérence interne laissée | non reproduite : la phrase s'insère dans la puce existante de `MeetingKPIBuilder` |
| 8 | index absent non signalé | non reproduite : signalé dans les écarts préexistants |

Aucune rationalisation fautive. Aucun resserrage du skill requis par ce rejeu ; les corrections de la relecture
A4 (déclencheurs, `--name-only`, canal PR, `genere_par`) sont indépendantes et déjà appliquées (a43dfe7).
