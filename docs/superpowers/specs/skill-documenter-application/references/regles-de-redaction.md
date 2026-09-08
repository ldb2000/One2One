# Règles de rédaction de la documentation développeur

## Langue
- Prose, titres, libellés : **français**. Symboles, chemins, commandes : anglais, entre accents graves.
- Dates **absolues** (2026-09-08), jamais « hier », « récemment », « la semaine dernière ».
- Nombres et mesures dans des tableaux, pas dans la prose.

## Ce qui est de la documentation, et ce qui ne l'est pas
| Est de la documentation | N'en est pas (va ailleurs) |
| --- | --- |
| Ce que fait un sous-système, où il vit, ce qui le garde (test) | Le récit d'une session (→ journal, STATUS) |
| Une décision et ses conséquences (→ ADR) | La consigne à l'agent (→ CLAUDE.md) |
| Un flux de bout en bout | Un plan d'implémentation (→ superpowers/plans) |

## Forme
- Une section = un sujet ; titre stable (listé dans le manifeste) ; on corrige en place.
- Chaque sous-système cite ses fichiers (chemins cliquables) et le test qui le garde.
- Un chemin cité existe. Un symbole cité a une déclaration. Un ADR cité existe.
- Pas de duplication entre documents : on renvoie (`voir §5`).
- Diagramme (Mermaid) seulement s'il montre un mécanisme ; jamais pour lister.

## Vérification avant commit
1. `test -e <chemin>` pour chaque chemin ajouté.
2. `grep -rn "\b\(struct\|class\|enum\|actor\|protocol\)\s\+<Symbole>\b" <sources>` pour chaque symbole ajouté.
3. La commande `tests` du manifeste est verte.
4. L'index référence le document.
