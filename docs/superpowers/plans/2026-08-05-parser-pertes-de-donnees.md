# Parser markdown — trois pertes de données

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Arrêter trois pertes de données mesurées sur les notes réelles de l'utilisateur, avant toute bascule d'éditeur.

**Architecture:** `MarkdownParser` ignore les nœuds qu'il ne modélise pas (`Table`, `HTMLBlock`) et les efface. On les conserve en *passthrough* : un run porteur du source littéral, réémis tel quel — même mécanisme que les blocs fencés. L'imbrication des listes et l'état des cases à cocher sont deux défauts distincts de `emitList`.

**Tech Stack:** Swift 6, AppKit (TextKit 1), `swift-markdown` (Apple), XCTest.

**Origine :** mesure du 2026-08-05 sur la base réelle (162 réunions, 122 notes non vides). Sauvegarde préalable dans `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`.

---

## Pourquoi ce plan passe avant la bascule d'éditeur

L'utilisateur a demandé de basculer les écrans **Préparation** et **Notes live** du moteur tiers `MarkdownEngine` vers le module maison. Une mesure préalable a montré que le module détruit des données, et qu'il le fait **déjà aujourd'hui** sur un écran migré de longue date.

`MeetingView.swift:976` (rapport de réunion) utilise le module. `applyInitialState` ne fait que parser, mais `textDidChange` sérialise **tout le tampon** et pousse dans SwiftData. Un tableau est donc invisible dès l'ouverture en édition, et **une seule frappe le détruit définitivement**.

Chiffres mesurés sur les données réelles :

| Champ | notes non vides | altérées sémantiquement |
|---|---|---|
| `summary` (rapports, **déjà sur le module**) | 68 | **15** |
| `liveNotes` (candidat à la bascule) | 48 | 4 |
| `prepNotes` (candidat à la bascule) | 6 | 1 |

1 078 mots perdus sur 33 623 (3,21 %), concentrés sur 9 notes — **exactement** les 9 qui contiennent un tableau GFM. Zéro bloc HTML, zéro note de bas de page, zéro titre d'image dans les données réelles.

Cas le plus lourd : `liveNotes` pk=158, débrief de 10 926 caractères, 4 tableaux, **299 mots supprimés (20,4 %)**.

## Les trois défauts

**1. Tableaux GFM et blocs HTML effacés.** `MarkdownParser.emit` (`MarkdownParser.swift:44-62`) a un `default:` qui descend dans `markup.children`. Pour un `Table`, les enfants sont des lignes puis des cellules dont le contenu est *inline* — or seul `emitBlock` émet de l'inline. La récursion traverse donc tout sans rien produire. Sortie : chaîne vide.

**2. Imbrication des listes aplatie.** `parse("- a\n  - b\n    - c")` → `"- a\n- b\n- c"`. Tous les niveaux collapsent. 14 notes concernées.

**3. État des cases à cocher imbriquées falsifié.** `parse("- [x] a\n  - [ ] b\n- [x] c")` ressort avec `b` **cochée**. Une tâche non faite devient faite — le défaut ment sur les données sans rien effacer, ce qui le rend plus dangereux qu'une perte visible.

## File map

| Chemin | Action |
|---|---|
| `OneToOne/Markdown/Markdown/MarkdownParser.swift` | modifier |
| `OneToOne/Markdown/Markdown/MarkdownSerializer.swift` | modifier |
| `OneToOne/Markdown/Model/MarkdownAttributeKeys.swift` | modifier |
| `Tests/MarkdownRoundTripTests.swift` | modifier |
| `Tests/MarkdownParserTests.swift` | modifier |

---

### Task 1 : tableaux et blocs HTML en passthrough

Le plus grave, et le seul qui répare les 15 rapports déjà exposés.

- [ ] **Step 1 : mesurer l'état actuel**

Écris un test temporaire qui parse puis sérialise :

```
| A | B |
|---|---|
| 1 | 2 |
```

et

```
<div>
bloc
</div>
```

Confirme la chaîne vide en sortie, et rapporte ce que produit réellement `MarkdownParser.parse` (longueur, runs, attributs) pour chacun. Supprime le test ensuite.

- [ ] **Step 2 : fixtures d'aller-retour (rouge)**

Ajoute à `Tests/MarkdownRoundTripTests.swift` une fixture tableau et une fixture bloc HTML. Lance, confirme l'échec, rapporte les messages exacts. Committe le test rouge séparément.

