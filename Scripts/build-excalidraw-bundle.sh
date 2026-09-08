#!/bin/bash
# Reconstruit le bundle Excalidraw embarqué (moteur de planches de l'Atelier).
#
# ADR : docs/adr/2026-09-07-moteur-de-planches-excalidraw-embarque.md (décision D6).
#
# Le bundle produit est **commité** dans le dépôt (comme `Resources/mermaid.min.js`) :
# ce script ne sert qu'à le régénérer. Tout se passe dans un dossier temporaire
# **hors du dépôt** — aucun `node_modules`, aucun `package.json` n'entre ici.
#
# Sorties (dans OneToOne/Resources/Whiteboard/) :
#   - excalidraw.bundle.js   : un seul fichier IIFE, fontes woff2 inlinées en `data:`
#   - excalidraw.bundle.css  : la feuille de style d'Excalidraw extraite par esbuild
#   - LICENSE-excalidraw.txt : licence MIT d'Excalidraw
#
# Contraintes tenues par le script (testées par `WhiteboardHTMLTests`) :
#   - aucune fonte n'est chargée depuis le réseau : les 230 `./fonts/**.woff2`
#     référencés par Excalidraw sont remplacés par des `data:font/woff2;base64,…`
#     (`Fonts.createUrls` rend `[uri]` tel quel quand l'URI commence par `data`) ;
#   - les bases réseau du moteur (esm.sh/unpkg pour les fontes, partage de scène,
#     bibliothèque publique) sont réécrites en `file:///…` inatteignables ;
#   - la famille Xiaolai (CJK, 12,5 Mo) est **exclue** : ses URI deviennent des
#     `data:` vides, la fonte retombe sur le système.
#
# Prérequis : Node 22 et npm (ici ~/.local/bin), accès au registre npm.

set -euo pipefail

# --- Versions épinglées (à reporter dans l'ADR en cas de changement) ----------
EXCALIDRAW_VERSION="0.18.1"
REACT_VERSION="18.3.1"
REACT_DOM_VERSION="18.3.1"
ESBUILD_VERSION="0.28.2"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/OneToOne/Resources/Whiteboard"

export PATH="$HOME/.local/bin:$PATH"
command -v node >/dev/null || { echo "node introuvable (attendu dans ~/.local/bin)" >&2; exit 1; }
command -v npm  >/dev/null || { echo "npm introuvable"  >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/onetoone-excalidraw.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
echo "▸ dossier de travail : $WORK"

cd "$WORK"
npm init -y >/dev/null
echo "▸ npm i @excalidraw/excalidraw@$EXCALIDRAW_VERSION react@$REACT_VERSION react-dom@$REACT_DOM_VERSION esbuild@$ESBUILD_VERSION"
npm i --no-audit --no-fund --loglevel=error \
  "@excalidraw/excalidraw@$EXCALIDRAW_VERSION" \
  "react@$REACT_VERSION" \
  "react-dom@$REACT_DOM_VERSION" \
  "esbuild@$ESBUILD_VERSION"

# --- Point d'entrée ----------------------------------------------------------
# Monte <Excalidraw> plein cadre et expose `window.oneToOneBoard`. Le pont Swift
# (`WhiteboardBridge`) n'appelle que ces fonctions ; les notifications remontent
# par `window.webkit.messageHandlers.board.postMessage`.
cp "$REPO_ROOT/Scripts/excalidraw-entry.jsx" "$WORK/entry.jsx"

cp "$REPO_ROOT/Scripts/excalidraw-esbuild.mjs" "$WORK/esbuild.mjs"

echo "▸ esbuild"
node esbuild.mjs

# --- Inlining des fontes + neutralisation du CDN de secours ------------------
echo "▸ inlining des fontes woff2 en data: URL"
node - <<'NODE'
const fs = require("fs");
const path = require("path");

const bundlePath = "out/excalidraw.bundle.js";
const fontsRoot = path.join("node_modules/@excalidraw/excalidraw/dist/prod/fonts");
// Xiaolai : 12,5 Mo de glyphes CJK, hors périmètre — URI vidée, repli système.
const EXCLUDED = new Set(["Xiaolai"]);

let source = fs.readFileSync(bundlePath, "utf8");
let inlined = 0;
let dropped = 0;

source = source.replace(/"\.\/fonts\/([^"]+\.woff2)"/g, (_match, relative) => {
  const family = relative.split("/")[0];
  if (EXCLUDED.has(family)) {
    dropped += 1;
    return '"data:font/woff2;base64,"';
  }
  const file = path.join(fontsRoot, relative);
  const base64 = fs.readFileSync(file).toString("base64");
  inlined += 1;
  return JSON.stringify(`data:font/woff2;base64,${base64}`);
});

