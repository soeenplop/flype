#!/bin/zsh
# Builds the sandboxed Mac App Store variant in build/AppStore.
# With FLYPE_PROVISIONING_PROFILE and the two distribution certificates installed, it also creates
# build/AppStore/Flype.pkg for the upload. Otherwise the app is signed ad hoc for local sandbox tests.
set -euo pipefail
cd "${0:A:h:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
app="build/AppStore/Flype.app"
xcrun swift build --disable-sandbox --configuration release --product Flype
rm -rf build/AppStore
mkdir -p "$app/Contents/MacOS"
cp .build/release/Flype "$app/Contents/MacOS/Flype"
FLYPE_APP_PATH="$app" python3 macos/scripts/bundle.py

identities="$(security find-identity -v -p codesigning)"
installers="$(security find-identity -v -p basic)"
if [[ -n "${FLYPE_PROVISIONING_PROFILE:-}" && "$identities" == *"Apple Distribution"* && "$installers" == *"3rd Party Mac Developer Installer"* ]]; then
    team="$(python3 -c "import json; print(json.load(open('shared/Config/Signing.json'))['teamID'])")"
    bundle_id="$(python3 -c "import json; print(json.load(open('shared/Config/Signing.json'))['macOSBundleID'])")"
    entitlements="build/AppStore/Flype.entitlements"
    cp macos/Flype-AppStore.entitlements "$entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $team.$bundle_id" "$entitlements"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $team" "$entitlements"
    cp "$FLYPE_PROVISIONING_PROFILE" "$app/Contents/embedded.provisionprofile"
    codesign --force --options runtime --entitlements "$entitlements" --sign "Apple Distribution" "$app"
    xcrun productbuild --component "$app" /Applications --sign "3rd Party Mac Developer Installer" build/AppStore/Flype.pkg
    print "Bereit zum Hochladen: build/AppStore/Flype.pkg"
else
    codesign --force --options runtime --entitlements macos/Flype-AppStore.entitlements --sign - "$app"
    print -u2 "Ad hoc signiert für lokale Tests. Für den Upload fehlen Vertriebszertifikate oder FLYPE_PROVISIONING_PROFILE."
fi
codesign --verify --deep --strict "$app"
print "Sandbox-App: $app"
