# Skill « documenter-application » — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un skill utilisateur générique qui réaligne la documentation développeur de `/docs` sur le code après chaque PR touchant du code documenté, gardé par des tests `swift test` et déclenché par un hook.

**Architecture:** Trois pièces découplées. Le **skill** (`~/.claude/skills/documenter-application/`) porte la méthode en cinq étapes et ne connaît aucun fait du projet. Le **dépôt** porte les faits : un manifeste `docs/documentation.yml`, les documents tenus, un générateur de registre des ADR et `Tests/DocumentationTests.swift` qui fait échouer la suite quand la documentation cite un chemin, un symbole ou un modèle qui n'existe plus. Le **hook** `PostToolUse` détecte une création de PR ou un push touchant les dossiers documentés et injecte à l'agent la consigne de lancer le skill ; il n'écrit rien.

**Tech Stack:** Swift Testing (suites en français, lecture des sources par `#filePath`), SwiftData (`CurrentSchema.models`), python3 (générateur de registre, parsing JSON du hook), zsh, Claude Code hooks (`PostToolUse`, `additionalContext`), format de skill agentskills.io (`SKILL.md` + `references/`).

**Spec:** `docs/superpowers/specs/2026-09-08-skill-documentation-design.md`

## Global Constraints

- Public développeur seulement (spec D1). Aucune documentation utilisateur.
- Skill dans `~/.claude/skills/documenter-application/` ; **aucun fait propre à OneToOne dans le skill** (spec D2) : les faits vont dans `docs/documentation.yml`.
- Mise à jour **par section**, jamais par régénération d'un document (spec D4). Exception unique : `docs/decisions.md`, registre **généré** par script.
- Le skill ne touche ni `CLAUDE.md` ni un ADR validé (spec D6).
- Fabrication en TDD de skill (spec D7) : ligne rouge **avant** d'écrire le skill ; tests de documentation **rouges** avant le réalignement de `/docs`.
- Description du skill = déclencheur seulement, en troisième personne, sans résumé de méthode (règle du skill `superpowers:writing-skills`).
- Conventions du dépôt : branche par tâche, PR obligatoire, jamais de commit sur `master` ; commits conventionnels ; libellés et commentaires en français, symboles en anglais ; `swift test` avant la PR ; `STATUS.md` mis à jour en fin de session.
- Aucune dépendance SwiftPM nouvelle (pas de bibliothèque YAML : le parsing du manifeste se limite au sous-ensemble utilisé).
- Le premier `swift build` compile les dépendances MLX : 10–20 min ; tests ciblés avec `swift test --filter DocumentationTests`.

---

## Carte des fichiers

| Fichier | Rôle | Tâche |
| --- | --- | --- |
| `docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md` | fautes observées sans le skill (verbatim) | A1 |
| `docs/documentation.yml` | manifeste : langue, branche, dossiers documentés, documents, vérités, hors périmètre | A2 |
| `Tests/DocumentationTests.swift` | six tests + parseur minimal du manifeste | A2 |
| `Scripts/generer-decisions.py` | `docs/decisions.md` depuis les en-têtes des ADR | A3 |
| `~/.claude/skills/documenter-application/SKILL.md` | méthode, garde-fous, erreurs fréquentes | A4 |
| `~/.claude/skills/documenter-application/references/regles-de-redaction.md` | style, symboles, tableaux, journal vs documentation | A4 |
| `~/.claude/skills/documenter-application/references/manifeste.md` | format du manifeste, exemple | A4 |
| `docs/README.md`, `docs/architecture.md`, `docs/decisions.md`, `docs/glossaire.md` | documents tenus, réalignés | A6 |
| `~/.claude/hooks/documentation-apres-pr.sh` | détecteur PostToolUse | B1 |
| `~/.claude/settings.json` | enregistrement du hook | B2 |
| `STATUS.md` | fin de session | B4 |

---

## Partie A — le skill et les tests de documentation (session 1)

### Task A1 : Ligne rouge — observer l'agent sans le skill

**Files:**
- Create: `docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md`

**Interfaces:**
- Produces: la liste des fautes verbatim qui dicte le contenu de `SKILL.md` (Task A4) et la table « Erreurs fréquentes ».

- [ ] **Step 1 : Créer la branche de travail**

```bash
git checkout master && git pull --ff-only && git checkout -b feat/skill-documentation
```

- [ ] **Step 2 : Lancer un sous-agent SANS le skill sur le scénario réel**

Dispatcher un agent `general-purpose` (worktree isolé, modèle au choix) avec exactement ce prompt, sans lui donner accès à la spec ni au skill :

```
Dans le dépôt /Users/laurent.deberti/Documents/dev/perso/OneToOne (branche master), la PR #51
« compteurs d'actions dérivés des données » a modifié OneToOne/Services/Meeting/ (nouveau
fichier MeetingActionCounts.swift, MeetingKPIBuilder.swift modifié) et OneToOne/Views/Meeting/Spaces/.
Mets la documentation développeur de /docs à jour en conséquence. Travaille dans un worktree,
sur une branche, commite, ne pousse pas. Rapport final : fichiers modifiés et résumé des changements.
```

- [ ] **Step 3 : Relire son diff et noter chaque faute, verbatim**

Vérifier au moins : a-t-il régénéré un document entier ? cité un chemin ou un symbole inexistant (contrôler chaque `` `…` `` par `test -e` / `grep -rn "struct|class|enum X"`) ? écrit en franglais ou en anglais ? raconté la session (« dans cette PR nous avons… ») ? touché `CLAUDE.md` ou un ADR ? ignoré `docs/README.md` (inexistant) ? oublié le journal ? Consigner dans le fichier :

