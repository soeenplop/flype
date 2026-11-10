#!/bin/zsh
# Runs from any directory. Pass one area, or nothing for everything except the Docker database tests.
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    selected_developer="$(xcode-select -p)"
    if [[ -d "$selected_developer/Platforms/iPhoneOS.platform" ]]; then
        export DEVELOPER_DIR="$selected_developer"
    else
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
fi

mkdir -p build/cache build/modules
export CLANG_MODULE_CACHE_PATH="$project_root/build/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/build/modules"

case "${1:-all}" in
    lint)
        ./scripts/lint.sh
        ;;
    backend)
        node --test supabase/functions/revoke-apple-token/index.test.mjs
        node --test supabase/functions/cloud-cleanup/handler.test.mjs
        node --test supabase/functions/_shared/billing.test.mjs
        node --test supabase/functions/billing/handler.test.mjs
        node --test supabase/functions/stripe-webhook/handler.test.mjs
        node --test supabase/functions/_shared/appstore.test.mjs
        node --test supabase/functions/app-store-verify/handler.test.mjs
        node --test supabase/functions/app-store-notifications/handler.test.mjs
        node --test supabase/eval/cleanup.test.mjs
        ;;
    core)
        xcrun swift test --package-path shared/FlypeCore --disable-sandbox \
            --cache-path "$project_root/build/cache" --scratch-path "$project_root/build/core"
        ;;
    ios)
        if [[ ! -d "$DEVELOPER_DIR/Platforms/iPhoneOS.platform" ]]; then
            print -u2 "Ein vollständiges Xcode mit iOS-SDK wird benötigt. DEVELOPER_DIR bei Bedarf setzen."
            exit 1
        fi
        # Release differs from Debug: it has no development helpers, and it is what App Review receives.
        for configuration in Debug Release; do
            xcodebuild -quiet -project ios/Flype.xcodeproj -scheme Flype -configuration "$configuration" \
                -destination generic/platform=iOS -derivedDataPath "$project_root/build/check/ios" \
                CODE_SIGNING_ALLOWED=NO build
        done
        ;;
    macos)
        # Never replace build/macos/Flype.app: an ad-hoc signature there would void its Accessibility permission.
        FLYPE_ADHOC_SIGN=1 FLYPE_APP_PATH=build/check/macos/Flype.app ./macos/scripts/build.sh
        ;;
    database)
        ./scripts/test-database.sh
        ;;
    all)
        for area in lint backend core ios macos; do
            print "== $area"
            ./scripts/check.sh "$area"
        done
        ;;
    *)
        print -u2 "Verwendung: scripts/check.sh [all|lint|backend|core|ios|macos|database]"
        exit 2
        ;;
esac
