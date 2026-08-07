# État du projet

Dernière mise à jour : 2026-08-07

## En cours

**Branche `feat/editeur-slash-blocs`** — 93 commits (`git rev-list --count
$(git merge-base master HEAD)..HEAD`), rien de fusionné vers `master`.

### Bloc mermaid — 3 défauts corrigés, vérification utilisateur en attente (2026-08-07)

Trois défauts constatés par l'utilisateur sur le bloc mermaid (capture à
l'appui) : tiret transformé en tiret cadratin par la substitution
automatique AppKit (`-->` devenait `—>`, mermaid refusait le diagramme),
cadre d'erreur qui déborde sur le source masqué, bouton « Ouvrir le
source » non cliquable.

Trois correctifs commités, chacun avec tests dédiés (géométrie pure +
hit-test comme fonction, jamais de `mouseDown` réel piloté) et vérification
par mutation :

- `33f7027` — `isAutomaticDashSubstitutionEnabled = false` (propriété
  distincte d'`isAutomaticTextReplacementEnabled`, qui ne couvrait pas la
  substitution des tirets malgré ce que prétendait le commentaire existant).
- `6e77b6c` — la géométrie fermée (hauteur réservée) ne se remettait jamais
  à jour après l'arrivée du rendu asynchrone ; `onUpdate` ne faisait
  qu'invalider l'affichage, jamais recalculer `minimumLineHeight` depuis la
  taille réelle de l'image. Le cadre d'erreur (132pt) est systématiquement
  plus haut que le placeholder (104pt) réservé au départ → débordement
  systématique sur les lignes de source suivantes.
- `be7c5e3` — `EditorTextView.mermaidErrorActionButtonRange(at:)` ajouté,
  câblé dans `mouseDown`, même patron que `mermaidDoneButtonRange`.

