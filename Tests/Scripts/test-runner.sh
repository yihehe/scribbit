#!/bin/bash
# Exercise the real wrapper without a compiler, SDK changes, or network access.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/.build/script-fixtures"
WORK="$(mktemp -d "$ROOT/.build/script-fixtures/runner.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PROJECT="$WORK/project with spaces"
TOOLS="$WORK/bin"
DEVELOPER="$WORK/Developer tools"
mkdir -p "$PROJECT/Scripts" "$TOOLS" "$DEVELOPER"
cp "$ROOT/Scripts/test.sh" "$ROOT/Scripts/toolchain-env.sh" "$PROJECT/Scripts/"

cat > "$TOOLS/xcode-select" <<'SH'
#!/bin/sh
printf '%s\n' "$FAKE_DEVELOPER_DIR"
SH
cat > "$TOOLS/swift" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$CAPTURE"
exit "${FAKE_SWIFT_EXIT:-0}"
SH
chmod +x "$TOOLS/xcode-select" "$TOOLS/swift"

run_wrapper() {
    PATH="$TOOLS:$PATH" FAKE_DEVELOPER_DIR="$DEVELOPER" CAPTURE="$WORK/actual" \
        FAKE_SWIFT_EXIT="${1:-0}" /bin/bash "$PROJECT/Scripts/test.sh"
}
common_arguments() {
    printf '%s\n' --disable-xctest --enable-swift-testing --disable-sandbox \
        --cache-path "$PROJECT/.build/package-cache" \
        --config-path "$PROJECT/.build/configuration" \
        --security-path "$PROJECT/.build/security" --enable-code-coverage
}

# Full Xcode can omit the CLT-specific Testing.framework directory.
run_wrapper
{ printf '%s\n' test; common_arguments; } > "$WORK/expected"
diff -u "$WORK/expected" "$WORK/actual"
printf 'PASS: no optional framework arguments under /bin/bash\n'

# CLT installations may need explicit framework/linker paths. Preserve spaces.
FRAMEWORKS="$DEVELOPER/Library/Developer/Frameworks"
mkdir -p "$FRAMEWORKS/Testing.framework"
run_wrapper
{
    printf '%s\n' test --triple "$(uname -m)-apple-macosx14.0" \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -F -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$DEVELOPER/Library/Developer/usr/lib"
    common_arguments
} > "$WORK/expected"
diff -u "$WORK/expected" "$WORK/actual"
printf 'PASS: optional framework arguments retain exact quoting and order\n'

# A failing compiler/test command must still fail the wrapper.
result=0
run_wrapper 23 || result=$?
test "$result" -eq 23
printf 'PASS: Swift failure status is propagated\n'
