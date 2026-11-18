#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${APP_PATH:-$PWD/build/milkdown-candidate/Scribbit Milkdown Candidate.app}"
APP_PATH="$OUT" Scripts/build-app.sh
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.stephenhe.Scribbit.candidate.milkdown' "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Scribbit Milkdown Candidate' "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Scribbit Milkdown Candidate' "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :ScribbitMilkdownCandidate bool true' "$OUT/Contents/Info.plist"
codesign --force --sign - "$OUT"
codesign --verify --strict "$OUT"
printf '\nMilkdown candidate built, not launched: %s\n' "$OUT"