```markdown
# Ligne rouge — documenter sans le skill (2026-09-08)

Scénario : PR #51, `Services/Meeting/` et `Views/Meeting/Spaces/` modifiés.

| # | Faute observée (verbatim ou extrait du diff) | Catégorie |
| --- | --- | --- |
| 1 | … | régénération / invention / langue / narration / périmètre / omission |

Rationalisations exprimées par l'agent (verbatim) :
- « … »
```

- [ ] **Step 4 : Jeter le worktree de l'agent sans conserver son diff**

```bash
git worktree list   # repérer le worktree de l'agent
git worktree remove --force <chemin> ; git branch -D <sa-branche>
```

- [ ] **Step 5 : Commit**

```bash
git add docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md
git commit -m "docs(spec): ligne rouge du skill documenter-application"
```

---

### Task A2 : Manifeste et tests de documentation (rouges)

**Files:**
- Create: `docs/documentation.yml`
- Create: `Tests/DocumentationTests.swift`

**Interfaces:**
- Produces: `DocumentationManifest` (test-only) : `documents: [String]`, `codeDocumente: [String]`, `sections: [String]` ; les six tests nommés dans la spec §7.1 plus `sectionsStablesPresentes`.
- Consumes: `CurrentSchema.models` (`OneToOne/Models/SchemaVersions.swift`, `typealias CurrentSchema = SchemaV3`).

Écart assumé avec la spec : le manifeste est créé ici et non en session 2, parce que les tests le lisent.

- [ ] **Step 1 : Relever les titres de section actuels d'`architecture.md`**

```bash
grep '^## ' docs/architecture.md
```

Copier la liste obtenue dans `sections` du manifeste ci-dessous, **sans les inventer** : ce sont les sections que le skill devra tenir stables.

- [ ] **Step 2 : Écrire `docs/documentation.yml`**

