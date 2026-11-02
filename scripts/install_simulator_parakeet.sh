#!/bin/zsh
# Copies the pinned Parakeet model into Flype on every booted simulator.
# Apple's speech recognition does not run in the simulator, so dictation there needs this model.
set -euo pipefail
cd "${0:A:h:h}"
revision="$(python3 -c "import json; print(json.load(open('shared/Config/parakeet-model-manifest.json'))['revision'])")"
model="parakeet-v3-$revision"
source="build/parakeet-models/$model"
[[ -f "$source/verified-revision" ]] || python3 scripts/fetch_parakeet_model.py

devices=("${(@f)$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p')}")
[[ -n "${devices[1]:-}" ]] || { print -u2 "Kein gestarteter Simulator gefunden."; exit 1; }
for device in "${devices[@]}"; do
    container="$(xcrun simctl get_app_container "$device" one.binda.flype.app data)"
    target="$container/Library/Application Support/FlypeModels"
    mkdir -p "$target"
    rm -rf "$target/$model"
    cp -R "$source" "$target/$model"
    print "Parakeet in Simulator $device installiert."
done
