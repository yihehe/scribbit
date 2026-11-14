#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run Scripts/test.sh first. This report intentionally includes low-coverage UI;
# GUI smoke exercises the release binary separately and does not inflate it.
xcrun llvm-cov report .build/debug/ScribbitPackageTests.xctest/Contents/MacOS/ScribbitPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -ignore-filename-regex='Tests/|\.derived/'
