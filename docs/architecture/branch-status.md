# État des branches — snapshot 10 août 2026

> **Archive.** Ce document est figé au 10 août 2026 et versé au dépôt le 2026-09-02 tel
> quel. Il n'est plus à jour : `feat/fusion-note-reunion`, qu'il décrit comme « active »,
> est fusionnée dans `master` depuis. Pour l'état courant, lire `STATUS.md`.

## Branche courante

**`feat/fusion-note-reunion`** — active dans le workspace.

### Intention

Fusionner l'entité `Note` dans `Meeting` en la représentant comme une réunion solo (`MeetingKind.note`). Retire la classe `Note` / `NoteAttachment` du modèle SwiftData et bascule tous les lecteurs vers `Meeting` avec `kind == .note`. Effet secondaire : les statistiques hebdomadaires, l'agenda, les sections « Notes » des fiches et l'écran global Notes fonctionnent tous sur la même table `Meeting`.

Documents de conception :
- `docs/superpowers/specs/2026-08-10-fusion-note-reunion-design.md` (313 lignes)
- `docs/superpowers/plans/2026-08-10-fusion-note-reunion.md` (2 329 lignes)

### Diff vs `master`

**47 fichiers modifiés — +3 921 / −1 045 lignes** (au 10 août 2026).

Points marquants :