- [ ] **Step 3 : implémenter le passthrough**

Même mécanisme que les blocs fencés, déjà en place : un run unique portant le **source littéral** dans un attribut, réémis tel quel à la sérialisation.

`swift-markdown` expose `Markup.format()`, qui reconstitue le markdown d'un nœud. **Vérifie ce qu'il rend exactement** pour un `Table` et un `HTMLBlock` — notamment s'il normalise l'alignement des colonnes. Si `format()` ne convient pas, la plage source (`markup.range`) est une alternative ; dis ce que tu as choisi et pourquoi.

Ajoute les cas `Table` et `HTMLBlock` à `MarkdownParser.emit`, un type de bloc dédié dans `BlockType`, et le cas symétrique dans `MarkdownSerializer`.

**Le contenu doit survivre même si le rendu ne le comprend pas.** Un tableau affiché en texte brut monospace est acceptable ; un tableau effacé ne l'est pas.

- [ ] **Step 4 : vérifier sur les données réelles**

Fais passer les 122 notes de `~/Documents/OneToOne-sauvegarde-notes-2026-08-05/notes/` dans l'aller-retour et compare avant/après. Rapporte combien divergent encore, et sur quoi.

C'est le seul test qui compte vraiment : les fixtures prouvent le mécanisme, les vraies notes prouvent le résultat.

- [ ] **Step 5 : mutation, puis commit**

---

### Task 2 : imbrication des listes

- [ ] **Step 1 : mesurer**

`parse("- a\n  - b\n    - c")` — quel `level` porte chaque item ? Le défaut est-il dans `emitList` (`MarkdownParser.swift:104-136`) qui calcule mal `listNesting`, ou dans le sérialiseur qui ignore `level` ? Mesure avant de corriger.

- [ ] **Step 2 : fixtures rouges, puis correctif, puis vérification sur les 122 notes réelles**

Attention : `MarkdownSerializer.prefix(for:)` indente déjà de deux espaces par niveau. Si le niveau est correct côté parser, le défaut est ailleurs.

---

### Task 3 : état des cases à cocher imbriquées

- [ ] **Step 1 : mesurer**

`parse("- [x] a\n  - [ ] b\n- [x] c")` — d'où vient le `checked` de `b` ? `emitList` propage-t-il l'état du parent, ou lit-il le mauvais nœud ?

- [ ] **Step 2 : fixture rouge, correctif, vérification sur les 122 notes**

Ce défaut **falsifie** une donnée au lieu de l'effacer. Une fixture ne suffit pas : vérifie sur les notes réelles qu'aucune case ne change d'état après aller-retour, et rapporte le chiffre.

---

## Règles de travail

- **Ne touche aucun fichier hors de ta tâche.** `K8s_Monitor_Prototype.html` à la racine et `CLAUDE.md` sont modifiés par l'utilisateur : n'y touche pas, ne les supprime pas, ne les commite pas.
- **Ne modifie jamais la base de données de l'utilisateur** ni la sauvegarde dans `~/Documents/`. Lecture seule stricte.
- L'état de `git status` est un **constat**, jamais un objectif.
- N'amende aucun commit existant.
- N'écris aucun commentaire dont tu n'as pas vérifié le contenu.
- Un test vert ne prouve rien : après chaque correctif, neutralise-le et vérifie qu'un test échoue.
- Si un test existant s'oppose à ton correctif, demande-toi lequel des deux a tort et **mesure** avant de trancher.

## Échecs préexistants — ne pas traiter ni masquer

`MenuBarStatsTests.test_badge_twelve_compact` et `test_todayStats_passedOnlyAndNoProject` (sensible à l'heure), crash `CalendarImportEventTests` (utiliser `swift test --skip CalendarImportEventTests`), `TranscriptEditServiceTests.test_delete_shiftsLaterSegmentsByRemovedDuration` (flaky).

## Ce que ce plan ne couvre pas

- **La bascule d'éditeur** elle-même — objet du plan suivant, une fois ces trois correctifs faits et vérifiés sur les données réelles.
- Les autres pertes mesurées, moins graves et absentes des données réelles : titres d'image, notes de bas de page, `<autolien>` réécrit, échappement agressif des parenthèses et crochets, citations aplaties, continuation de paragraphe dans un item.
- Le menu `/` n'expose ni tableau ni bloc de code — à revoir une fois le passthrough en place.
