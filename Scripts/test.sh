#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/toolchain-env.sh
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
# Empty "$@" is safe with nounset on macOS Bash 3.2; an empty array is not.
set --
if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    set -- --triple "$(uname -m)-apple-macosx14.0" -Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$(xcode-select -p)/Library/Developer/usr/lib"
fi
swift test "$@" --disable-xctest --enable-swift-testing --disable-sandbox --cache-path "$PWD/.build/package-cache" --config-path "$PWD/.build/configuration" --security-path "$PWD/.build/security" --enable-code-coverage
