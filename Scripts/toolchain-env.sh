#!/bin/bash
# Source from scripts after changing to the project root. Never edits the SDK.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache-v2"
MANIFEST_API="$(xcode-select -p)/usr/lib/swift/pm/ManifestAPI"
# Some CLT installations ship a stale private PackageDescription interface next
# to an up-to-date public interface and dylib. Swift prefers the stale private
# interface. Use a project-local public-interface-only copy on those hosts.
if grep -q 'public enum SwiftVersion' "$MANIFEST_API/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface" 2>/dev/null &&
   grep -q 'public enum SwiftLanguageMode' "$MANIFEST_API/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface" 2>/dev/null; then
    LOCAL_API="$PWD/.build/compatible-manifest/ManifestAPI"
    mkdir -p "$LOCAL_API/PackageDescription.swiftmodule"
    for ARCH in arm64 x86_64; do
        cp "$MANIFEST_API/PackageDescription.swiftmodule/$ARCH-apple-macos.swiftinterface" "$LOCAL_API/PackageDescription.swiftmodule/"
    done
    cp "$MANIFEST_API/libPackageDescription.dylib" "$LOCAL_API/"
    export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/compatible-manifest"
    printf 'Using project-local public PackageDescription interfaces for mismatched CLT installation.\n' >&2
fi
