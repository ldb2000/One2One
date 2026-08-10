# Confier une action à un agent Claude

**Date** : 2026-08-10
**Statut** : validée
**Origine** : demande de l'auteur — « j'ai des tâches qui me sont affectées (écrire un mail,
prendre un rendez-vous, faire une doc…), je voudrais que Claude m'aide à les faire ».
**Branche** : `feat/agent-taches-claude`

---

## Le problème

`ActionTask` sait déjà **qu'une chose est à faire** : le titre, l'échéance, le projet, le
collaborateur, l'urgence, l'importance, les commentaires, la réunion d'où l'action est
sortie. Ce qu'elle ne sait pas faire, c'est **la faire**.

Or OneToOne détient précisément ce qui manque à un agent généraliste pour la faire
correctement : les comptes rendus des réunions où le sujet a été discuté, les mails classés
du projet, la fiche du collaborateur concerné, les alertes ouvertes. Un agent qui voit tout
cela écrit un mail juste ; un agent qui ne voit que l'intitulé de la tâche écrit un mail
générique.

Cette spec décrit **le pont entre une action et un agent**, pas un agent de plus.

---

## L'état de l'art, et ce qu'il change

Une recherche a été menée avant conception. Résumé de ce qui existe et de ce qu'on en tire.

### Ce qui existe déjà

