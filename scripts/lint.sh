#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swift-format lint --strict --recursive \
    ios/App ios/Keyboard macos/App macos/scripts/CleanupProbe.swift \
    shared/App shared/FlypeCore shared/FlypeSpeech/Sources Package.swift
python3 - <<'PY'
import ast
from pathlib import Path
for path in [*Path("scripts").glob("*.py"), *Path("macos/scripts").glob("*.py")]:
    ast.parse(path.read_text(), filename=str(path))
PY
