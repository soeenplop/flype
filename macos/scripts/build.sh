#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swift build --disable-sandbox --configuration release --product Flype
app="${FLYPE_APP_PATH:-build/macos/Flype.app}"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Flype "$app/Contents/MacOS/Flype"
python3 macos/scripts/bundle.py
# Checks are explicit local builds; normal app builds always use the configured binda team.
if [[ "${FLYPE_ADHOC_SIGN:-0}" == "1" ]]; then
  codesign --force --sign - "$app"
else
  python3 macos/scripts/sign.py
fi