| Zone | Ce qui change |
|---|---|
| Modèle | Suppression de `Note` / `NoteAttachment`. Ajout de `MeetingKind.note`. `Meeting.noteDisplayTitle` / `notePreview` factorisent le rendu d'une note. |
| Vues | `AllNotesView` liste des `Meeting kind=note`. `NotesSection` (utilisée dans `DetailsViews`) liste également des réunions filtrées par kind. `Sidebar` : décompte hebdo exclut les notes. `Menubar/QuickNotePopover` crée un `Meeting` via `NoteFactory`. |
| Services | Nouveau `NoteFactory` (crée une réunion solo). Nouveau `NoteDisplay` (helpers d'affichage). `SpotlightIndexService` indexe réunions ET notes (hors transcriptions). `MailProjectMatcher` tire aussi les emails depuis les participants d'une réunion. `ChatbotEntryCommands` : commandes `/ajouter` créent note ou action. |
| Reunion | Filtrage des onglets/chrome selon `meeting.kind` (`MeetingVisibleSections`). Le kind `note` masque enregistrement audio, transcription, rapport, capture. |
| Tests | 12 nouveaux fichiers de tests : `NoteFactoryTests`, `NoteDisplayTests`, `NoteListFilteringTests`, `NotesSectionScopeTests`, `MeetingVisibleSectionsTests`, `MeetingStatsScopeTests`, `SpotlightMeetingIndexTests`, `QuickLaunchURLHandlerTests`, `ChatbotEntryCommandsTests`, `MailProjectMatcherTests`, `ReportTemplatingCollabNotesTests`, `ManagerCRGeneratorTests`. |
| Vue globale « Notes » | Nouvel écran `AllNotesView` accessible depuis la sidebar. |
| Deep-links | `QuickLaunchURLHandler` route `onetoone://note/xxx` vers `MeetingView` en mode note. |

### Commits (33 depuis `master`)

```
a711d11 docs(spec): consigne l'ouverture d'une reunion depuis un resultat Spotlight
c359623 refactor(modele): supprime les entrees datees projet, vides et remplacees par les notes
d7c6f8c feat(mail): tire les emails de projet des participants des reunions
83d3daa refactor(projet): retire les sections d'entrees datees de la fiche projet
3d074ad feat(assistant): les commandes ajout creent une note ou une action
168ca17 fix(app): retire une modification etrangere emportee par erreur dans 110565c
0da8253 docs(plan): indexer par morceaux quand un fichier porte deja des modifications etrangeres
110565c refactor(modele): supprime Note et NoteAttachment, remplaces par le kind note
50b6f57 docs(plan): trois defauts trouves en tache 7 (type, OneToOneApp, ChatbotView)
9a86b20 feat(note): bascule les derniers lecteurs de Note vers Meeting kind note
c50781a refactor(note): factorise titre/apercu de note dans Meeting.noteDisplayTitle/notePreview
859b0ce feat(note): la section Notes des fiches liste des reunions de kind note
876dbde test(note): garde-fou sur la rawValue de MeetingKind.note
a6a290a feat(note): l'ecran Notes liste des reunions de kind note
d0fc949 feat(spotlight): ouvre une reunion ou une note depuis un resultat Spotlight
829d525 fix(spotlight): coupe la course indexation/suppression d'une reunion
0c0883c docs(plan): second contexte pour prouver la persistance de la relation
732e5a9 feat(spotlight): indexe les reunions et les notes, hors transcriptions
b9357be feat(reunion): filtre les onglets et le chrome selon le kind
432667f refactor(test): second contexte pour la persistance, et commentaire précis
8fb9997 docs(plan): renforce le test de relation de NoteFactory (save + relecture)
317846b refactor(test): persistance de la relation collaborateur-participants et clarté du commentaire NoteFactory
01b94da feat(note): fabrique une note comme reunion solo via NoteFactory
a5f6412 fix(reunion): un événement d'agenda compte même si sa réunion devient une note
fff8b8c fix(reunion): exclut les notes de la boucle agenda du décompte hebdomadaire
6c5c1f2 docs(spec,plan): quatre appelants de la regle d'exclusion, pas trois
bd8ede3 fix(reunion): exclut aussi les notes du décompte hebdomadaire de la sidebar
bc04118 feat(reunion): ajoute le kind note et l'exclut des statistiques d'activité
563ba9a docs(plan): commits a chemins explicites, l'arbre porte un chantier etranger
1612430 docs(plan): plan d'implementation de la fusion Note/Reunion
b020a03 docs(spec): fusionne Note dans Meeting comme réunion solo
```

## Modifications locales non commitées

Actuellement **en cours** dans le workspace, non poussées :

### Fichiers modifiés (`M`, 24 fichiers) — chantier étranger déjà connu

Un chantier d'éditeur/blocs (`feat/editeur-slash-blocs`) est mêlé au workspace :

```
CLAUDE.md
Info.plist
OneToOne/Markdown/Blocks/ImageAttachmentFactory.swift
OneToOne/Markdown/Blocks/MermaidAttachmentFactory.swift
OneToOne/Markdown/Blocks/MermaidBlockLayout.swift
OneToOne/Markdown/Blocks/MermaidRenderCache.swift
OneToOne/Markdown/Blocks/MermaidRenderer.swift
OneToOne/Markdown/Core/BlockMoveCommands.swift
OneToOne/Markdown/Core/EditorRepresentable.swift
OneToOne/Markdown/Core/TableControlLayout.swift
OneToOne/Markdown/Core/TableEditCommands.swift
OneToOne/Markdown/Core/TableLayout.swift
OneToOne/Markdown/Slash/SlashController.swift
OneToOne/OneToOneApp.swift
Package.resolved
Package.swift
Tests/BlockMoveCommandsTests.swift
Tests/MermaidAttachmentFactoryTests.swift
Tests/MermaidBlockLayoutTests.swift
Tests/MermaidRenderCacheTests.swift
Tests/SlashControllerTests.swift
Tests/StyleRendererTests.swift
Tests/TableControlLayoutTests.swift
Tests/TableEditCommandsTests.swift
```

Le fichier `docs/superpowers/plans/2026-08-10-fusion-note-reunion.md` documente cette contamination : les commits de la fusion utilisent des chemins explicites pour ne pas emporter ces modifications.

### Fichiers non trackés (`??`)

Plusieurs livrables en cours non encore ajoutés :

- `AGENTS.md` — instructions pour agents
- `K8s_Monitor_Prototype.html` — prototype externe
- `OneToOne/Markdown/Blocks/NativeMermaidRenderer.swift` — refonte du renderer Mermaid
- `OneToOne/Services/Agent/*.swift` — nouveaux services de l'assistant IA agentique (7 fichiers)
- `Tests/Agent*Tests.swift` + `Tests/EditorTextViewBlockMutationUndoTests.swift` + `Tests/EditorRepresentableMermaidEditingTests.swift` + `Tests/NativeMermaidRendererTests.swift` — nouveaux tests
- `Vendor/` — libs vendorées
- `design_handoff_editor_blocs/` — handoff de design (blocs éditeur)
- `docs/superpowers/specs/2026-08-05-commandes-slash-manquantes.md`
- `docs/superpowers/specs/2026-08-10-agent-taches-claude-design.md`
- `docs/superpowers/specs/2026-08-10-json-canonique-notes-design.md`
- `docs/adr/README.md`

## Autres branches locales

Branches présentes dans le clone (résultat de `git branch -a`) :

```
feat/Actions-enhanced
feat/agent-claude
feat/agent-taches-claude
feat/agent-taches-claude-wip
feat/diarize-first
feat/editeur-slash-blocs
feat/fusion-note-reunion  ← courante
feat/habillage-vitrine-actions
feature/meeting-view-redesign
fix/code-review-data-safety-perf
```

Chacune correspond à un chantier distinct — voir le nom pour l'intention. La branche `feat/editeur-slash-blocs` est celle dont les modifications polluent actuellement le workspace de `feat/fusion-note-reunion`.

## Recommandations

1. **Finaliser la fusion Note/Réunion** : le plan couvre 21 tâches, la plupart déjà commitées. Vérifier qu'il ne reste pas de tâches ouvertes dans `docs/superpowers/plans/2026-08-10-fusion-note-reunion.md`.
2. **Isoler le chantier éditeur** : les 24 fichiers `M` non liés à la fusion mériteraient d'être `git stash -u` ou déplacés vers `feat/editeur-slash-blocs` proprement pour désencombrer le workspace de la branche courante.
3. **Committer ou nettoyer les `??`** : les nouveaux services `Agent/`, les tests associés et les nouveaux specs devraient être rattachés à leur branche cible.
4. **Vérifier** avant PR : `swift test --skip CalendarImportEventTests` (voir `STATUS.md` pour la raison).
