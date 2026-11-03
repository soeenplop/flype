# Flype for iPhone and iPad

The main app and the keyboard extension. The keyboard handles typing, word suggestions and starting a transcription. Recording and speech recognition run in the main app, because iOS does not let keyboard extensions use the microphone.

## Run it

```sh
open ios/Flype.xcodeproj
./scripts/check.sh ios
```

You need iOS or iPadOS 26 or later and Xcode with the matching SDK. The scheme is `Flype`. On a real device, the configured team needs access to both bundle IDs and the App Group. `shared/Config/Signing.json` holds these values:

- Team: binda UG, `4K9Y59Z87Y`
- App: `one.binda.flype.app`
- Keyboard: `one.binda.flype.app.keyboard`
- App Group: `group.one.binda.flype.shared`

`scripts/generate_project.py` writes the Xcode project, so run it after adding or removing Swift files. It keeps the team and bundle IDs already set in the project, but it rewrites the Info.plist and entitlements files. Make changes to those in the generator.

## First transcription

1. Open Flype and follow the guided setup.
2. Add the keyboard under **Settings > General > Keyboard > Keyboards** and allow Full Access. Typing works without it, transcription does not.
3. Allow the microphone during setup.
4. In any text field, switch to Flype and tap the microphone next to the space bar.
5. Speak, then tap the round stop button. The text is inserted but never sent.

There is a test field under **Start > Try it here**, and help under **Settings > Setup & help**.

## How a transcription runs

The first tap opens Flype briefly, which starts a standby session. After that, you start and stop further transcriptions directly in the keyboard. The session ends when you turn it off, when the device locks, or after five minutes without an active keyboard. Recordings last at most two minutes.

An arbitrary link cannot start a recording. The keyboard stores a random request that is valid for 30 seconds in the shared container, and the app checks it and uses it exactly once. Invalid, expired or repeated links do not turn on the microphone.

Debug builds return to the previous app automatically through KeyboardKitHostPlugin and a private iOS call. This code sits behind `#if DEBUG`, so Release contains neither the plugin nor the private call.

## Data on the device

- Recordings live in the protected temporary app folder and are deleted on success, failure or cancellation. After a crash, they are deleted at the next start.
- A finished transcription waits in the shared container for the keyboard and expires after ten minutes. A file lock ensures the keyboard can claim it only once.
- The last text stays in memory only, so you can copy or delete it on the home screen.

## Speech recognition and cleanup

Parakeet is the default recognizer but does not ship with the app. On first launch, or if the model is missing, the app offers to download it (about 632 MB, 20 files, each checked against a fixed size and hash) or to use Apple speech recognition where available. The download continues in the background. The pinned version is in `shared/Config/parakeet-model-manifest.json`, and `python3 scripts/fetch_parakeet_model.py` fetches it. Weights never go into the repository.

**Verbatim** keeps what was recognized. **Cleaned** also runs [cleanup](../docs/TEXT-CLEANUP.md). [Personal words](../docs/DICTIONARY-CORRECTION.md) apply in both modes.

## Simulator

Apple speech recognition does not run in the simulator, so simulator builds use Parakeet on the CPU. After installing the app, this copies the model so you can skip the download:

```sh
./scripts/install_simulator_parakeet.sh
```

Build with code signing on, or the shared App Group container will be missing. Do not set `CODE_SIGNING_ALLOWED=NO` for builds you want to run.

## Before you ship

See [App Store submission](../docs/ios/APP-STORE.md).
