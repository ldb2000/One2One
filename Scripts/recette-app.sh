#!/bin/bash
# recette-app.sh — empaquette un OneToOne.app **de recette**.
#
# À quoi ça sert
#   Comparer un écran à sa maquette demande un vrai bundle `.app` : hors
#   bundle, les fontes IBM Plex embarquées ne sont pas enregistrées et le
#   `default.metallib` de MLX est introuvable. `Scripts/bump-and-build.sh`
#   sait faire cela, mais il **incrémente** `CFBundleVersion` et **installe**
#   dans `~/Applications` ou `/Applications` : deux effets de bord
#   inacceptables depuis un worktree de travail, où l'on ne veut ni toucher au
#   dépôt principal ni remplacer l'application installée de l'utilisateur.
#
#   Ce script ne fait que la partie empaquetage : binaire, `Info.plist`,
#   `PkgInfo`, bundle de ressources SwiftPM, `default.metallib` si on le
#   trouve, signature ad hoc. **Il n'incrémente rien et n'installe rien.**
#
# Usage
#   swift build -c release          # ou debug, cf. --config
#   Scripts/recette-app.sh [dossier-de-sortie] [--config debug|release] [--force]
#
#   dossier-de-sortie   défaut : "${TMPDIR}/onetoone-recette"
#   --config            défaut : release
#   --force             empaquette même si le binaire est plus vieux que les
#                       sources (cf. « Fraîcheur » ci-dessous)
#
# Sortie
#   <dossier-de-sortie>/OneToOne.app, à lancer avec Scripts/recette-run.sh.
#   Son `CFBundleIdentifier` porte le suffixe `.recette` et son `CFBundleName`
#   est « OneToOne (recette) » : aucun outil système ne peut alors le confondre
#   avec l'application de l'utilisateur — c'est ainsi qu'une fenêtre de
#   production a été redimensionnée pendant la recette des vagues 1-4.
#
# Fraîcheur du binaire (écart (c) n° 12 de cette recette)
#   Le premier bundle de la session du 7 septembre 2026 venait d'un
#   `.build/release/OneToOne` antérieur au build en cours : il lui manquait
#   trois lots, ce qui a produit deux heures d'observations fausses avant que
#   la comparaison des chaînes du binaire ne le révèle. Le script refuse
#   maintenant, affiche le `md5` de ce qu'il copie, et vérifie que la copie
#   correspond à la source.
#
# Vérification (manuelle, une minute — aucun test SwiftPM n'exécute un script)
#   1. swift build -c release && Scripts/recette-app.sh /tmp/rec
#      → « Binaire : md5 … », « Identité de recette : com.onetoone.app.recette »
#   2. touch OneToOne/OneToOneApp.swift && Scripts/recette-app.sh /tmp/rec
#      → « ✗ Binaire périmé : 1 fichier(s) source plus récent(s) », code 1
#   3. Scripts/recette-app.sh /tmp/rec --force
#      → « ⚠️  Binaire périmé … empaquetage forcé », code 0
#   4. /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
#        /tmp/rec/OneToOne.app/Contents/Info.plist   → …app.recette
#
# Cf. Scripts/bump-and-build.sh (dont la partie empaquetage est reprise) et
# CLAUDE.md § « MLX / Metal — default.metallib requis ».

set -e

APP_NAME="OneToOne"
CONFIGURATION="release"
OUT_DIR=""
FORCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            CONFIGURATION="${2:-release}"
            shift 2
            ;;
        --config=*)
            CONFIGURATION="${1#*=}"
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            sed -n '2,58p' "$0"
            exit 0
            ;;
        *)
            OUT_DIR="$1"
            shift
            ;;
    esac
done

case "${CONFIGURATION}" in
    debug|release) ;;
    *)
        echo "✗ --config attend 'debug' ou 'release' (reçu : ${CONFIGURATION})"
        exit 1
        ;;
esac

if [ -z "${OUT_DIR}" ]; then
    OUT_DIR="${TMPDIR:-/tmp}onetoone-recette"
fi

# Le dossier courant fait foi : le script s'utilise depuis un worktree.
REPO_ROOT="$(pwd)"
BINARY="${REPO_ROOT}/.build/${CONFIGURATION}/${APP_NAME}"
INFO_PLIST="${REPO_ROOT}/Info.plist"
RESOURCE_BUNDLE="${REPO_ROOT}/.build/${CONFIGURATION}/${APP_NAME}_${APP_NAME}.bundle"
APP="${OUT_DIR}/${APP_NAME}.app"

if [ ! -x "${BINARY}" ]; then
    echo "✗ Binaire introuvable : ${BINARY}"
    echo "  Lance d'abord : swift build$( [ "${CONFIGURATION}" = release ] && echo ' -c release' )"
    exit 1
fi
if [ ! -f "${INFO_PLIST}" ]; then
    echo "✗ Info.plist introuvable : ${INFO_PLIST} (lance le script depuis la racine du dépôt)"
    exit 1
fi

