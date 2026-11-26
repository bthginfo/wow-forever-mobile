#!/usr/bin/env bash
# Puts the Pixel edition's PowerVR DXVK archive in app/src/pixelTest/assets/bundled_components/.
#
# The archive is built from the pinned DXVK source with tools/dxvk-powervr/build.sh. Releases publish it next to the
# APKs; this script downloads that copy and checks it against the pinned digest. Pass a directory that already holds
# the archive to copy it from there instead.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_DIR/app/src/pixelTest/assets/bundled_components"
NAME=dxvk-2.4.1-wow-powervr.wcp
SHA256=ff439b2e7bc6ca059fe66508e0df9e7f01261d9f494d0078bea4cc6ad35decae
URL="${PIXEL_COMPONENT_URL:-https://github.com/bthginfo/wow-forever-mobile/releases/download/v2.4.4-mobile.34/$NAME}"

mkdir -p "$DEST"
if [ ! -s "$DEST/$NAME" ]; then
    if [ -n "${1:-}" ] && [ -s "$1/$NAME" ]; then
        cp "$1/$NAME" "$DEST/$NAME"
    else
        curl -fL --retry 3 -o "$DEST/$NAME.part" "$URL"
        mv "$DEST/$NAME.part" "$DEST/$NAME"
    fi
fi
echo "$SHA256  $DEST/$NAME" | sha256sum -c -