```yaml
# Manifeste de documentation — lu par le skill documenter-application et par
# Tests/DocumentationTests.swift. Sous-ensemble YAML : clés simples, listes de chaînes,
# listes d'objets à clés `chemin`, `public`, `role`, `sections`.
langue: fr
branche_principale: master
tests: swift test --filter DocumentationTests

code_documente:
  - OneToOne/Models/
  - OneToOne/Services/
  - OneToOne/Views/Meeting/
  - OneToOne/Views/Project/
  - Scripts/
  - Package.swift

documents:
  - chemin: docs/README.md
    public: tous
    role: index — une ligne par document, public visé
  - chemin: docs/architecture.md
    public: développeur
    sections:
      # coller ici la sortie de `grep '^## ' docs/architecture.md`, une entrée par ligne, sans le `## `
      - "1. Présentation"
  - chemin: docs/decisions.md
    public: développeur
    role: registre généré par Scripts/generer-decisions.py depuis docs/adr/*.md
  - chemin: docs/glossaire.md
    public: développeur
    role: termes métier français ↔ symboles Swift

verites:
  modeles_persistes: OneToOne/Models/SchemaVersions.swift
  adr: docs/adr/

hors_perimetre:
  - CLAUDE.md
  - docs/superpowers/
  - docs/mesures/
```

- [ ] **Step 3 : Écrire les tests**

```swift
import Foundation
import Testing
@testable import OneToOne

/// La documentation développeur est fausse de façon bruyante, comme le code :
/// tout chemin, symbole, modèle ou ADR cité dans `/docs` doit exister.
@Suite("Documentation — ce qui est écrit dans /docs existe dans le code")
struct DocumentationTests {

    // MARK: - Racine et manifeste

    private var racine: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Sous-ensemble du manifeste : `- chemin:` sous `documents:`, `- …` sous `code_documente:`,
    /// `- "…"` sous `sections:`. Pas de bibliothèque YAML (aucune dépendance nouvelle).
    struct DocumentationManifest {
        var documents: [String] = []
        var codeDocumente: [String] = []
        var sections: [String] = []

        init(texte: String) {
            var bloc = ""
            for brute in texte.split(separator: "\n", omittingEmptySubsequences: false) {
                let ligne = String(brute)
                let nette = ligne.trimmingCharacters(in: .whitespaces)
                if nette.hasPrefix("#") || nette.isEmpty { continue }
                if !ligne.hasPrefix(" "), nette.hasSuffix(":") { bloc = String(nette.dropLast()); continue }
                if nette.hasPrefix("sections:") { bloc = "sections"; continue }
                if nette.hasPrefix("- chemin:") {
                    documents.append(nette.replacingOccurrences(of: "- chemin:", with: "").trimmingCharacters(in: .whitespaces))
                    bloc = "documents"
                } else if bloc == "code_documente", nette.hasPrefix("- ") {
                    codeDocumente.append(String(nette.dropFirst(2)))
                } else if bloc == "sections", nette.hasPrefix("- ") {
                    sections.append(String(nette.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
            }
        }
    }

    private func manifeste() throws -> DocumentationManifest {
        let url = racine.appendingPathComponent("docs/documentation.yml")
        return DocumentationManifest(texte: try String(contentsOf: url, encoding: .utf8))
    }

    private func texte(_ relatif: String) throws -> String {
        try String(contentsOf: racine.appendingPathComponent(relatif), encoding: .utf8)
    }

    /// Le contenu des accents graves, hors blocs de code ``` … ```.
    private func citations(dans texte: String) -> [String] {
        var horsCode = ""
        var dansBloc = false
        for ligne in texte.split(separator: "\n", omittingEmptySubsequences: false) {
            if ligne.hasPrefix("```") { dansBloc.toggle(); continue }
            if !dansBloc { horsCode += ligne + "\n" }
        }
        let motif = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
        let ns = horsCode as NSString
        return motif.matches(in: horsCode, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    private func existe(_ relatif: String) -> Bool {
        FileManager.default.fileExists(atPath: racine.appendingPathComponent(relatif).path)
    }

    // MARK: - Tests

    @Test("Tout chemin cité dans un document tenu existe")
    func cheminsCitesExistent() throws {
        let m = try manifeste()
        var manquants: [String] = []
        for doc in m.documents where existe(doc) {
            for c in citations(dans: try texte(doc)) {
                guard c.hasPrefix("OneToOne/") || c.hasPrefix("Scripts/") || c.hasPrefix("Tests/") || c.hasPrefix("docs/") else { continue }
                if c.contains("*") || c.contains("<") || c.contains("…") { continue }
                let chemin = c.split(separator: ":").first.map(String.init) ?? c   // `Fichier.swift:123`
                if !existe(chemin) { manquants.append("\(doc) → \(c)") }
            }
        }
        #expect(manquants.isEmpty, "Chemins inexistants cités : \(manquants)")
    }

    @Test("Tout symbole cité dans architecture.md est déclaré dans les sources")
    func symbolesCitesExistent() throws {
        let declares = try typesDeclares()
        let motif = try NSRegularExpression(pattern: "^[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*$")   // exclut les sigles (MLX, WAV…)
        var inconnus: [String] = []
        for c in citations(dans: try texte("docs/architecture.md")) {
            let ns = c as NSString
            guard motif.firstMatch(in: c, range: NSRange(location: 0, length: ns.length)) != nil else { continue }
            if !declares.contains(c) { inconnus.append(c) }
        }
        #expect(inconnus.isEmpty, "Symboles inconnus : \(Array(Set(inconnus)).sorted())")
    }

    /// Noms de `struct|class|enum|actor|protocol|typealias` déclarés sous OneToOne/ et Tests/.
    private func typesDeclares() throws -> Set<String> {
        let motif = try NSRegularExpression(pattern: "\\b(?:struct|class|enum|actor|protocol|typealias)\\s+([A-Z][A-Za-z0-9]*)")
        var noms = Set<String>()
        for dossier in ["OneToOne", "Tests"] {
            let base = racine.appendingPathComponent(dossier)
            guard let it = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in it where url.pathExtension == "swift" {
                let s = try String(contentsOf: url, encoding: .utf8)
                let ns = s as NSString
                for r in motif.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    noms.insert(ns.substring(with: r.range(at: 1)))
                }
            }
        }
        return noms
    }

    @Test("La liste des modèles documentée égale CurrentSchema.models")
    func modelesDocumentesEgalentLeSchema() throws {
        let doc = try texte("docs/architecture.md")
        // Section « Modèle de données » : du titre de niveau 2 qui la contient au prochain `## `.
        guard let debut = doc.range(of: "Modèle de données") else { Issue.record("Section « Modèle de données » absente"); return }
        let reste = doc[debut.upperBound...]
        let fin = reste.range(of: "\n## ")?.lowerBound ?? reste.endIndex
        let section = String(reste[..<fin])
        let documentes = Set(citations(dans: section).filter { $0.range(of: "^[A-Z][A-Za-z0-9]+$", options: .regularExpression) != nil })
        let schema = Set(CurrentSchema.models.map { String(describing: $0) })
        #expect(schema.subtracting(documentes).isEmpty, "Modèles du schéma absents de la doc : \(schema.subtracting(documentes).sorted())")
        #expect(documentes.intersection(schema) == schema)
    }

    @Test("Tout ADR référencé existe et tout ADR figure dans decisions.md")
    func adrReferencesExistent() throws {
        let m = try manifeste()
        let motif = try NSRegularExpression(pattern: "docs/adr/(\\d{4}-\\d{2}-\\d{2}-[a-z0-9-]+\\.md)")
        for doc in m.documents where existe(doc) {
            let s = try texte(doc); let ns = s as NSString
            for r in motif.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let f = ns.substring(with: r.range(at: 0))
                #expect(existe(f), "\(doc) cite \(f), absent")
            }
        }
        let registre = try texte("docs/decisions.md")
        let adrs = try FileManager.default.contentsOfDirectory(atPath: racine.appendingPathComponent("docs/adr").path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
        for f in adrs { #expect(registre.contains(f), "decisions.md ne mentionne pas \(f)") }
    }

    @Test("docs/README.md référence chaque document de /docs hors archives")
    func indexComplet() throws {
        let index = try texte("docs/README.md")
        let fm = FileManager.default
        var attendus = try fm.contentsOfDirectory(atPath: racine.appendingPathComponent("docs").path)
            .filter { $0.hasSuffix(".md") && $0 != "README.md" }
        attendus.append("adr/README.md")
        for f in attendus { #expect(index.contains(f), "README.md n'indexe pas \(f)") }
    }

    @Test("Les documents tenus n'emploient que des dates absolues")
    func datesAbsolues() throws {
        let m = try manifeste()
        let interdits = ["hier", "la semaine dernière", "récemment", "ce matin", "demain matin", "il y a quelques jours"]
        for doc in m.documents where existe(doc) {
            let s = try texte(doc).lowercased()
            for mot in interdits { #expect(!s.contains(mot), "\(doc) contient « \(mot) »") }
        }
    }

    @Test("Les sections stables du manifeste sont présentes dans architecture.md")
    func sectionsStablesPresentes() throws {
        let m = try manifeste()
        let doc = try texte("docs/architecture.md")
        for s in m.sections { #expect(doc.contains("## \(s)"), "Section « \(s) » absente") }
    }
}
```

- [ ] **Step 4 : Lancer et constater le rouge**

Run: `swift test --filter DocumentationTests`
Expected: FAIL — au moins `indexComplet` (pas de `docs/README.md`), `adrReferencesExistent` (pas de `decisions.md`), et probablement `cheminsCitesExistent`/`symbolesCitesExistent` sur `architecture.md`. Noter **quels** tests échouent et pourquoi : c'est la liste de travail de la Task A6.

- [ ] **Step 5 : Commit**

```bash
git add docs/documentation.yml Tests/DocumentationTests.swift
git commit -m "test(docs): tests de documentation et manifeste, rouges sur l'état actuel"
```

---

### Task A3 : Générateur du registre des décisions

**Files:**
- Create: `Scripts/generer-decisions.py`
- Create: `docs/decisions.md` (sortie du script)

**Interfaces:**
- Produces: `docs/decisions.md`, tableau `Date | Décision | Statut | Fichier`, trié par date décroissante. Les en-têtes d'ADR sont hétérogènes (`Statut : accepté …` en prose ou `- **Statut** : accepté, …`) : le script prend la première ligne contenant « Statut ».

- [ ] **Step 1 : Écrire le script**

```python
#!/usr/bin/env python3
"""Génère docs/decisions.md depuis les en-têtes de docs/adr/*.md.

Registre lisible des décisions : date (nom du fichier), titre (premier `# `),
statut (première ligne contenant « Statut », balises markdown retirées).
Ré-exécuté par le skill documenter-application à chaque ADR ajouté.
"""
import re, sys
from pathlib import Path

racine = Path(__file__).resolve().parent.parent
adr = racine / "docs" / "adr"
lignes = []
for f in sorted(adr.glob("*.md"), reverse=True):
    if f.name == "README.md":
        continue
    m = re.match(r"(\d{4}-\d{2}-\d{2})-", f.name)
    date = m.group(1) if m else "—"
    titre, statut = f.stem, "—"
    for l in f.read_text(encoding="utf-8").splitlines():
        if l.startswith("# ") and titre == f.stem:
            titre = l[2:].strip()
        if "Statut" in l and statut == "—":
            s = re.sub(r"[*_`]", "", l)
            s = re.sub(r"^\W*Statut\s*:\s*", "", s).strip().rstrip(".")
            statut = s
    lignes.append(f"| {date} | {titre} | {statut} | `docs/adr/{f.name}` |")

sortie = racine / "docs" / "decisions.md"
sortie.write_text(
    "# Registre des décisions d'architecture\n\n"
    "> Généré par `Scripts/generer-decisions.py` depuis les en-têtes de `docs/adr/`. Ne pas éditer à la main :\n"
    "> corriger l'ADR, puis relancer le script.\n\n"
    "| Date | Décision | Statut | Fichier |\n| --- | --- | --- | --- |\n" + "\n".join(lignes) + "\n",
    encoding="utf-8",
)
print(f"{len(lignes)} décisions → {sortie.relative_to(racine)}")
```

- [ ] **Step 2 : Exécuter et relire**

Run: `chmod +x Scripts/generer-decisions.py && Scripts/generer-decisions.py && head -20 docs/decisions.md`
Expected: `11 décisions → docs/decisions.md` ; chaque ligne a un titre lisible et un statut non vide. Si un statut sort vide ou tronqué, corriger la ligne « Statut » de l'ADR concerné **sans changer sa décision**, puis relancer.

- [ ] **Step 3 : Vérifier le test correspondant**

Run: `swift test --filter DocumentationTests/adrReferencesExistent`
Expected: PASS pour la partie « chaque ADR figure dans decisions.md » (la partie « ADR référencés existent » dépend d'`architecture.md`, Task A6).

- [ ] **Step 4 : Commit**

```bash
git add Scripts/generer-decisions.py docs/decisions.md
git commit -m "docs(adr): registre des décisions généré depuis les en-têtes des ADR"
```

---

### Task A4 : Écrire le skill contre les fautes observées

**Files:**
- Create: `~/.claude/skills/documenter-application/SKILL.md`
- Create: `~/.claude/skills/documenter-application/references/regles-de-redaction.md`
- Create: `~/.claude/skills/documenter-application/references/manifeste.md`

**Interfaces:**
- Consumes: la table des fautes de `2026-09-08-skill-documentation-ligne-rouge.md` (Task A1) : chaque faute observée doit avoir son contre dans « Erreurs fréquentes » ou dans un garde-fou.
- Produces: le skill que la Task A5 rejoue.

- [ ] **Step 1 : `SKILL.md`** (< 500 mots ; adapter la table finale aux fautes réellement observées)

```markdown
---
name: documenter-application
description: Utiliser quand le code documenté d'un projet a changé et que /docs doit être réaligné, ou quand un hook signale un écart de documentation (chemin ou symbole cité qui n'existe plus, modèle persisté ajouté sans mention, PR touchant un dossier listé dans docs/documentation.yml).
---

# Documenter l'application (documentation développeur, en français)

## Principe

La documentation doit être **vraie**, pas exhaustive. On la réaligne **par section** sur le code qui a
changé, et on laisse des tests la rendre fausse de façon bruyante. On ne régénère jamais un document.

## Quand l'utiliser

- Un hook signale que la PR touche un dossier de `code_documente` du manifeste.
- Un test de documentation est rouge (chemin, symbole, modèle, ADR, index, date relative).
- On vous demande de « mettre la doc à jour » après un changement de code.

Ne pas l'utiliser pour la documentation utilisateur ni pour `CLAUDE.md` (consignes pour l'agent).

## Méthode

1. **Lire le manifeste** `docs/documentation.yml` (format : `references/manifeste.md`). Absent → le
   proposer et s'arrêter.
2. **Calculer l'écart, sans écrire** : `git diff --name-only <branche_principale>...HEAD` croisé avec
   les sections qui citent ces fichiers ; symboles cités dont la déclaration a disparu ; modèles
   persistés ajoutés/retirés ; décision structurante dans le diff (dépendance, sous-système, format de
   stockage, retrait de fonctionnalité) sans ADR. **Lister les écarts avant toute modification.**
3. **Mettre à jour par section** : corriger en place la section désignée par chaque écart ; ajouter une
   section manquante à l'endroit prévu par le manifeste. Vérifier **chaque** chemin et symbole cité
   (`test -e`, recherche de la déclaration) avant de l'écrire.
4. **Vérifier** : lancer la commande `tests` du manifeste ; relire avec `references/regles-de-redaction.md`.
5. **Proposer un ADR** (statut « proposé », convention du dossier) si l'étape 2 a trouvé une décision sans
   trace. Ne jamais éditer un ADR validé : le superséder.
6. **Consigner** : un commit `docs(...)` par document, et un paragraphe « Documentation » dans la PR
   (réaligné / à trancher). Régénérer `docs/decisions.md` avec le script indiqué dans le manifeste.

## Garde-fous

- Régénérer un document entier → interdit ; si l'écart dépasse une PR, proposer un lot de documentation.
- Supprimer une section sans écart avéré → interdit ; marquer « retirée le <date>, voir <ADR> ».
- Toucher `CLAUDE.md`, `docs/superpowers/`, un ADR validé → interdit.
- Citer un chemin ou un symbole non vérifié → interdit.

## Erreurs fréquentes (observées lors de la ligne rouge)

| Faute | Correction |
| --- | --- |
| Réécrire `architecture.md` de zéro | Ne toucher que les sections désignées par l'écart |
| Citer `Services/Meeting/Foo.swift` sans vérifier | `test -e` d'abord ; sinon ne pas citer |
| Raconter la PR (« nous avons ajouté… ») | Décrire l'état : ce que fait le composant, où il vit |
| Anglais ou franglais dans la prose | Français ; symboles en anglais entre accents graves |
| Modifier `CLAUDE.md` « pour aller vite » | Hors périmètre, toujours |
| Oublier l'index `docs/README.md` | Chaque document tenu y a sa ligne |
```

- [ ] **Step 2 : `references/regles-de-redaction.md`**

```markdown
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
```

- [ ] **Step 3 : `references/manifeste.md`**

```markdown
# Le manifeste `docs/documentation.yml`

Il rend le skill générique : les faits du projet y vivent, versionnés avec le code.

| Clé | Rôle |
| --- | --- |
| `langue` | langue de la prose (`fr`) |
| `branche_principale` | base du `git diff` de l'étape 2 |
| `tests` | commande qui vérifie la documentation (ex. `swift test --filter DocumentationTests`) |
| `code_documente` | dossiers/fichiers dont un changement déclenche le réalignement (lus par le hook) |
| `documents[].chemin` | document tenu ; `public` ; `role` ou `sections` (titres stables de niveau 2) |
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
documents:
  - chemin: docs/README.md
    public: tous
    role: index
  - chemin: docs/architecture.md
    public: développeur
    sections:
      - "1. Présentation"
verites:
  modeles_persistes: OneToOne/Models/SchemaVersions.swift
  adr: docs/adr/
hors_perimetre:
  - CLAUDE.md
```

## Proposer un manifeste à un projet qui n'en a pas
Repérer : la branche principale, le dossier de documentation, les dossiers de code que la documentation
décrit, la commande de tests. Écrire le fichier, l'expliquer à l'auteur, s'arrêter : le premier
réalignement se fait à la PR suivante.
```

- [ ] **Step 4 : Vérifier le format et la taille**

Run: `head -4 ~/.claude/skills/documenter-application/SKILL.md && wc -w ~/.claude/skills/documenter-application/SKILL.md`
Expected: frontmatter avec `name` et `description` (< 1 024 caractères, troisième personne, déclencheur seulement) ; < 500 mots.

- [ ] **Step 5 : Versionner une copie dans le dépôt**

Le skill vit dans `~/.claude/skills`, mais sa source doit survivre au poste : copier le dossier dans `docs/superpowers/specs/skill-documenter-application/` (copie de référence, pas la copie active).

```bash
mkdir -p docs/superpowers/specs/skill-documenter-application
cp -R ~/.claude/skills/documenter-application/. docs/superpowers/specs/skill-documenter-application/
git add docs/superpowers/specs/skill-documenter-application
git commit -m "docs(skill): copie de référence du skill documenter-application"
```

---

### Task A5 : Rejeu avec le skill et resserrage

**Files:**
- Modify: `~/.claude/skills/documenter-application/SKILL.md` (table « Erreurs fréquentes », garde-fous)
- Modify: `docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md` (section « Rejeu »)

- [ ] **Step 1 : Rejouer le scénario de A1 avec le skill**

Dispatcher un sous-agent avec le **même prompt** que A1, en ajoutant une seule phrase : « Utilise le skill `documenter-application` (`~/.claude/skills/documenter-application/SKILL.md`). » Ne pas donner la spec.

- [ ] **Step 2 : Contrôler son diff contre la table des fautes**

Pour chaque faute de A1 : reproduite ou non ? Pour chaque chemin/symbole ajouté : vérifié ? A-t-il listé les écarts avant d'écrire ? A-t-il touché seulement les sections désignées ? Consigner dans une section « Rejeu 1 » du fichier de ligne rouge.

- [ ] **Step 3 : Resserrer**

Toute faute reproduite → ajouter la ligne exacte dans « Erreurs fréquentes » ou un garde-fou ; toute nouvelle rationalisation (verbatim) → un contre explicite. Rejouer (Step 1) jusqu'à un rejeu sans faute. Jeter les worktrees des sous-agents sans garder leurs diffs.

- [ ] **Step 4 : Synchroniser la copie de référence et commiter**

```bash
cp -R ~/.claude/skills/documenter-application/. docs/superpowers/specs/skill-documenter-application/
git add docs/superpowers/specs/skill-documenter-application docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md
git commit -m "docs(skill): rejeu du skill documenter-application et resserrage"
```

---

### Task A6 : Réaligner `/docs` jusqu'au vert

**Files:**
- Create: `docs/README.md`, `docs/glossaire.md`
- Modify: `docs/architecture.md` (par section), `docs/documentation.yml` (`sections` réelles)

**Interfaces:**
- Consumes: la liste des tests rouges relevée en A2 Step 4.

- [ ] **Step 1 : `docs/README.md`**

```markdown
# Documentation — OneToOne

| Document | Public | Contenu |
| --- | --- | --- |
| `architecture.md` | développeur | sous-systèmes, modèle de données, flux, intégrations, dette |
| `decisions.md` | développeur | registre des décisions d'architecture (généré depuis `adr/`) |
| `adr/README.md` | développeur | convention des ADR et liste des décisions validées |
| `glossaire.md` | développeur | termes métier français ↔ symboles Swift |
| `cleanup-report.md` | développeur | revue de nettoyage et dette restante |

Tenue par le skill `documenter-application`, manifeste `documentation.yml`, gardée par
`Tests/DocumentationTests.swift` (`swift test --filter DocumentationTests`).

Archives de travail, hors index : `superpowers/` (specs et plans de chaque chantier), `mesures/`.
```

Compléter le tableau avec tout `.md` présent à la racine de `docs/` (le test `indexComplet` fait foi).

- [ ] **Step 2 : `docs/glossaire.md`**

```markdown
# Glossaire — termes métier et symboles

| Terme (français) | Définition | Symbole Swift |
| --- | --- | --- |
| Réunion | unité de travail : audio, notes, transcription, rapport | `Meeting` |
| Note horodatée | ligne de note liée à l'audio par `t` | `MeetingNote` |
| Tête de lecture | position courante sur l'axe audio, partagée par tout l'écran | `MeetingPlayhead` |
| Action | tâche issue d'une réunion, avec source (`sourceRef`) | `ActionTask` |
| Fil 1:1 | suite des entretiens avec un collaborateur | `OneOnOneThread` |
| Engagement | promesse tenue ou non, par côté (manager / collaborateur) | `Commitment` |
| Sujet d'ordre du jour | point à aborder, reporté s'il n'est pas traité | `OneOnOneAgendaItem` |
| Humeur | cran de moral saisi en séance | `MoodEntry` |
| Objectif | objectif suivi sur le fil | `OneOnOneObjective` |
| Pièce | fichier, lien ou capture rattaché à une réunion | `MeetingAttachment` |
| Capture | image d'écran horodatée, texte extrait par OCR | `SlideCapture` |
| Planche | tableau blanc d'un atelier, stocké sur disque | `Board` |
| Fiche projet | jalons, interlocuteurs, budget, périmètre d'un projet | `Project`, `ProjectMilestone`, `ProjectContact` |
| Espace / mode | `Réunion`, `Rapport`, `Ressources` × `Préparer`, `En séance`, `Relire` | `MeetingScreenModel` |
```

Vérifier chaque symbole avec `grep -rn "\(struct\|class\|enum\) <Nom>" OneToOne/` avant de le laisser dans la table.

- [ ] **Step 3 : Réaligner `architecture.md` section par section**

Pour chaque échec de `cheminsCitesExistent` et `symbolesCitesExistent` : corriger la citation (renommage) ou retirer la phrase (disparition), **dans la section concernée seulement**. Pour `modelesDocumentesEgalentLeSchema` : mettre la table « Inventaire des modèles » de la section « Modèle de données » en accord avec `CurrentSchema.models` (ajouts de la refonte : `MeetingNote`, `Board`, `ProjectMilestone`, `ProjectContact`, `OneOnOneThread`, `Commitment`, `OneOnOneAgendaItem`, `MoodEntry`, `OneOnOneObjective`, `ChatSession`, `ChatMessageEntity`…). Remplacer dans `documentation.yml` la liste `sections` par les titres réels (`grep '^## ' docs/architecture.md`).

Run après chaque section : `swift test --filter DocumentationTests`

- [ ] **Step 4 : Vert complet**

Run: `swift test --filter DocumentationTests`
Expected: 7 tests PASS.

- [ ] **Step 5 : Preuve par mutation**

Renommer temporairement un chemin cité dans `architecture.md` (par ex. `MeetingPlayhead.swift` → `MeetingPlayheadX.swift` dans le texte), relancer : `cheminsCitesExistent` doit **échouer**. Rétablir.

- [ ] **Step 6 : Commit**

```bash
git add docs/README.md docs/glossaire.md docs/architecture.md docs/documentation.yml
git commit -m "docs: index, glossaire et architecture réalignés ; tests de documentation verts"
```

---

## Partie B — le hook, le manifeste en place, la PR (session 2)

### Task B1 : Script du hook

**Files:**
- Create: `~/.claude/hooks/documentation-apres-pr.sh`
- Create: `docs/superpowers/specs/skill-documenter-application/hooks/documentation-apres-pr.sh` (copie de référence)

**Interfaces:**
- Consumes: l'entrée JSON du hook `PostToolUse` sur stdin (`tool_name`, `tool_input.command`, `cwd`).
- Produces: sur stdout, un JSON `hookSpecificOutput.additionalContext` quand un dossier de `code_documente` est touché ; rien sinon. Code de sortie toujours 0 (ne bloque jamais).

- [ ] **Step 1 : Vérifier le format d'entrée/sortie des hooks avec le skill `update-config`**

Confirmer les champs exacts (`tool_input.command`, `hookSpecificOutput.hookEventName = "PostToolUse"`, `additionalContext`). Adapter le script si le format documenté diffère.

- [ ] **Step 2 : Écrire le script**

```bash
#!/bin/zsh
# Hook PostToolUse (Bash) : après `gh pr create` ou `git push`, si la PR touche un dossier
# listé dans docs/documentation.yml (code_documente), injecte à l'agent la consigne de lancer
# le skill documenter-application. N'écrit rien, ne bloque jamais (exit 0).
set -u
entree=$(cat)
commande=$(printf '%s' "$entree" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null) || exit 0
case "$commande" in
  *"gh pr create"*|*"git push"*) ;;
  *) exit 0 ;;
esac
cwd=$(printf '%s' "$entree" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
racine=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
manifeste="$racine/docs/documentation.yml"
[ -f "$manifeste" ] || exit 0
base=$(sed -n 's/^branche_principale:[[:space:]]*//p' "$manifeste" | head -1); base=${base:-master}
dossiers=$(awk '/^code_documente:/{f=1;next} /^[^ ]/{f=0} f && /^[[:space:]]*-[[:space:]]*/{sub(/^[[:space:]]*-[[:space:]]*/,""); print}' "$manifeste")
[ -n "$dossiers" ] || exit 0
changes=$(git -C "$racine" diff --name-only "origin/$base...HEAD" 2>/dev/null || git -C "$racine" diff --name-only "$base...HEAD" 2>/dev/null)
touches=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  m=$(printf '%s\n' "$changes" | grep -F "$d" | head -5)
  [ -n "$m" ] && touches="$touches$m"$'\n'
