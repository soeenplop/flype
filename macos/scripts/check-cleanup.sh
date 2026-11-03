#!/bin/zsh
# Optional integration check: requires macOS 26 and an available Apple Intelligence model.
set -euo pipefail
cd "${0:A:h:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swift-format lint --strict macos/scripts/CleanupProbe.swift
xcrun swift build --package-path shared/FlypeCore --scratch-path build/check/cleanup-core --disable-sandbox --configuration release
mkdir -p build
xcrun swiftc -parse-as-library -target arm64-apple-macos26.0 \
  -I build/check/cleanup-core/release/Modules shared/App/TextCleanupService.swift macos/scripts/CleanupProbe.swift \
  build/check/cleanup-core/release/FlypeCore.build/*.swift.o -o build/CleanupProbe
./build/CleanupProbe
