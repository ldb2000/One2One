#!/bin/bash
# prepare-mlx-metallib.sh
# SwiftPM ne compile pas les shaders Metal (doc officielle mlx-swift).
# Ce script récupère le `default.metallib` compilé par Xcode (via Mickey.app
# ou DerivedData Xcode de mlx-swift) et le place là où MLX le cherche au
# démarrage de l'exécutable.
#
# Usage :
#   Scripts/prepare-mlx-metallib.sh                 # toutes les config (debug + release)
#   Scripts/prepare-mlx-metallib.sh debug           # uniquement .build/debug
#   Scripts/prepare-mlx-metallib.sh release
#
# À relancer :
#   - après `swift package clean` / suppression de `.build`
#   - après rebuild de Mickey (si la version du metallib change)

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-all}"

# --- Localise un default.metallib utilisable ---
MLX_METALLIB=""
for CANDIDATE in \
    "/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Library/Developer/Xcode/DerivedData/Mickey-"*"/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Library/Developer/Xcode/DerivedData/Mickey-"*"/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Library/Developer/Xcode/DerivedData/mlx-swift-"*"/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
do
    for M in ${CANDIDATE}; do
        if [ -f "$M" ]; then
            MLX_METALLIB="$M"
            break 2
        fi
    done
done

if [ -z "${MLX_METALLIB}" ]; then
    echo "✗ Aucun default.metallib trouvé."
    echo "  Solutions :"
    echo "   1. Installer Mickey.app (build Xcode) : les ressources MLX seront disponibles"
    echo "   2. Ouvrir .build/checkouts/mlx-swift/xcode/MLX.xcodeproj dans Xcode et build le scheme mlx-swift-Package"
    exit 1
fi

echo "→ Source metallib : ${MLX_METALLIB}"

# --- Copie dans les dirs SwiftPM debug/release ---
configure() {
    local CONFIG="$1"
    local BUILD_DIR="${REPO_ROOT}/.build/${CONFIG}"
    if [ ! -d "${BUILD_DIR}" ]; then
        echo "  Skip ${CONFIG}: ${BUILD_DIR} absent. Lance 'swift build -c ${CONFIG}' d'abord."
        return
    fi

    local BUNDLE_RES="${BUILD_DIR}/mlx-swift_Cmlx.bundle/Contents/Resources"
    mkdir -p "${BUNDLE_RES}"
    cp "${MLX_METALLIB}" "${BUNDLE_RES}/default.metallib"

    # Info.plist minimal (pour que CFBundleGetBundleWithIdentifier reconnaisse le bundle).
    cat > "${BUILD_DIR}/mlx-swift_Cmlx.bundle/Contents/Info.plist" << 'PLIST_EOF'
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

    # Fallback : metallib colocated (MLX cherche aussi `mlx.metallib` à côté du binaire).
    cp "${MLX_METALLIB}" "${BUILD_DIR}/mlx.metallib"

    echo "✓ ${CONFIG} : ${BUNDLE_RES}/default.metallib + ${BUILD_DIR}/mlx.metallib"
}

case "${TARGET}" in
    all)
        configure debug
        configure release
        ;;
    debug|release)
        configure "${TARGET}"
        ;;
    *)
        echo "Usage: $0 [all|debug|release]"
        exit 1
        ;;
esac

echo "✓ Done. Tu peux maintenant lancer : ./.build/debug/OneToOne  ou  swift run"
