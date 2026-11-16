#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${OUTPUT:-$PWD/build/file-watching-benchmarks}"
mkdir -p "$OUTPUT"
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$OUTPUT/module-cache" Sources/ScribbitCore/NoteStore.swift Sources/ScribbitCore/NoteSession.swift Sources/ScribbitCore/WatchedNoteStore.swift Scripts/FileWatchingBenchmark.swift -o "$OUTPUT/file-watching-benchmark"
python3 Scripts/benchmark-file-watching.py --binary "$OUTPUT/file-watching-benchmark" --output "$OUTPUT" "$@"