| Projet | Ce qu'il fait | Ce qui manque pour notre usage |
|---|---|---|
| [Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork) | Agent bureau qui lit/écrit dans un dossier, skills docx/pptx/xlsx/pdf intégrées | Ne voit qu'un dossier — aucun accès aux projets, CR, mails, collaborateurs |
| [Asana AI Teammates](https://asana.com/uses/ai-task-management) | On assigne un agent à une tâche comme à une personne | SaaS, données hors machine, modèle métier étranger |
| [GitLab Duo Agent Platform](https://about.gitlab.com/blog/gitlab-duo-agent-platform-what-is-next-for-intelligent-devsecops/), panneau Agents de GitHub Copilot | Délégation + suivi d'agents | Orientés code |
| [Dust.tt](https://dust.tt/), [Onyx](https://github.com/onyx-dot-app/onyx) | Ateliers d'agents open source, Onyx produit des artefacts | Serveur à héberger, connecteurs génériques |
| [langchain-ai/agent-inbox](https://github.com/langchain-ai/agent-inbox) | UX « boîte de réception » pour agents human-in-the-loop | Patron d'interface réutilisable, pas un composant |
| [anthropics/skills](https://github.com/anthropics/skills), [tfriedel/claude-office-skills](https://github.com/tfriedel/claude-office-skills) | Les vraies skills Office (docx, pptx, xlsx, pdf) | — réutilisées telles quelles |
| [OfficeCLI](https://github.com/iOfficeAI/OfficeCLI), [opendocswork-mcp](https://github.com/Aimino-Tech/opendocswork-mcp) | Production Office sans Office installé | Solution de repli si les skills Python déçoivent |
| [jamesrochabrun/ClaudeCodeSDK](https://github.com/jamesrochabrun/ClaudeCodeSDK), [ttnear/Clarc](https://github.com/ttnear/Clarc) | Pilotage du CLI `claude` depuis Swift / SwiftUI | Preuve que la voie sous-processus fonctionne |

**Personne n'a fait exactement ceci** : un gestionnaire d'actions personnel dont le contexte
métier (CR de réunion, mails, projets, collaborateurs) alimente un agent qui rend un
livrable bureautique. La valeur est là, et nulle part ailleurs.

### Trois contraintes que la recherche a établies

1. **Le Claude Agent SDK n'existe qu'en Python et TypeScript.** La voie officiellement
   documentée depuis un autre langage est de lancer le CLI en sous-processus
   (`claude -p --output-format stream-json`). C'est ce que font ClaudeCodeSDK et Clarc.
   → Aucune dépendance SwiftPM n'est nécessaire : `Process` suffit.
2. **`AskUserQuestion` s'auto-résout à vide en headless sans TTY**
   ([claude-code#50728](https://github.com/anthropics/claude-code/issues/50728)).
   → La question posée par l'agent **ne peut pas** reposer dessus. Elle passe par un fichier.
3. **Anthropic n'autorise pas les tiers à exposer le login claude.ai ou les quotas
   d'abonnement dans leur produit.** Sans objet pour un usage personnel et non distribué,
   mais à consigner : si OneToOne était un jour diffusé, ce point devrait être revu.

### Ce qu'on ne réutilise pas, et pourquoi

- **ClaudeCodeSDK** : dépendance en beta, hooks non implémentés, pour environ 300 lignes de
  plomberie qu'on maîtrise mieux nous-mêmes. La règle 4 de `CLAUDE.md` (« pas de dépendance
  nouvelle sans justification ») tranche contre.
- **Les bibliothèques Swift OOXML** : aucune ne sait écrire du `pptx`. Faire produire
  l'Office par l'agent lui-même coûte cent fois moins.

---

## Périmètre

### Dans le périmètre

- Confier une `ActionTask` à un agent depuis la liste des actions.
- Construire un dossier de travail contenant le contexte OneToOne pertinent.
- Piloter le CLI `claude` en sous-processus, suivre sa progression, l'annuler.
- L'agent pose une question bloquante quand il lui manque une information ; on y répond
  depuis l'app ; il reprend.
- Récupérer le livrable : brouillon de mail, prompt, Markdown, docx, pptx, xlsx, pdf.
- Persister l'état d'une délégation et son journal d'échanges.

### Hors périmètre

- **Aucun serveur MCP sur la base SwiftData.** L'agent ne lit que des fichiers exportés.
- **Aucun onglet ni écran nouveau.** Le lancement se fait depuis la ligne d'action, le suivi
  dans le tiroir `JobQueue` existant.
- **Aucun envoi automatique.** Un mail est déposé en brouillon, jamais expédié.
- **Aucune écriture dans la base par l'agent.** Il ne crée ni action, ni réunion, ni note.
- Pas d'exécution planifiée ou récurrente.
- Pas de plusieurs agents en parallèle sur une même action.
- Pas de modification du provider IA existant (`AIProvider`) : cette fonction a son propre
  moteur et n'utilise ni `AIClient`, ni `DirectLLMClient`.

---

## L'environnement réel de la machine cible

Relevé le 2026-08-10, et déterminant pour la conception.

| Fait | Conséquence |
|---|---|
| `claude` v2.1.226 en `~/.local/bin/claude` (lien vers `~/.local/share/claude/versions/…`) | Chemin par défaut, mais **réglable** : il change à chaque mise à jour majeure |
| `claude` est **aliasé dans `~/.zshrc`** vers un `echo` | On lance le binaire **par son chemin absolu**, jamais via un shell interactif |
| Deux configurations : `~/.claude-pro` et `~/.claude-perso` (`CLAUDE_CONFIG_DIR`) | Il en faut une **troisième, dédiée** — voir ci-dessous |
| `uv` présent en `/opt/homebrew/bin/uv` | Voie retenue pour les scripts Office |
| `python3` = 3.9.6 système, sans `python-docx` | On n'installe rien globalement ; `uv run --with …` fait tout |

---

## Architecture

### Vue d'ensemble

```
ActionsListView (menu ⋮)
        │  « Confier à l'agent… »
        ▼
AgentLaunchSheet ──► TaskAgentService ──► AgentWorkspace  (écrit le dossier)
                            │
                            ├──► AgentRunner ──► Process(claude -p …)
                            │         │                   │ stdout: stream-json
                            │         └── AgentStreamDecoder ──► JobQueue (progression)
                            │
                            ├──► AgentStateContract (lit etat.json)
                            │
                            └──► AgentDeliverableRouter ──► ExportService / SavedPrompt / Finder
```

### 1. `AgentWorkspace` — le dossier de travail

`enum` namespace, fonctions **pures**. Emplacement :

```
~/Library/Application Support/OneToOne/Agents/<uuid-délégation>/
```

Le dossier est indexé par le `stableID` de l'`AgentRun`, **pas** par l'action : `ActionTask`
n'a pas d'identifiant stable, et confier deux fois la même action doit donner deux dossiers
distincts plutôt qu'écraser le premier travail.

Contenu écrit au lancement :

```
BRIEF.md                 la demande + la fiche de l'action
AGENT.md                 prompt système ajouté (rôle, contrat de sortie, outils)
contexte/
  projet.md              nom, phase, sponsor, entité, description
  collaborateur.md       fiche du collaborateur concerné, s'il y en a un
  alertes.md             alertes ouvertes du projet
  reunions/NNN-<titre>.md   CR des réunions liées (les plus récentes d'abord)
  mails/NNN-<objet>.md      mails classés du projet (ProjectMailStore)
livrables/               vide au départ — l'agent y dépose
echange/
  question.md            écrit par l'agent
  reponse.md             écrit par OneToOne à partir de ta réponse
etat.json                le contrat de fin de tour
```

**Testabilité.** La construction est une fonction pure `plan(_ input: WorkspaceInput) ->
[WorkspaceFile]` où `WorkspaceInput` est un DTO `Sendable` (pas de `ActionTask`, pas de
`ModelContext`) et `WorkspaceFile` est `(chemin relatif, contenu)`. Une seule fonction
d'entrée/sortie écrit le plan sur disque. Les tests portent sur `plan`.

**Périmètre du contexte.** Réglable dans la feuille de lancement, valeurs par défaut :
les 10 réunions les plus récentes liées au projet ou au collaborateur, les 20 mails les plus
récents du projet, tronqués à 8 000 caractères chacun. Ces plafonds sont des constantes
nommées, pas des littéraux dispersés.

**Ce qui n'est jamais exporté** : l'audio, les transcriptions brutes (seuls les CR
rédigés partent), les autres collaborateurs que celui de l'action, les mails d'autres
projets.

### 2. `AgentRunner` — le pilotage du CLI

`@MainActor final class AgentRunner`, singleton `.shared` (convention « service »).

Commande construite :

```
<chemin claude> -p
  --output-format stream-json --verbose
  --append-system-prompt-file <workspace>/AGENT.md
  --permission-mode acceptEdits
  --allowedTools "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash(uv run *)"
  [--resume <session_id>]          # tours 2..n
```

- `currentDirectoryURL` = le dossier de l'action. L'agent ne voit que lui.
- `environment` : `CLAUDE_CONFIG_DIR=~/.claude-onetoone`, `PATH` complété de
  `/opt/homebrew/bin` (pour `uv`). Environnement **construit explicitement**, jamais hérité
  d'un shell de connexion.
- Le prompt du tour est passé sur **stdin**, pas en argument : il peut être long et
  contenir n'importe quel caractère.
- stdout est lu **ligne à ligne** et décodé par `AgentStreamDecoder`.
- Annulation : `Process.terminate()` (SIGTERM). Le CLI abandonne le tour, tue l'arbre des
  processus enfants et sort en 143 — comportement documenté, pas une supposition.
- Plafond de durée par tour : 10 minutes (constante réglable), puis SIGTERM.

**Injection.** `AgentRunner` reçoit un `AgentProcessLauncher` (protocole `Sendable`) dont la
conformité de production lance le vrai `Process` et dont la conformité de test rejoue un
flux enregistré. **Aucun test n'appelle le vrai CLI.**

#### La configuration dédiée `~/.claude-onetoone`

**Décision, à consigner en ADR.** L'agent tourne sous un `CLAUDE_CONFIG_DIR` qui lui est
propre, connecté une fois à la main.

- *Pourquoi pas `~/.claude-perso`* : l'agent hériterait des plugins, skills, hooks et
  `CLAUDE.md` globaux de l'auteur — dont `superpowers`, qui n'a rien à faire dans la
  rédaction d'un mail, et qui rendrait le comportement dépendant d'un état extérieur au
  dépôt.
- *Pourquoi pas `--bare`* : le mode isolerait bien, mais il **n'ouvre ni les identifiants
  OAuth ni le trousseau** ; il exigerait une `ANTHROPIC_API_KEY` facturée à l'usage, alors
  qu'un abonnement existe.
- *Conséquence* : au premier lancement, si le dossier n'existe pas ou n'est pas connecté,
  l'app affiche la marche à suivre — une commande à copier — plutôt que d'échouer
  silencieusement.

### 3. `AgentStreamDecoder` — la lecture du flux

`enum` namespace, fonction pure `decode(line: String) -> AgentEvent?`. Événements retenus :

| Ligne | Ce qu'on en fait |
|---|---|
| `system` / `init` | On garde `session_id` (indispensable pour `--resume`) |
| `assistant` | Le texte alimente le libellé de progression du job |
| `system` / `api_retry` | Affiché tel quel : « nouvelle tentative (2/5) — surcharge » |
| `result` | Fin de tour : coût, durée, texte final |
| autre / illisible | Ignoré, sans faire échouer le tour |

Une ligne non-JSON ou tronquée **ne casse jamais la lecture** : elle est ignorée et comptée.

### 4. `AgentStateContract` — le contrat de fin de tour

L'agent termine chaque tour en écrivant `etat.json` :

```json
{
  "etat": "question",
  "question": "Quel budget dois-je annoncer dans la note ?",
  "livrables": [
    { "fichier": "livrables/note.docx", "type": "docx", "titre": "Note de cadrage" }
  ],
  "hypotheses": ["J'ai retenu la version du CR du 3 août, pas celle du 12 juillet"],
  "resume": "Note rédigée à partir des trois CR ; il manque le budget."
}
```

`etat` vaut `question`, `livrable` ou `bloque`. Les autres champs sont facultatifs.

**Pourquoi un fichier et non `AskUserQuestion`** : voir contrainte 2 de l'état de l'art.
Le fichier est en outre observable — l'auteur peut l'ouvrir — et survit à un plantage de
l'app.

**Repli.** Si `etat.json` est absent, illisible, ou porte un `etat` inconnu, on **ne perd
pas le travail** : la délégation passe en état *à revoir*, le texte du message `result` est
affiché tel quel, et les fichiers présents dans `livrables/` sont proposés en vrac.

### 5. `AgentDeliverableRouter` — l'atterrissage du livrable

| Type | Destination |
|---|---|
| `mail` | Brouillon Mail.app ou Outlook via `ExportService` (déjà écrit) — **jamais envoyé** |
| `prompt` | Un `SavedPrompt` créé dans la galerie « Enregistré » |
| `md` | Aperçu dans le panneau de l'action (`MarkdownText`) |
| `docx`, `pptx`, `xlsx`, `pdf` | Rattaché à l'action, boutons « Ouvrir » (`NSWorkspace`) et « Révéler dans le Finder » |
| inconnu | Traité comme un fichier joint, sans aperçu |

**Production de l'Office.** L'agent appelle les scripts des skills Anthropic via
`uv run --with python-docx …` (respectivement `python-pptx`, `openpyxl`). Rien n'est
installé de façon permanente. `AGENT.md` documente ces appels ; la présence de `uv` est
vérifiée **avant** le lancement, avec un message clair si elle manque.

### 6. Modèle de données

Trois entités nouvelles dans `Models/OtherModels.swift`, plus une version de schéma dans
`Models/SchemaVersions.swift` (migration légère : ajout pur).

```swift
@Model final class AgentRun {
    var stableID: UUID? = nil          // Optionnel — voir la note SwiftData ci-dessous
    var task: ActionTask?
    var demande: String                 // ce que l'auteur a écrit dans la feuille
    var sessionID: String?              // pour --resume
    var workspacePath: String
    var etatRaw: String = AgentRunState.preparation.rawValue
    var etat: AgentRunState {                        // wrapper calculé, non stocké
        get { AgentRunState(rawValue: etatRaw) ?? .echec }
        set { etatRaw = newValue.rawValue }
    }
    var createdAt: Date
    var updatedAt: Date
    var coutUSD: Double = 0
    var tours: Int = 0
    var derniereErreur: String?
    @Relationship(deleteRule: .cascade, inverse: \AgentExchange.run) var echanges: [AgentExchange] = []
    @Relationship(deleteRule: .cascade, inverse: \AgentDeliverable.run) var livrables: [AgentDeliverable] = []
}

enum AgentRunState: String, Codable, CaseIterable, Sendable {
    case preparation, travaille, attenteReponse, livrablePret, aRevoir, echec, annule
}

@Model final class AgentExchange {   // le journal des tours
    var date: Date
    var roleRaw: String              // "agent" | "auteur"
    var texte: String
    var run: AgentRun?
}

@Model final class AgentDeliverable {
    var fichier: String              // chemin relatif au dossier de travail
    var typeRaw: String
    var titre: String
    var creeLe: Date
    var run: AgentRun?
}
```

Conformément aux conventions du dépôt : enums persistées en `…Raw: String` + wrapper
calculé, et `stableID` déclaré **optionnel avec défaut `nil`** — un `UUID` non optionnel avec
valeur par défaut est un piège SwiftData connu du projet.

`ActionTask` reçoit une relation inverse `agentRuns: [AgentRun]` en cascade : supprimer une
action supprime ses délégations. **Le dossier de travail sur disque n'est pas supprimé
automatiquement** — voir « Nettoyage ».

### 7. Interface

Aucun écran nouveau.

**Lancement.** `ActionsListView` — le menu `⋮` de la ligne (autour de la ligne 735) reçoit
une entrée « Confier à l'agent… ». Elle ouvre `AgentLaunchSheet` :

- une zone de texte « Ce que j'attends », pré-remplie par le titre de l'action ;
- un repli « Contexte » : réunions du projet, réunions du collaborateur, mails du projet,
  alertes — cochés par défaut selon ce que l'action référence ;
- un repli « Format attendu » : *auto* par défaut, sinon mail / document / présentation /
  tableur / prompt / note ;
- un bouton « Confier ».

**Suivi.** La ligne d'action porte une pastille :

| État | Pastille |
|---|---|
| `travaille` | ⏳ gris animé |
| `attenteReponse` | 🟠 « te demande quelque chose » |
| `livrablePret` | ✅ vert |
| `aRevoir` | 🟡 |
| `echec` | 🔴 |

Le détail passe par `JobQueue` avec un `JobKind.agent` nouveau, concurrence maximale **2**
(deux délégations en parallèle, pas plus — au-delà, la file). La `JobQueueSidebar` existante
l'affiche sans modification autre que le libellé du kind.

**Question et réponse.** Un clic sur la pastille orange ouvre le panneau de l'action :
la question de l'agent, le journal des échanges, un champ de réponse, un bouton « Répondre ».
La réponse est écrite dans `echange/reponse.md` et le tour suivant démarre avec `--resume`.
Une notification locale est postée quand l'agent bascule en `attenteReponse` ou en
`livrablePret`. `MeetingNotificationService` porte déjà l'autorisation `UNUserNotificationCenter`
et son délégué, mais ses catégories sont propres aux réunions : on y ajoute une catégorie
`AGENT_ATTENTE` et une action « Répondre », plutôt que de monter un second centre de
notifications concurrent.

---

## Sécurité et périmètre d'action de l'agent

- L'agent ne voit **que** son dossier d'action : `currentDirectoryURL` y pointe, aucun
  `--add-dir` n'est passé.
- Il n'a **aucun accès à la base SwiftData**. Tout ce qu'il sait vient des fichiers exportés.
- `--permission-mode acceptEdits` l'autorise à écrire dans son dossier sans demander.
  Toute commande shell hors de `Bash(uv run *)` est refusée et fait échouer le tour, avec le
  refus consigné.
- Le web (`WebSearch`, `WebFetch`) est **autorisé** — sans lui l'agent ne peut pas
  « comprendre le contexte général » d'un sujet. Un réglage permet de le couper.
- Rien ne part : un mail est un brouillon, un fichier reste sur le disque. L'auteur valide.

---

## Gestion des erreurs

| Cas | Comportement |
|---|---|
| Binaire `claude` introuvable | État `echec`, message nommant le chemin essayé, lien vers Réglages → IA |
| `~/.claude-onetoone` absent ou non connecté | État `echec`, marche à suivre affichée avec la commande à copier |
| `uv` absent alors qu'un format Office est demandé | Refus **avant** lancement, message explicite |
| Sortie non nulle du CLI | État `echec`, stderr conservé dans `derniereErreur` et affiché |
| `etat.json` absent ou cassé | État `aRevoir` — le texte du `result` et les fichiers de `livrables/` sont proposés |
| `--resume` refusé (session expirée) | Nouveau tour sans `--resume`, avec le journal des échanges réinjecté dans le prompt |
| Dépassement des 10 minutes | SIGTERM, état `echec`, la reprise reste possible via `--resume` |
| Annulation par l'auteur | SIGTERM, état `annule`, le dossier est conservé |
| Ligne de flux illisible | Ignorée et comptée ; jamais fatale |

---

## Nettoyage

Les dossiers de travail s'accumulent. `Services/Maintenance/OrphanCleanupService.swift`
reçoit une passe qui supprime les dossiers dont l'`AgentRun` n'existe plus, et ceux terminés
depuis plus de 90 jours. Jamais
automatiquement au démarrage : l'auteur déclenche. Un dossier orphelin ne casse rien.

---

## Tests

Les parties pures portent les tests. Swift Testing, conformément au dépôt.

| Fichier | Ce qu'il vérifie |
|---|---|
| `AgentWorkspacePlanTests` | `plan()` : fichiers attendus pour une action avec/sans projet, sans collaborateur, sans réunion ; troncature aux plafonds ; **absence** des données hors périmètre (audio, transcription brute, autres projets) |
| `AgentStreamDecoderTests` | `init`, `assistant`, `api_retry`, `result` sur captures réelles ; ligne vide, ligne tronquée, ligne non-JSON, type inconnu |
| `AgentStateContractTests` | `etat.json` valide (les trois états) ; champ manquant ; JSON cassé ; `etat` inconnu ; type de livrable inconnu ; chemin de livrable qui sort du dossier (**rejeté**) |
| `AgentDeliverableRouterTests` | Routage par type avec un `ExportService` mocké ; création du `SavedPrompt` ; type inconnu traité en pièce jointe |
| `AgentCommandBuilderTests` | Arguments et environnement produits : présence de `--resume` au tour 2 et son absence au tour 1, `CLAUDE_CONFIG_DIR`, `PATH` complété, liste d'outils autorisés |
| `AgentRunnerTests` | Machine à états sur un lanceur rejouant un flux enregistré : nominal, question puis reprise, annulation, sortie non nulle, dépassement de délai |

Vérification avant PR : `swift test --skip CalendarImportEventTests`.

---

## Ce que cette spec laisse ouvert

- **Le modèle utilisé** n'est pas fixé ici : c'est celui de la configuration
  `~/.claude-onetoone`. Un réglage dans l'app viendra si le besoin apparaît.
- **La qualité des livrables Office** dépend des skills Anthropic. Si elles déçoivent,
  `OfficeCLI` (binaire unique, sans Python) est la solution de repli identifiée.
- **La reprise après redémarrage de l'app** : un tour en cours est perdu si l'app est tuée,
  comme pour les autres jobs (`JobQueue` ne persiste pas). Le `sessionID` étant en base, la
  reprise manuelle par `--resume` reste possible ; l'automatiser n'est pas dans ce lot.

---

## Décisions à consigner en ADR

1. **Pilotage du CLI `claude` en sous-processus** plutôt que l'API Messages ou une
   dépendance Swift tierce — le SDK n'existe pas en Swift, et l'écriture de `pptx` n'existe
   pas non plus.
2. **Configuration `~/.claude-onetoone` dédiée** plutôt que la configuration personnelle de
   l'auteur ou `--bare` — isolation sans renoncer à l'abonnement.
3. **Contrat de sortie par fichier `etat.json`** plutôt que `AskUserQuestion` — contournement
   documenté d'un défaut amont en mode headless.
