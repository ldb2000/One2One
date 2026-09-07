# Moteur de planches : Excalidraw embarqué dans un `WKWebView`

- **Date :** 2026-09-07
- **Statut :** acceptée (décision **D6** du plan directeur `docs/superpowers/plans/2026-09-07-refonte-reunion-programme.md`)
- **Lot :** 16 — Atelier : socle des planches et mode Croquis (6a partiel)
- **Périmètre :** type de réunion `Atelier`, derrière le drapeau `AppSettings.workshopEnabled` (défaut `false`)

## Contexte

La spécification `docs/superpowers/specs/refonte-2026-09/specs-one2one.md` §7 introduit un type de
réunion **Atelier** dont la production n'est pas du texte mais des **planches** : croquis à main
levée, schéma à formes et connecteurs, manuscrit au stylet. Les cibles annoncées (§7.4) sont
exigeantes :

- 2 000 objets par planche à 60 fps, 40 planches par réunion ;
- historique d'annulation de profondeur 100 **par planche** ;
- bibliothèque de formes et connecteurs magnétisés (mode Schéma, lot 17) ;
- export PNG, SVG et format natif ;
- **aucune requête réseau, aucun compte, fonctionnement complet hors ligne** (§7.4, §8).

Le code existant n'offre aucun canevas interactif. Les deux seuls précédents de dessin sont
`Vendor/BeautifulMermaidSwift` (rendu statique CoreGraphics + elk) et `OneToOne/Markdown/Blocks/MermaidRenderer.swift`,
qui charge `mermaid.min.js` (3,4 Mo) dans un `WKWebView` **hors écran** en inlinant le script dans
le HTML — WebKit refuse les `file://` relatives depuis une page chargée par `loadHTMLString`.

## Décision

**Excalidraw (MIT) est embarqué dans l'application et rendu dans un `WKWebView` plein cadre.**

- Le bundle est construit **hors du dépôt** par `Scripts/build-excalidraw-bundle.sh`, qui produit un
  fichier JS unique (IIFE) et sa feuille de style, tous deux **commités** dans
  `OneToOne/Resources/Whiteboard/` — même politique que `mermaid.min.js`. Le script sert à
  régénérer, pas à builder l'app.
- Le point d'entrée `Scripts/excalidraw-entry.jsx` monte `<Excalidraw>` et expose une API réduite
  sur `window.oneToOneBoard` (`load`, `getScene`, `exportPNG`, `exportSVG`, `exportThumbnail`,
  `setTool`, `setColor`, `setStrokeWidth`, `undo`, `redo`, `zoomTo`, `fitToScreen`, `setMode`). Les
  notifications (`ready`, `change`) remontent par `window.webkit.messageHandlers.board`.
- **Un seul moteur pour les trois modes** : Croquis, Schéma et Manuscrit ne sont pas trois moteurs
  mais trois jeux de réglages (`setMode`) — rugosité, fonte, style de trait, outil par défaut.
- **Toute la chrome est native.** L'interface d'Excalidraw (`.layer-ui__wrapper`) est masquée en CSS ;
  la barre d'outils 32 px, la palette verticale 52 px et le dock 314 px sont du SwiftUI aux jetons
  `One2OneToken`, conformément à la capture `6a-atelier-planche.png`.
- **Export `.drawio` hors v1** (spec §7.3 le mentionne « en secours seulement »). PNG et SVG sont
  natifs au moteur ; le format `.excalidraw` est le format de scène persisté.
- **Mono-utilisateur** (décision D11) : la pilule de présence de la maquette est masquée, les champs
  de session (`collaborators`, sélections, curseurs) ne sont pas persistés.

### Versions épinglées

| Paquet | Version |
| --- | --- |
| `@excalidraw/excalidraw` | 0.18.1 |
| `react` | 18.3.1 |
| `react-dom` | 18.3.1 |
| `esbuild` | 0.28.2 |

Toute montée de version passe par `Scripts/build-excalidraw-bundle.sh` et met à jour ce tableau
ainsi que `OneToOne/Resources/Whiteboard/VERSIONS.txt`, écrit par le script.

## Alternatives écartées

### (b) Moteur natif CoreGraphics / SwiftUI `Canvas`, écrit de zéro

Techniquement le plus propre — pas de WebKit, pas de pont, pas de 3,5 Mo de ressource. Mais il
faudrait écrire, tester et maintenir : le hit-testing, la sélection multiple, les poignées de
redimensionnement et de rotation, l'historique 100 niveaux, l'édition de texte dans la forme, les
connecteurs magnétisés avec points d'ancrage, le lissage de trait à main levée, le zoom/panoramique
tuilé pour tenir 60 fps à 2 000 objets, et deux exportateurs (PNG, SVG). C'est un projet à part
entière, pas un lot. Écarté sur le délai, pas sur le principe : si le pont JS devient un fardeau,
c'est la sortie de secours (le format de scène reste lisible).

### (c) Hybride : natif pour Manuscrit, Excalidraw pour Croquis et Schéma

Deux moteurs, deux formats de scène, deux exportateurs, et la règle §7.1 (« changer de mode crée une
nouvelle planche ») deviendrait « changer de mode change de moteur ». Le dock devrait afficher des
vignettes produites par deux chaînes différentes. Écarté : le coût de la couture dépasse le gain.

### tldraw

