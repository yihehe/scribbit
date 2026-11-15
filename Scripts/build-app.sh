#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain-env.sh
swift build -c release --disable-sandbox --cache-path "$PWD/.build/package-cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security"
DESTINATION="${APP_PATH:-$PWD/build/Scribbit.app}"
mkdir -p "$PWD/build" "$(dirname "$DESTINATION")"
# Assemble a fresh bundle: never carry retired dependency notices/resources into
# a native build. Preserve an existing bundle rather than deleting it in place.
PACKAGE_DIR="$(mktemp -d "$PWD/build/app-package.XXXXXX")"
APP="$PACKAGE_DIR/Scribbit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Scribbit "$APP/Contents/MacOS/Scribbit"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# BrandAssets loads this signed location; SwiftPM's root lookup is for CLI/tests.
cp -R .build/release/Scribbit_Scribbit.bundle "$APP/Contents/Resources/"
# Ad-hoc signing works locally. Use a stable Developer ID identity for distribution.
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$PACKAGE_DIR/Previous Scribbit.app"
    printf '\nPrevious bundle preserved: %s\n' "$PACKAGE_DIR/Previous Scribbit.app"
fi
mv "$APP" "$DESTINATION"
printf '\nBuilt: %s\n' "$DESTINATION"
