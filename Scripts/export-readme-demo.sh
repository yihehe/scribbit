#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/Docs/Images/scribbit-demo.gif}"
BUILD="$PWD/build/readme-demo"
mkdir -p "$BUILD/module-cache" "$(dirname "$OUT")"
# Compile the actual pure geometry/motion sources into a documentation-only
# exporter. This does not build/run Scribbit or create an application/window.
swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path "$BUILD/module-cache" \
    Sources/ScribbitCore/NotchMotion.swift Sources/ScribbitCore/NotchGeometry.swift \
    Sources/ScribbitCore/HoverDelay.swift \
    Scripts/ReadmeDemo.swift -o "$BUILD/export-demo"
STAGE="$(mktemp -d "$BUILD/export.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Preserve existing committed assets unless both images export and validate.
"$BUILD/export-demo" "$STAGE/demo.gif" "$STAGE/demo.png" \
    "$PWD/Sources/Scribbit/Resources/FrogPencil-14@2x.png"
mv "$STAGE/demo.gif" "$OUT"
mv "$STAGE/demo.png" "${OUT%.gif}.png"
