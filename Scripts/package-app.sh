#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${APP_PATH:-$PWD/build/Scribbit.app}"
OUT="${1:-$PWD/build/development}"
test -x "$APP/Contents/MacOS/Scribbit"
codesign --verify --strict "$APP"
mkdir -p "$OUT"
STAGE="$(mktemp -d "$OUT/.package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# ZIP the bundle, rather than uploading its files: artifact storage does not
# retain executable modes. ditto also preserves macOS bundle metadata/symlinks.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/Scribbit-macOS.zip"
# Verify what a downloader receives, not only the pre-archive bundle.
ditto -x -k "$STAGE/Scribbit-macOS.zip" "$STAGE/check"
EXTRACTED="$STAGE/check/$(basename "$APP")"
test -x "$EXTRACTED/Contents/MacOS/Scribbit"
codesign --verify --strict "$EXTRACTED"
python3 - "$STAGE" <<'PY'
import hashlib
import json
import os
import pathlib
import platform
import sys

stage = pathlib.Path(sys.argv[1])
metadata = {
    "commit": os.environ.get("GITHUB_SHA", ""),
    "architecture": platform.machine(),
    "sha256": hashlib.sha256((stage / "Scribbit-macOS.zip").read_bytes()).hexdigest(),
}
(stage / "build-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
PY
mv "$STAGE/Scribbit-macOS.zip" "$OUT/Scribbit-macOS.zip"
mv "$STAGE/build-metadata.json" "$OUT/build-metadata.json"
printf 'Packaged: %s/Scribbit-macOS.zip\n' "$OUT"
