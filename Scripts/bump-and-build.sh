#!/bin/bash
# bump-and-build.sh
# Bumps Info.plist CFBundleVersion to the current git commit count,
# builds OneToOne via SwiftPM, wraps the binary into a proper .app bundle,
# then installs it to the correct location depending on mode.
#
# OneToOne is a SwiftPM executable (no Xcode project). The script builds
#   .build/<config>/OneToOne
# and packages it into OneToOne.app/Contents/{MacOS,Resources} with the
# project's Info.plist + SwiftPM-generated resource bundle.
#
# Usage:
#   Scripts/bump-and-build.sh           # defaults to dev
#   Scripts/bump-and-build.sh dev       # Debug build  → ~/Applications/OneToOne.app
#   Scripts/bump-and-build.sh prod      # Release build → /Applications/OneToOne.app (sudo if needed)

set -e

MODE="${1:-dev}"

case "${MODE}" in
    dev)
        CONFIGURATION="debug"
        INSTALL_DIR="${HOME}/Applications"
        NEEDS_SUDO=""
        ;;
    prod)
        CONFIGURATION="release"
        INSTALL_DIR="/Applications"
        if [ -w "${INSTALL_DIR}" ]; then
            NEEDS_SUDO=""
        else
            NEEDS_SUDO="sudo"
        fi
        ;;
    *)
        echo "Usage: $0 [dev|prod]"
        echo "  dev  (default) : Debug build   → ~/Applications/OneToOne.app"
        echo "  prod           : Release build → /Applications/OneToOne.app"
        exit 1
        ;;
esac

APP_NAME="OneToOne"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

INFO_PLIST="${REPO_ROOT}/Info.plist"
BUILD_PRODUCTS="${REPO_ROOT}/.build/${CONFIGURATION}"
BINARY="${BUILD_PRODUCTS}/${APP_NAME}"
RESOURCE_BUNDLE="${BUILD_PRODUCTS}/${APP_NAME}_${APP_NAME}.bundle"
STAGING="${REPO_ROOT}/.build/stage-${CONFIGURATION}/${APP_NAME}.app"
DEST="${INSTALL_DIR}/${APP_NAME}.app"

# git safe directory — needed if the script runs under sudo.
git config --global --add safe.directory "${REPO_ROOT}" 2>/dev/null || true

BUILD_NUMBER=$(git rev-list --count HEAD)
SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}" 2>/dev/null || echo "1.0")

echo "→ Mode: ${MODE} (${CONFIGURATION})"
echo "→ Bumping CFBundleVersion to ${BUILD_NUMBER} (Short: ${SHORT_VERSION})"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${INFO_PLIST}"

echo "→ Building via SwiftPM (${CONFIGURATION})…"
if [ "${CONFIGURATION}" = "release" ]; then
    swift build -c release 2>&1 | tail -20
else
    swift build 2>&1 | tail -20
fi

if [ ! -x "${BINARY}" ]; then
    echo "✗ Build artifact not found at ${BINARY}"
    exit 1
fi

# ----------------------------------------------------------------------
# Package the SwiftPM binary into a proper macOS .app bundle.
# ----------------------------------------------------------------------
echo "→ Packaging ${APP_NAME}.app bundle at ${STAGING}"
rm -rf "${STAGING}"
mkdir -p "${STAGING}/Contents/MacOS"
mkdir -p "${STAGING}/Contents/Resources"

cp "${BINARY}" "${STAGING}/Contents/MacOS/${APP_NAME}"
cp "${INFO_PLIST}" "${STAGING}/Contents/Info.plist"

# PkgInfo — some macOS APIs still sniff this 8-byte marker.
printf "APPL????" > "${STAGING}/Contents/PkgInfo"

# Embed SwiftPM resource bundle (sample_projects.json etc.).
if [ -d "${RESOURCE_BUNDLE}" ]; then
    cp -R "${RESOURCE_BUNDLE}" "${STAGING}/Contents/Resources/"
fi

# MLX metallib — SwiftPM ne compile pas les shaders Metal (doc officielle MLX).
# On récupère le metallib compilé par Xcode depuis Mickey.app (voisin, même modèle
# MLX). Sans ce fichier, MLX crashe à la première opération GPU.
MLX_METALLIB=""
for CANDIDATE in \
    "/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Applications/Mickey.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Library/Developer/Xcode/DerivedData/Mickey-*/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "${HOME}/Library/Developer/Xcode/DerivedData/Mickey-*/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
do
    # Expansion glob manuelle.
    for M in ${CANDIDATE}; do
        if [ -f "$M" ]; then
            MLX_METALLIB="$M"
            break 2
        fi
    done
done

if [ -n "${MLX_METALLIB}" ]; then
    echo "→ Embed MLX metallib depuis : ${MLX_METALLIB}"
    MLX_BUNDLE_DIR="${STAGING}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources"
    mkdir -p "${MLX_BUNDLE_DIR}"
    cp "${MLX_METALLIB}" "${MLX_BUNDLE_DIR}/default.metallib"
    # Info.plist minimal pour que le bundle soit reconnu par CFBundleGetBundleWithIdentifier.
    cat > "${STAGING}/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Info.plist" << 'PLIST_EOF'
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
    echo "⚠️  MLX metallib introuvable — la STT Cohere crashera. Installe Mickey.app ou build mlx-swift via Xcode pour obtenir default.metallib."
fi

# Ad-hoc codesign so LaunchServices trusts the freshly rebuilt bundle
# and app Group / Keychain entitlements bind correctly.
codesign --force --sign - --deep "${STAGING}" 2>/dev/null || \
    echo "  (codesign ad-hoc failed — continuing)"

# ----------------------------------------------------------------------
# Stop any running instance before overwriting the install location.
# ----------------------------------------------------------------------
echo "→ Killing any running ${APP_NAME} instance"
pkill -x "${APP_NAME}" 2>/dev/null || true
pkill -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
    if ! pgrep -f "/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then break; fi
    sleep 0.5
done

# ----------------------------------------------------------------------
# Install.
# ----------------------------------------------------------------------
echo "→ Installing to ${DEST}"
if [ -n "${NEEDS_SUDO}" ]; then
    echo "  (requires sudo for ${INSTALL_DIR})"
fi
mkdir -p "${INSTALL_DIR}" 2>/dev/null || ${NEEDS_SUDO} mkdir -p "${INSTALL_DIR}"
${NEEDS_SUDO} rsync -a --delete "${STAGING}/" "${DEST}/"

# In prod mode, remove the dev copy to avoid LaunchServices picking the
# wrong bundle.
if [ "${MODE}" = "prod" ]; then
    DEV_COPY="${HOME}/Applications/${APP_NAME}.app"
    if [ -d "${DEV_COPY}" ]; then
        echo "→ Removing dev copy at ${DEV_COPY}"
        rm -rf "${DEV_COPY}"
    fi
fi

# Refresh LaunchServices so `open` picks the freshly-installed bundle.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
    -f "${DEST}" >/dev/null 2>&1 || true

echo "→ Launching ${APP_NAME} from ${DEST}"
open -n "${DEST}"

echo "✓ Done. Build ${BUILD_NUMBER} (${CONFIGURATION}) running from ${DEST}"