# ----------------------------------------------------------------------
# Fraîcheur du binaire — écart (c) n° 12 de la recette des vagues 1-4. Un
# bundle empaqueté depuis un binaire antérieur au build en cours ne se voit
# pas : l'application démarre, les écrans s'affichent, et ce sont ceux d'il y
# a trois lots. Deux heures d'observations ont été perdues ainsi.
# ----------------------------------------------------------------------
PLUS_RECENT="$(find OneToOne -name '*.swift' -newer "${BINARY}" 2>/dev/null | head -1)"
if [ -n "${PLUS_RECENT}" ]; then
    NB="$(find OneToOne -name '*.swift' -newer "${BINARY}" 2>/dev/null | wc -l | tr -d ' ')"
    if [ -n "${FORCE}" ]; then
        echo "⚠️  Binaire périmé : ${NB} source(s) plus récente(s), dont"
        echo "    ${PLUS_RECENT}"
        echo "    — empaquetage forcé par --force."
    else
        echo "✗ Binaire périmé : ${NB} fichier(s) source plus récent(s) que"
        echo "  ${BINARY}"
        echo "  Le premier : ${PLUS_RECENT}"
        echo ""
        echo "  Reconstruis d'abord :"
        echo "      swift build$( [ "${CONFIGURATION}" = release ] && echo ' -c release' )"
        echo "  ou passe --force si tu empaquettes sciemment un binaire ancien."
        exit 1
    fi
fi

echo "→ Empaquetage de recette (${CONFIGURATION}) dans ${APP}"
mkdir -p "${OUT_DIR}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BINARY}" "${APP}/Contents/MacOS/${APP_NAME}"

# Ce qu'on vient réellement de copier, dit à voix haute — et vérifié : une
# copie tronquée par un disque plein donnerait un bundle qui démarre mal sans
# qu'on sache pourquoi.
MD5_SOURCE="$(md5 -q "${BINARY}")"
MD5_BUNDLE="$(md5 -q "${APP}/Contents/MacOS/${APP_NAME}")"
if [ "${MD5_SOURCE}" != "${MD5_BUNDLE}" ]; then
    echo "✗ La copie du binaire ne correspond pas à la source :"
    echo "  source ${MD5_SOURCE}"
    echo "  bundle ${MD5_BUNDLE}"
    exit 1
fi
echo "→ Binaire : md5 ${MD5_SOURCE}"
echo "            $(du -h "${BINARY}" | cut -f1), modifié le $(date -r "${BINARY}" '+%Y-%m-%d %H:%M:%S')"

# `Info.plist` copié **tel quel** : aucun bump de CFBundleVersion, c'est la
# différence avec bump-and-build.sh. Deux clés sont ensuite réécrites, et
# elles seules.
cp "${INFO_PLIST}" "${APP}/Contents/Info.plist"
printf "APPL????" > "${APP}/Contents/PkgInfo"

# ----------------------------------------------------------------------
# Identité distincte du bundle de recette — écart (c) n° 7. Deux instances
# qui partagent le même `CFBundleIdentifier` se confondent dans les outils
# système : le 7 septembre 2026, une fenêtre de production a été
# redimensionnée à la place de celle de la recette. Un suffixe suffit à
# rendre la confusion impossible.
# ----------------------------------------------------------------------
BASE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist" 2>/dev/null)"
if [ -n "${BASE_ID}" ]; then
    case "${BASE_ID}" in
        *.recette) RECETTE_ID="${BASE_ID}" ;;
        *)         RECETTE_ID="${BASE_ID}.recette" ;;
    esac
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${RECETTE_ID}" \
        "${APP}/Contents/Info.plist" >/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleName OneToOne (recette)" \
        "${APP}/Contents/Info.plist" >/dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleName string OneToOne (recette)" \
            "${APP}/Contents/Info.plist" >/dev/null
    echo "→ Identité de recette : ${RECETTE_ID} · « OneToOne (recette) »"
else
    echo "⚠️  CFBundleIdentifier illisible : le bundle de recette gardera"
    echo "    l'identité de l'application. Cible tes fenêtres par pid."
fi

# Bundle de ressources SwiftPM : fontes IBM Plex, sample_projects.json…
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP}/Contents/Resources/"
else
    echo "⚠️  Bundle de ressources absent (${RESOURCE_BUNDLE}) — les fontes Plex retomberont sur la fonte système."
fi

# MLX metallib : SwiftPM ne compile pas les shaders Metal. Sans lui, MLX
# crashe à la première opération GPU. Une recette visuelle ne lance pas de
# transcription, donc son absence est tolérable — mais on le copie si on l'a.
MLX_METALLIB=""
for CANDIDATE in \
    "/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "/Applications/${APP_NAME}.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Applications/${APP_NAME}.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
do
    for M in ${CANDIDATE}; do
        if [ -f "$M" ]; then
            MLX_METALLIB="$M"
            break 2
        fi
    done
done

if [ -n "${MLX_METALLIB}" ]; then
    echo "→ metallib MLX depuis : ${MLX_METALLIB}"
    MLX_DIR="${APP}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources"
    mkdir -p "${MLX_DIR}"
    cp "${MLX_METALLIB}" "${MLX_DIR}/default.metallib"
    cat > "${APP}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>mlx-swift_Cmlx</string>
    <key>CFBundleName</key>
    <string>mlx-swift_Cmlx</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
</dict>
</plist>
PLIST_EOF
else
    echo "⚠️  metallib MLX introuvable — la transcription crashera. Sans effet sur une recette visuelle."
fi

# Signature ad hoc : LaunchServices refuse d'ouvrir un bundle non signé
# fraîchement écrit. ⚠️ L'autorisation « Enregistrement de l'écran » n'est pas
# héritée par un bundle ad hoc (cf. programme §2.4 point 7).
codesign --force --sign - --deep "${APP}" 2>/dev/null || \
    echo "  (signature ad hoc échouée — on continue)"

echo "✓ ${APP}"
echo "  Lancer :  Scripts/recette-run.sh --app \"${APP}\" --seed"