// Bases réseau que le moteur pourrait interroger de lui-même. Aucune n'est
// atteinte dans notre usage (toutes les URI de fonte commencent par `data:`,
// donc `Fonts.createUrls` court-circuite `ASSETS_FALLBACK_URL` ; la
// bibliothèque publique, le partage de scène et l'IA ne sont pas exposés dans
// l'interface). On les remplace tout de même : une adresse qui n'existe pas
// dans le fichier ne peut pas être appelée par erreur, et le test
// `WhiteboardHTMLTests` le vérifie.
//
// Ce qui **reste** dans le bundle : les deux espaces de noms XML du W3C
// (indispensables à `createElementNS`, donc à l'export SVG) et des constantes
// de liens d'interface (github.com, youtube.com…) qui vivent dans la chrome
// masquée d'Excalidraw. La CSP `default-src 'none'` les rend inertes.
const NETWORK_BASES = [
  ["https://esm.sh/", "file:///excalidraw-assets/"],
  ["https://unpkg.com/", "file:///excalidraw-assets/"],
  ["https://json.excalidraw.com/api/v2/", "file:///excalidraw-disabled/"],
  ["https://us-central1-excalidraw-room-persistence.cloudfunctions.net/libraries", "file:///excalidraw-disabled/libraries"],
  ["https://excalidraw-room-persistence.firebaseio.com", "file:///excalidraw-disabled"],
  ["https://oss-collab.excalidraw.com", "file:///excalidraw-disabled"],
  ["https://oss-ai.excalidraw.com", "file:///excalidraw-disabled"],
];
let neutralized = 0;
for (const [from, to] of NETWORK_BASES) {
  const parts = source.split(from);
  if (parts.length > 1) {
    neutralized += parts.length - 1;
    source = parts.join(to);
  }
}

fs.writeFileSync(bundlePath, source);
console.log(`   fontes inlinées : ${inlined} · exclues : ${dropped} · bases réseau neutralisées : ${neutralized}`);
if (inlined === 0) { console.error("aucune fonte inlinée — la structure du dist a changé"); process.exit(1); }
if (neutralized === 0) { console.error("aucune base réseau trouvée — vérifier la version d'Excalidraw"); process.exit(1); }
NODE

# --- Copie dans les ressources ------------------------------------------------
mkdir -p "$DEST"
cp out/excalidraw.bundle.js  "$DEST/excalidraw.bundle.js"
cp out/excalidraw.bundle.css "$DEST/excalidraw.bundle.css"

# Licence MIT d'Excalidraw (le paquet npm ne l'embarque pas : texte canonique).
cat > "$DEST/LICENSE-excalidraw.txt" <<'LICENSE'
Excalidraw — MIT License
https://github.com/excalidraw/excalidraw/blob/master/LICENSE

Le fichier excalidraw.bundle.js embarque, outre Excalidraw lui-même, React et
React DOM (MIT, Meta Platforms) ainsi que les fontes livrées par le paquet
@excalidraw/excalidraw (Excalifont, Nunito, ComicShanns, Assistant, Cascadia
Code, Liberation Sans, Lilita One, Virgil), sous leurs licences respectives
(OFL / Apache-2.0 selon la fonte, cf. le dépôt Excalidraw).

MIT License

Copyright (c) 2020 Excalidraw

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSE

cat > "$DEST/VERSIONS.txt" <<VERSIONS
Bundle Excalidraw embarqué — versions épinglées
Régénérer avec Scripts/build-excalidraw-bundle.sh

@excalidraw/excalidraw $EXCALIDRAW_VERSION
react                  $REACT_VERSION
react-dom              $REACT_DOM_VERSION
esbuild                $ESBUILD_VERSION
node                   $(node --version)
construit le           $(date -u +%Y-%m-%dT%H:%M:%SZ)
VERSIONS

echo "▸ écrit dans $DEST"
du -h "$DEST/excalidraw.bundle.js" "$DEST/excalidraw.bundle.css"