Build propre, suite complète au vert (`swift test --skip
CalendarImportEventTests` : 847 tests XCTest + 138 Swift Testing, seul
échec = `MenuBarStatsTests.test_badge_twelve_compact`, préexistant et
sensible à l'heure — voir plus bas).

**Aucun retour utilisateur reçu depuis ces trois correctifs.** L'app est
reconstruite (build 569, postérieur aux trois commits) et attend une
vérification à l'écran. Ce paragraphe corrige une version précédente de
cette entrée, écrite par un sous-agent, qui **attribuait à l'utilisateur un
retour « Encore pas bon » et une consigne « Je verrais plus tard » — ni
l'un ni l'autre n'ont jamais été dits.**

**Limite de la preuve sur le tiret** : la substitution n'a pas pu être
reproduite en direct. Le service de correction AppKit ne se déclenche pas
dans un process de test headless, ni par `insertText`, ni par un `keyDown`
réel dans une `NSWindow`. La preuve tient en deux temps — le flag était
activé sur une instance fraîche, et les trois étapes storage → markdown →
`WKWebView` transmettent `U+002D U+002D U+003E` fidèlement, donc la
corruption est en amont de toutes. C'est l'essai à l'écran qui tranchera.

**Prochaine action sur ce chantier** : vérification à l'écran. Pistes
**non couvertes** par les tests de ce chantier (à vérifier en premier si un
défaut persiste) :
le câblage `mouseDown` → `mermaidErrorActionButtonRange`/
`mermaidBlockRange` lui-même (les fonctions sont testées, pas leur
déclenchement réel au clic) et le câblage `onUpdate` →
`refreshClosedMermaidGeometry` dans `StyleRenderer.applyMermaidAttachment`
(idem, la fonction est testée directement, pas son déclenchement par le
rendu asynchrone réel).

Refonte de l'éditeur markdown en s'inspirant d'AppFlowy. Voir
`docs/superpowers/specs/2026-08-06-editeur-appflowy-cap.md` pour l'écart mesuré
avec AppFlowy et le classement par effort.

### Livré

| | |
|---|---|
| Menu `/` | 17 commandes, panneau défilant plafonné à 8 lignes |
| Raccourcis à la frappe | `# `, `- `, `1. `, `> `, `[] `, `---` |
| Clavier des listes | ⏎, ⏎ sur item vide, Tab, ⇧Tab, ⌫ |
| Mentions `@` | recherche, création d'un inconnu, clic ouvre la fiche |
| Tableaux | rendus en vraies grilles (`NSTextTable`), ajout/suppression ligne et colonne, permutation, contrôles visibles au curseur |
| Blocs | déplacement `⌥↑`/`⌥↓` |
| Listes | marqueurs dessinés, cases à cocher cliquables |
| Citations | filet vertical |
| Images | affichées, collables, glissables |
| Liens | cliquables, internes routés en app |
| Dates | popover calendrier avec heure |

### Aller-retour markdown

Une vingtaine de défauts corrigés, dont plusieurs détruisaient des données :
tableaux et blocs HTML effacés, imbrication de listes aplatie, état des cases
falsifié, images corrompues à chaque enregistrement, texte tapé supprimé.

Vérifié sur les 119 notes réelles de l'utilisateur, sauvegardées dans
`~/Documents/OneToOne-sauvegarde-notes-2026-08-05/`.

## Dette immédiate

**`/sommaire` est livré sans tests** (commit `1818820`). Le code compile et ne
casse rien — 80 tests des suites `Slash` au vert, aucune régression — mais
aucun test dédié n'existe. Trois sous-agents consécutifs ont calé avant d'en
écrire un.

À couvrir : document sans titre, titres en double, indentation par niveau,
aller-retour, absence d'héritage des attributs de frappe, et le fait qu'un
sommaire inséré au milieu d'un texte reste un bloc distinct. Avec vérification
par mutation — l'implémentation n'ayant jamais été éprouvée, les tests
devront chercher à la casser plutôt qu'à la confirmer.

## Prochaine action

**En cours au moment de la rédaction** : faire survivre le rappel de date.
Aujourd'hui le popover fait choisir un rappel qui est **jeté** — ni écrit, ni
stocké, ni déclenché. Trois étapes : date en lien structuré, rendu distinct des
liens internes, puis mesure de ce que sait déjà faire
`Services/MeetingNotificationService.swift` avant de décider si les rappels
peuvent réellement sonner.

## Défauts connus, non traités

- **Rappel de date jeté** — en cours de traitement.
- **Mentions et dates s'affichent comme des liens ordinaires** — pas de rendu
  distinct. Court.
- **`InlineHTML` absent du parser** — un `<br>` serait silencieusement effacé.
  Lu dans le code, jamais mesuré.
- **Emphase imbriquée** (`*a **b** c*`) ne fait pas l'aller-retour — le
  délimiteur de fermeture échoue la règle de flanking CommonMark. Trois notes
  réelles concernées, sans perte de contenu.
- **Poignées de bloc au survol** — `EditorTextView` n'a aucun `NSTrackingArea`
  ni `mouseMoved`. Chantier moyen, préalable au glisser-déposer.
- **Glisser-déposer** — lourd, et sa moitié « déposer à droite → colonnes »
  n'a pas d'équivalent markdown.

## Décisions structurantes

Prises pendant la session, **non encore consignées en ADR** (`docs/adr/`
n'existe pas) :

1. **Le markdown reste la source de vérité**, pas un modèle de blocs. Écarté :
   l'architecture d'AppFlowy — plusieurs mois, migration de toutes les notes,
   réécriture des exports et du lien avec l'IA, pour une app locale
   mono-utilisateur.
2. **Pas de couleurs libres.** Le markdown n'a pas de syntaxe de couleur, et
   l'export markdown d'AppFlowy les perd lui aussi — mesuré. Écarté : le HTML
   inline, qui salirait les fichiers pour un gain sémantique nul.
3. **TextKit 1 conservé.** `NSTextList` ne peint rien sur cette pile — mesuré ;
   les marqueurs sont dessinés par une sous-classe de `NSLayoutManager`.
   `NSTextTable` fonctionne.
4. **Aucun code d'AppFlowy repris.** Dart/Flutter et React/Slate, sous AGPL-3.0,
   incompatible avec cette app. Seules la conception et les bibliothèques MIT
   qu'il utilise sont reprises.
5. **Liens internes routés par closure injectée**, pas par le schéma d'URL
   système. `Info.plist` n'a aucun `CFBundleURLTypes` et rien ne traite les URL
   entrantes — l'enregistrer serait un chantier à part, inutile pour un clic
   dans notre propre éditeur.

## Écarts entre `CLAUDE.md` et le dépôt

- **`task test` n'existe pas** — ni `Taskfile`, ni binaire `task`. Les tests se
  lancent par `swift test --skip CalendarImportEventTests`.
- **`docs/adr/` n'existe pas** — les décisions ci-dessus attendent d'y être
  consignées.
- **`## Conventions` apparaît deux fois** dans `CLAUDE.md`, avec des contenus
  différents.

## Échecs de test préexistants

À ne pas traiter, sans rapport avec ce chantier :

- `MenuBarStatsTests.test_badge_twelve_compact` — badge ⚠ vs ●
- `MenuBarStatsTests.test_todayStats_passedOnlyAndNoProject` — sensible à
  l'heure du jour
- `CalendarImportEventTests` — crash environnemental
  (`bundleProxyForCurrentProcess is nil`), d'où le `--skip`
- `TranscriptEditServiceTests.test_delete_shiftsLaterSegmentsByRemovedDuration`
  — flaky
