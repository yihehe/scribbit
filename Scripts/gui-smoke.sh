#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ENGINE="${1:-native}"
if [ "$ENGINE" != native ]; then
    printf 'Only the native editor is supported.\n' >&2
    exit 64
fi
OUT="${2:-$PWD/build/smoke-$ENGINE}"
mkdir -p "$OUT"
set +e
"${APP_PATH:-$PWD/build/Scribbit.app}/Contents/MacOS/Scribbit" --smoke-test "$OUT" "$ENGINE" > "$OUT/run.log" 2>&1
RESULT=$?
set -e
cat "$OUT/run.log"
if [ "$RESULT" -ne 0 ]; then exit "$RESULT"; fi
if grep -Eq 'Exception detected while handling key input|Fatal error|Assertion failed|SMOKE_FAIL' "$OUT/run.log"; then
    printf 'GUI validation rejected a runtime error despite process success.\n' >&2
    exit 1
fi
for MARKER in GUI_SMOKE_PASS PRESENTER_LIFECYCLE_SMOKE_PASS EDITOR_INPUT_SMOKE_PASS INDENT_SMOKE_PASS COMPOSITION_SAVE_SMOKE_PASS NATIVE_HISTORY_SMOKE_PASS SHELL_SMOKE_PASS; do
    grep -q "$MARKER" "$OUT/run.log"
done
grep -q 'COMPOSITION_CONTRACTS: 5/5 passed for native' "$OUT/run.log"
