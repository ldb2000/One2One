# Le manifeste `docs/documentation.yml`

Il rend le skill générique : les faits du projet y vivent, versionnés avec le code.

| Clé | Rôle |
| --- | --- |
| `langue` | langue de la prose (`fr`) |
| `branche_principale` | base du `git diff` de l'étape 2 |
| `tests` | commande qui vérifie la documentation (ex. `swift test --filter DocumentationTests`) |
| `code_documente` | dossiers/fichiers dont un changement déclenche le réalignement (lus par le hook) |
| `symboles_externes` | types système, modules SwiftPM, termes d'interface cités dans la doc sans déclaration dans les sources — hors préfixes de frameworks (NS, UI, CG, CF, AV, WK, SC, CT, EK, CN, UN, AX, MLX), déjà exclus par le test ; chaque entrée est un choix conscient |
| `documents[].chemin` | document tenu ; `public` ; `role` ou `sections` (titres stables de niveau 2) |
| `documents[].genere_par` | optionnel : script qui régénère ce document (ex. `Scripts/generer-decisions.py`) — seul cas où une régénération complète est légitime |
| `verites` | sources que les tests confrontent aux documents (schéma des modèles, dossier des ADR) |
| `hors_perimetre` | ce que le skill ne touche jamais |

Sous-ensemble YAML lu par les tests : clés simples, listes de chaînes, listes d'objets. Pas d'ancres,
pas de multi-lignes.

## Exemple (OneToOne)

```yaml
langue: fr
branche_principale: master
tests: swift test --filter DocumentationTests
code_documente:
  - OneToOne/Models/
  - OneToOne/Services/

# Types système, modules SwiftPM et termes d'interface cités dans la doc et qui n'ont pas de
# déclaration dans les sources ; chaque entrée est un choix conscient.
symboles_externes:

documents:
  - chemin: docs/README.md
    public: tous
    role: index
  - chemin: docs/architecture.md
    public: développeur
    sections:
      - "1. Présentation"
  - chemin: docs/decisions.md
    public: développeur
    genere_par: Scripts/generer-decisions.py
verites:
  modeles_persistes: OneToOne/Models/SchemaVersions.swift
  adr: docs/adr/
hors_perimetre:
  - CLAUDE.md
```

Une entrée dans `symboles_externes` déclare un symbole cité qu'on assume sans déclaration source
(type Apple, module tiers, terme d'interface) : le test des symboles ne le signale plus comme
inconnu. Ajouter une entrée est un choix conscient à faire au moment du réalignement, pas un
réflexe pour faire taire un test rouge.

## Proposer un manifeste à un projet qui n'en a pas
Repérer : la branche principale, le dossier de documentation, les dossiers de code que la documentation
décrit, la commande de tests. Écrire le fichier, l'expliquer à l'auteur, s'arrêter : le premier
réalignement se fait à la PR suivante.