Excellent moteur, API React comparable. **Licence** : tldraw v2 est sous une licence propriétaire
« tldraw license » (watermark obligatoire, licence commerciale payante pour le retirer). Écarté sur
la licence, pas sur la technique.

### draw.io / diagrams.net embarqué

Le mode Schéma de la spec §7.1 dit explicitement « type draw.io ». `drawio` est sous Apache-2.0 et
s'embarque, mais : l'intégration se fait par `iframe` + `postMessage` sur une application complète
(éditeur, menus, dialogues) qu'on ne peut pas réduire à un canevas ; le bundle dépasse 10 Mo ; et il
faudrait alors **deux** moteurs (draw.io ne fait pas de main levée). Écarté au profit de la
bibliothèque de formes d'Excalidraw (lot 17). L'export `.drawio` reste hors v1.

## Conséquences

### Taille du bundle

`excalidraw.bundle.js` pèse **3,1 Mo** (fontes `woff2` inlinées comprises) et
`excalidraw.bundle.css` **248 Ko**, soit ~3,5 Mo — l'ordre de grandeur de `mermaid.min.js`
(3,4 Mo) déjà embarqué. Deux allègements délibérés (`Scripts/excalidraw-esbuild.mjs`), sans quoi le
fichier ferait 8,5 Mo :

- **les 55 traductions** d'Excalidraw sont remplacées par des modules vides, sauf `en` (repli du
  moteur) et `fr-FR` — l'interface d'Excalidraw est masquée, ses libellés ne sont jamais affichés ;
- **le convertisseur Mermaid → Excalidraw** (mermaid + chevrotain + langium, ~4 Mo) est remplacé
  par une souche qui lève : sa boîte de dialogue n'est pas atteignable.
- la famille de fontes **Xiaolai** (12,5 Mo de glyphes CJK) n'est pas inlinée : ses URI deviennent
  des `data:` vides et le rendu retombe sur la fonte système.

### CSP et absence de réseau

La page produite par `WhiteboardHTML.page()` porte

```
default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:
```

et n'a **ni `<script src>` ni `<link href>`** : le JS et le CSS sont inlinés, comme pour Mermaid.
Les 230 fontes `./fonts/**.woff2` référencées par Excalidraw sont réécrites en
`data:font/woff2;base64,…` par le script de construction ; `Fonts.createUrls` rend une telle URI
telle quelle et ne consulte jamais son CDN de secours. Ce CDN (`esm.sh`) et les autres bases
interrogeables du moteur (partage de scène `json.excalidraw.com`, bibliothèque publique, points
d'entrée IA et collaboration) sont malgré tout réécrites en `file:///excalidraw-disabled/…`.

**Écart assumé, testé par `WhiteboardHTMLTests` :** le bundle contient encore des URL `http(s)`
qui ne sont *pas* des ressources chargées — les deux espaces de noms XML du W3C
(`http://www.w3.org/2000/svg`, `http://www.w3.org/1999/xhtml`), **indispensables** à
`createElementNS` et donc à l'export SVG, et des constantes de liens d'interface (github.com,
youtube.com, plus.excalidraw.com…) situées dans la chrome masquée. Le test vérifie donc :
présence exacte de la CSP, absence de tout attribut `src`/`href` réseau, absence de toute URL de
fonte non-`data:`, et absence des bases interrogeables listées ci-dessus. La CSP
`default-src 'none'` rend les constantes résiduelles inertes.

### Pont JS

Le pont est un **protocole Swift** (`WhiteboardBridge`, `OneToOne/Services/Workshop/`) : la règle
métier et `BoardStore` sont testés contre un double, jamais contre WebKit. `swift test` ne charge
aucun `WKWebView` (parade du plan §8 : « aucun test ne touche MLX, ScreenCaptureKit ou WebKit
interactif »). Coûts acceptés :

- **un seul `WKWebView` vivant par réunion**, porté par `WorkshopState` : le bundle est réanalysé à
  chaque création de vue, il ne faut donc pas en créer une par planche ;
- l'annulation/rétablissement passe par un **rejeu de raccourci clavier** — Excalidraw n'expose pas
  `undo()`/`redo()` dans son API impérative (`history` ne porte que `clear()`) ;
- la pression du stylet n'est pas transmise par WebKit ; le mode Manuscrit du lot 17 devra la
  pousser depuis un moniteur `NSEvent` ou se contenter d'une épaisseur fixe (spec : « pression si
  disponible »).

### Licence

Excalidraw est sous **MIT** ; React et React DOM également. Le texte de la licence est copié dans
`OneToOne/Resources/Whiteboard/LICENSE-excalidraw.txt` avec la liste des fontes embarquées et leurs
licences (OFL / Apache-2.0). Aucune dépendance SwiftPM n'est ajoutée : le bundle est une
**ressource**, conformément à la règle invariable du plan §7.

### Stockage

`Board.scenePath` / `Board.thumbPath` pointent des fichiers **sur disque**
(`recordings/<uuid de la réunion>/boards/<stableID>.excalidraw.json` et `.png`), pas des colonnes :
une scène de 2 000 objets pèse plusieurs mégaoctets et la stocker en base ferait grossir le store à
chaque trait. `StorageStatsService` compte le dossier `boards/`, `BackupService` embarque scène et
vignette en base64 dans un `BoardDTO`.
