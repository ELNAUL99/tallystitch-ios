#!/usr/bin/env bash
# Compile the real core sources + the verification runner and execute them.
#
# Why this exists alongside the XCTest suites: on a machine with only the
# Command Line Tools (no full Xcode), `swift test` can't run — XCTest isn't
# bundled and SwiftPM can't resolve the manifest. This wrapper uses plain
# `swiftc` so the core stock math can still be verified there. On a Mac with
# full Xcode, prefer `swift test` (runs the full XCTest suites in Tests/).
set -euo pipefail
cd "$(dirname "$0")/.."

# swiftc requires top-level code to live in a file literally named main.swift.
tmp_main="$(mktemp -d)/main.swift"
cp Scripts/verify.swift "$tmp_main"

out="$(mktemp -d)/ts_verify"
swiftc Sources/TallystitchCore/StockMath.swift \
       Sources/TallystitchCore/Models.swift \
       Sources/TallystitchCore/Formatting.swift \
       "$tmp_main" -o "$out"
"$out"
