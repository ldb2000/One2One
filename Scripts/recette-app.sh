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
#   Scripts/recette-app.sh [dossier-de-sortie] [--config debug|release]
#
#   dossier-de-sortie   défaut : "${TMPDIR}/onetoone-recette"
#   --config            défaut : release
#
# Sortie
#   <dossier-de-sortie>/OneToOne.app, à lancer avec Scripts/recette-run.sh.
#
# Cf. Scripts/bump-and-build.sh (dont la partie empaquetage est reprise) et
# CLAUDE.md § « MLX / Metal — default.metallib requis ».

set -e

APP_NAME="OneToOne"
CONFIGURATION="release"
OUT_DIR=""

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
        -h|--help)
            sed -n '2,30p' "$0"
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

echo "→ Empaquetage de recette (${CONFIGURATION}) dans ${APP}"
mkdir -p "${OUT_DIR}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BINARY}" "${APP}/Contents/MacOS/${APP_NAME}"
# `Info.plist` copié **tel quel** : aucun bump de CFBundleVersion, c'est la
# différence avec bump-and-build.sh.
cp "${INFO_PLIST}" "${APP}/Contents/Info.plist"
printf "APPL????" > "${APP}/Contents/PkgInfo"

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