done <<< "$dossiers"
[ -n "$touches" ] || exit 0
liste=$(printf '%s' "$touches" | sort -u | tr '\n' ' ')
python3 - "$liste" <<'PY'
import json, sys
msg = ("Documentation : cette PR modifie du code documenté (" + sys.argv[1].strip() + "). "
       "Lancer le skill documenter-application avant de clore, puis pousser le commit de documentation "
       "sur la branche de la PR.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
PY
exit 0
```

- [ ] **Step 3 : Test déterministe du script, sans PR réelle**

```bash
chmod +x ~/.claude/hooks/documentation-apres-pr.sh
cd /Users/laurent.deberti/Documents/dev/perso/OneToOne
git checkout -b essai-hook && echo "// essai" >> OneToOne/Services/Meeting/MeetingActionCounts.swift && git commit -qam "essai hook"
printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title x"},"cwd":"%s"}' "$PWD" | ~/.claude/hooks/documentation-apres-pr.sh
```
Expected: une ligne JSON contenant `additionalContext` et `MeetingActionCounts.swift`.

```bash
printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s"}' "$PWD" | ~/.claude/hooks/documentation-apres-pr.sh; echo "rc=$?"
```
Expected: aucune sortie, `rc=0`.

```bash
git checkout master && git branch -D essai-hook
git checkout -b essai-hook2 && echo "// essai" >> Tests/MenuBarStatsTests.swift && git commit -qam "essai hook 2"
printf '{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"%s"}' "$PWD" | ~/.claude/hooks/documentation-apres-pr.sh; echo "rc=$?"
git checkout master && git branch -D essai-hook2
```
Expected: aucune sortie (seul `Tests/` touché), `rc=0`.

- [ ] **Step 4 : Copie de référence et commit (sur la branche `feat/skill-documentation`)**

```bash
git checkout feat/skill-documentation
mkdir -p docs/superpowers/specs/skill-documenter-application/hooks
cp ~/.claude/hooks/documentation-apres-pr.sh docs/superpowers/specs/skill-documenter-application/hooks/
git add docs/superpowers/specs/skill-documenter-application/hooks
git commit -m "docs(skill): copie de référence du hook documentation-apres-pr"
```

---

### Task B2 : Enregistrer le hook

**Files:**
- Modify: `~/.claude/settings.json` (clé `hooks`)

- [ ] **Step 1 : Ajouter la configuration avec le skill `update-config`**

Contenu attendu (à adapter au format confirmé en B1 Step 1) :

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/documentation-apres-pr.sh", "timeout": 20 }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2 : Vérifier**

Run: `python3 -c "import json;print(json.dumps(json.load(open('$HOME/.claude/settings.json'))['hooks'],indent=1))"`
Expected: l'entrée `PostToolUse` ci-dessus, le reste du fichier intact.

- [ ] **Step 3 : Test de bout en bout dans une nouvelle session Claude Code**

Ouvrir une nouvelle session (les hooks se chargent au démarrage), créer une branche touchant `OneToOne/Services/Meeting/`, exécuter `git push -u origin <branche>` via l'outil Bash : l'agent doit recevoir le contexte « Documentation : cette PR modifie du code documenté… ». Supprimer ensuite la branche distante (`git push origin --delete <branche>`). Consigner le résultat dans `STATUS.md` (Task B4).

---

### Task B3 : Suite complète et paragraphe « Documentation » de la PR

**Files:**
- Modify: aucun nouveau ; vérification.

- [ ] **Step 1 : Suite complète**

Run: `swift build && swift test`
Expected: `swift build` propre ; suite verte (3 103 tests de référence + 7 `DocumentationTests`).

- [ ] **Step 2 : Lancer le skill sur la PR elle-même**

Cette PR touche `Scripts/` (dossier documenté) : lancer le skill `documenter-application` sur la branche `feat/skill-documentation`. Attendu : il ajoute `Scripts/generer-decisions.py` à la section outillage d'`architecture.md` (ou constate que c'est déjà fait), ne régénère rien, et produit le paragraphe « Documentation » du corps de la PR. Commiter ce qu'il propose après relecture.

---

### Task B4 : `STATUS.md` et PR

**Files:**
- Modify: `STATUS.md`

- [ ] **Step 1 : Section en tête de `STATUS.md`**

```markdown
## Skill documenter-application — documentation développeur gardée par les tests (2026-09-08)

Branche `feat/skill-documentation`. Spec `docs/superpowers/specs/2026-09-08-skill-documentation-design.md`,
plan `docs/superpowers/plans/2026-09-08-skill-documentation.md`.

- Skill installé dans `~/.claude/skills/documenter-application/` (copie de référence dans
  `docs/superpowers/specs/skill-documenter-application/`), ligne rouge et rejeu consignés dans
  `docs/superpowers/specs/2026-09-08-skill-documentation-ligne-rouge.md`.
- Manifeste `docs/documentation.yml` ; `Tests/DocumentationTests.swift` (7 tests, rouges avant, verts
  après réalignement, preuve par mutation faite) ; `Scripts/generer-decisions.py` → `docs/decisions.md`.
- `/docs` réaligné : `README.md` (index), `glossaire.md`, `architecture.md` par sections.
- Hook `~/.claude/hooks/documentation-apres-pr.sh` enregistré (`PostToolUse`/Bash), testé sur trois
  cas (code documenté → contexte ; commande ordinaire → rien ; `Tests/` seul → rien) et de bout en
  bout : <résultat du test B2 Step 3>.
- Tests : <chiffres réels de swift test>.

**Prochaine action** : première PR de code après fusion → vérifier que le hook déclenche le skill et
que le paragraphe « Documentation » apparaît dans la PR.
```

- [ ] **Step 2 : Commit, push, PR**

```bash
git add STATUS.md
git commit -m "docs(status): consigner la session du skill documenter-application"
git push -u origin feat/skill-documentation
gh pr create --base master --title "feat(docs): skill documenter-application, tests de documentation, manifeste et hook" --body "$(cat <<'EOF'
## Objet
Documentation développeur gardée par les tests et réalignée par un skill déclenché à la création de PR.
Spec : docs/superpowers/specs/2026-09-08-skill-documentation-design.md.

## Contenu
- `docs/documentation.yml` (manifeste), `Tests/DocumentationTests.swift` (7 tests, preuve par mutation),
  `Scripts/generer-decisions.py` → `docs/decisions.md`, `docs/README.md`, `docs/glossaire.md`,
  `docs/architecture.md` réaligné par sections.
- Copie de référence du skill et du hook sous `docs/superpowers/specs/skill-documenter-application/`
  (les copies actives sont dans `~/.claude`).

## Documentation
<paragraphe produit par le skill en B3>

## Vérification
`swift build` propre ; `swift test` : <chiffres>.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Auto-revue

- **Couverture de la spec** : §3 fonctionnement → A4/B1/B2 ; §4 skill (emplacement, en-tête, méthode, garde-fous, erreurs) → A4, A5 ; §5 manifeste → A2 (+ écart assumé : créé en session 1) ; §6 hook → B1, B2 ; §7.1 tests → A2 (six tests) + `sectionsStablesPresentes` ; §7.2 restructuration → A3 (`decisions.md`), A6 (`README.md`, `glossaire.md`, `architecture.md`) ; §8 fabrication → A1, A5 ; §9 critères : 1 → A6 Step 5, 2 → B1 Step 3 et B2 Step 3, 3 → A5, 4 → A6 ; §10 hors périmètre respecté.
- **Placeholders** : les seuls `<…>` sont des valeurs mesurées à l'exécution (chiffres de tests, résultat du test de bout en bout, paragraphe produit par le skill), et la liste `sections` du manifeste est dérivée d'une commande donnée.
- **Cohérence des noms** : `DocumentationManifest` (A2) utilisé par les tests seulement ; `generer-decisions.py` (A3) cité dans le manifeste (A2), le skill (A4), le README (A6) ; `documentation-apres-pr.sh` (B1) enregistré en B2 ; sept tests nommés identiquement en A2 et §7.1 (`sectionsStablesPresentes` en plus).
