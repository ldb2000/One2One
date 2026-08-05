# Éditeur markdown — menu `/` et blocs riches (mermaid, images, draw.io)

Date : 2026-08-03
Branche : `feat/editeur-slash-blocs`

> ## ⚠️ Annotation du 2026-08-06 — état réel, trois sections devenues fausses
>
> Ce document reste la spec d'origine et garde la trace du raisonnement. Il est
> **partiellement périmé**. La spec qui fait foi désormais est
> [`2026-08-06-editeur-appflowy-cap.md`](2026-08-06-editeur-appflowy-cap.md).
>
> **Livré** (vérifié par lecture du code sur `feat/editeur-slash-blocs`) :
> menu `/` (12 entrées, `OneToOne/Markdown/Slash/`), images inline
> (`ImageAttachmentFactory`, `ImagePlaceholder`), `MediaStore` (ex-`ImagePasteService`),
> `MarkdownBlockCommands` opérant par attributs, marqueurs de liste et filet de
> citation dessinés par `MarkdownLayoutManager`, tableaux GFM en vraie grille
> `NSTextTable`, mentions `@`, sélecteur de date en popover.
>
> **Non livré, et devenu faux dans le texte ci-dessous** :
>
> | Section | Ce qu'elle annonce | État réel |
> |---|---|---|
> | Objectif 2, « Moteur mermaid », « Rendu asynchrone et cache », « Édition d'un bloc » | mermaid rendu dans l'éditeur, `Blocks/MermaidRenderer`, `RenderCache`, `mermaid.min.js` embarqué | **rien de tout cela n'existe.** `OneToOne/Markdown/Blocks/` ne contient qu'`ImageAttachmentFactory.swift`. Aucun fichier du projet ne mentionne mermaid hors le commentaire « hors périmètre » de `SlashCatalog.swift`. Mis hors périmètre par décision utilisateur du 2026-08-04 |
> | Objectif 4, « Images et draw.io » | `DrawIOImporter`, CLI draw.io | **n'existe pas.** Même décision du 2026-08-04 |
> | Objectif 5, « Unification des chemins markdown » | `MarkdownText.swift` consomme `MarkdownParser` | **non fait.** `OneToOne/Views/MarkdownText.swift` fait toujours 198 lignes et garde son analyseur ligne-à-ligne écrit à la main (`hasPrefix("```")`, `hasPrefix("> ")`…). L'étape 1 du découpage, annoncée « en premier », n'a jamais été exécutée |
> | Tableau « Catalogue » | « Bloc de code ` ``` ` » dans Blocs de base ; groupes « Média » (mermaid, draw.io) et « IA » | le catalogue réel n'a **pas** de bloc de code, pas de mermaid, pas de draw.io, pas d'IA. Il a en revanche **Tableau** et **Date**, absents de ce tableau |
> | « Non-objectifs » | « Mentions `@collaborateur` … tableaux » hors périmètre | les deux **sont livrés** depuis (commits `fc2234a`, `b7f3c59`) |
>
> **Toujours vrai et structurant** : le markdown reste seule source de vérité ;
> TextKit 1 conservé ; `NSTextAttachmentViewProvider` exigerait TextKit 2 ;
> aucun code AppFlowy n'est repris (AGPL-3.0).

## Contexte

L'éditeur `OneToOne/Markdown/` (issu de `2026-05-22-wysiwyg-markdown.md`, complété
par `2026-07-10-markdown-note-editor-preview-design.md`) gère aujourd'hui le texte
enrichi CommonMark + GFM : gras, italique, titres, listes, cases à cocher,
citations, blocs de code, séparateurs. Il ne sait afficher **aucun contenu non
textuel**, et ses commandes ne sont accessibles que par la barre d'outils ou les
raccourcis clavier.

L'inspiration vient d'AppFlowy (menu `/`, diagrammes rendus dans le texte). **Aucun
code d'AppFlowy n'est repris** : le client est en Dart/Flutter, le web en
React/Slate/Yjs, et les deux dépôts principaux sont sous AGPL-3.0 — incompatible
avec une app propriétaire. Seules sont reprises la *conception* du menu (structure
de `slash-menu-options.ts` : clé, libellé, mots-clés, alias, raccourci, groupe,
filtrage contextuel) et l'indication des bibliothèques utilisées. AppFlowy n'écrit
d'ailleurs pas de code de rendu de diagramme : il appelle `mermaid` (npm, MIT),
`prismjs` (MIT) et `katex` (MIT). Ce sont ces bibliothèques MIT que nous
reprenons, à la source.

## Objectifs

1. Un menu `/` qui expose toutes les commandes d'édition, filtrable à la frappe.
2. Des diagrammes **mermaid** rendus dans l'éditeur, à la place du bloc source.
3. Des **images** affichées dans l'éditeur — et non plus perdues (voir bug ci-dessous).
4. L'**import de fichiers draw.io**, convertis en image.
5. Un **seul analyseur markdown** dans l'app : `swift-markdown` partout, au lieu
   d'un analyseur maison concurrent dans `MarkdownText.swift`.

## Non-objectifs

- Modèle de blocs persistés façon AppFlowy. OneToOne est local et mono-utilisateur ;
  le coût (migration de toutes les notes, réécriture des exports, conversion à
  chaque aller-retour avec l'IA) n'achèterait que de l'édition collaborative
  temps réel, dont l'app n'a pas besoin.
- Éditeur graphique de diagrammes (dessin à la souris). Import uniquement.
- Migration TextKit 2. Reste possible plus tard sans toucher au modèle de données.
- Mentions `@collaborateur`, liens vers projet/réunion, tableaux. Fonctionnalités
  à part entière, à traiter dans leurs propres branches.

## Décisions structurantes

| Décision | Choix | Raison |
|---|---|---|
| Stockage | markdown texte, inchangé | l'IA produit et consomme du markdown ; exports et notes existantes intacts |
| Rendu des blocs | `NSTextAttachment` avec `NSImage` | fonctionne en TextKit 1, pas de migration |
| Source du bloc | porté par un attribut du texte | garantit l'aller-retour même si le rendu échoue |
| Moteur mermaid | `mermaid.min.js` embarqué + `WKWebView` | app autonome, hors ligne |
| Conversion `.drawio` | CLI draw.io Desktop si présent | 0 Mo ajouté, dégradation propre si absent |

> **Note du 2026-08-04 — cette section décrit un bug depuis corrigé.** Le cas
> `Markdown.Image` a été ajouté par le commit `05ac0e4` ; il se trouve
> désormais à `MarkdownParser.swift:186-196`. La section est conservée pour la
> trace du raisonnement.

## Bug existant corrigé au passage

`OneToOne/Markdown/Markdown/MarkdownParser.swift:203` — le visiteur inline traite
`Text`, `Strong`, `Emphasis`, `InlineCode`, `Link`, `Strikethrough`, puis :

```swift
default:
    for child in node.children { emitInlineNode(child, into: out) }
```

Aucun cas `Image`. Une image tombe dans le `default`, qui descend dans ses enfants,
c'est-à-dire le texte alternatif. `![Plan R+2](file://…/img_ab12.png)` devient le
texte `Plan R+2` et **l'URL est perdue définitivement** au premier aller-retour.
Une image collée puis ré-enregistrée disparaît. Ce n'est pas un manque de confort
mais une perte de données ; elle est corrigée par la même mécanique que mermaid.

## Architecture

### Principe

Le markdown reste la seule source de vérité. Le parser remplace certains blocs par
un caractère `U+FFFC` (*object replacement character*) portant deux attributs : le
type de bloc et **son texte source intégral**. L'éditeur dessine une image à sa
place. Le serializer relit l'attribut et réécrit le markdown d'origine à
l'identique.

```
  ```mermaid
  flowchart TD                      MarkdownParser      ┌─────────┐
    A[Relevé] --> B[Validation]   ─────────────────→   │ ▭ → ▭  │  NSTextAttachment
  ```                              (swift-markdown)     └─────────┘
        ▲                                                    │
        └──────────────────────────────────────────────────┘
                      MarkdownSerializer
              (relit .mdBlockSource, réécrit le fence)
```

**Invariant central : `parse(serialize(x)) == x` pour tout document.** Le source
vivant dans l'attribut, il ne peut pas être perdu, même si mermaid échoue.

`MarkdownParser` utilise déjà `swift-markdown` d'Apple, et `emitCodeBlock`
(ligne 138) reçoit déjà le langage du fence : détecter ` ```mermaid ` est un `if`
dans une fonction existante.

### Arborescence

```
OneToOne/Markdown/
├── Core/                        (existant, étendu)
│   ├── EditorTextView.swift          + clic sur attachment, glisser-déposer
│   ├── EditorRepresentable.swift     + hôte du panneau slash
│   ├── StyleRenderer.swift           + pose les attachments
│   ├── MarkdownEditingCommands.swift
│   └── ShortcutDetector.swift
├── Markdown/
│   ├── MarkdownParser.swift          + Image, + CodeBlock(mermaid)
│   └── MarkdownSerializer.swift      + réciproque
├── Blocks/                      ★ nouveau
│   ├── BlockRenderer.swift           protocole : source → NSImage
│   ├── MermaidRenderer.swift         WKWebView hors écran + mermaid.min.js
│   ├── ImageBlockRenderer.swift      fichier disque → NSImage
│   └── RenderCache.swift             SHA256(source+thème+largeur) → PNG disque
├── Slash/                       ★ nouveau
│   ├── SlashCommand.swift            modèle d'une entrée
│   ├── SlashCatalog.swift            catalogue, filtrage, groupement
│   ├── SlashPanel.swift              NSPanel + liste SwiftUI
│   └── SlashController.swift         détection, navigation, insertion
├── Media/                       ★ nouveau (déménagement)
│   ├── MediaStore.swift              ex-ImagePasteService
│   └── DrawIOImporter.swift
├── Model/
│   └── MarkdownAttributeKeys.swift   + .mermaid, .image dans BlockType
└── Public/
    └── MarkdownFeature.swift         + .slashMenu, .mermaid, .image
```

Chaque dossier a une responsabilité unique et se teste isolément : `Blocks/` ignore
l'éditeur (texte → image), `Slash/` ignore le markdown (produit une commande
d'édition), `Media/` ne connaît que le disque.

### TextKit 1 conservé

`NSTextAttachment` porteur d'une `NSImage` fonctionne en TextKit 1, que
`EditorRepresentable.swift:31-45` monte explicitement
(`NSTextStorage → NSLayoutManager → NSTextContainer`). Pas de migration, donc pas
de revalidation des cases à cocher cliquables, de l'auto-format à la frappe ni de
la barre d'outils.

> Note : le plan de 2026-05-22 annonçait TextKit 2 dans sa pile technique, mais
> l'implémentation livrée est bien TextKit 1 — un commentaire du code explique que
> c'était pour contourner un bug de `scrollableTextView()`. Le présent design
> s'appuie sur le code réel.

`NSTextAttachmentViewProvider` (vues vivantes inline, macOS 12+) exigerait TextKit 2.
Non retenu : pour un diagramme, une image statique suffit — on le regarde, on ne le
manipule pas.

## Le menu `/`

### Déclenchement et cycle de vie

`/` tapé en début de ligne ou après une espace ouvre un `NSPanel` sans bordure et
non-activant (le focus reste dans le texte), positionné sous le curseur via
`firstRect(forCharacterRange:)`.

| Touche | Effet |
|---|---|
| lettres | filtre la liste en direct |
| ↑ ↓ | navigue |
| ⏎ / Tab | insère |
| Échap | ferme, conserve le `/` tapé |
| ⌫ avant le `/` | ferme |
| clic ailleurs | ferme |

À l'insertion, le texte `/requête` est effacé puis la commande applique le
changement de bloc.

> **Correction du 2026-08-04 — cette section disait le contraire.** Elle
> prévoyait d'appeler `MarkdownEditingCommands`, « les mêmes fonctions que la
> barre d'outils ». Une enquête sur le code a établi que ce chemin est
> destructeur et qu'il ne faut pas l'emprunter.
>
> `MarkdownEditingCommands` manipule des marqueurs markdown **littéraux**
> (`## `, `- `), mais ses deux appelants lui passent `tv.string`, c'est-à-dire
> le texte **d'affichage**, qui n'en contient aucun — le storage de l'éditeur
> ne porte que des attributs. Le résultat est ensuite reparsé intégralement.
> Mesures d'exécution :
>
> | Action | Entrée | Résultat |
> |---|---|---|
> | bouton h2 | `Voici du **gras** et un [lien](https://ex.com)` | `## Voici du gras et un lien` — gras et lien détruits |
> | bouton liste | `Avant ![alt](file:///tmp/a.png) après` | `- Avant ￼ après` — URL perdue, fichier orphelin |
> | bouton h2 ×2 | `## Titre` | `## Titre` — jamais réversible |
>
> Le second cas est exactement la corruption d'image que cette branche a
> écartée dans `EditorTextView.paste`, réintroduite par une autre porte.
>
> Le bon mécanisme est de muter les attributs du `NSTextStorage`
> (`.mdBlockType`, `.mdListInfo`) sur la plage de la ligne, puis d'appeler
> `StyleRenderer.applyVisualStyle` et `didChangeText()`. Vérifié : le `.mdBold`
> d'une ligne survit et `serialize` produit bien `## Voici du **gras** ici`.
> C'est déjà le mécanisme des boutons gras/italique (`toggleInlineAttribute`),
> qui eux ne perdent rien.
>
> L'intention « un seul chemin d'édition » reste valable, mais dans l'autre
> sens : écrire une couche `MarkdownBlockCommands` opérant par attributs, y
> brancher le menu `/` **et** la barre d'outils, puis retirer
> `toggleLinePrefix` et `wrapSelection` (cette dernière n'a aucun appelant en
> production).

### Catalogue

Chaque entrée est conditionnée par un `MarkdownFeature` : un champ configuré en
`.basic` n'affiche que ce qu'il sait faire.

| Groupe | Entrées |
|---|---|
| **Blocs de base** | Texte, Titre 1 `#`, Titre 2 `##`, Titre 3 `###`, Liste à puces `-`, Liste numérotée `1.`, Case à cocher `[]`, Citation `>`, Séparateur `---`, Bloc de code ` ``` ` |
| **Média** | Image (fichier ou presse-papiers), Diagramme mermaid, Importer un `.drawio` |
| **IA** | Résumer, Reformuler, Continuer l'écriture, Extraire les actions |

Le groupe IA réutilise les services existants (`DirectLLMClient`, `SavedPrompt`) ;
aucun nouveau service. **À vérifier à l'écriture du plan** : si la plomberie
« appliquer un prompt à une sélection » n'existe pas déjà, ce groupe bascule en
étape 5 plutôt que d'élargir les étapes précédentes.

## Les blocs

### Protocole de rendu

```swift
/// Apparence demandée pour le rendu — fait partie de la clé de cache.
enum BlockRenderAppearance: String { case light, dark }

protocol BlockRenderer {
    func render(source: String,
                appearance: BlockRenderAppearance,
                width: CGFloat) async throws -> NSImage
}
```

Trois implémentations : mermaid, image disque, draw.io. Aucune ne connaît
l'éditeur.

### Moteur mermaid

`WKWebView` hors écran, instance unique partagée, pilotée par un acteur
`MermaidRenderer`. Le bundle embarque `mermaid.min.js` (**3,4 Mo mesurés**, MIT) et
une page HTML locale. Sortie SVG convertie en `NSImage`. Aucun accès réseau, ce qui
est cohérent avec la ligne on-device du projet.

`Package.swift` déclare déjà `resources: [.process("Resources")]` — le JS s'y range.
**Point de vigilance** : `Scripts/bump-and-build.sh` fabrique le `.app` ; vérifier
que la ressource atterrit bien dans `Contents/Resources` du bundle final.

### Rendu asynchrone et cache

L'affichage du texte n'attend jamais un rendu.

```
parse → attachment « placeholder » (cadre gris, taille estimée) posé immédiatement
      → RenderCache interrogé : clé = SHA256(source + thème + largeur)
         ├─ trouvé  → image posée dans la foulée, aucun calcul
         └─ absent  → rendu en tâche de fond, puis remplace le placeholder
```

Cache disque dans `Application Support/OneToOne/render-cache/`, cohérent avec
`images/` et les enregistrements. La clé inclut le thème : la bascule clair/sombre
déclenche un re-rendu sans invalidation manuelle.

Remplacer l'image d'un attachment **ne modifie pas `NSTextStorage`** : pas de pile
d'annulation polluée, pas de sauvegarde déclenchée, pas de curseur qui saute.

### Erreurs

Mermaid a une syntaxe stricte et l'IA en produit parfois de l'invalide. Un
diagramme cassé affiche un cadre rouge avec le message de mermaid, et **le fence
source reste intact dans le markdown**. Aucun scénario où une erreur de rendu
abîme le document.

### Édition d'un bloc

Clic sur un schéma → l'attachment est remplacé par le texte du fence, encadré en
police à chasse fixe, curseur placé dedans. Échap ou clic ailleurs → re-rendu.
C'est une substitution de texte ordinaire, donc ⌘Z se comporte normalement.

### Images et draw.io

`ImagePasteService` (`Views/EditableTextField.swift:6-59`) fait déjà le travail :
sauvegarde dans `Application Support/OneToOne/images/`, compression JPEG au-delà de
2 Mo, référence markdown. Il devient `Media/MediaStore.swift` **sans changement de
comportement ni de format sur disque**.

Ajouts : glisser-déposer d'un fichier dans l'éditeur, entrée « Image » du menu `/`.

`DrawIOImporter` accepte :

| Entrée | Traitement |
|---|---|
| `.png` / `.svg` exporté de draw.io | affiché tel quel ; le XML embarqué (option `--embed-diagram`) est conservé, le fichier reste ré-ouvrable dans draw.io |
| `.drawio` brut | converti en PNG via le CLI si draw.io Desktop est installé ; sinon message clair demandant un export PNG |

CLI vérifié sur la machine cible : draw.io Desktop 30.2.6,
`/Applications/draw.io.app/Contents/MacOS/draw.io -x -f png -e`.

Dans tous les cas le résultat est une image dans `images/` et une référence markdown
standard `![alt](url)`. Aucune syntaxe propriétaire : les notes restent lisibles par
n'importe quel outil.

## Unification des chemins markdown

État actuel — quatre endroits traitent du markdown :

| Fichier | Nature | Action |
|---|---|---|
| `OneToOne/Markdown/` | `swift-markdown` → `NSAttributedString` | référence, à étendre |
| `Services/Report/MarkdownToHTMLRenderer.swift` | `swift-markdown` → HTML | **légitime** — même AST, cible différente ; doit apprendre mermaid |
| `Views/MarkdownText.swift` | analyseur ligne-à-ligne **écrit à la main**, 198 lignes | consomme `MarkdownParser` ; ne garde que le rendu SwiftUI |
| `Views/EditableTextField.swift` | `ImagePasteService`, `PastableMarkdownTextView`, `MarkdownEditorRegistry` | `ImagePasteService` → `Media/MediaStore.swift` ; collage intégré à `EditorTextView` |

Seul `MarkdownText.swift` est une vraie duplication : son analyseur divergera dès
l'ajout de mermaid, produisant un diagramme visible en édition et des lignes brutes
en aperçu.

`MarkdownToHTMLRenderer` doit gérer le cas `CodeBlock(language: "mermaid")` en
insérant l'image rendue (référence fichier ou data-URI base64), sinon un diagramme
disparaît des rapports exportés.

Ce déplacement est mécanique et sans changement fonctionnel : il se fait **en
premier**, sur une base de tests verte.

## Tests

Le projet utilise Swift Testing + XCTest. Tests markdown existants :
`MarkdownParserTests`, `MarkdownSerializerTests`, `MarkdownRoundTripTests`,
`MarkdownEditingCommandsTests`, `MarkdownToHTMLRendererTests`.

1. **Aller-retour** — `parse(serialize(x)) == x` sur un corpus élargi : mermaid,
   images, code, listes imbriquées, cases à cocher, contenus mélangés. Filet de
   sécurité principal ; attrape le bug d'image ci-dessus.
2. **Catalogue slash** — filtrage, groupement, respect des `MarkdownFeature`.
   Logique pure, sans interface.
3. **Cache de rendu** — même source ⇒ aucun second rendu ; thème changé ⇒ re-rendu ;
   erreur mermaid ⇒ pas d'exception propagée, source préservé.
4. **HTML** — un diagramme mermaid dans une note produit bien une image dans le
   rapport exporté.

Le rendu mermaid réel passe par `WKWebView` : couvert par un unique cas
d'intégration, hors tests unitaires.

## Découpage

| # | Étape | Livrable vérifiable |
|---|---|---|
| 1 | Unification des chemins + tests d'aller-retour élargis | comportement identique, tests verts, une seule définition du markdown |
| 2 | Attachments + support des images | bug de perte d'URL corrigé, images affichées en place |
| 3 | Menu `/` avec les blocs de base | le menu couvre tout ce que l'éditeur sait déjà faire |
| 4 | Bloc mermaid + cache + erreurs + rendu HTML | diagrammes rendus en édition, en aperçu et dans les rapports |
| 5 | Import draw.io + entrées IA | périmètre complet |

Chaque étape est indépendamment utile et sans régression. Un arrêt après l'étape 3
laisse déjà un éditeur nettement meilleur.

## Risques

| Risque | Parade |
|---|---|
| `mermaid.min.js` absent du `.app` packagé | vérifier le bundle dès l'étape 4 ; échec de rendu ⇒ cadre d'erreur, jamais de perte de source |
| Aller-retour cassé par les attachments | tests d'aller-retour écrits à l'étape 1, avant toute modification du parser |
| Régression sur `MarkdownText.swift` | son analyseur maison peut différer subtilement de `swift-markdown` ; comparer les sorties sur les notes réelles avant bascule |
| 3,4 Mo ajoutés au bundle | accepté ; alternative (CLI draw.io pour mermaid aussi) rejetée car dépendance externe |
| Périmètre du groupe IA | vérifié à l'écriture du plan ; bascule en étape 5 si la plomberie manque |
